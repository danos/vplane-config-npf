#!/usr/bin/env python3

# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

"""
Unit-tests for the res_grp_provisioner.py module.
"""

from unittest.mock import Mock, MagicMock

import pytest

from vyatta.res_grp.res_grp_provisioner import Provisioner


TEST_DATA = [
    (
        # test_input
        {
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
        },
        # expected_result
        [
            (
                'resources group dscp-group group-a dscp',
                'npf-cfg add dscp-group:group-a 0 0;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15',
                'ALL',
                'SET'
            ),
            (
                'resources group dscp-group group-b dscp',
                'npf-cfg add dscp-group:group-b 0 16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31',
                'ALL',
                'SET'
            ),
            (
                'resources group dscp-group group-c dscp',
                'npf-cfg add dscp-group:group-c 0 32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47',
                'ALL',
                'SET'
            ),
            (
                'resources group dscp-group group-d dscp',
                'npf-cfg add dscp-group:group-d 0 48;49;50;51;52;53;54;55;56;57;58;59;60;61;62;63',
                'ALL',
                'SET'
            ),
            (
                'qos commit',
                'qos commit',
                'ALL',
                'SET'
            )
        ]
    )
]


@pytest.mark.parametrize("test_input, expected_result", TEST_DATA)
def test_provisioner(test_input, expected_result):
    """ Simple unit-test for the provisioner class """
    # Mock up a dataplane context manager
    mock_dataplane = MagicMock()
    mock_dataplane.__enter__.return_value = mock_dataplane

    # Mock up a controller class
    attrs = {
        'get_dataplanes.return_value': [mock_dataplane],
        'store.return_value': 0
    }
    ctrl = Mock(**attrs)

    prov = Provisioner({}, test_input)
    assert prov is not None
    # prov.commands writes the resources group config commands to the mocked
    # controller
    prov.commands(ctrl)
    for call_args in expected_result:
        ctrl.store.assert_any_call(*call_args)
