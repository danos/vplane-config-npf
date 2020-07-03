#!/usr/bin/env python3
#
# Copyright (c) 2019-2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
The module that defines the resources group epheremal VCI module.
"""

import argparse
import json
import logging
import logging.handlers
import sys
import traceback

from systemd.journal import JournalHandler

from vplaned import Controller, ControllerException

from vyatta.res_grp.res_grp_provisioner import Provisioner

RESOURCES_GROUP_CONFIG_FILE = '/etc/vyatta/res-grp.json'


def get_saved_config():
    """ Try to return a JSON configuration file """
    config = {}
    try:
        with open(RESOURCES_GROUP_CONFIG_FILE) as json_data:
            config = json.load(json_data)

    except OSError:
        pass

    except json.JSONDecodeError:
        LOG.error(f"Failed to decode JSON config file {RESOURCES_GROUP_CONFIG_FILE}")

    return config


def save_new_config(config):
    """ Save the JSON configuration to the config file """
    with open(RESOURCES_GROUP_CONFIG_FILE, "w") as write_file:
        write_file.write(json.dumps(config, indent=4, sort_keys=True))


def start():
    """ Start the daemon listening on the Dbus """
    LOG.debug("res-grp-vci:start")
    return 0


def stop():
    """ Stop the daemon listening on the Dbus """
    LOG.debug("res-grp-vci:stop")
    return 0


def validate():
    """ Validate the new configuration """
    LOG.debug("res-grp-vci:validate")
    # Nothing to do Yang provides all the validation needed for dscp-groups
    return 0


def commit():
    """
    Use the Provisioner class to compare the new configuration against the
    previously saved configuration, and then call prov.commands to
    write dataplane configuration commands to the vplane-controller.
    If successful, save the new configuration so that we can compare against
    it the next time the configuration changes.
    """
    LOG.debug("res-grp-vci:commit")
    new_config = json.load(sys.stdin)
    old_config = get_saved_config()
    prov = Provisioner(old_config, new_config)
    try:
        with Controller() as ctrl:
            prov.commands(ctrl)
            save_new_config(new_config)
            status = 0

    except ControllerException:
        LOG.error(f"Failed to connect to vplane-controller: {sys.exc_info()[0]}")
        traceback.print_exc()
        status = 1

    return status


def get_config():
    """
    Return the last saved configuration.
    """
    LOG.debug("res-grp-vci:get-config")
    config = get_saved_config()
    print(f"{config}")
    return 0


def get_state():
    """ Return any op-mode state, current resources group has none. """
    LOG.debug("res-grp-vci:get-state")
    print("{}")
    return 0


FUNCTION_DICT = {
    "start": start,
    "stop": stop,
    "validate": validate,
    "commit": commit,
    "get-config": get_config,
    "get-state": get_state
}

if __name__ == "__main__":
    try:
        PARSER = argparse.ArgumentParser(description='Resources Group ephemeral VCI Service')
        PARSER.add_argument('--action', action='store', help='The requested action')
        PARSER.add_argument('--debug', action='store_true', help='Enable debugging')
        ARGS = PARSER.parse_args()
        logging.root.addHandler(JournalHandler(SYSLOG_IDENTIFIER='vyatta-res-grp-vci'))
        LOG = logging.getLogger('Resources Group ephermal VCI service')

        if ARGS.debug:
            LOG.setLevel(logging.DEBUG)
            LOG.debug("Debug enabled")

        RESULT = FUNCTION_DICT[ARGS.action]()

    except Exception:
        traceback.print_exc()
        LOG.error(f"Unexpected error: {sys.exc_info()[0]}")
        RESULT = 1

    sys.exit(RESULT)
