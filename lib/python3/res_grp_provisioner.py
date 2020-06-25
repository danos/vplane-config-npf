#!/usr/bin/env python3
#
# Copyright (c) 2020, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
The module that defines the Provisioner class of the resources group epheremal
VCI module.
"""

import logging

from vyatta.res_grp.res_grp_config import ResGrpConfig

LOG = logging.getLogger('Resources Group ephemeral VCI service')


class Provisioner:
    """
    The Provisioner class determines what has changed between two different
    configurations.  New objects that didn't exist in the old configuration
    are added to the _obj_create list.   Objects that existed in the old
    configuration, but don't exist in the new configuration are added to the
    _obj_delete list.  For existing objects that have been modified by the new
    configurartion, the old objects are added to the _obj_delete list and the
    new objects are added to the _obj_create list.
    """
    def __init__(self, old, new):
        """ Create a provisioner object """
        self._obj_delete = []
        self._obj_create = []

        old_config = ResGrpConfig(old)
        new_config = ResGrpConfig(new)

        self._check_dscp_groups(old_config, new_config)

    def _check_dscp_groups(self, old_config, new_config):
        """ Check for any changes to dscp-groups """
        for dscp_group in new_config.dscp_groups.values():
            old_dscp_group = old_config.get_dscp_group(dscp_group.name)
            if old_dscp_group is not None:
                # We have an existing dscp-group, has it changed?
                if dscp_group != old_dscp_group:
                    # It has changed, delete the old, create the new
                    self._obj_delete.append(old_dscp_group)
                    self._obj_create.append(dscp_group)
            else:
                # We have a new dscp-group
                self._obj_create.append(dscp_group)

        for dscp_group in old_config.dscp_groups.values():
            new_dscp_group = new_config.get_dscp_group(dscp_group.name)
            if new_dscp_group is None:
                # Delete the old dscp-group
                self._obj_delete.append(dscp_group)

    def _delete_objects(self, ctrl):
        """ Delete any old objects. """
        for dataplane in ctrl.get_dataplanes():
            with dataplane:
                for obj in self._obj_delete:
                    (path, cmd) = obj.delete_cmd()
                    ctrl.store(path, cmd, "ALL", "DELETE")
                    LOG.debug(f"delete {cmd}")

    def _create_objects(self, ctrl):
        """ Create any new or modified objects. """
        for dataplane in ctrl.get_dataplanes():
            with dataplane:
                for obj in self._obj_create:
                    for (path, cmd) in obj.commands():
                        ctrl.store(path, cmd, "ALL", "SET")
                        LOG.debug(f"set {cmd}")

    def _qos_commit(self, ctrl):
        """
        Send a 'qos commit' to the dataplane to tell QoS that it needs to
        re-evaluate any resources groups that it refers to
        """
        for dataplane in ctrl.get_dataplanes():
            with dataplane:
                ctrl.store("qos commit", "qos commit", "ALL", "SET")
                LOG.debug("set qos commit")

    def commands(self, ctrl):
        """
        Write the necessary commands to vplaned's cstore to delete, modify
        and create the required resources group objects
        """
        self._delete_objects(ctrl)
        self._create_objects(ctrl)
        self._qos_commit(ctrl)
