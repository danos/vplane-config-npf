#! /usr/bin/perl

# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2017, Brocade Communications Systems, Inc.
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
use Vyatta::Config;
use Vyatta::FWHelper qw(get_proto_name);
use Vyatta::VrfManager qw(get_vrf_id get_vrf_name get_vrf_list);

my $fabric;
my ( $dp_ids, $dp_conns, $local_controller ) =
  Vyatta::Dataplane::setup_fabric_conns($fabric);

my ( $opt_type, $opt_name, $opt_action );

# set up actions dispatch table
my %actions = (
    "clear"    => \&clear,
);

#
# type   - all, halfopen, ratelimit
#
GetOptions(
    "type=s"   => \$opt_type,
    "name=s"   => \$opt_name,
    "action=s" => \$opt_action,
);

if ( not defined $opt_name ) {
    $opt_name = "all";
}

die "Missing --action=<action> option\n"
  if ( !defined($opt_action) );

die "Missing --type=<type> option\n"
  if ( !defined($opt_type) );

# dispatch action
( $actions{$opt_action} )->();

# Close down ZMQ sockets. This is needed or sometimes a hang
# can occur due to timing issues with libzmq - see VRVDR-17233 .
Vyatta::Dataplane::close_fabric_conns( $dp_ids, $dp_conns );

exit 0;

sub clear_param {
    my $name = shift;
    my $cmd = "npf-op fw clear session-limit name $name";

    vplane_exec_cmd( $cmd, $dp_ids, $dp_conns, 0 );
}

# npf-op clear all: session-rproc
sub clear_group {
    my $name = shift;
    my $cmd = "npf-op clear all: session-rproc";

    vplane_exec_cmd( $cmd, $dp_ids, $dp_conns, 0 );
}

sub clear {
    if ( $opt_type eq 'all' or $opt_type eq 'param' ) {
        clear_param( $opt_name );
    }
    if ( $opt_type eq 'all' or $opt_type eq 'group' ) {
        clear_group( $opt_name );
    }
}
