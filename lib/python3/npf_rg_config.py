#!/usr/bin/env python3
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
The module that defines the RgConfig class.
"""

from vyatta.npf.dscp_group import DscpGroup


class RgConfig:
    """
    A class to represent all the chunks of Resources Group config.
    """
    def __init__(self, config_dict):
        """ Create a RgConfig object """
        self._dscp_groups = {}

        try:
            res_dict = config_dict['vyatta-resources-v1:resources']
            misc_dict = res_dict['vyatta-resources-group-misc-v1:group']
            dscp_group_list = misc_dict['vyatta-resources-dscp-group-v1:dscp-group']
            self._process_dscp_groups(dscp_group_list)

        except KeyError:
            pass

    def _process_dscp_groups(self, dscp_group_list):
        """ Process the dscp-group list to create dscp-group objects """
        for dscp_group_dict in dscp_group_list:
            dscp_group = DscpGroup(dscp_group_dict)
            self._dscp_groups[dscp_group.name] = dscp_group

    @property
    def dscp_groups(self):
        """ Return the dictionary of dscp-groups, keyed by name. """
        return self._dscp_groups

    def get_dscp_group(self, name):
        """ Return the specified dscp-group, or None if it doesn't exist. """
        return self._dscp_groups.get(name)
