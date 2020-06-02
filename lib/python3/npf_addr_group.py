#!/usr/bin/env python3
#
# Copyright (c) 2019-2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

import vplaned


#
# Fetch address-groups from dataplane and show
#
# name - Name of the address-group
# af   - "ipv4", "ipv6" or None (= v4 and v6)
#
# hc1  - Headline col 1 text
# hc0w - Headline col 0 width (i.e. headline indent)
# hc1w - Headline col 1 width (left-justified)
# hc2w - Headline (name) col 2 width (right-justified)
#
# ac0w - Addr entry col 0 width (i.e. indent)
# ac1w - Addr entry col 1 width (left-justified)
# ac2w - Addr entry col 2 width (right-justified)
#
# option - One of:
#          None      Default listing of prefixes and ranges entered by user
#          "detail"  Default listing, but with extra details
#          "brief"   List of address group names
#          "tree"    List prefixes used to program ptree
#          "optimal" Optimal list of prefixes derived from the ptree
#
# "hc0w + hc1w + hc2w" should equal "ac0w + ac1w + ac2w" if the right side of
# column 2 is to line-up.
#
# All parameters are optional.  If only the name parameter is specified then
# the output will be as follows:
#
# Address-group ADDR_GRP_CGNAT1 (0)
#   Prefix         10.10.1.0/28
#   Address        10.10.1.10
#   Address        10.10.1.11
#   Address-range  10.10.1.20 to 10.10.1.30
#
# This is also called from CGNAT to embed specific address-group info inside
# CGNAT show output, e.g. CGNAT policies embed the 'match' address group.
#
def npf_show_address_group(name=None, af=None, option=None,
                           hc1="Address-group",
                           hc0w=0, hc1w=0, hc2w=0,
                           ac0w=2, ac1w=14, ac2w=0):
    """For fetching and displaying one or more address-groups"""

    #
    # Prepare the dataplane command
    #
    cmd = "npf-op fw show address-group"

    if name:
        cmd += " name=%s" % (name)

    if af:
        cmd += " af=%s" % (af)

    if option:
        cmd += " option=%s" % (option)

    # List of address-groups.  May be IPv4, IPv6 or a mix.
    ag_list = []

    with vplaned.Controller() as controller:
        for dp in controller.get_dataplanes():
            with dp:
                rv = dp.json_command(cmd)
                if "address-groups" in rv:
                    ag_list.extend(rv["address-groups"])

    # Exit if no address-groups returned
    if not ag_list:
        return

    for ag in ag_list:
        npf_show_address_group_one(ag, hc1, hc0w, hc1w, hc2w,
                                   ac0w, ac1w, ac2w)


#
# Display one address-group
#
# This is used in two places:
#
#   1. The function npf_show_address_group  (see above) for address group
#      show commands, cgnat policy show commands, and nat pool blacklist, and
#
#   2. Directly from NAT pool show command for displaying hidden address-group
#
# See npf_show_address_group, above, for parameter details.
#
def npf_show_address_group_one(ag, hc1, hc0w=0, hc1w=0, hc2w=0,
                               ac0w=2, ac1w=14, ac2w=0):
    """For displaying one address-group"""

    # Is this an address-group?
    if not ag or "name" not in ag or "id" not in ag:
        return

    #
    # Inner function to display entries in a list.  Entries are either address
    # ranges or prefixes.  This is re-entrant as sub-lists *may* be present
    # for range entries
    #
    def _inner_show_list(ag_list, ac0w, ac1w, ac2w):

        #
        # Entry format specifier.  The three fields are:
        # <indent> <entry type> <entry> for example:
        #
        #   Prefix         10.10.1.0/28
        #
        afmt = "%*s%-*s %*s"

        # For each address-group entry ...
        for ae in ag_list:
            #
            # Type 0 contain a prefix and mask, or an address.  The "Prefix"
            # and "Address" strings mirror the config option used to create
            # the entry.
            #
            if ae["type"] == 0:
                if "mask" in ae:
                    ae_type = "Prefix"
                    val = "%s/%u" % (ae["prefix"], ae["mask"])
                else:
                    ae_type = "Address"
                    val = "%s" % (ae["prefix"])

                print(afmt % (ac0w, "", ac1w, ae_type, ac2w, val))

            #
            # Type 1 is an address range.  This may have a sub-list of
            # prefixes derived from the range.
            #
            elif ae["type"] == 1:
                ae_type = "Address-range"
                val = "%s to %s" % (ae["start"], ae["end"])

                print(afmt % (ac0w, "", ac1w, ae_type, ac2w, val))

                #
                # Has the address-range been broken down into constituent
                # prefixes?
                #
                if "entries" in ae:
                    _inner_show_list(ae["entries"], ac0w+2, ac1w-2, ac2w)

            else:
                print(afmt % (ac0w, "", ac1w, "Unknown", ac2w, ""))

    #
    # Headline format specifier.  The three fields are:
    # <indent> <description> <group name and ID> for example:
    #
    # Address-group SRC_MATCH1 (4)
    #
    # The description is typically just "Address-group", but may be different
    # when displaying an address-group from within another object, e.g. CGNAT
    # blacklist.
    #
    hfmt = "%*s%-*s %*s"

    # Display name and table ID
    name = "%s (%u)" % (ag["name"], ag["id"])

    # Print headline and address-group name and ID
    print(hfmt % (hc0w, "", hc1w, hc1, hc2w, name))

    addr_list = []

    def _inner_get_entries(ag, af):
        if af in ag and "entries" in ag[af]:
            return ag[af]["entries"]
        return []

    #
    # Get the per-address family entries.  Note that an address-group may
    # contain both.
    #
    addr_list.extend(_inner_get_entries(ag, "ipv4"))
    addr_list.extend(_inner_get_entries(ag, "ipv6"))

    # Display the list of entries
    _inner_show_list(addr_list, ac0w, ac1w, ac2w)
