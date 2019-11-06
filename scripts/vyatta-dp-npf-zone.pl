#! /usr/bin/perl

# Copyright (c) 2018-2019, AT&T Intellectual Property. All rights reserved.
# All Rights Reserved.
# Copyright (c) 2012-2015, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Getopt::Long;
use Vyatta::Config;
use Vyatta::VPlaned;
use Vyatta::Npf::Warning qw(npf_warn_if_intf_doesnt_exist);

use Data::Dumper;

# Vyatta config
my $config = new Vyatta::Config;

# Vyatta controller conf cmd utility
my $ctrl = new Vyatta::VPlaned;

my $pfx   = "security zone-policy zone";
my $debug = 0;

my @zones_orig = $config->listOrigNodes($pfx);
my @zones_cur  = $config->listNodes($pfx);

my $old_pass_all_count = 0;
my $new_pass_all_count = 0;

# Calculate old pass-all count, and detach pass-all rulesets
calc_old_pass_all_count( $config, \@zones_orig );

add_zones( $config, \@zones_cur );
del_policies( $config, \@zones_orig );
del_interfaces( $config, \@zones_orig );

add_interfaces( $config, \@zones_cur );
add_policies( $config, \@zones_cur );
del_zones( $config, \@zones_orig );

# Calculate new pass-all count, and attach pass-all rulesets
calc_new_pass_all_count( $config, \@zones_cur );

# Add or delete pass-all ruleset (or neither)
set_zone_pass_all_ruleset();

# Tell the dataplane to rebuild its rulesets
cmd_commit();

exit;

sub store {
    my ( $key, $cmd, $all, $action ) = @_;

    if ($debug) {
        print "Store:\n";
        print "  key: $key\n";
        print "  cmd: $cmd\n";
    }

    $ctrl->store( $key, $cmd, $all, $action );
}

sub cmd_commit {
    store( "npf-cfg commit", "npf-cfg commit", "ALL", "SET" );
}

sub set_zone_pass_all_ruleset {
    if ( $old_pass_all_count == 0 && $new_pass_all_count > 0 ) {
        store(
            "zone-policy pass-all-rule",
            'npf-cfg add fw-internal:pass-all 1 action=accept',
            "ALL", "SET"
        );
    } elsif ( $old_pass_all_count > 0 && $new_pass_all_count == 0 ) {
        store(
            "zone-policy pass-all-rule",
            'npf-cfg delete fw-internal:pass-all 1 action=accept',
            "ALL", "DELETE"
        );
    }
}

#
# Count number of times the pass-all internal rule was applied between a pair
# of zones and is no longer required.
#
sub calc_old_pass_all_count {
    my $config     = $_[0];
    my @zones_orig = @{ $_[1] };

    foreach my $zone (@zones_orig) {
        my $orig_da = $config->returnOrigValue("$pfx $zone default-action");
        my $cur_da  = $config->returnValue("$pfx $zone default-action");

        if ( !defined($orig_da) || $orig_da eq "drop" ) {
            next;
        }

        # orig default-action is 'accept'

        my @to_zones = $config->listOrigNodes("$pfx $zone to");

        foreach my $to_zone (@to_zones) {
            if (   !defined($cur_da)
                || $cur_da eq "drop"
                || !$config->exists("$pfx $zone to $to_zone") )
            {

                $old_pass_all_count += 1;

                my $ap = $zone . ">" . $to_zone;

                store(
                    "zone-policy zone $zone default-action pass-all",
                    "npf-cfg detach zone:$ap zone fw-internal:pass-all",
                    "ALL",
                    "DELETE"
                );
            }
        }
    }
}

#
# Count number of times the pass-all internal rule needs to be applied between
# a pair of zones.
#
sub calc_new_pass_all_count {
    my $config    = $_[0];
    my @zones_cur = @{ $_[1] };

    foreach my $zone (@zones_cur) {
        my $orig_da = $config->returnOrigValue("$pfx $zone default-action");
        my $cur_da  = $config->returnValue("$pfx $zone default-action");

        if ( !defined($cur_da) || $cur_da eq "drop" ) {
            next;
        }

        # Current default-action is 'accept'

        my @to_zones = $config->listNodes("$pfx $zone to");

        foreach my $to_zone (@to_zones) {
            if (   !defined($orig_da)
                || $orig_da eq "drop"
                || !$config->existsOrig("$pfx $zone to $to_zone") )
            {

                $new_pass_all_count += 1;

                my $ap = $zone . ">" . $to_zone;

                store(
                    "zone-policy zone $zone default-action pass-all",
                    "npf-cfg attach zone:$ap zone fw-internal:pass-all",
                    "ALL",
                    "SET"
                );
            }
        }
    }
}

#
# Add new zones
#
sub add_zones {
    my $config    = $_[0];
    my @zones_cur = @{ $_[1] };

    foreach my $zone (@zones_cur) {
        if ( !$config->existsOrig("$pfx $zone") ) {
            store( "$pfx $zone", "npf-cfg zone add $zone", "ALL", "SET" );
        }

        # Check if local-zone attribute has been added.
        if (  !$config->existsOrig("$pfx $zone local-zone")
            && $config->exists("$pfx $zone local-zone") )
        {
            store(
                "$pfx $zone local-zone", "npf-cfg zone local $zone set",
                "ALL",                   "SET"
            );
        }
    }
}

