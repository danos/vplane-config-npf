# Copyright (c) 2018-2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

use strict;
use warnings;

package Vyatta::Npf::Warning;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(npf_config_warning npf_warn_if_intf_doesnt_exist);

use Sys::Syslog qw(:standard :macros);
use Vyatta::Interface;

sub npf_config_warning {
    my ($msg) = @_;

    print "Warning: $msg\n";
    syslog( LOG_WARNING, "%s", $msg );
}

my @existing_interfaces;

sub npf_warn_if_intf_doesnt_exist {
    my ($intf) = @_;

    @existing_interfaces =
      map { $_->{name} } Vyatta::Interface::get_interfaces()
      if ( !@existing_interfaces );

    my $matches = grep { $_ eq $intf } @existing_interfaces;

    npf_config_warning("interface $intf does not exist on this system")
      unless $matches > 0;
}

1;
