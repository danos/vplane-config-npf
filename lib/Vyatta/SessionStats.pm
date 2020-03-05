#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2015 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
use strict;
use warnings;

package Vyatta::SessionStats;
require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(merge_rsp);

sub new {
    my $type = shift;
    my $self = shift;

    return bless $self, $type;
}

sub merge_rsp {
    my $self      = shift;
    my $new_entry = shift;
    my $stats     = $self->{config}->{sessions}->{statistics};
    my $new_stats = $new_entry->{config}->{sessions}->{statistics};

    $stats->{max}  += $new_stats->{max};
    $stats->{used} += $new_stats->{used};
    $stats->{nat}  += $new_stats->{nat};

    $stats->{tcp}->{syn_sent}     += $new_stats->{tcp}->{syn_sent};
    $stats->{tcp}->{syn_received} += $new_stats->{tcp}->{syn_received};
    $stats->{tcp}->{established}  += $new_stats->{tcp}->{established};
    $stats->{tcp}->{fin_wait}     += $new_stats->{tcp}->{fin_wait};
    $stats->{tcp}->{close_wait}   += $new_stats->{tcp}->{close_wait};
    $stats->{tcp}->{last_ack}     += $new_stats->{tcp}->{last_ack};
    $stats->{tcp}->{time_wait}    += $new_stats->{tcp}->{time_wait};
    $stats->{tcp}->{closed}       += $new_stats->{tcp}->{closed};
    $stats->{tcp}->{closing}      += $new_stats->{tcp}->{closing};

    $stats->{udp}->{new}         += $new_stats->{udp}->{new};
    $stats->{udp}->{established} += $new_stats->{udp}->{established};
    $stats->{udp}->{closed}      += $new_stats->{udp}->{closed};

    $stats->{other}->{new}         += $new_stats->{other}->{new};
    $stats->{other}->{established} += $new_stats->{other}->{established};
    $stats->{other}->{closed}      += $new_stats->{other}->{closed};

    return;
}
