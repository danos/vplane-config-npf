#!/usr/bin/env python3
#
# Copyright (c) 2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
Config for General Packet Classifier
"""

import logging

from vyatta_resources_gpc_vci.group import Group

LOG = logging.getLogger('GPC VCI')

RES_NAMESPACE = "vyatta-resources-v1"
GPC_NAMESPACE = "vyatta-resources-packet-classifier-v1"


class GpcConfig:
    """
    A class to represent the GPC configuration.
    """
    def __init__(self, new_config, old_config):
        """ Initialise config object """
        self._groups = {}
        self._modified_groups = []

        old_group_names = self._get_group_names_from_config(old_config)
        groups = self._build_groups_from_config(new_config)

        for name in groups:
            if name in old_group_names:
                self._modified_groups.append(name)

        self._groups = groups

    def _get_group_config(self, cfg_dict):
        """ Get the group config """
        group_list = None

        if cfg_dict is not None:
            res_dict = cfg_dict.get(f"{RES_NAMESPACE}:resources")
            if res_dict is not None:
                gpc_dict = res_dict.get(f"{GPC_NAMESPACE}:packet-classifier")
                if gpc_dict is not None:
                    group_list = gpc_dict.get('group')

        return group_list

    def _get_group_names_from_config(self, cfg_dict):
        """ Get a list of group names from config"""
        names = []
        group_list = self._get_group_config(cfg_dict)

        if group_list is not None:
            for group_dict in group_list:
                names.append(group_dict['group-name'])

        return names

    def _build_groups_from_config(self, cfg_dict):
        """ Build a dictionary of groups """
        groups = {}

        group_list = self._get_group_config(cfg_dict)

        if group_list is not None:
            for group_dict in group_list:
                group = Group(group_dict)
                groups[group.name] = group

        return groups

    @property
    def modified_groups(self):
        """Retrieve a list of modified groups """
        return self._modified_groups

    def get_group(self, group_name):
        """ Retrieve a group by name """
        return self._groups.get(group_name)
