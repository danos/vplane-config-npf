#! /usr/bin/perl

# Copyright (c) 2019-2020, AT&T Intellectual Property. All rights reserved.
#
# Copyright (C) 2013-2015 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5";

use Getopt::Long;
use Vyatta::Dataplane;
use Vyatta::Dataplane qw(vplane_exec_cmd);

my %g_yang_to_dataplane_dict = (
    "source-ip"        => {
                              "order" => "1",
                              "dp_name" => "saddr",
                              "cmd_help" => "[source <src-ip>]",
                          },
    "source-port"      => {
                              "order" => "2",
                              "dp_name" => "sport",
                              "cmd_help" => "[source-port <src-port>]",
                          },
    "destination-ip"   => {
                              "order" => "3",
                              "dp_name" => "daddr",
                              "cmd_help" => "[destination <dst-ip>]",
                          },
    "destination-port" => {
                              "order" => "4",
                              "dp_name" => "dport",
                              "cmd_help" => "[destination-port <dst-port>]",
                          },
    "protocol"         => {
                              "order" => "5",
                              "dp_name" => "proto",
                              "cmd_help" => "[protocol <protocol>]",
                              "convert_value_fn" => \&convert_protocol_from_string_to_int,
                          },
);

sub isdigit {
    my $input_str = $_[0];
    if ($input_str =~ /^[0-9]{1,}$/) {
        return 1;
    }

    return;
}

my %protocol_to_num = (
    "udp" => 17,
    "tcp" => 6,
    "icmp" => 1,
    "ipv6-icmp" => 58,
);

sub convert_protocol_str_to_number {
   my $protocol_str = $_[0];
   my $protocol_num;

   if (defined($protocol_to_num{$protocol_str})) {
       $protocol_num = $protocol_to_num{$protocol_str};
   } else {
       $protocol_num = getprotobyname($protocol_str);
       if (!defined ($protocol_num)) {
           print("Invalid command: protocol string '$protocol_str' is not recognized\n");
           exit 0;
       }
   }

   return $protocol_num;
}

sub convert_protocol_from_string_to_int {
   my $input_val = $_[0];
   my $output_val;

   if (isdigit($input_val)) {
       if ($input_val >= 0 and $input_val <= 255 ) {
           $output_val = $input_val;
       } else {
           print("Invalid command: protocol shall be in range 0-255\n");
           exit 0;
       }
   } else {
       $output_val = convert_protocol_str_to_number($input_val);
   }

   return $output_val;
}

sub usage {
    print "Usage: $0 --id=index\n";
    print "       $0 --all\n";
    print "       $0 --flt <filter_options>\n";
    print "       <filter_options> = \n";

    foreach my $yang_param ( sort {
        $g_yang_to_dataplane_dict{$a}{"order"} <=> $g_yang_to_dataplane_dict{$b}{'order'} }
        keys %g_yang_to_dataplane_dict) {
        print "            $g_yang_to_dataplane_dict{$yang_param}{'cmd_help'}\n";
    }

    exit 1;
}

# input:
#     $_[0] - string array of tuples {name_from_yang, value_from_yang}
#                        {name, value}...{name, value}
#     index in array:        0      1        i    i+1
#
# uses:
#     global hash g_yang_to_dataplane_dict - hash table that contain
#     yang model valid attributes names as key
#
# does: validates format of data coming from yang
#
# returns: hash that has <key> set as attribute name and <value> as attribute value.
sub parse_yang_cmd {
    my @flt_cli_arr = @_;
    my %flt_dict;
    my %dup_params_count;

    if (@flt_cli_arr == 0) {
        print("Invalid command: --flt <filter_options> - shall contain at least one parameter\n");
        exit 0;
    }

    for (my $i = 0; $i < @flt_cli_arr; $i += 2) {
        my $param = $flt_cli_arr[$i];
        my $value = $flt_cli_arr[$i+1];

        if ( exists($g_yang_to_dataplane_dict{$param})) {
            if ( exists($flt_cli_arr[$i+1]) ) {
                $flt_dict{$param} = $value;
            } else {
                print("Invalid command: parameter $param does not have value\n");
                exit 0;
            }
        } else {
            print("Invalid command: parameter $param is not supported\n");
            exit 0;
        }

        if ($dup_params_count{$param}++) {
            print("Invalid command: duplicate parameter $param\n");
            exit 0;
        }
    }

   return %flt_dict;
}

# input:   hash that has <key> set as attribute name and <value> as attribute value.
# does:    converts hash representation of yang data to dataplane string command format.
# returns: string command line in dataplane format. order of parameters is important
#          for dataplane
sub convert_yang_to_dataplane {
    my %yang_flt_dict = @_;
    my $dp_filter;

    foreach my $yang_param ( sort { $g_yang_to_dataplane_dict{$a}{"order"}
        <=> $g_yang_to_dataplane_dict{$b}{'order'}  }
        keys %g_yang_to_dataplane_dict) {
        my $dp_param_name;
        my $dp_param_value;
        if (exists($yang_flt_dict{$yang_param})) {
            my $yang_value = $yang_flt_dict{$yang_param};

            if (defined($g_yang_to_dataplane_dict{$yang_param}{"convert_value_fn"})) {
                $dp_param_value =
                    $g_yang_to_dataplane_dict{$yang_param}{"convert_value_fn"}->($yang_value);
            } else {
                $dp_param_value = $yang_value;
            }
        } else {
            $dp_param_value = "any";
        }

        $dp_param_name = $g_yang_to_dataplane_dict{$yang_param}{'dp_name'};
        $dp_filter .= " $dp_param_name $dp_param_value";
    }

    return $dp_filter;
}

my ( $index, $all, @flt, $fabric );

GetOptions(
    'id=s'  => \$index,
    'all'   => \$all,
    'flt=s{1,}' => \@flt,
) or usage();

my ( $dp_ids, $dp_conns, $local_controller );

( $dp_ids, $dp_conns, $local_controller ) =
  Vyatta::Dataplane::setup_fabric_conns($fabric);

if ( defined($all) ) {
    vplane_exec_cmd( "session-op clear session all", $dp_ids, $dp_conns, 0 );
} elsif ( @flt > 0 ) {
    my %yang_flt_dict = parse_yang_cmd(@flt);
    my $dp_flt = convert_yang_to_dataplane(%yang_flt_dict);
    vplane_exec_cmd( "session-op clear session filter $dp_flt",
        $dp_ids, $dp_conns, 0 );
} elsif ( defined($index) ) {
    vplane_exec_cmd( "session-op clear session id $index", $dp_ids, $dp_conns, 0 );
}

exit 0;

