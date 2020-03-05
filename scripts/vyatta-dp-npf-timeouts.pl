#! /usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2012-2015 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use lib '/opt/vyatta/share/perl5';
use warnings;
use Getopt::Long;
use NetAddr::IP;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::FWHelper qw(build_rule get_vrf_default_id is_vrf_available);
use Module::Load::Conditional qw[can_load];

# Vyatta config
my $config = new Vyatta::Config;

#
# main
#
my ( $cmd, $rule_num, $proto, $state, $timeout, $vrf );

GetOptions(
    "cmd=s"     => \$cmd,
    "rule=s"    => \$rule_num,
    "proto=s"   => \$proto,
    "state=s"   => \$state,
    "timeout=s" => \$timeout,
    "vrf:s"     => \$vrf,
);

my $ctrl = new Vyatta::VPlaned;

my $vrf_id = get_vrf_default_id();

if ( is_vrf_available() ) {
    $vrf_id =
      ( $vrf ne "" )
      ? Vyatta::VrfManager::get_vrf_id($vrf)
      : get_vrf_default_id();
}

# For timeouts
if ( !defined($rule_num) ) {

    # update a timeout.
    if ( $cmd eq "update" ) {
        $ctrl->store(
            "system session timeout $proto $state $vrf_id",
            "npf-cfg fw global timeout $vrf_id update $proto $state $timeout",
            undef,
            "SET"
        );
    }

    # Delete a timeout, send the default value.
    if ( $cmd eq "delete" ) {
        $ctrl->store(
            "system session timeout $proto $state $vrf_id",
            "npf-cfg fw global timeout $vrf_id delete $proto $state $timeout",
            undef,
            "DELETE"
        );
    }
    exit(0);
}

# For rules
if ( $cmd =~ /delete/ ) {
    $ctrl->store(
        "system session timeout custom $rule_num $vrf_id",
        "npf-cfg delete custom-timeout:$vrf_id $rule_num",
        undef, "DELETE"
    );
    exit(0);
}

my $level = "system session timeout custom rule $rule_num";
$level = "routing routing-instance $vrf " . $level
  if ($vrf);
my $expire = $config->returnValue( $level . " expire" );
my $rule = build_rule( $level, $expire, 0);

$ctrl->store(
    "system session timeout custom $rule_num $vrf_id",
    "npf-cfg add custom-timeout:$vrf_id $rule_num $rule",
    undef, "SET"
);

exit(0);
