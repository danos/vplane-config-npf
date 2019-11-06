#! /usr/bin/perl

# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
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

my ( $dp_ids, $dp_conns, $local_controller );

sub usage {
    print "Usage: $0 --id=index\n";
    print "       $0 --all\n";
    print "       $0 --src=saddr[:sport]\n";
    print "       $0 --dst=daddr[:dport]\n";
    exit 1;
}

my ( $index, $all, $src, $dst, $fabric );

GetOptions(
    'id=s'  => \$index,
    'all'   => \$all,
    'src=s' => \$src,
    'dst=s' => \$dst,
) or usage();

( $dp_ids, $dp_conns, $local_controller ) =
  Vyatta::Dataplane::setup_fabric_conns($fabric);

if ( defined($index) ) {
    vplane_exec_cmd( "session-op clear session id $index", $dp_ids, $dp_conns, 0 );
} elsif ( defined($src) || defined($dst) ) {
    my $filt = "";
    if ( defined($src) ) {
        my @ele = split( ":", $src );
        if ( defined( $ele[0] ) ) {
            $filt .= "saddr $ele[0] ";
        } else {
            $filt .= "saddr any ";
        }

        if ( defined( $ele[1] ) ) {
            $filt .= "sport $ele[1] ";
        } else {
            $filt .= "sport any ";
        }
    } else {
        $filt .= "saddr any sport any ";
    }

    if ( defined($dst) ) {
        my @ele = split( ":", $dst );
        if ( defined( $ele[0] ) ) {
            $filt .= "daddr $ele[0] ";
        } else {
            $filt .= "daddr any ";
        }

        if ( defined( $ele[1] ) ) {
            $filt .= "dport $ele[1] ";
        } else {
            $filt .= "dport any ";
        }
    } else {
        $filt .= "daddr any dport any";
    }
    vplane_exec_cmd( "session-op clear session filter $filt",
        $dp_ids, $dp_conns, 0 );
} elsif ( defined($all) ) {
    vplane_exec_cmd( "session-op clear session all", $dp_ids, $dp_conns, 0 );
}
exit 0;
