#!/usr/bin/env python3
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#

import pprint


class NpfDebug:
    """Handles printing debug information if debug is enabled"""

    def __init__(self, level=0, pprinter=None):
        self._level = level
        self._assign_pprinter(pprinter)

    def _assign_pprinter(self, pprinter):
        if pprinter is None:
            self._pprinter = pprint.PrettyPrinter(indent=2)
        else:
            self._pprinter = pprinter

    @property
    def level(self):
        return self._level

    @level.setter
    def level(self, value):
        self._level = value

    @property
    def pprinter(self):
        return self._pprinter

    @pprinter.setter
    def pprinter(self, value):
        self._assign_pprinter(value)

    def enable(self):
        self.level = 1

    def disable(self):
        self.level = 0

    def is_enabled(self):
        return self.level > 0

    def pprint(self, msg, min_level=1):
        if self.level >= min_level:
            self.pprinter.pprint(msg)
