#! /usr/bin/perl
#
# Copyright (c) 2017-2019, AT&T Intellectual Property. All rights reserved.
# Copyright (C) 2012-2015 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

# Note that this script handles both Firewall and PBR npf configuration.
# Some of the command values will only be passed in for Firewall, e.g.
# "update-global-default".

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::FWHelper
  qw(get_rules_mod get_rules_del build_rule build_app_rule get_port_num
  get_proto_num is_vrf_available);
use Vyatta::DSCP qw(str2dscp);

my $config = new Vyatta::Config;

my $main_table_id = 254;  # The main routing table. See /etc/iproute2/rt_tables.
my $default_rule_number = 10000;

my ( $variant, $cmd, $group, $dir, $interface, $intf_type, $set_type,
    $set_name, $commit );

# set up command dispatch table
my %cmds = (
    "update-default"            => \&cmd_update_default,
    "update-global-table-size"  => \&cmd_update_fw_global_table_size,
    "update-global-tcp-strict"  => \&cmd_update_fw_global_tcp_strict,
    "update-global-default"     => \&cmd_update_fw_global_default,
    "update-global-icmp-strict" => \&cmd_update_fw_global_icmp_strict,
    "update"                    => \&cmd_update,
    "delete-group"              => \&cmd_delete_group,
    "commit"                    => \&cmd_commit,
    "no-match-action"           => \&cmd_no_match_action,
);

# application group name to prefix conversions
my %app_group2prefix = (
    'name'     => '_N',
    'protocol' => '_P',
    'type'     => '_T',
);

GetOptions(
    "variant=s"   => \$variant,
    "cmd=s"       => \$cmd,
    "group=s"     => \$group,
    "dir=s"       => \$dir,
    "interface=s" => \$interface,
    "intf-type=s" => \$intf_type,
    "set-type=s"  => \$set_type,
    "set-name=s"  => \$set_name,
    "commit"      => \$commit,
);

my $ctrl = new Vyatta::VPlaned;

my $rule_group_class;
my $config_prefix;
my @npf_if_types;
my %if_prefixes_ruleset;

if ( defined $variant ) {
    if ( $variant eq "firewall" ) {
        $config_prefix    = 'security firewall name';
        $rule_group_class = 'fw';

        %if_prefixes_ruleset = (
            'firewall in'    => 'fw-in',
            'firewall out'   => 'fw-out',
            'firewall l2'    => 'bridge',
            'firewall local' => 'local',
        );
    } elsif ( $variant eq "route" ) {
        $config_prefix    = 'policy route pbr';
        $rule_group_class = 'pbr';

        %if_prefixes_ruleset = ( 'policy route pbr' => 'pbr', );
    } elsif ( $variant eq "app-firewall" ) {
        $config_prefix    = 'security application firewall name';
        $rule_group_class = 'app-firewall';

        %if_prefixes_ruleset = ();
    } elsif ( $variant eq "session-limiter" ) {
        $config_prefix    = 'system session limit group name';
        $rule_group_class = 'session-limiter';
    } elsif ( $variant eq "app" ) {
        $config_prefix    = 'service';
        $rule_group_class = 'app';

        %if_prefixes_ruleset = ();
    } else {
        die "Unknown variant: $variant\n";
    }
}

die "A command needs provided with the --cmd=<cmd> option\n"
  if ( !defined($cmd) );

sub error_cmd {
    die "$0: Unknown command: $cmd\n";
}

# dispatch to run the function associated with the command passed in
( $cmds{$cmd} || error_cmd )->();

# Finally, execute an optional "commit".
$cmds{"commit"}->() if ( defined $commit );

# The following are functions handling the various commands

sub cmd_update_default {

    # get default action, e.g. security firewall name <name> default-action drop
    my $action = $config->returnValue("$config_prefix $group default-action");
    my $log    = $config->exists("$config_prefix $group default-log");

    if ( !defined($action) and !defined($log) ) {
        $ctrl->store(
            "$config_prefix $group default-action",
            "npf-cfg delete $rule_group_class:$group $default_rule_number ",
            undef, "DELETE"
        );
        return;
    }

    my $rule;
    if ( defined($action) ) {
        $rule = "action=$action ";
    } else {
        $rule = "action=drop ";
    }
    $rule .= "rproc=log "
      if defined($log);

    $ctrl->store(
        "$config_prefix $group default-action",
        "npf-cfg add $rule_group_class:$group $default_rule_number $rule",
        undef, "SET"
    );
}

sub cmd_no_match_action {

    # get action on no rule match, i.e. security application firewall name
    #    no-match-action drop|accept
    my $action = $config->returnValue("$config_prefix $group no-match-action");

    if ( !defined($action) || $action eq "drop" ) {
        $ctrl->store(
            "$config_prefix $group no-match-action",
            "npf-cfg delete $rule_group_class:$group $default_rule_number",
            undef, "DELETE"
        );
        return;
    }

    $ctrl->store(
        "$config_prefix $group no-match-action",
"npf-cfg add $rule_group_class:$group $default_rule_number no-match-action=accept",
        undef,
        "SET"
    );
}

