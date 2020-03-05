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
use Vyatta::Config;
use Vyatta::VPlaned;

# Vyatta config
my $config = new Vyatta::Config;

#
# main
#
my ( $cmd, $proto, $state );

GetOptions(
    "cmd=s"   => \$cmd,
    "proto=s" => \$proto,
    "state=s" => \$state,
);

my $ctrl = new Vyatta::VPlaned;

if ( $cmd =~ /enable/ ) {
    $ctrl->store(
        "firewall session-log $proto $state",
        "npf-cfg fw session-log add $proto $state",
        undef, "SET"
    );
} elsif ( $cmd =~ /disable/ ) {
    $ctrl->store(
        "firewall session-log $proto $state",
        "npf-cfg fw session-log remove $proto $state",
        undef, "DELETE"
    );
}
