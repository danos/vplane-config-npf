#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2015-2016 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
use strict;
use warnings;

package Vyatta::Aggregate;
require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(aggregate_npf_responses);

use JSON qw( decode_json );
use Data::Dumper;

sub aggregate_npf_responses {
    my ( $dp_arr, $dp_responses, $type ) = @_;
    my ( $agg_rsp, $npf_rsp );

    foreach my $dp_id ( @{$dp_arr} ) {
        if ( defined( ${$dp_responses}[$dp_id] ) ) {
            $npf_rsp = ${$dp_responses}[$dp_id];
            if ( $npf_rsp !~ /^\s*$/ ) {
                my $decoded = decode_json($npf_rsp);
                if ( !defined($agg_rsp) ) {
                    $agg_rsp = new $type($decoded);
                } else {
                    $agg_rsp->merge_rsp($decoded);
                }
            }
        }
    }

    return $agg_rsp;
}
