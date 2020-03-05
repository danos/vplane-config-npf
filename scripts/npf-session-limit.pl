#! /usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (c) 2017, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

# Session policy config

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::Npf::Warning qw(npf_warn_if_intf_doesnt_exist);

my $config = new Vyatta::Config;

my ( $cmd, $type, $name, $low, $high );

my $param_cmd_pfx = "npf-cfg fw session-limit param";

#
# set up command dispatch tables
#
my %cmds_group = ( "assign" => \&cmd_assign_group, );

my %cmds_param = (
    "update" => \&cmd_update_param,
    "delete" => \&cmd_delete_param,
);

my %cmds_global = (
    "update" => \&cmd_update_global,
    "delete" => \&cmd_delete_global,
    "assign" => \&cmd_assign_global,
);

GetOptions(
    "cmd=s"  => \$cmd,
    "type=s" => \$type,
    "name=s" => \$name,
    "low=s"  => \$low,
    "high=s" => \$high,
);

my $ctrl = new Vyatta::VPlaned;

die "Missing --cmd=<cmd> option\n"
  if ( !defined($cmd) );

die "Missing --type=<type> option\n"
  if ( !defined($type) );

sub error_cmd {
    die "$0: Unknown command: $cmd\n";
}

# dispatch to run the function associated with the command passed in
if ( $type eq 'group' ) {
    ( $cmds_group{$cmd} || error_cmd )->();
}

if ( $type eq 'param' ) {
    ( $cmds_param{$cmd} || error_cmd )->();
}

if ( $type eq 'global' ) {
    ( $cmds_global{$cmd} || error_cmd )->();
}

exit(0);

#
# Add or update session limit parameter
#
sub cmd_update_param {

    die "A command needs provided with the --name=<name> option\n"
      if ( !defined($name) );

    my $cfg_pfx;

    if ( $name eq "global" ) {
        $cfg_pfx = "system session limit global";
    } else {
        $cfg_pfx = "system session limit parameter name $name";
    }

    if (  !$config->existsOrig("$cfg_pfx")
        && $config->exists("$cfg_pfx") )
    {
        $ctrl->store( "$cfg_pfx", "$param_cmd_pfx add name $name",
            undef, "SET" );
    }

    #
    # max-halfopen
    #
    if ( $config->exists("$cfg_pfx max-halfopen") ) {
        my ( $max, $orig_max );

        # Get current values
        #
        $max = $config->returnValue("$cfg_pfx max-halfopen");

        #
        # Does max-halfopen node exist?
        #
        if ( !$config->existsOrig("$cfg_pfx max-halfopen") ) {
            $ctrl->store(
                "$cfg_pfx max-halfopen",
                "$param_cmd_pfx add name $name maxhalfopen $max",
                undef, "SET"
            );
        } else {
            #
            # max-halfopen node already exists.  Check if parameters have
            # changed.
            #
            $orig_max = $config->returnOrigValue("$cfg_pfx max-halfopen");

            if ( $orig_max != $max ) {
                $ctrl->store(
                    "$cfg_pfx max-halfopen",
                    "$param_cmd_pfx add name $name maxhalfopen $max",
                    undef, "SET"
                );
            }
        }
    } elsif ( $config->existsOrig("$cfg_pfx max-halfopen") ) {
        $ctrl->store(
            "$cfg_pfx max-halfopen",
            "$param_cmd_pfx delete name $name maxhalfopen",
            undef, "DELETE"
        );
    }

    #
    # rate-limit
    #
    if ( $config->exists("$cfg_pfx rate-limit") ) {
        my ( $limit, $orig_limit, $burst, $orig_burst );

        # Get current values
        #
        $limit = $config->returnValue("$cfg_pfx rate-limit rate");
        $burst = $config->returnValue("$cfg_pfx rate-limit burst");

        #
        # Does rate-limit node exist?
        #
        if ( !$config->existsOrig("$cfg_pfx rate-limit") ) {
            $ctrl->store(
                "$cfg_pfx rate-limit rate",
                "$param_cmd_pfx add name $name "
                  . "ratelimit rate $limit burst $burst",
                undef,
                "SET"
            );
        } else {
            #
            # rate-limit node already exists.  Check if parameters have
            # changed.
            #
            $orig_limit = $config->returnOrigValue("$cfg_pfx rate-limit rate");

            $orig_burst = $config->returnOrigValue("$cfg_pfx rate-limit burst");

            if ( $orig_limit != $limit || $orig_burst != $burst ) {
                $ctrl->store(
                    "$cfg_pfx rate-limit rate",
                    "$param_cmd_pfx add name $name "
                      . "ratelimit rate $limit burst $burst",
                    undef,
                    "SET"
                );
            }
        }
    } elsif ( $config->existsOrig("$cfg_pfx rate-limit") ) {

        $ctrl->store(
            "$cfg_pfx rate-limit",
            "$param_cmd_pfx delete name $name ratelimit",
            undef, "DELETE"
        );
    }
}

