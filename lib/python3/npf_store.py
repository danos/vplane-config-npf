#!/usr/bin/env python3
#
# Copyright (c) 2019-2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

from vplaned import Controller


def store_cfg(key, command, action, dbg=None, intf="ALL"):
    with Controller() as ctrl:
        if dbg:
            dbg.pprint("store_cfg: key: {}; cmd: {}; "
                       "action: {}; interface: {}"
                       .format(key, command, action, intf))
        ctrl.store(key, command, action=action, interface=intf)


def dataplane_commit(dbg):
    store_cfg("npf-cfg commit", "npf-cfg commit", "SET", dbg)
