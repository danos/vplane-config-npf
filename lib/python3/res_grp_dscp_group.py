#!/usr/bin/env python3
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
The module that defines the resources group dscp-group class.
"""

DSCP_CMD = "dscp-group"

RG_BASE = "resources group"
BASE_DSCP_PATH = RG_BASE + " " + DSCP_CMD

"""
DSCP name-to-id conversion table
"""
DSCPTABLE = {
    'default': 0,
    'cs0':     0,
    'cs1':     8,
    'cs2':     16,
    'cs3':     24,
    'cs4':     32,
    'cs5':     40,
    'cs6':     48,
    'cs7':     56,
    'af11':    10,
    'af12':    12,
    'af13':    14,
    'af21':    18,
    'af22':    20,
    'af23':    22,
    'af31':    26,
    'af32':    28,
    'af33':    30,
    'af41':    34,
    'af42':    36,
    'af43':    38,
    'ef':      46,
    'va':      44,
}


class DscpGroup:
    """
    A class to represent a dscp-group object.
    """
    def __init__(self, dscp_group_dict):
        """ Create a dscp-group object """
        self._dscp_group_dict = dscp_group_dict
        self._name = dscp_group_dict['group-name']
        self._dscp_values = []
        for dscp_value in dscp_group_dict['dscp']:
            self._dscp_values.append(DSCPTABLE.get(dscp_value, dscp_value))

    def __eq__(self, dscp_group):
        """ Compare the original JSON config dictionary of two dscp-groups """
        return self._dscp_group_dict == dscp_group.dscp_group_dict

    @property
    def name(self):
        """ Return the dscp-group's name """
        return self._name

    @property
    def dscp_values(self):
        """ Return the list of dscp-values assigned to this dscp-group """
        return self._dscp_values

    @property
    def dscp_group_dict(self):
        """ Return the original JSON config dictionary of this dscp-group """
        return self._dscp_group_dict

    def commands(self):
        """
        Generate a list of (path, command) tuples required to create this RG
        dscp-group
        """
        dscp_values = ""
        for dscp in sorted(self._dscp_values, key=int):
            if dscp_values != "":
                dscp_values += ";"

            dscp_values += f"{dscp}"

        path = f"{BASE_DSCP_PATH} {self._name} dscp"
        cmd = f"npf-cfg add dscp-group:{self._name} 0 {dscp_values}"
        return [(path, cmd)]

    def delete_cmd(self):
        """
        Generate the (path, command) tuple required to delete this RG
        dscp-group
        """
        path = f"{BASE_DSCP_PATH} {self._name}"
        cmd = f"npf-cfg delete dscp-group:{self._name}"
        return path, cmd
