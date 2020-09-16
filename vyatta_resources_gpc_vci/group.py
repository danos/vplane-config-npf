#!/usr/bin/env python3
#
# Copyright (c) 2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
General Packet Classifier Group - a group of classification rules
"""
import logging

import sys
sys.path.append('/usr/lib/python3/dist-packages/vyatta/proto')
from vyatta.proto import GPCConfig_pb2
from vyatta_resources_gpc_vci.rule import Rule

LOG = logging.getLogger('GPC VCI')


class Group:
    """
    A group of classification rules.
    """
    def __init__(self, group_config):
        """ Initialise group object """

        self._name = group_config['group-name']
        self._results = group_config['results']
        self._rules = []
        self._pb_message = GPCConfig_pb2.Rules()
        if group_config.get('ip-version') == "ipv4":
            self._pb_message.traffic_type = GPCConfig_pb2.IPV4
        else:
            self._pb_message.traffic_type = GPCConfig_pb2.IPV6

        rules_list = group_config.get('rule')
        if rules_list is not None:
            for rule_dict in rules_list:
                # Skip disabled rules
                if 'disable' in rule_dict.keys():
                    continue
                self._rules.append(Rule(rule_dict, self._pb_message))

    @property
    def name(self):
        return self._name

    def pb_message(self):
        LOG.debug(f"MESSAGE {self._pb_message}")
        return self._pb_message.SerializeToString()