#
# Delete session limit parameter
#
sub cmd_delete_param {

    die "A command needs provided with the --name=<name> option\n"
      if ( !defined($name) );

    my $cfg_pfx;

    if ( $name eq "global" ) {
        $cfg_pfx = "system session limit global";
    } else {
        $cfg_pfx = "system session limit parameter name $name";
    }

    if ( $config->existsOrig("$cfg_pfx max-halfopen")
        && !$config->exists("$cfg_pfx maxhalfopen") )
    {
        $ctrl->store(
            "$cfg_pfx max-halfopen",
            "$param_cmd_pfx delete name $name maxhalfopen",
            undef, "DELETE"
        );
    }

    if ( $config->existsOrig("$cfg_pfx rate-limit")
        && !$config->exists("$cfg_pfx rate-limit") )
    {
        $ctrl->store(
            "$cfg_pfx rate-limit",
            "$param_cmd_pfx delete name $name ratelimit",
            undef, "DELETE"
        );
    }

    if ( $config->existsOrig("$cfg_pfx")
        && !$config->exists("$cfg_pfx") )
    {
        $ctrl->store( "$cfg_pfx", "$param_cmd_pfx delete name $name",
            undef, "DELETE" );
    }
}

sub cmd_commit {
    $ctrl->store( "dummy path", "npf-cfg commit", undef, "DELETE" );
}

# Assign the list of interface in a session limiter group
#
sub cmd_assign_group {
    die "A command needs provided with the --name=<name> option\n"
      if ( !defined($name) );

    my $cfg_pfx   = "system session limit group name " . $name;
    my $do_commit = 0;

    my @original = $config->listOrigNodes("$cfg_pfx interface");
    my @proposed = $config->listNodes("$cfg_pfx interface");

    foreach my $intf (@original) {
        if ( $config->existsOrig("$cfg_pfx interface $intf")
            && !$config->exists("$cfg_pfx interface $intf") )
        {
            $ctrl->store(
                "$cfg_pfx interface $intf",
"npf-cfg detach interface:$intf session-rproc session-limiter:$name",
                undef,
                "DELETE"
            );
            $do_commit = 1;
        }
    }

    foreach my $intf (@proposed) {
        if (  !$config->existsOrig("$cfg_pfx interface $intf")
            && $config->exists("$cfg_pfx interface $intf") )
        {
            npf_warn_if_intf_doesnt_exist($intf);
            $ctrl->store(
                "$cfg_pfx interface $intf",
"npf-cfg attach interface:$intf session-rproc session-limiter:$name",
                undef,
                "SET"
            );
            $do_commit = 1;
        }
    }

    if ($do_commit) {
        cmd_commit();
    }
}

sub cmd_update_global {
    my $cfg_pfx = "system session limit global";
    my $add_rs  = 0;

    if (  !$config->existsOrig("$cfg_pfx")
        && $config->exists("$cfg_pfx") )
    {
        $add_rs = 1;
    }

    #
    # Update parameter 'global'
    #
    $name = "global";
    cmd_update_param();

    #
    # Create a ruleset ('global') with a default rule for the global session
    # limiter parameter 'global'
    #
    if ($add_rs) {
        $ctrl->store(
            "$cfg_pfx ruleset",
"npf-cfg add session-limiter:global 10000 handle=session-limiter(parameter=global)",
            undef,
            "SET"
        );
        cmd_commit();
    }
}

sub cmd_delete_global {
    my $cfg_pfx = "system session limit global";

    if ( $config->existsOrig("$cfg_pfx") && !$config->exists("$cfg_pfx") ) {
        #
        # Remove the global session limiter ruleset
        #
        $ctrl->store(
            "$cfg_pfx ruleset", "npf-cfg delete session-limiter:global",
            undef,              "DELETE"
        );
        cmd_commit();
    }

    #
    # Delete parameter 'global'
    #
    $name = "global";
    cmd_delete_param();

}

sub cmd_assign_global {
    my $cfg_pfx = "system session limit global";

    if ( $config->existsOrig("$cfg_pfx") && !$config->exists("$cfg_pfx") ) {

        $ctrl->store(
            "$cfg_pfx attach",
            "npf-cfg detach global: session-rproc session-limiter:global",
            undef,
            "DELETE"
        );
        cmd_commit();
    }

    if ( !$config->existsOrig("$cfg_pfx") && $config->exists("$cfg_pfx") ) {

        $ctrl->store(
            "$cfg_pfx attach",
            "npf-cfg attach global: session-rproc session-limiter:global",
            undef,
            "SET"
        );
        cmd_commit();
    }
}
