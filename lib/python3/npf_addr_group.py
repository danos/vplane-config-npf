#!/usr/bin/env python3

#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

import vplaned


#
# Show an npf address-group
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
# "hc0w + hc1w + hc2w" should equal "ac0w + ac1w + ac2w" if the right side of
# column 2 is to line-up.
#
# All parameters except for the group name are optional.  If only the name
# parameter is specified then the output will look as follows:
#
# Address-group ADDR_GRP_CGNAT1 (0)
#     Prefix         10.10.1.0/28
#     Address        10.10.1.10
#     Address        10.10.1.11
#     Address-range  10.10.1.20 to 10.10.1.30
#
def npf_show_address_group(name, af=None, hc1="Address-group",
                           hc0w=0, hc1w=0, hc2w=0,
                           ac0w=4, ac1w=14, ac2w=0):
    """For displaying an npf address-group"""

    # Dataplane does not currently support fetching more than one
    # address-group at a time
    if not name:
        return

    # Prepare the dataplane command
    cmd = "npf-op fw show address-group"

    # For when 'name' is optional
    if name:
        cmd += " name=%s" % (name)

    if af:
        cmd += " af=%s" % (af)

    # List of dictionaries returned from dataplane (one per address-group)
    ag_list = []

    with vplaned.Controller() as controller:
        for dp in controller.get_dataplanes():
            with dp:
                ag_dict = dp.json_command(cmd)
                if "address-group" in ag_dict:
                    ag_list.append(ag_dict)

    # Headline format specifier
    hfmt = "%*s%-*s %*s"

    # Entry format specifier
    afmt = "%*s%-*s %*s"

    # If no address-groups not returned ...
    if not ag_list:
        name = "%s (-)" % (name)
        print(hfmt % (hc0w, "", hc1w, hc1, hc2w, name))
        return

    for ag in ag_list:
        # Display name and table ID
        name = "%s (%u)" % (ag["address-group"]["name"],
                            ag["address-group"]["id"])

        # Print headline and address-group name
        print(hfmt % (hc0w, "", hc1w, hc1, hc2w, name))

        addr_list = []

        # Get IPv4 entries
        if "ipv4" in ag["address-group"]:
            tmp_list = ag["address-group"]["ipv4"]["list-entries"]
            if tmp_list:
                addr_list.extend(tmp_list)

        # Get IPv6 entries
        if "ipv6" in ag["address-group"]:
            tmp_list = ag["address-group"]["ipv6"]["list-entries"]
            if tmp_list:
                addr_list.extend(tmp_list)

        for addr in addr_list:
            # Type 0 contain prefix and mask, or an address
            if addr["type"] == 0:
                if "mask" in addr:
                    addr_type = "Prefix"
                    val = "%s/%u" % (addr["prefix"], addr["mask"])
                else:
                    addr_type = "Address"
                    val = "%s" % (addr["prefix"])

            # Type 1 is an address range
            elif addr["type"] == 1:
                addr_type = "Address-range"
                val = "%s to %s" % (addr["start"], addr["end"])

            print(afmt % (ac0w, "", ac1w, addr_type, ac2w, val))
