#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (C) 2015-2016 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

use strict;
use warnings;

package Vyatta::NpfRuleset;
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
    my $tmp_group;

    foreach my $attach_point ( @{ $new_entry->{config} } ) {
        foreach my $ruleset ( @{ $attach_point->{rulesets} } ) {
            foreach my $group ( @{ $ruleset->{groups} } ) {
                my $interface = $group->{interface};
                $interface = "" if ( !defined($interface) );
                my $key =
"$attach_point->{attach_type},$attach_point->{attach_point},$ruleset->{ruleset_type},$group->{name},$interface";
                $tmp_group = $self->{group_hash}->{$key};
                if ( defined($tmp_group) ) {
                    my %tmp_rules = %{ $tmp_group->{rules} };
                    my %rules     = %{ $group->{rules} };
                    while ( my ( $rule_name, $rule ) = each(%rules) ) {
                        $tmp_rules{$rule_name}->{packets}  += $rule->{packets};
                        $tmp_rules{$rule_name}->{bytes}    += $rule->{bytes};
                        $tmp_rules{$rule_name}->{total_ts} += $rule->{total_ts}
                          if defined( $rule->{total_ts} );
                        $tmp_rules{$rule_name}->{used_ts} += $rule->{used_ts}
                          if defined( $rule->{used_ts} );
                    }
                } else {
                    $self->{group_hash}->{$key} = $group;
                }
            }
        }
    }
}
