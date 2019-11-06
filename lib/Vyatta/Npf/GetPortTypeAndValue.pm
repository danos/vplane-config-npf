#
# Copyright (c) 2017-2019, AT&T Intellectual Property. All rights reserved.
# Copyright (C) 2012-2017, Brocade Communications Systems, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';

package Vyatta::Npf::GetPortTypeAndValue;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(get_port_type_and_value);

use Vyatta::Npf::GetPort qw(get_port_num);

# Takes parameter 'source' or 'destination' and gives the type
# and value for the current rule. For type it returns "Port", "Port-range",
# "Services", "Port-group", "Not-exist".
sub get_port_type_and_value {
    my ( $config, $src_dst ) = @_;
    my $port_val = $config->{$src_dst}->{"port"};

    return ( "Not-exist", $port_val )
      if ( !defined($port_val) );
    return ( "Port", $port_val )
      if ( $port_val =~ /^[0-9]+$/ );
    if ( $port_val =~ /^([0-9]+)-([0-9]+)$/ ) {
        return ( "Port-range", $port_val )
          if ( $1 >= 1 && $1 <= 65535 && $2 >= 1 && $2 <= 65535 );
    }
    my $port_num = get_port_num($port_val);
    return ( "Services", $port_num )
      if ( defined($port_num) );
    return ( "Port-group", $port_val );
}

1;