sub cmd_update_fw_global_table_size {
    my $t_size = $config->returnValue("system session table-size");
    $t_size = '0'
      if ( !defined($t_size) );    # set to default if deleted.
    $ctrl->store(
        "system session table-size", "session-cfg sessions-max $t_size",
        undef,                       "SET"
    );
}

sub cmd_update_fw_global_tcp_strict {
    if ( $config->exists("security firewall tcp-strict") ) {
        $ctrl->store(
            "security firewall tcp-strict",
            "npf-cfg fw global tcp-strict enable",
            undef, "SET"
        );
    } else {
        $ctrl->store(
            "security firewall tcp-strict",
            "npf-cfg fw global tcp-strict disable",
            undef, "DELETE"
        );
    }
}

sub cmd_update_fw_global_icmp_strict {
    if ( $config->exists("security firewall icmp-strict") ) {
        $ctrl->store(
            "security firewall icmp-strict",
            "npf-cfg fw global icmp-strict enable",
            undef, "SET"
        );
    } else {
        $ctrl->store(
            "security firewall icmp-strict",
            "npf-cfg fw global icmp-strict disable",
            undef, "DELETE"
        );
    }
}

sub cmd_update_fw_global_default {

    # Need to resend all the rules again (so the state behavior can be toggled).

    foreach my $name ( $config->listNodes("$config_prefix") ) {
        foreach my $rule ( $config->listNodes("$config_prefix $name rule") ) {

            # ignore disabled rules
            next
              if ( $config->exists("$config_prefix $name rule $rule disable") );

            # only allow rules will be modified
            my $action =
              $config->returnValue("$config_prefix $name rule $rule action");
            if ( defined($action) && $action =~ /accept/ ) {

                #iterate over group
                my $rules = "npf-cfg add $rule_group_class:$name $rule ";

                #now build of single group with rules...
                $rules .= build_rule("$config_prefix $name rule $rule");

                my $cmd = join( ' ', $rules );

                #Have to override node action here since this operates
                #on another collection of nodes
                $ctrl->store( "$config_prefix $name rule $rule",
                    $cmd, undef, "SET" );
            }
        }
    }
}

# This function updates the automatically generated application firewall
# groups, by checking which are required based on the original firewall
# rules and the candidate firewall rules
#
# Note: the "show firewall" command re-formats the names of the generated
# firewall application groups. If the format changes then the function
# format_npf_match in file vyatta-dp-npf-show-rules many need to be updated.
sub update_generated_app_fw_groups {
    my $rprefix = "$config_prefix $group rule";
    my ( %old_groups, %new_groups );

    # Look to see if "session application name/protocol/type" is being
    # used by existing rules, and note the applications/types being matched.
    foreach my $r ( $config->listOrigNodes("$rprefix") ) {
        foreach my $appvariant ( keys %app_group2prefix ) {
            my $val;
            if ( $appvariant eq 'type' ) {
                $val = $config->returnOrigValue(
                    "$rprefix $r session application $appvariant");
            } else {
                $val = (
                    $config->listOrigNodes(
                        "$rprefix $r session application $appvariant")
                )[0];
            }
            $old_groups{$appvariant}{$val} = 1
              if ( defined($val) );
        }
    }

    # Look to see if "session application name/protocol/type" is being
    # used by candidate rules, and note the applications/types being matched.
    foreach my $r ( $config->listNodes("$rprefix") ) {
        foreach my $appvariant ( keys %app_group2prefix ) {
            my $val;
            if ( $appvariant eq 'type' ) {
                $val = $config->returnValue(
                    "$rprefix $r session application $appvariant");
            } else {
                $val = (
                    $config->listNodes(
                        "$rprefix $r session application $appvariant")
                )[0];
            }
            $new_groups{$appvariant}{$val} = 1
              if ( defined($val) );
        }
    }

    my $key_prefix   = "security application firewall name";
    my $d_cmd_prefix = "npf-cfg delete app-firewall:";

    # remove firewall application groups we did have and are no longer used
    foreach my $appvariant ( keys %app_group2prefix ) {
        foreach my $val ( keys %{ $old_groups{$appvariant} } ) {
            if ( !defined( $new_groups{$appvariant}{$val} ) ) {
                my $appfw = "$app_group2prefix{$appvariant}${group}+$val";
                $ctrl->store(
                    "$key_prefix $appfw", "$d_cmd_prefix$appfw",
                    undef,                "DELETE"
                );
            }
        }
    }

    my $a_cmd_prefix = "npf-cfg add app-firewall:";

    # add firewall application groups which are new
    foreach my $appvariant ( keys %app_group2prefix ) {
        foreach my $val ( keys %{ $new_groups{$appvariant} } ) {
            if ( !defined( $old_groups{$appvariant}{$val} ) ) {
                my $appfw = "$app_group2prefix{$appvariant}${group}+$val";
                $ctrl->store(
                    "$key_prefix $appfw rule $default_rule_number",
"$a_cmd_prefix$appfw $default_rule_number action=accept $appvariant=$val",
                    undef,
                    "SET"
                );
            }
        }
    }
}

