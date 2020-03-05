#
# Copyright (c) 2018-2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

use strict;
use warnings;

package Vyatta::NPTv6Stats;
require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(merge_rsp);

use Data::Dumper;

sub new {
    my ( $type, $self ) = @_;

    bless $self, $type;

    $self->merge_rsp($self);

    return $self;
}

sub merge_rsp {
    my ( $self, $new_entry ) = @_;

    foreach my $attach_point ( @{ $new_entry->{config} } ) {
        foreach my $ruleset ( @{ $attach_point->{rulesets} } ) {
            foreach my $group ( @{ $ruleset->{groups} } ) {
                my %rules = %{ $group->{rules} };
                while ( my ( $rule_name, $rule ) = each(%rules) ) {
                    my $rprocs    = $rule->{rprocs};
                    my $rule_dir  = $rprocs->{nptv6};
                    my $interface = $rule_dir->{interface};
                    my $direction = $rule_dir->{direction};
                    my $name      = $rule_dir->{name};

                    my $tmp_rule = $self->{rule_hash}->{$interface}->{$name};

                    if ( !defined($tmp_rule) ) {
                        my $tmp_intf = $self->{rule_hash}->{$interface};
                        if ( !defined($tmp_intf) ) {
                            $tmp_intf = {};
                            $self->{rule_hash}->{$interface} = $tmp_intf;
                        }

                        $tmp_rule = {
                            'stats_in'  => {},
                            'stats_out' => {},
                            'icmperr'   => 0,
                            'outside'   => $rule_dir->{outside},
                            'inside'    => $rule_dir->{inside}
                        };
                        $tmp_intf->{$name} = $tmp_rule;
                    }

                    my $stats_dir = "stats_$direction";
                    my $tmp_stats = $tmp_rule->{$stats_dir};
                    my $stats     = $rule_dir->{stats};

                    # Correct even when field is not present in JSON
                    $tmp_rule->{icmperr} |= 1
                      if ( $rule_dir->{'icmperr'} );

                    $tmp_stats->{packets} += $stats->{packets};
                    $tmp_stats->{bytes}   += $stats->{bytes};
                    $tmp_stats->{drops}   += $stats->{drops};
                }
            }
        }
    }
}
