#! /usr/bin/perl
#
# Copyright (c) 2018-2019, AT&T Intellectual Property. All rights reserved.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::FWHelper qw(get_rules_mod get_rules_del);
use Vyatta::Npf::Warning qw(npf_warn_if_intf_doesnt_exist);

my $config = new Vyatta::Config;
my ( $cmd, $name, $interface );

# set up command dispatch table
my %cmds = (
    "nptv6-xlt" => \&cmd_nptv6_xlt,
    "nptv6-int" => \&cmd_nptv6_int,
);

GetOptions(
    "cmd=s"       => \$cmd,
    "name=s"      => \$name,
    "interface=s" => \$interface,
);

my $ctrl = new Vyatta::VPlaned;

die "A command needs provided with the --cmd=<cmd> option\n"
  if ( !defined($cmd) );

sub error_cmd {
    die "$0: Unknown command: $cmd\n";
}

# dispatch to run the function associated with the command passed in
( $cmds{$cmd} || error_cmd )->();

# NPTv6 translator config
sub cmd_nptv6_xlt {
    return if ( !defined($name) );

    my $group         = "nptv6";
    my $config_prefix = "service nat $group name $name";

    my $inside  = $config->returnValue("$config_prefix inside");
    my $outside = $config->returnValue("$config_prefix outside");

    if ( defined($inside) && defined($outside) ) {
        my $rulenum = 10;
        my $icmp =
          $config->exists("$config_prefix disable-translation-icmp-errors")
          ? ",icmperr=no"
          : "";

        $ctrl->store(
            "$config_prefix out",
            "npf-cfg add $group-out:$name $rulenum src-addr=$inside handle=nptv6(inside=$inside,outside=$outside$icmp)",
            undef,
            "SET"
        );
        $ctrl->store(
            "$config_prefix in",
            "npf-cfg add $group-in:$name $rulenum dst-addr=$outside handle=nptv6(inside=$inside,outside=$outside$icmp)",
            undef,
            "SET"
        );
    }
    else {
        $ctrl->store(
            "$config_prefix out", "npf-cfg delete $group-out:$name",
            undef,
            "DELETE"
        );
        $ctrl->store(
            "$config_prefix in", "npf-cfg delete $group-in:$name",
            undef,
            "DELETE"
        );
    }
}

# NPTv6 interface config
sub cmd_nptv6_int {
    return if ( !defined($interface) );

    my $group         = "nptv6";
    my $config_prefix = "service nat $group interface $interface translator";

    my @xltrs = get_rules_del( $config, "$config_prefix" );
    foreach my $xlt (@xltrs) {
        $ctrl->store(
            "$config_prefix $xlt out",
            "npf-cfg detach interface:$interface $group-out $group-out:$xlt",
            undef,
            "DELETE"
        );
        $ctrl->store(
            "$config_prefix $xlt in",
            "npf-cfg detach interface:$interface $group-in $group-in:$xlt",
            undef,
            "DELETE"
        );
    }

    @xltrs = get_rules_mod( $config, "$config_prefix" );

    npf_warn_if_intf_doesnt_exist($interface)
      if ( @xltrs );

    foreach my $xlt (@xltrs) {
        $ctrl->store(
            "$config_prefix $xlt out",
            "npf-cfg attach interface:$interface $group-out $group-out:$xlt",
            undef,
            "SET"
        );
        $ctrl->store(
            "$config_prefix $xlt in",
            "npf-cfg attach interface:$interface $group-in $group-in:$xlt",
            undef,
            "SET"
        );
    }
}
