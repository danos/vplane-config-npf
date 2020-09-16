#!/usr/bin/env python3
#
# Copyright (c) 2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
The Generic Packet Classifier VCI entrypoint module
"""

import argparse
import logging
import logging.handlers
import json
import sys
from traceback import format_tb
import zmq
import vci

from systemd.journal import JournalHandler

from vyatta_resources_gpc_vci.gpc_config import GpcConfig

LOG = logging.getLogger('GPC VCI')

GPC_CONFIG_FILE = '/etc/vyatta/resources-gpc.json'

RES_NAMESPACE = 'vyatta-resources-v1'
GPC_NAMESPACE = 'vyatta-resources-packet-classifier-v1'
gpc_config = None


def get_config():
    """ Try to return JSON configuration file """
    filename = GPC_CONFIG_FILE
    config = {}
    try:
        with open(filename) as json_data:
            config = json.load(json_data)

    except OSError:
        LOG.info(f"Failed to open JSON config file {filename} "
                 f"{sys.exc_info()[0]}")

    except json.JSONDecodeError:
        LOG.error(f"Failed to decode JSON config file {filename}")

    return config


def save_config(config):
    """ Save the JSON configuration """
    filename = GPC_CONFIG_FILE
    with open(filename, "w") as write_file:
        write_file.write(json.dumps(config, indent=4, sort_keys=True))


class Config(vci.Config):
    """
    The Configuration mode class for GPC VCI
    """
    json_config = {}

    def set(self, new_json_config):
        """
        Do config stuff
        """
        global gpc_config
        LOG.debug(f"Config:set - {new_json_config}")

        if not self.json_config:
            old_json_config = get_config()
        else:
            old_json_config = self.json_config

        try:
            gpc_config = GpcConfig(new_json_config, old_json_config)

            save_config(new_json_config)

        except Exception:
            tb_type = sys.exc_info()[0]
            tb_value = sys.exc_info()[1]
            tb_info = format_tb(sys.exc_info()[2])
            tb_output = ""
            for line in tb_info:
                tb_output += line

            LOG.error(f"Unhandled exception: {tb_type}\n{tb_value}\n"
                      f"{tb_output}")

        self.json_config = new_json_config

    def get(self):
        """ Get current config """
        LOG.debug("Config:get")
        if not self.json_config:
            self.json_config = get_config()

        return self.json_config

    def check(self, proposed_config):
        """ Check anything not checked in yang """
        LOG.debug(f"Config:check - {proposed_config}")


if __name__ == "__main__":
    try:
        PARSER = argparse.ArgumentParser(
            description='Resources GPC VCI Service')
        PARSER.add_argument(
            '--debug', action='store_true', help='Enabled debugging')
        ARGS = PARSER.parse_args()

        logging.root.addHandler(
            JournalHandler(SYSLOG_IDENTIFIER='vyatta-resources-gpc-vci'))
        LOG = logging.getLogger('GPC VCI')

        if ARGS.debug:
            LOG.setLevel(logging.DEBUG)
            LOG.debug("Debug enabled")

        LOG.debug("About to register with VCI")

        # Attempt to load previous config
        saved_json_config = get_config()
        if saved_json_config is not None:
            gpc_config = GpcConfig(saved_json_config, None)

        (vci.Component("net.vyatta.vci.resources.gpc")
         .model(vci.Model("net.vyatta.vci.resources.gpc.v1")
                .config(Config()))
         .run())

        context = zmq.Context()
        rep = context.socket(zmq.REP)
        rep.bind("ipc://tmp/gpc_update.socket")

        while True:
            group_name = rep.recv_string()
            LOG.debug(f"grp req {group_name}")

            reply = b"None"
            if gpc_config is not None:
                group = gpc_config.get_group(group_name)
                if group is not None:
                    reply = group.pb_message()

            rep.send(reply)
            LOG.debug(f"sent grp {group_name}")

    except Exception:
        LOG.error(f"Unexpected error: {sys.exc_info()[0]}")
        tb_type = sys.exc_info()[0]
        tb_value = sys.exc_info()[1]
        tb_info = format_tb(sys.exc_info()[2])
        tb_output = ""
        for line in tb_info:
            tb_output += line

        LOG.error(f"Unhandled exception: {tb_type}\n{tb_value}\n"
                  f"{tb_output}")
