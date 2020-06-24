#! /usr/bin/perl
#
# Copyright (c) 2018-2020, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2012-2016 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use lib '/opt/vyatta/share/perl5';
use warnings;
use POSIX;
use Set::Scalar;
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use NetAddr::IP;
use Vyatta::FWHelper qw(build_rule get_port_num);
use Vyatta::Npf::Warning qw(npf_warn_if_intf_doesnt_exist);

# Vyatta config
my $config = new Vyatta::Config;

# if VDR, there will be a list of vplane ids
my @vplane_ids = $config->listNodes("distributed dataplane");

#
# main
#
my $type;

GetOptions( "type=s" => \$type, );

my $ctrl = new Vyatta::VPlaned;

die "usage: vyatta-dp-npf-nat-nat44.pl --type=source|destination\n"
    if ( !defined($type) );

# A 'pinhole' option is added to every firewall rule by default
my $def_rule_pinhole = 1;

#
# If "explicit-firewall-pinhole" is configured then the per-rule command
# "firewall-pinhole" is required to enable pinhole behaviour for a NAT
# session.
#
my $def_pinhole_cmd = "service nat $type explicit-firewall-pinhole";

if ( $config->exists($def_pinhole_cmd) ) {
    # A 'pinhole' option is *not* added to every firewall rule by default
    $def_rule_pinhole = 0;
}

#
# Get the sets of current and proposed rule numbers.
# Then determine who was deleted if any
#
my $level = "service nat $type rule";
my @curr  = $config->listOrigNodes($level);
my @prop  = $config->listNodes($level);

# $current and $proposed contain sets of rule numbers
my $current  = Set::Scalar->new(@curr);
my $proposed = Set::Scalar->new(@prop);

# set of rules in $current but not in $proposed (i.e. rules being deleted)
my $deleted = $current - $proposed;

# set of rules in $current and also in $proposed (i.e. rules being changed)
my $changed = $current * $proposed;

# Iterate through the deleted rules.
while ( defined( my $d = $deleted->each ) ) {
    if ( $type =~ /source/ ) {
        delete_rule( $type, "snat", $d );
    } elsif ( $type =~ /destination/ ) {
        delete_rule( $type, "dnat", $d );
    }
}

# Iterate through the changed rules.
while ( defined( my $c = $changed->each ) ) {

    # If a rule is being changed and the interface is different, then need
    # to delete the old rule.
    if ( $type =~ /source/ ) {
        delete_rule_diff_if( $type, "snat", $c, "outbound-interface" );
    } elsif ( $type =~ /destination/ ) {
        delete_rule_diff_if( $type, "dnat", $c, "inbound-interface" );
    }
}

# Add the changed and new rules
while ( defined( my $p = $proposed->each ) ) {
    if ( $type =~ /source/ ) {
        add_rule( $type, "snat", $p );
    } elsif ( $type =~ /destination/ ) {
        add_rule( $type, "dnat", $p );
    }
}

# send fencepost for VDR SNAT
$ctrl->store( "nat $type vdr", "npf-cfg vplane done", undef, "SET" )
  if ( @vplane_ids and $type =~ /source/ );

exit 0;

sub delete_rule_diff_if {
    my ( $type, $gclass, $rule_num, $if_dir ) = @_;

    my $path   = "service nat $type rule $rule_num $if_dir";
    my $old_if = $config->returnOrigValue($path);
    my $new_if = $config->returnValue($path);

    if ( $old_if ne $new_if ) {
        delete_rule( $type, $gclass, $rule_num );
    }
}

sub vdr_split_nat_ports {
    my $cmd = shift;

    # Need to split the port range down for the vplanes Extract the high and
    # low port ranges

    my $NUM_VPLANES = scalar @vplane_ids;

    my ( $lowest_port, $highest_port );

    if ( ( $lowest_port, $highest_port ) =
        ( $cmd =~ /trans-port=(\d+)-(\d+) / ) )
    {
        $cmd =~ s/trans-port=\d+-\d+ //;
    } else {
        $lowest_port  = 1;
        $highest_port = 65535;
    }

    my $total_range = $highest_port - $lowest_port + 1;

    die "sNAT must be configured with more ports than configured vplanes"
      if ( $total_range < $NUM_VPLANES );

    # The number of ports to be assigned to each vplane.
    my $range_increment = floor( $total_range / $NUM_VPLANES ) - 1;
    my $remainder       = $total_range % $NUM_VPLANES;

    # Return array, each element a list: (vp_id, cmd).
    my @ret_arr;

    # Must be defined outside the foreach loop as current iteration depends on
    # values set in previous iterations
    my ( $low_port, $high_port );

    foreach my $vp_id (@vplane_ids) {

        # Calculate the high and low port numbers for this specific vplane.
        if ( !defined($low_port) ) {
            $low_port = $lowest_port;
        } else {
            $low_port = $high_port + 1;
        }

        $high_port = $low_port + $range_increment;

        # Only using the range increment (above) would leave some ports
        # unutilised. Assign these "extra" ports to the early vplanes.
        if ( $remainder > 0 ) {
            $high_port += 1;
            $remainder -= 1;
        }

        # Make sure we don't overshoot our total range.
        $high_port = $highest_port
          if ( $high_port > $highest_port );

        # Regexp and replace the original cmd with the split range and
        # put it into a vplane specific cmd (preserve the original).
        my $vp_cmd = $cmd;
        $vp_cmd .= "trans-port=$low_port-$high_port";

        # Gather the information up into a list and push that list to the array
        push @ret_arr, [ $vp_id, "$vp_cmd" ];
    }
    return @ret_arr;
}

