#
# Copyright (c) 2017-2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2012-2017, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';

package Vyatta::Npf::ValidateNpfRule;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(validate_npf_rule);

use Vyatta::Npf::GetPortTypeAndValue qw(get_port_type_and_value);

# Handling for both 'source' and 'destination'
my %src_dst_hash = (
    'source'      => 'Source',
    'destination' => 'Destination',
);

# Validates a single NPF rule under FW, PBR, or QoS
# Note that most validation is now done in Yang "must" statements.
# Parameter 1: should be a hash of the configuration on the rule
# Parameter 2: should be at hash at "resources group"
# Parameter 3: should be the path of the nodes
# Parameter 4: should be the error function to call
sub validate_npf_rule {
    my ( $config, $group_config, $node_path, $err_fn ) = @_;

    my %port_type  = ();
    my %port_value = ();

    # For 'source' and 'destination' ports
    for my $src_dst ( keys %src_dst_hash ) {
        ( $port_type{$src_dst}, $port_value{$src_dst} ) =
          get_port_type_and_value( $config, $src_dst );

        $err_fn->(
            $node_path,
"$src_dst_hash{$src_dst} port-group '$port_value{$src_dst}' does not exist"
          )
          if ( $port_type{$src_dst} eq "Port-group"
            && !$group_config->{'group'}->{'port-group'}
            ->{ $port_value{$src_dst} } );
    }

    return;
}

1;