sub del_old_table_mappings {
    my $r = shift;

    # pbr "accept" action needs a table id
    if ( $variant eq "route" ) {
        my $pbr_table;
        my $vrf;
        my $action =
          $config->returnOrigValue("$config_prefix $group rule $r action");

        if ( defined($action) && $action eq "accept" ) {
            $pbr_table =
              $config->returnOrigValue("$config_prefix $group rule $r table");
            $pbr_table = $main_table_id
              if !defined($pbr_table) || $pbr_table eq "main";
            $vrf = $config->returnOrigValue(
                "$config_prefix $group rule $r routing-instance");
        }

        # Ignore errors that are expected on the routing domain model
        # and suppress the table number that appears in stdout with
        # the upstream VRF model.
        system(
"/opt/vyatta/sbin/vrf-manager --del-table $vrf $pbr_table > /dev/null 2>&1"
        ) if is_vrf_available() && defined($vrf) && defined($pbr_table);
    }
}

sub cmd_update {
    my $check_for_warnings = 0;
    my @rules = get_rules_del( $config, "$config_prefix $group rule" );
    foreach my $r (@rules) {
        del_old_table_mappings($r);

        $ctrl->store(
            "$config_prefix $group rule $r",
            "npf-cfg delete $rule_group_class:$group $r",
            undef, "DELETE"
        );
    }

    #if the rule has been disabled then ignore any update to it
    @rules = get_rules_mod( $config, "$config_prefix $group rule" );
    foreach my $r (@rules) {
        del_old_table_mappings($r);

        if ( $config->exists("$config_prefix $group rule $r disable") ) {
            $ctrl->store(
                "$config_prefix $group rule $r",
                "npf-cfg delete $rule_group_class:$group $r",
                undef, "DELETE"
            );
        } else {

            #iterate over group
            my $rules = "npf-cfg add $rule_group_class:$group $r ";
            my $kernel_table;

            # pbr "accept" action needs a table id
            if ( $variant eq "route" ) {
                my $pbr_table;
                my $action =
                  $config->returnValue("$config_prefix $group rule $r action");
                if ( defined($action) && $action eq "accept" ) {
                    $pbr_table = $config->returnValue(
                        "$config_prefix $group rule $r table");
                    if ( !defined($pbr_table) || $pbr_table eq "main" ) {
                        $pbr_table = $main_table_id;
                    } else {
                        die "pbr table value must be in the range 1-128\n"
                          if ( $pbr_table < 1 or $pbr_table > 128 );
                    }
                }

                my $vrf = $config->returnValue(
                    "$config_prefix $group rule $r routing-instance");
                if ( is_vrf_available() && defined($vrf) && defined($pbr_table) ) {
                    system(
    "/opt/vyatta/sbin/vrf-manager --add-table $vrf $pbr_table > /dev/null 2>&1"
                    );
                    $kernel_table =
                      `/opt/vyatta/sbin/getvrftable --pbr-table $vrf $pbr_table`;
                } else {

                    # If VRF isn't available then getvrftable isn't
                    # available, but we can rely on the identity mapping
                    # for the default VRF
                    $kernel_table = $pbr_table
                      if defined($pbr_table);
                }
            }

            if ( $variant eq "app-firewall" ) {
                $rules .= build_app_rule( "$config_prefix $group rule $r",
                    $kernel_table );
            } else {
                $rules .=
                  build_rule( "$config_prefix $group rule $r", $kernel_table );
                $check_for_warnings = 1
                  if (index($rules, " stateful=y ") != -1);
            }
            my $cmd = join( ' ', $rules );
            $ctrl->store( "$config_prefix $group rule $r", $cmd, undef, "SET" );
        }
    }

    update_generated_app_fw_groups;

    system( "end-npf-interfaces", "--ruleset-warnings" )
      if $check_for_warnings;
}

sub cmd_delete_group {
    if ( $variant eq "route" ) {
        my @rules = $config->listOrigNodes("$config_prefix $group rule");
        foreach my $r (@rules) {
            del_old_table_mappings($r);
        }
    }

    $ctrl->store(
        "$config_prefix $group", "npf-cfg delete $rule_group_class:$group",
        undef,                   "DELETE"
    );

    update_generated_app_fw_groups;
}

sub cmd_commit {
    $ctrl->store( "npf-cfg commit", "npf-cfg commit", undef, "SET" );
}
