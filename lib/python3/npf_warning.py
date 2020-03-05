#!/usr/bin/env python3
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

import syslog


def npf_config_warning(msg, path=None):
    """For displaying and syslogging a warning relating to configuration"""

    if path is None:
        smsg = msg
    else:
        print("[{}]\n".format(path))
        smsg = "[{}]: {}".format(path, msg)

    print("Warning: {}".format(msg))
    syslog.syslog(syslog.LOG_WARNING, smsg)
