#!/usr/bin/env python3
#
# Copyright (c) 2020-2021, AT&T Intellectual Property.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
"""
General Packet Classifier Rule - a classification rule within a classifier
"""
import logging
import ipaddress
from vyatta.proto import GPCConfig_pb2

LOG = logging.getLogger('GPC VCI')


class Rule:
    """
    A classification rule within a generic packet classifier.
    It consists of a set of match criteria and a result.
    """
    def __init__(self, rule_config, pb_message):
        """ Initialise rule object """

        self._number = rule_config.get('number')
        self._result = rule_config.get('result')

        rule_message = pb_message.rules.add()
        rule_message.number = rule_config.get('number')
        rule_message.result = rule_config.get('result')

        match = rule_config.get('match')
        if match:
            for key in match:
                self._match_message_from_match(key, match.get(key),
                                               rule_message)

    def _match_addr_val(self, is_dest, address, rule_message):
        """ Build protobuf IP address matches for rule """
        for addr in address:
            match_message = rule_message.matches.add()

            if addr == "host":
                ipaddr = ipaddress.ip_address(address.get(addr))
                version = ipaddr.version
                if version == 4:
                    v4addr = int(ipaddr)
                    length = 32
                else:
                    v6addr = ipaddr.packed
                    length = 128
            else:
                ipnet = ipaddress.ip_network(address.get(addr))
                version = ipnet.version
                if version == 4:
                    v4addr = int(ipnet.network_address)
                else:
                    v6addr = ipnet.network_address.packed
                length = ipnet.prefixlen

            if is_dest:
                if version == 4:
                    match_message.dest_ip.address.ipv4_addr = v4addr
                else:
                    match_message.dest_ip.address.ipv6_addr = v6addr
                match_message.dest_ip.length = length
            else:
                if version == 4:
                    match_message.src_ip.address.ipv4_addr = v4addr
                else:
                    match_message.src_ip.address.ipv6_addr = v6addr
                match_message.src_ip.length = length

    def _match_port_val(self, is_dest, ports, rule_message):
        """ Build protobuf L4 port matches for rule """
        for port in ports:
            match_message = rule_message.matches.add()

            ports_list = ports.get(port)

            # currently a list in yang with max 1 item
            for p in ports_list:
                if is_dest:
                    match_message.dest_port = p
                else:
                    match_message.src_port = p

    def _match_addr_port(self, is_dest, match_val, rule_message):
        """ Build protobuf matches for src or dst IP address or port number """
        for field in match_val:
            if field == "ipv4" or field == "ipv6":
                self._match_addr_val(is_dest, match_val.get(field),
                                     rule_message)
            else:
                self._match_port_val(is_dest, match_val.get(field),
                                     rule_message)

    def _match_proto(self, match_val, rule_message):
        """ Build protobuf matches for protocol field """
        protocol_dict = {
            'hopopt':           0,
            'icmp':             1,
            'igmp':             2,
            'ggp':              3,
            'ipencap':          4,
            'st':               5,
            'tcp':              6,
            'egp':              8,
            'igp':              9,
            'pup':              12,
            'udp':              17,
            'hmp':              20,
            'xns-idp':          22,
            'rdp':              27,
            'iso-tp4':          29,
            'dccp':             33,
            'xtp':              36,
            'ddp':              37,
            'idpr-cmtp':        38,
            'ipv6':             41,
            'ipv6-route':       43,
            'ipv6-frag':        44,
            'idrp':             45,
            'rsvp':             46,
            'gre':              47,
            'esp':              50,
            'ah':               51,
            'skip':             57,
            'ipv6-icmp':        58,
            'ipv6-nonxt':       59,
            'ipv6-opts':        60,
            'rspf':             73,
            'vmtp':             81,
            'eigrp':            88,
            'ospf':             89,
            'ax.25':            93,
            'ipip':             94,
            'etherip':          97,
            'encap':            98,
            'pim':              103,
            'ipcomp':           108,
            'vrrp':             112,
            'l2tp':             115,
            'isis':             124,
            'sctp':             132,
            'fc':               133,
            'mobility-header':  135,
            'udplite':          136,
            'mpls-in-ip':       137,
            'manet':            138,
            'hip':              139,
            'shim6':            140,
            'wesp':             141,
            'rohc':             142,
        }

        for proto in match_val:
            match_message = rule_message.matches.add()

            proto_dict = match_val.get(proto)
            for proto_format in proto_dict:
                val = proto_dict.get(proto_format)
                if proto_format == "name":
                    proto_num = protocol_dict.get(val)
                elif proto_format == "number":
                    proto_num = val
                else:
                    proto_num = 256

            if proto == "base":
                match_message.proto_base = proto_num
            else:
                match_message.proto_final = proto_num

    def _match_dscp(self, match_val, rule_message):
        """ Build protobuf matches for dscp """
        dscp_dict = {
            'cs0': 0,
            'cs1': 8,
            'cs2': 16,
            'cs3': 24,
            'cs4': 32,
            'cs5': 40,
            'cs6': 48,
            'cs7': 56,
            'af11': 10,
            'af12': 12,
            'af13': 14,
            'af21': 18,
            'af22': 20,
            'af23': 22,
            'af31': 26,
            'af32': 28,
            'af33': 30,
            'af41': 34,
            'af42': 36,
            'af43': 38,
            'ef': 46,
            'va': 44,
            'default': 0,
        }

        match_message = rule_message.matches.add()

        for dscp_format in match_val:
            if dscp_format == "name":
                dscp_val = dscp_dict.get(match_val.get(dscp_format))
            else:
                dscp_val = match_val.get(dscp_format)

        match_message.dscp = dscp_val

    def _match_frag(self, match_val, rule_message):
        """ Build protobuf matches for fragments """
        match_msg = rule_message.matches.add()

        if match_val == "any":
            match_msg.fragment = GPCConfig_pb2.RuleMatch.FRAGMENT_ANY
        elif match_val == "initial-only":
            match_msg.fragment = GPCConfig_pb2.RuleMatch.FRAGMENT_INITIAL
        else:
            match_msg.fragment = GPCConfig_pb2.RuleMatch.FRAGMENT_SUBSEQUENT

    def _match_icmp(self, is_v4, match_val, rule_message):
        """ Build protobuf matches for ICMP """
        CODE_UNUSED = 256

        icmpv4_dict = {
            'echo-reply': (0, 256),
            'destination-unreachable': (3, CODE_UNUSED),
            'network-unreachable': (3, 0),
            'host-unreachable': (3, 1),
            'protocol-unreachable': (3, 2),
            'port-unreachable': (3, 3),
            'fragmentation-needed': (3, 4),
            'source-route-failed': (3, 5),
            'network-unknown': (3, 6),
            'host-unknown': (3, 7),
            'network-prohibited': (3, 9),
            'host-prohibited': (3, 10),
            'TOS-network-unreachable': (3, 11),
            'TOS-host-unreachable': (3, 12),
            'communication-prohibited': (3, 13),
            'host-precedence-violation': (3, 14),
            'precedence-cutoff': (3, 15),
            'source-quench': (4, CODE_UNUSED),
            'redirect': (5, CODE_UNUSED),
            'network-redirect': (5, 0),
            'host-redirect': (5, 1),
            'TOS-network-redirect': (5, 2),
            'TOS-host-redirect': (5, 3),
            'echo-request': (8, CODE_UNUSED),
            'router-advertisement': (9, CODE_UNUSED),
            'router-solicitation': (10, CODE_UNUSED),
            'time-exceeded': (11, CODE_UNUSED),
            'ttl-zero-during-reassembly': (11, 0),
            'ttl-zero-during-transit': (11, 1),
            'parameter-problem': (12, CODE_UNUSED),
            'ip-header-bad': (12, 0),
            'required-option-missing': (12, 1),
            'timestamp-request': (13, CODE_UNUSED),
            'timestamp-reply': (14, CODE_UNUSED),
            'address-mask-request': (17, CODE_UNUSED),
            'address-mask-reply': (18, CODE_UNUSED)
        }

        icmpv6_dict = {
            'destination-unreachable': (1, CODE_UNUSED),
            'no-route': (1, 0),
            'communication-prohibited': (1, 1),
            'address-unreachable': (1, 3),
            'port-unreachable': (1, 4),
            'packet-too-big': (2, CODE_UNUSED),
            'time-exceeded': (3, CODE_UNUSED),
            'ttl-zero-during-transit': (3, 0),
            'ttl-zero-during-reassembly': (3, 1),
            'parameter-problem': (4, CODE_UNUSED),
            'bad-header': (4, 0),
            'unknown-header-type': (4, 1),
            'unknown-option': (4, 2),
            'echo-request': (128, CODE_UNUSED),
            'echo-reply': (129, CODE_UNUSED),
            'multicast-listener-query': (130, CODE_UNUSED),
            'multicast-listener-report': (131, CODE_UNUSED),
            'multicast-listener-done': (132, CODE_UNUSED),
            'router-solicitation': (133, CODE_UNUSED),
            'router-advertisement': (134, CODE_UNUSED),
            'neighbor-solicitation': (135, CODE_UNUSED),
            'neighbor-advertisement': (136, CODE_UNUSED),
            'redirect': (137, CODE_UNUSED),
            'mobile-prefix-solicitation': (146, CODE_UNUSED),
            'mobile-prefix-advertisement': (147, CODE_UNUSED)
        }

        for icmp in match_val:
            match_msg = rule_message.matches.add()
            if icmp == "class":
                v6class = match_val.get(icmp)
                if v6class == "info":
                    match_msg.icmpv6_class = GPCConfig_pb2.RuleMatch.CLASS_INFO
                else:
                    match_msg.icmpv6_class = \
                        GPCConfig_pb2.RuleMatch.CLASS_ERROR
            else:
                if icmp == "type":
                    # This is a list with 1 entry because of the match yang
                    icmp_type_list = match_val.get(icmp)
                    typenum = icmp_type_list[0].get('type-number')
                    code = icmp_type_list[0].get('code')
                else:
                    icmp_name = match_val.get(icmp)
                    if is_v4:
                        typenum, code = icmpv4_dict.get(icmp_name)
                    else:
                        typenum, code = icmpv6_dict.get(icmp_name)

                if is_v4:
                    match_msg.icmpv4.typenum = typenum
                    if code is not None and code != CODE_UNUSED:
                        match_msg.icmpv4.code = code
                else:
                    match_msg.icmpv6.typenum = typenum
                    if code is not None and code != CODE_UNUSED:
                        match_msg.icmpv6.code = code

    def _match_ttl(self, match_val, rule_message):
        """ Build protobuf matches for ttl field """
        ttl_val = match_val.get("equals")
        match_message = rule_message.matches.add()
        match_message.ttl = ttl_val

    def _match_message_from_match(self, match_key, match_val, rule_message):
        """ Build protobuf match message fields from config """

        if match_key == "destination":
            self._match_addr_port(True, match_val, rule_message)

        elif match_key == "source":
            self._match_addr_port(False, match_val, rule_message)

        elif match_key == "protocol":
            self._match_proto(match_val, rule_message)

        elif match_key == "dscp":
            self._match_dscp(match_val, rule_message)

        elif match_key == "fragment":
            self._match_frag(match_val, rule_message)

        elif match_key == "icmp":
            self._match_icmp(True, match_val, rule_message)

        elif match_key == "icmpv6":
            self._match_icmp(False, match_val, rule_message)

        elif match_key == "ttl":
            self._match_ttl(match_val, rule_message)
