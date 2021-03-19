#!/usr/bin/env python3
#
# Copyright (c) 2020-2021, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
Config for General Packet Classifier
"""

import logging

from vyatta_resources_gpc_vci.classifier import Classifier

LOG = logging.getLogger('GPC VCI')

RES_NAMESPACE = "vyatta-resources-v1"
GPC_NAMESPACE = "vyatta-resources-packet-classifier-v1"


class GpcConfig:
    """
    A class to represent the GPC configuration.
    """
    def __init__(self, new_config, old_config):
        """ Initialise config object """
        self._classifiers = {}
        self._modified_classifiers = []

        old_class_names = self._get_classifier_names_from_config(old_config)
        classifiers = self._build_classifiers_from_config(new_config)

        for name in classifiers:
            if name in old_class_names:
                self._modified_classifiers.append(name)

        self._classifiers = classifiers

    def _get_classifier_config(self, cfg_dict):
        """ Get the classifier config """
        classifier_list = None

        if cfg_dict is not None:
            res_dict = cfg_dict.get(f"{RES_NAMESPACE}:resources")
            if res_dict is not None:
                gpc_dict = res_dict.get(f"{GPC_NAMESPACE}:packet-classifier")
                if gpc_dict is not None:
                    classifier_list = gpc_dict.get('classifier')

        return classifier_list

    def _get_classifier_names_from_config(self, cfg_dict):
        """ Get a list of classifier names from config"""
        names = []
        classifier_list = self._get_classifier_config(cfg_dict)

        if classifier_list is not None:
            for classifier_dict in classifier_list:
                names.append(classifier_dict['classifier-name'])

        return names

    def _build_classifiers_from_config(self, cfg_dict):
        """ Build a dictionary of classifiers """
        classifiers = {}

        classifier_list = self._get_classifier_config(cfg_dict)

        if classifier_list is not None:
            for classifier_dict in classifier_list:
                classifier = Classifier(classifier_dict)
                classifiers[classifier.name] = classifier

        return classifiers

    @property
    def modified_classifiers(self):
        """Retrieve a list of modified classifiers """
        return self._modified_classifiers

    def get_classifier(self, classifier_name):
        """ Retrieve a classifier by name """
        return self._classifiers.get(classifier_name)
