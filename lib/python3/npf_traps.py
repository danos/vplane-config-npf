#!/usr/bin/env python3

#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
# Note this currently uses a perl function, but n future could be changed
# to be native python. It does a check for npf traps being enabled first,
# to save calling the perl program if they are not enabled.

import sys
import subprocess
from vyatta import configd

TRAP_PATH = "security firewall config-trap"


def err(msg):
    print(msg, file=sys.stderr)


def npf_traps_enabled(dbg=None):
    try:
        client = configd.Client()
    except Exception as exc:
        err("Cannot establish client session: '{}'".format(str(exc).strip()))
        return False

    try:
        value = client.node_get(configd.Client.AUTO, TRAP_PATH)
    except configd.Exception as exc:
        if dbg:
            dbg.pprint("cannot get node {} : {}".format(TRAP_PATH,
                       str(exc).strip()))
        return False

    if dbg:
        dbg.pprint("\'{}\' value is \'{}\'".format(TRAP_PATH, value[0]))

    return value[0] == "enable"


def send_npf_snmp_traps(paths, dbg=None):
    """ send SNMP traps for changes under the given paths, if traps
        are enabled """

    final_retcode = 0

    if not npf_traps_enabled(dbg):
        return 0

    for path in paths:
        params = ['/opt/vyatta/sbin/vyatta-dp-npf-snmptrap.pl',
                  '--level=' + path]

        if dbg and dbg.is_enabled():
            params.append("--debug")

        retcode = subprocess.run(params)
        # Disable debug below, as it causes error "vbash: syntax error near
        # unexpected token `('" due to configd passing it to bash for
        # processing
        if False and dbg:
            dbg.pprint("send_npf_snmp_traps: {}".format(retcode))

        if retcode != 0:
            final_retcode = retcode

    return final_retcode
