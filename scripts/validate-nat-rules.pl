#! /usr/bin/perl
#
# Copyright (c) 2018-2019, AT&T Intellectual Property.  All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";

use Vyatta::Config;
use Vyatta::Interface;
use Vyatta::SwitchConfig qw(verify_int_is_hw);

my @containers = (
    [ "service nat source",       "outbound-interface" ],
    [ "service nat destination",  "inbound-interface" ],
    [ "service nat ipv6-to-ipv4", "inbound-interface" ]
);

my $failure;
my @cfgifs = map { $_->{name} } Vyatta::Interface::get_interfaces();
my @allmsg;

for my $i ( 0 .. $#containers ) {
    my $cfg = Vyatta::Config->new( $containers[$i][0] );

    foreach my $rule ( $cfg->listNodes("rule") ) {
        my $intf      = "rule $rule $containers[$i][1]";
        my $intf_name = $cfg->returnValue($intf);

        if ( defined($intf_name) ) {
            my ( $msg, $fail, $warn ) =
              verify_int_is_hw( $intf_name, \@cfgifs );
            if ($fail) {
                $failure = 1;
                $msg     = "\n" . $msg;
                push( @allmsg,
                    ( "[$containers[$i][0] $intf $intf_name]", $msg ) );
            }
        }
    }
}

# nptv6 does not easily fit in the above model
my $nat_nptv6 = "service nat nptv6";
my $cfg       = Vyatta::Config->new($nat_nptv6);
foreach my $intf_name ( $cfg->listNodes("interface") ) {
    my ( $msg, $fail, $warn ) = verify_int_is_hw( $intf_name, \@cfgifs );
    if ($fail) {
        $failure = 1;
        $msg     = "\n" . $msg;
        push( @allmsg, ( "$nat_nptv6 interface", $msg ) );
    }
}

if ( scalar @allmsg ) {
    print join( "\n", @allmsg ) . "\n";
}

if ( defined $failure ) {
    exit 1;
}
