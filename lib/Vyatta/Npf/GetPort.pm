#
# Copyright (c) 2017-2019, AT&T Intellectual Property. All rights reserved.
# Copyright (C) 2012-2017, Brocade Communications Systems, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

use strict;
use warnings;

package Vyatta::Npf::GetPort;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(get_port_name get_port_num);

# looks up ports and stores information in arrays, if not done already
my %port_num_to_name;
my %port_name_to_num;

sub _store_ports {
    return if %port_num_to_name;
    while ( ( my $name, my $aliases, my $num, my $proto ) = getservent() ) {
        $port_num_to_name{$num} = "$name"
          unless defined( $port_num_to_name{$num} );
        $port_name_to_num{"$name"} = $num
          unless defined( $port_name_to_num{"$name"} );
    }
}

# converts a port number to a name - returns undef if not found
sub get_port_name {
    _store_ports();
    return $port_num_to_name{ $_[0] };
}

# converts a port name to a number - returns undef if not found
sub get_port_num {
    _store_ports();
    return $port_name_to_num{ $_[0] };
}

1;