sub add_rule {
    my ( $type, $gclass, $rule_num ) = @_;
    my ( $cmd, $iface ) = generate_rule( $type, $rule_num );

    if ( defined($cmd) ) {

        # Do we need to worry about port mapping for VDR?
        my $has_ports;
        if ( $cmd =~ m/ nat-exclude=y / ) {
            $has_ports = 0;
        } elsif ( ( $cmd =~ m/ action=accept / )
            and ( $cmd =~ m/ proto-final=(\d+) / ) )
        {
            # TCP/UDP/DCCP/UDP-Lite,  not SCTP
            if ( $1 == 6 || $1 == 17 || $1 == 33 || $1 == 136 ) {
                $has_ports = 1;
            }
        } else {

            # A match all protocols rule will hit here
            $has_ports = 1;
        }

        # an SNAT rule and on VDR?
        if ( $has_ports and @vplane_ids and $type =~ /source/ ) {

            my @vdr_cmds = vdr_split_nat_ports($cmd);

            foreach my $vp_ruleset (@vdr_cmds) {
                my $vp_id  = shift @$vp_ruleset;
                my $vp_cmd = shift @$vp_ruleset;

                $ctrl->store(
                    "nat $type rule $rule_num $vp_id",
"npf-cfg vplane $vp_id add $gclass:$iface $rule_num $vp_cmd",
                    undef,
                    "SET"
                );
            }
        } else {
            $ctrl->store(
                "nat $type rule $rule_num",
                "npf-cfg add $gclass:$iface $rule_num $cmd",
                undef, "SET"
            );
        }
    } else {
        $ctrl->store(
            "nat $type rule $rule_num",
            "npf-cfg delete $gclass:$iface $rule_num",
            undef, "DELETE"
        );
    }
}

sub delete_rule {
    my ( $type, $gclass, $rule_num ) = @_;
    my $iface;

    my $level = "service nat $type rule $rule_num ";

    if ( $type eq "source" ) {
        $iface = $config->returnOrigValue( $level . "outbound-interface" );
    } else {
        $iface = $config->returnOrigValue( $level . "inbound-interface" );
    }

    $ctrl->store(
        "nat $type rule $rule_num", "npf-cfg delete $gclass:$iface $rule_num",
        undef,                      "DELETE"
    ) if defined($iface);
}

sub generate_rule {
    my ( $type, $rule_num ) = @_;

    my $level = "service nat $type rule $rule_num ";
    my $conf  = Vyatta::Config->new($level);
    my $val;
    my $rule = "";
    my $iface;

    if ( $type eq "source" ) {
        $rule .= "nat-type=snat ";
        $iface = $conf->returnValue("outbound-interface");
    } else {
        $rule .= "nat-type=dnat ";
        $iface = $conf->returnValue("inbound-interface");
    }

    npf_warn_if_intf_doesnt_exist($iface);

    $val = $conf->exists("disable");
    return ( undef, $iface )
      if defined($val);

    # Use common NPF rule parsing for match part of the rule
    $rule .= build_rule($level, undef, 0);

    $val = $conf->exists("exclude");
    if ( defined($val) ) {
        $rule .= "nat-exclude=y ";
        return ( $rule, $iface );
    }

    # Conditionally install a pin-hole
    if ( $def_rule_pinhole || $conf->exists("firewall-pinhole") ) {
        $rule .= "nat-pinhole=y ";
    }

    $val = $conf->returnValue("translation address");
    if ( defined($val) ) {
        if ( $val =~ /masquerade/ ) {
            $rule .= "trans-addr-masquerade=y ";
        } elsif ( $val =~ /\// ) {

            # convert address/mask into a range of addresses
            my $ip    = new NetAddr::IP($val);
            my $first = $ip->first();
            my $last  = $ip->last();
            $first =~ s/\/.*$//;
            $last =~ s/\/.*$//;

            $rule .= "trans-addr=${first}-${last} ";
        } elsif ( $val =~ /\./ ) {    # an IP address
            $rule .= "trans-addr=$val ";
        } else {
            $rule .= "trans-addr-group=$val ";
        }
    } else {
        $rule .= "trans-addr=0.0.0.0-255.255.255.255 ";
    }

    $val = $conf->returnValue("translation port");
    if ( defined($val) ) {
        my $trans_port_num = get_port_num($val);
        $trans_port_num = $val if !defined($trans_port_num);
        $rule .= "trans-port=$trans_port_num ";
    } else {

        # Can't specify translation port ranges (or bug that needs to
        # be fixed) -- for now this is required in order to get an implicit
        # mapping to work here.
        $rule .= "trans-port=1-65535 "
          if $type eq "destination";
    }

    return ( $rule, $iface );
}
