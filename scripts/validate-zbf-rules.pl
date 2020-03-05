#! /usr/bin/perl
#
# Copyright (c) 2018-2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5/";

use Vyatta::Config;
use Vyatta::Interface;
use Vyatta::SwitchConfig qw(verify_int_is_hw);

my $failure;
my @cfgifs = map { $_->{name} } Vyatta::Interface::get_interfaces();
my @allmsg;
my $zbf_intf = "security zone-policy zone";
my $cfg      = Vyatta::Config->new($zbf_intf);
foreach my $zone ( $cfg->listNodes() ) {
    foreach my $intf ( $cfg->returnValues("$zone interface") ) {
        if ( defined($intf) ) {
            my ( $msg, $fail, $warn ) = verify_int_is_hw( $intf, \@cfgifs );
            if ($fail) {
                $failure = 1;
                $msg     = "\n" . $msg;
                push( @allmsg, ( "[$zbf_intf $zone interface $intf]", $msg ) );
            }
        }
    }
}

if ( scalar @allmsg ) {
    print join( "\n", @allmsg ) . "\n";
}

if ( defined $failure ) {
    exit 1;
}
