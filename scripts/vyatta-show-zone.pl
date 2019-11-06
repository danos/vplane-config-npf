#! /usr/bin/perl

# Copyright (c) 2018-2019, AT&T Intellectual Property. All rights reserved.
# All Rights Reserved.
# Copyright (c) 2012-2015, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Getopt::Long;
use Data::Dumper;

my $config = new Vyatta::Config;

my $zone_in;
my $show_localz = 0;
GetOptions( "zone=s" => \$zone_in, "local-zone" => \$show_localz );

my $format = "  %-40s%-40s\n";

my @zones = $config->listOrigNodes("security zone-policy zone");
for my $zone (@zones) {
    my $is_local = 0;

    if ( defined($zone_in) && $zone_in ne $zone ) {
        next;
    }

    if ( $config->existsOrig("security zone-policy zone $zone local-zone") ) {
        $is_local = 1;
    }
    if ( $show_localz && !$is_local ) {
        next;
    }

    my $desc =
      $config->returnOrigValue("security zone-policy zone $zone description");

    print "-------------------\n";
    print "Name: $zone ";

    if ( $is_local ) {
        print "(local-zone) ";
    }

    if ( defined($desc) ) {
        print "$desc";
    }
    print "\n";

    if ( !$is_local ) {
        my @interfaces =
            $config->returnOrigValues("security zone-policy zone $zone interface");

        print "Interfaces: @interfaces\n";
    } else {
        print "Interfaces: n/a\n";
    }

    print "\n";
    print "To Zone:\n";
    printf( $format, "name", "firewall" );
    printf( $format, "----", "--------" );
    my @to_zones = $config->listOrigNodes("security zone-policy zone $zone to");

    for my $to_zone (@to_zones) {
        my @firewall = $config->returnOrigValues(
            "security zone-policy zone $zone to $to_zone firewall");
        if (@firewall) {
            printf( $format, "$to_zone", "@firewall" );
        } else {
            printf( $format, "$to_zone", "-" );
        }
    }
    print "\n";
}

