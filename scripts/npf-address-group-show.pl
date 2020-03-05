#! /usr/bin/perl
#
# Copyright (c) 2017-2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use Getopt::Long;
use Config::Tiny;
use JSON qw( decode_json );
use List::Util qw( max min );
use Data::Dumper;

use lib "/opt/vyatta/share/perl5";

use Vyatta::Dataplane;
use Vyatta::Dataplane qw(vplane_exec_cmd);
use Vyatta::Aggregate;
use Vyatta::NpfRuleset;
use Vyatta::Config;
use Vyatta::FWHelper qw(get_proto_name);

my $fabric;
my ( $dp_ids, $dp_conns, $local_controller ) =
  Vyatta::Dataplane::setup_fabric_conns($fabric);

my ( $opt_af, $opt_list, $opt_tree, $opt_name, $opt_action );

# set up actions dispatch table
my %actions = (
    "show-summary" => \&show_summary,
    "show-detail"  => \&show_detail,
    "show-optimal" => \&show_optimal,
);

#
# af     = ipv4 | ipv6 | all*
# list   = none | list-only* | all
# tree   = none* | all
# name   = <name>
# action = show-summary | show-detail | show-optimal
#
# '*' denotes default
#
GetOptions(
    "af=s"     => \$opt_af,
    "list=s"   => \$opt_list,
    "tree=s"   => \$opt_tree,
    "name=s"   => \$opt_name,
    "action=s" => \$opt_action,
);

if ( not defined $opt_af ) {
    $opt_af = "all";
}

if ( not defined $opt_list ) {
    $opt_list = "list-only";
}

if ( not defined $opt_tree ) {
    $opt_tree = "none";
}

if ( not defined $opt_name ) {
    $opt_name = "all";
}

if ( not defined $opt_action ) {
    $opt_action = "show-detail";
}

die "Missing --action=<action> option\n"
  if ( !defined($opt_action) );

# dispatch action
( $actions{$opt_action} )->();

# Close down ZMQ sockets. This is needed or sometimes a hang
# can occur due to timing issues with libzmq - see VRVDR-17233 .
Vyatta::Dataplane::close_fabric_conns( $dp_ids, $dp_conns );

exit 0;

sub address_group_list {
    my $name = shift;

    my $config = new Vyatta::Config;
    my @names  = ();

    if ( $name eq "all" ) {
        my @tmp = $config->listOrigNodes("resources group address-group");
        push( @names, @tmp );
    } elsif ( $config->existsOrig("resources group address-group $name") ) {
        @names = ($name);
    }

    return @names;
}

sub show_address_group_pfx {
    my ( $indent, $pfx, $af_name, $opt ) = @_;

    my $host = 0;
    if ( !defined $pfx->{'mask'} )
    {
        $host = 1;
    }

    if ( $host && $opt ) {
        printf( "%*s%s %s\n", $indent, " ", "address", $pfx->{'prefix'} );
    } else {
        printf( "%*s%s %s/%d\n",
            $indent, " ", "prefix ", $pfx->{'prefix'}, $pfx->{'mask'} );
    }
}

sub show_address_group_range {
    my ( $indent, $range, $af_name ) = @_;

    printf(
        "%*s%s %s to %s\n",
        $indent, " ", "address-range ",
        $range->{'start'}, $range->{'end'}
    );

    if ( defined $range->{'range-prefixes'} ) {
        $indent += 4;

        my @entries = @{ $range->{'range-prefixes'} };

        foreach my $entry (@entries) {
            if ( $entry->{'type'} == 0 ) {
                show_address_group_pfx( $indent, $entry, $af_name, 0 );
            }
        }
    }
}

sub show_address_group_af {
    my ( $indent, $af_name, $af ) = @_;

    if ( defined $af->{'list-entries'} ) {
        my @entries = @{ $af->{'list-entries'} };

        foreach my $entry (@entries) {
            if ( $entry->{'type'} == 0 ) {
                show_address_group_pfx( $indent, $entry, $af_name, 1 );
            } elsif ( $entry->{'type'} == 1 ) {
                show_address_group_range( $indent, $entry, $af_name );
            }
        }
    }

    if ( defined $af->{'tree'} ) {
        my @entries = @{ $af->{'tree'} };

        foreach my $entry (@entries) {
            if ( $entry->{'type'} == 0 ) {
                show_address_group_pfx( $indent, $entry, $af_name );
            } elsif ( $entry->{'type'} == 1 ) {
                show_address_group_range( $indent, $entry, $af_name );
            }
        }
    }
}

sub show_address_group_cmd {
    my ($cmd) = @_;

    for my $dp_id ( sort @{$dp_ids} ) {
        my $sock   = ${$dp_conns}[$dp_id];
        my $indent = 4;

        next unless $sock;

        my $raw_summary = $sock->execute($cmd);

        next if !defined $raw_summary or $raw_summary =~ /^\s*$/;

        my $decoded = decode_json($raw_summary);

        next if !defined $decoded;
        next if !defined $decoded->{'address-group'};

        my $ag = $decoded->{'address-group'};

        printf( "Address-group %s (id %d)\n", $ag->{'name'}, $ag->{'id'} );

        if ( defined $ag->{'ipv4'} ) {
            show_address_group_af( $indent, "IPv4", $ag->{'ipv4'} );
        }
        if ( defined $ag->{'ipv6'} ) {
            show_address_group_af( $indent, "IPv6", $ag->{'ipv6'} );
        }
    }
    printf("\n");
}

sub show_address_group {
    my ( $name, $brief ) = @_;
    my @grp_list;

    @grp_list = address_group_list($name);
    if ( @grp_list == 0 ) {
        return;
    }

    foreach my $n (@grp_list) {
        my $cmd = "npf-op fw show address-group";

        if ( $opt_af ne "all" ) {
            $cmd = "$cmd af=$opt_af";
        }

        if ( $opt_list ne "list-only" ) {
            $cmd = "$cmd list=$opt_list";
        }

        if ( $opt_tree ne "none" ) {
            $cmd = "$cmd tree=$opt_tree";
        }

        $cmd = "$cmd name=$n";

        show_address_group_cmd($cmd);
    }
}

#
# Show all entries for one address-group
#
sub show_detail {
    my $brief = 0;

    show_address_group( $opt_name, $brief );
}

#
# Show a list of address-groups
#
sub show_summary {
    my @grp_list;

    @grp_list = address_group_list("all");
    if ( @grp_list == 0 ) {
        return;
    }

    foreach my $name (@grp_list) {
        printf( "%s\n", $name );
    }
}

#
# Show list of optimal prefixes for an address-group
#
sub show_optimal {
    if ( $opt_af eq "all" ) {
        return;
    }

    my @grp_list;

    @grp_list = address_group_list($opt_name);

    # Empty list?
    if ( @grp_list == 0 ) {
        return;
    }

    foreach my $name (@grp_list) {
        my $cmd = "npf-op fw show address-group optimal af=$opt_af name=$name";
        show_address_group_cmd($cmd);
    }
}
