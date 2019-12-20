#!/usr/bin/env python3

# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

"""
Unit-tests for the qos_config.py module.
"""

from vyatta.res_grp.res_grp_config import ResGrpConfig

TEST_DATA = {
    'vyatta-resources-v1:resources': {
        'vyatta-resources-group-misc-v1:group': {
            'vyatta-resources-dscp-group-v1:dscp-group': [
                {
                    'group-name': 'group-a',
                    'dscp': [
                        '0', '1', '2', '3', '4', '5', '6', '7', '8',
                        '9', '10', '11', '12', '13', '14', '15'
                    ]
                }, {
                    'group-name': 'group-b',
                    'dscp': [
                        '16', '17', '18', '19', '20', '21', '22', '23',
                        '24', '25', '26', '27', '28', '29', '30', '31'
                    ]
                }, {
                    'group-name': 'group-c',
                    'dscp': [
                        '32', '33', '34', '35', '36', '37', '38', '39',
                        '40', '41', '42', '43', '44', '45', '46', '47'
                    ]
                }, {
                    'group-name': 'group-d',
                    'dscp': [
                        '48', '49', '50', '51', '52', '53', '54', '55',
                        '56', '57', '58', '59', '60', '61', '62', '63'
                    ]
                }
            ]
        }
    }
}


def test_rgconfig():
    """ Simple unit-test for the ResGrpConfig class """
    config = ResGrpConfig(TEST_DATA)
    assert config is not None
    assert len(config.dscp_groups) == 4
    assert config.get_dscp_group("group-a") is not None
    assert config.get_dscp_group("group-b") is not None
    assert config.get_dscp_group("group-c") is not None
    assert config.get_dscp_group("group-d") is not None
    assert config.get_dscp_group("group-e") is None
