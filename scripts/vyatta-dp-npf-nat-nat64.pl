#! /usr/bin/perl
#
# Copyright (c) 2018-2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2012-2016 Vyatta, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use lib '/opt/vyatta/share/perl5';
use warnings;
use POSIX;
use Set::Scalar;
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use NetAddr::IP;
use Vyatta::Npf::Warning qw(npf_warn_if_intf_doesnt_exist);

# Vyatta config
my $config = new Vyatta::Config;

# main
#
my $type;

# Old nat64 config did not use group names.  This is the default name given
# to old-style nat64 config when used with the new dataplane nat64.
# It is suffixed with the interface name, e.g. "_NAT64_dp0p1s1"
#
my $old_group_pfx = "_NAT64";

GetOptions( "type=s" => \$type, );

my $ctrl = new Vyatta::VPlaned;

#
# Get the sets of current and proposed rule numbers.
# Then determine who was deleted if any
#
my $level = "service nat $type rule";
my @curr  = $config->listOrigNodes($level);
my @prop  = $config->listNodes($level);

# $current and $proposed contain sets of rule numbers
my $current  = Set::Scalar->new(@curr);
my $proposed = Set::Scalar->new(@prop);

# set of rules in $current but not in $proposed (i.e. rules being deleted)
my $deleted = $current - $proposed;

# set of rules in $current and also in $proposed (i.e. rules being changed)
my $changed = $current * $proposed;

# Iterate through the deleted rules.
while ( defined( my $d = $deleted->each ) ) {
    if ( $type =~ /ipv6-to-ipv4/ ) {
        process_nat6to4( "delete", $d );
    }
}

# Iterate through the changed rules.
while ( defined( my $c = $changed->each ) ) {

    # If a rule is being changed and the interface is different, then need
    # to delete the old rule.
    if ( $type =~ /ipv6-to-ipv4/ ) {
        delete_rule_diff_if( $type, "nat64", $c, "inbound-interface" );
    }
}

# Add the changed and new rules
while ( defined( my $p = $proposed->each ) ) {
    if ( $type =~ /ipv6-to-ipv4/ ) {
        process_nat6to4( "add", $p );
    }
}

exit 0;

sub delete_rule_diff_if {
    my ( $type, $gclass, $rule_num, $if_dir ) = @_;

    my $path   = "service nat $type rule $rule_num $if_dir";
    my $old_if = $config->returnOrigValue($path);
    my $new_if = $config->returnValue($path);

    if ( $old_if ne $new_if ) {
        delete_rule( $type, $gclass, $rule_num );
    }
}

sub delete_rule {
    my ( $type, $gclass, $rule_num ) = @_;

    my $level = "service nat $type rule $rule_num ";

    my $iface = $config->returnOrigValue( $level . "inbound-interface" );

    if ( !defined($iface) ) {
        return;
    }

    # Default group name for converting old nat64 config to use new nat64
    my $group = $old_group_pfx . "_" . $iface;

    $ctrl->store(
        "nat nat6to4 rule $rule_num interface $iface",
        "npf-cfg detach interface:$iface nat64 nat64:$group",
        undef, "DELETE"
    );
    $ctrl->store(
        "nat nat6to4 rule $rule_num", "npf-cfg delete nat64:$group $rule_num",
        undef,                        "DELETE"
    );
}

#
# Funct to handle nat6to4 configuration
#
# Basically needs to build up a command like:
#     npf-cfg add nat64:dp0p3p1 100 src-addr=2001:db8:4::/96
#                                   dst-addr=2001:db8:5::/96"
#
sub process_nat6to4 {
    my $op       = $_[0];
    my $rule_num = $_[1];

    my $level = "service nat ipv6-to-ipv4 rule $rule_num ";
    if ( $op =~ /add/ ) {
        my $to_prefix   = $config->returnValue( $level . "destination prefix" );
        my $from_prefix = $config->returnValue( $level . "source prefix" );
        my $iface       = $config->returnValue( $level . "inbound-interface" );

        npf_warn_if_intf_doesnt_exist($iface);

        #prefixes can only have the following masks:
        #32, 40, 48, 56, 64, or 96

        my $to_pref   = new NetAddr::IP($to_prefix);
        my $from_pref = new NetAddr::IP($from_prefix);

        my $spl = $from_pref->masklen();
        my $dpl = $to_pref->masklen();

        # Default group name for converting old nat64 config to use new nat64
        my $group = $old_group_pfx . "_" . $iface;

        $ctrl->store(
            "nat nat6to4 rule $rule_num",
"npf-cfg add nat64:$group $rule_num src-addr=$from_prefix dst-addr=$to_prefix handle=nat64(stype=rfc6052,spl=$spl,dtype=rfc6052,dpl=$dpl)",
            undef,
            "SET"
        );
        $ctrl->store(
            "nat nat6to4 rule $rule_num interface $iface",
            "npf-cfg attach interface:$iface nat64 nat64:$group",
            undef, "SET"
        );
    }
    elsif ( $op =~ /delete/ ) {
        my $iface = $config->returnOrigValue( $level . "inbound-interface" );

        # Default group name for converting old nat64 config to use new nat64
        my $group = $old_group_pfx . "_" . $iface;

        $ctrl->store(
            "nat nat6to4 rule $rule_num interface $iface",
            "npf-cfg detach interface:$iface nat64 nat64:$group",
            undef, "DELETE"
        );
        $ctrl->store(
            "nat nat6to4 rule $rule_num",
            "npf-cfg delete nat64:$group $rule_num",
            undef, "DELETE"
        );
    }
}
