#!/usr/bin/env python3

# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

"""
Unit-tests for the dscp_group.py module.
"""

import pytest

from vyatta.res_grp.res_grp_dscp_group import DscpGroup

TEST_DATA = [
    (
        # test_input
        {
            'group-name': 'group-a',
            'dscp': ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
                     '11', '12', '13', '14', '15']
        },
        # expected result
        [
            (
                "resources group dscp-group group-a dscp",
                "npf-cfg add dscp-group:group-a 0 0;1;2;3;4;5;6;7;8;9;10;" \
                "11;12;13;14;15"
            )
        ]
    ),
    (
        # test_input
        {
            'group-name': 'group-b',
            'dscp': ['16', '17', '18', '19', '20', '21', '22', '23', '24',
                     '25', '26', '27', '28', '29', '30', '31']
        },
        # expected_result
        [
            (
                "resources group dscp-group group-b dscp",
                "npf-cfg add dscp-group:group-b 0 16;17;18;19;20;21;22;23;" \
                "24;25;26;27;28;29;30;31"
            )
        ]
    ),
    (
        # test_input
        {
            'group-name': 'group-c',
            'dscp': ['32', '33', '34', '35', '36', '37', '38', '39', '40',
                     '41', '42', '43', '44', '45', '46', '47']
        },
        # expected_result
        [
            (
                "resources group dscp-group group-c dscp",
                "npf-cfg add dscp-group:group-c 0 32;33;34;35;36;37;38;39;" \
                "40;41;42;43;44;45;46;47"
            )
        ]
    ),
    (
        # test_input
        {
            'group-name': 'group-d',
            'dscp': ['48', '49', '50', '51', '52', '53', '54', '55', '56',
                     '57', '58', '59', '60', '61', '62', '63']
        },
        # expected_result
        [
            (
                "resources group dscp-group group-d dscp",
                "npf-cfg add dscp-group:group-d 0 48;49;50;51;52;53;54;55;" \
                "56;57;58;59;60;61;62;63"
            )
        ]
    ),
    (
        # test_input
        {
            'group-name': 'group-e',
            'dscp': ['default', 'cs1', 'cs2', 'cs3', 'cs4', 'cs5', 'cs6', 'cs7',
                     'af11', 'af12', 'af13', 'af21', 'af22', 'af23', 'af31',
                     'af32', 'af33', 'af41', 'af42', 'af43', 'ef', 'va']
        },
        # expected_result
        [
            (
                "resources group dscp-group group-e dscp",
                "npf-cfg add dscp-group:group-e 0 0;8;10;12;14;16;18;20;22;" \
                "24;26;28;30;32;34;36;38;40;44;46;48;56"
            )
        ]
    )
]


@pytest.mark.parametrize("test_input, expected_result", TEST_DATA)
def test_profile(test_input, expected_result):
    """ Unit-test the dscp-group class """
    dscp_group = DscpGroup(test_input)
    assert dscp_group is not None
    assert dscp_group.commands() == expected_result
    _, cmd = dscp_group.delete_cmd()
    assert cmd == f"npf-cfg delete dscp-group:{dscp_group.name}"