#
# Delete old zones
#
sub del_zones {
    my $config     = $_[0];
    my @zones_orig = @{ $_[1] };

    foreach my $zone (@zones_orig) {
        if ( !$config->exists("$pfx $zone") ) {
            store( "$pfx $zone", "npf-cfg zone remove $zone", "ALL", "DELETE" );
        } else {

            # Zone has not been deleted.  Check if local-zone attribute has
            # been cleared.
            if ( $config->existsOrig("$pfx $zone local-zone")
                && !$config->exists("$pfx $zone local-zone") )
            {
                store(
                    "$pfx $zone local-zone", "npf-cfg zone local $zone clear",
                    "ALL",                   "DELETE"
                );
            }
        }
    }
}

#
# Add new policies and attach rulesets
#
sub add_policies {
    my $config    = $_[0];
    my @zones_cur = @{ $_[1] };

    foreach my $fm_zone (@zones_cur) {
        my @to_zones = $config->listNodes("$pfx $fm_zone to");

        foreach my $to_zone (@to_zones) {

            my $ap = $fm_zone . ">" . $to_zone;

            #
            # First create empty policies (i.e. without rulesets)
            #
            if ( !$config->existsOrig("$pfx $fm_zone to $to_zone") ) {
                store(
                    "$pfx $fm_zone to $to_zone policy",
                    "npf-cfg zone policy add $fm_zone $to_zone",
                    "ALL", "SET"
                );
            }

            my @orig =
              $config->returnOrigValues("$pfx $fm_zone to $to_zone firewall");
            my @cur =
              $config->returnValues("$pfx $fm_zone to $to_zone firewall");

            #
            # For each firewall in the current config, add it if it
            # does not exist in the orig config or it is *not* in the
            # same position.  We do something similar in del_policies,
            # and so avoid duplicate rulesets.
            #
            for ( my $i = 0 ; $i < @cur ; $i++ ) {
                if ( $i >= @orig || $orig[$i] ne $cur[$i] ) {
                    store(
                        "$pfx $fm_zone to $to_zone firewall $cur[$i]",
                        "npf-cfg attach zone:$ap zone fw:$cur[$i]",
                        "ALL", "SET"
                    );
                }
            }
        }
    }
}

#
# Detach old rulesets and delete policies
#
sub del_policies {
    my $config     = $_[0];
    my @zones_orig = @{ $_[1] };

    foreach my $fm_zone (@zones_orig) {
        my @to_zones = $config->listOrigNodes("$pfx $fm_zone to");

        foreach my $to_zone (@to_zones) {

            my $ap = $fm_zone . ">" . $to_zone;
            my @orig =
              $config->returnOrigValues("$pfx $fm_zone to $to_zone firewall");

            #
            # If the to_zone is not in current config, then delete all
            # firewalls, and delete the policy
            #
            if ( !$config->exists("$pfx $fm_zone to $to_zone") ) {
                foreach my $fw (@orig) {
                    store(
                        "$pfx $fm_zone to $to_zone firewall $fw",
                        "npf-cfg detach zone:$ap zone fw:$fw",
                        "ALL", "DELETE"
                    );
                }

                store(
                    "$pfx $fm_zone to $to_zone policy",
                    "npf-cfg zone policy remove $fm_zone $to_zone",
                    "ALL", "DELETE"
                );
                next;
            }

            my @cur =
              $config->returnValues("$pfx $fm_zone to $to_zone firewall");

            #
            # For each firewall in the orig config, delete it if it
            # does not exist in the current config or it is *not* in
            # the same position.  We do something similar in
            # add_policies, and so avoid duplicate rulesets.
            #
            for ( my $i = 0 ; $i < @orig ; $i++ ) {
                if ( $i >= @cur || $cur[$i] ne $orig[$i] ) {
                    store(
                        "$pfx $fm_zone to $to_zone firewall $orig[$i]",
                        "npf-cfg detach zone:$ap zone fw:$orig[$i]",
                        "ALL",
                        "DELETE"
                    );
                }
            }

            #
            # If there are no rulesets in the current config then
            # delete the policy
            #
            if ( @cur == 0 ) {
                store(
                    "$pfx $fm_zone to $to_zone policy",
                    "npf-cfg zone policy remove $fm_zone $to_zone",
                    "ALL", "DELETE"
                );
            }
        }
    }
}

#
# Add new interfaces
#
sub add_interfaces {
    my $config    = $_[0];
    my @zones_cur = @{ $_[1] };

    foreach my $zone (@zones_cur) {
        my @intfs = $config->returnValues("$pfx $zone interface");

        foreach my $intf (@intfs) {
            if ( !$config->existsOrig("$pfx $zone interface $intf") ) {
                npf_warn_if_intf_doesnt_exist($intf);
                store(
                    "$pfx $zone interface $intf",
                    "npf-cfg zone intf add $zone $intf",
                    "ALL", "SET"
                );
            }
        }
    }
}

#
# Delete old interfaces
#
sub del_interfaces {
    my $config     = $_[0];
    my @zones_orig = @{ $_[1] };

    foreach my $zone (@zones_orig) {
        my @intfs = $config->returnOrigValues("$pfx $zone interface");

        foreach my $intf (@intfs) {
            if ( !$config->exists("$pfx $zone interface $intf") ) {
                store(
                    "$pfx $zone interface $intf",
                    "npf-cfg zone intf remove $zone $intf",
                    "ALL", "DELETE"
                );
            }
        }
    }
}
