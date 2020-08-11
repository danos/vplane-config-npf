#!/usr/bin/env python3
#
# Copyright (c) 2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

import socket


#
# class ProtocolTable
#
class ProtocolTable:
    """Create a table from /etc/protocols

    Table is indexed with a protocol number.
    """

    def __init__(self):
        self._protocol_names = {}
        with open('/etc/protocols', 'r') as f:
            for line in f:
                proto_data, _, _ = line.partition('#')
                if not proto_data:
                    continue
                fields = proto_data.split()
                if len(fields) > 2:
                    self._protocol_names[int(fields[1])] = fields[0]

    def __getitem__(self, protocol_number):
        name = self._protocol_names.get(protocol_number)
        if name is None:
            name = "Unassigned"
        return name


# Global proto_table
proto_table = []


#
# num2proto
#
def num2proto(pnum):
    """Protocol number to name"""

    # Look for the common ones first
    if pnum == 6:
        return "tcp"
    elif pnum == 17:
        return "udp"
    elif pnum == 1:
        return "icmp"
    elif pnum == 58:
        # Use the short form of icmp-ipv6 when appropriate
        return "icmpv6"

    # Get cached proto table, else create new one
    global proto_table
    if not bool(proto_table):
        proto_table = ProtocolTable()

    pname = proto_table[pnum]

    # If not found, return the number as a string
    if pname == "Unassigned":
        return str(pnum)

    return pname


#
# proto2num
#
def proto2num(name):
    """Protocol name or number to number.  (This is similar to the C
    function getprotoent used by perl in FWHelper.pm)
    """

    # Ignore 'ip' and 'ipv6'.  These are listed in /etc/protocols but are not
    # protocols in the sense that we want to use this function.
    if name in ('ip', 'ipv6'):
        return 0

    # Some likely protocol values
    proto2num = {
        'icmp': 1,
        'tcp': 6,
        'udp': 17,
        'ipv6-icmp': 58
    }

    if name.isdigit():
        # Already a number?
        return int(name)

    if name in proto2num:
        # Common protocol?
        return proto2num[name]

    # else uncommon protocol
    try:
        return socket.getprotobyname(name)
    except socket.error:
        return 0
