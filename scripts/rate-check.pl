#!/usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (c) 2015, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings;

use lib "/opt/vyatta/share/perl5";

use Vyatta::Rate qw(parse_ppt);

parse_ppt( $ARGV[0] );

1;
