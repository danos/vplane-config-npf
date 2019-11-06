#! /usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2013-2017, Brocade Communications Systems, Inc.
# All Rights Reserved
#
# SPDX-License-Identifier: GPL-2.0-only
#
#
#  Disabling and enabling of ALGs is done independent of configuring
#  of ports and programs.

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';

use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::FWHelper qw(get_vrf_default_id is_vrf_available);

# Vyatta config
my ( $config, $module, $vrf, $level );

my $ctrl = Vyatta::VPlaned->new();

GetOptions(
    "module=s" => \$module,
    "vrfid:s"  => \$vrf
);

my $vrf_id = get_vrf_default_id();

if ( is_vrf_available() ) {
    $vrf_id =
      ( $vrf ne "" )
      ? Vyatta::VrfManager::get_vrf_id($vrf)
      : get_vrf_default_id();
}

if ( $vrf eq "" ) {
    $config = Vyatta::Config->new();
} else {
    $config = Vyatta::Config->new("routing routing-instance $vrf");
}

#
# Enable/disable
#
# Only send a single enable/disable
#
my $new = $config->exists("system alg $module disable");
my $old = $config->existsOrig("system alg $module disable");

if ( $new && !$old ) {
    $ctrl->store(
        "system alg $module $vrf_id",
        "npf-cfg fw alg $vrf_id disable $module",
        "ALL", "SET"
    );
}

if ( !$new && $old ) {
    $ctrl->store(
        "system alg $module $vrf_id", "npf-cfg fw alg $vrf_id enable $module",
        "ALL",                        "DELETE"
    );
}

# icmp and pptp only have enable/disable
if ( $module eq "icmp" || $module eq "pptp" || $module eq "rsh" ) {
    exit 0;
}

#
# The following only have cntl ports.
#
if ( $module eq "sip" || $module eq "ftp" || $module eq "tftp" ) {
    update_leaf_list( 'port', $module, $config, $ctrl, $vrf_id );
}

#
# RPC has programs.
#
if ( $module eq "rpc" ) {
    update_leaf_list( 'program', $module, $config, $ctrl, $vrf_id );
}

# Generic routine to delete/add a list of items.
# We only send what changed - those deleted, and those added.
sub update_leaf_list {
    my ( $node, $module, $config, $ctrl, $vrf_id ) = @_;
    my @old     = $config->returnOrigValues("system alg $module $node");
    my @curr    = $config->returnValues("system alg $module $node");
    my %lcurr   = map { $_ => 1 } @curr;
    my %lold    = map { $_ => 1 } @old;
    my @deleted = grep ( !$lcurr{$_}, @old );
    my @new     = grep ( !$lold{$_}, @curr );

    # Remove any deleted items.
    foreach my $item (@deleted) {
        $ctrl->store(
            "system alg $module $node $vrf_id $item",
            "npf-cfg fw alg $vrf_id delete $module $node $item",
            "ALL", "DELETE"
        );
    }

    # Send all new items.
    foreach my $item (@new) {
        $ctrl->store(
            "system alg $module $node $vrf_id $item",
            "npf-cfg fw alg $vrf_id set $module $node $item",
            "ALL", "SET"
        );
    }
}
