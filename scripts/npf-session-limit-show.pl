#! /usr/bin/perl
#
# Copyright (c) 2019, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (c) 2017, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;

use Getopt::Long;
use Config::Tiny;
use JSON qw( decode_json );
use List::Util qw( max min );
use Data::Dumper;

use lib "/opt/vyatta/share/perl5";

use Vyatta::Dataplane;
use Vyatta::Dataplane qw(vplane_exec_cmd);
use Vyatta::Aggregate;
use Vyatta::NpfRuleset;
use Vyatta::Config;
use Vyatta::FWHelper qw(get_proto_name);

my $fabric;
my ( $dp_ids, $dp_conns, $local_controller ) =
  Vyatta::Dataplane::setup_fabric_conns($fabric);

my ( $opt_type, $opt_name, $opt_action );

# set up actions dispatch table
my %actions = (
    "show-brief"  => \&show_brief,
    "show-detail" => \&show_detail,
);

# 'show .. brief' column widths.  These are dynamic, and may
# increase as required.
#
my $BRIEF_COL1 = 16;
my $BRIEF_COL2 = 16;
my $BRIEF_COL3 = 16;
my $BRIEF_COL4 = 12;
my $BRIEF_COL5 = 12;
my $BRIEF_COL6 = 12;

# 'show .. session' column widths.
#
my $SESS_COL1 = 15;
my $SESS_COL2 = 31;
my $SESS_COL3 = 31;
my $SESS_COL4 = 15;
my $SESS_COL5 = 7;
my $SESS_COL6 = 15;

#
# type   - all, param, or group
#
GetOptions(
    "type=s"   => \$opt_type,
    "name=s"   => \$opt_name,
    "action=s" => \$opt_action,
);

if ( not defined $opt_name ) {
    $opt_name = "all";
}

die "Missing --action=<action> option\n"
  if ( !defined($opt_action) );

die "Missing --type=<type> option\n"
  if ( !defined($opt_type) );

# dispatch action
( $actions{$opt_action} )->();

# Close down ZMQ sockets. This is needed or sometimes a hang
# can occur due to timing issues with libzmq - see VRVDR-17233 .
Vyatta::Dataplane::close_fabric_conns( $dp_ids, $dp_conns );

exit 0;

#
# Return a list of zero, one or more valid names
#
sub list_param_names {
    my $name = shift;

    my $config = new Vyatta::Config;
    my @names  = ();

    if ( $config->existsOrig("system session limit global")
        and ( $name eq "all" or $name eq "global" ) )
    {
        push( @names, "global" );
    }

    if ( $name eq "all" ) {
        my @tmp = $config->listOrigNodes("system session limit parameter name");
        push( @names, @tmp );
    } elsif ( $config->existsOrig("system session limit parameter name $name") )
    {
        @names = ($name);
    }

    return @names;
}

sub list_group_names {
    my $name = shift;

    my $config = new Vyatta::Config;
    my @names;

    if ( $name eq "all" ) {
        @names = $config->listOrigNodes("system session limit group name");
    } elsif ( $config->existsOrig("system session limit group name $name") ) {
        @names = ($name);
    }

    return @names;
}

sub format_secs {
    my $secs = shift;

    if ( $secs >= 2**31 ) {
        return "never";
    }

    if ( $secs >= 365 * 24 * 60 * 60 ) {
        return sprintf '%.1fy', $secs / ( 365 * 24 * 60 * 60 );
    } elsif ( $secs >= 24 * 60 * 60 ) {
        return sprintf '%.1fd', $secs / ( 24 * 60 * 60 );
    } elsif ( $secs >= 60 * 60 ) {
        return sprintf '%.1fh', $secs / ( 60 * 60 );
    } elsif ( $secs >= 60 ) {
        return sprintf '%.1fm', $secs / (60);
    } else {
        return sprintf '%.1fs', $secs;
    }
}

#
# Return 0 if there have been no sessions created in the interval we
# are averaging over
#
sub format_rate {
    my $rate      = shift;
    my $time      = shift;
    my $last_sess = shift;

    if ( $last_sess > $time ) {
        return 0;
    }
    return $rate;
}

sub show_param_one {
    my $name = shift;

    my $cmd = "npf-op fw show session-limit name $name summary";

    my $WIDTH_COL1 = 58;
    my $WIDTH_COL2 = 28;

    print "Session limit parameter \"$name\":\n";

    for my $dp_id ( sort @{$dp_ids} ) {
        my $sock = ${$dp_conns}[$dp_id];

        next unless $sock;

        my $raw_summary = $sock->execute($cmd);

        next if !defined $raw_summary or $raw_summary =~ /^\s*$/;

        my $decoded = decode_json($raw_summary);

        next if !defined $decoded;
        next if !defined $decoded->{'session-limit'};
        next if !defined $decoded->{'session-limit'}->{'parameter'}->{$name};

        my $summary =
          $decoded->{'session-limit'}->{'parameter'}->{$name}->{'summary'};
        next if !defined $summary;

        my $halfopen   = $summary->{'halfopen'};
        my $ratelimit  = $summary->{'ratelimit'};
        my $blocked_ct = 0;

        if ( defined $ratelimit ) {
            $blocked_ct += $ratelimit->{blocked_ct};
        }
        if ( defined $halfopen ) {
            $blocked_ct += $halfopen->{blocked_ct};
        }

        my $rate_1sec = format_rate( $summary->{rate_1sec}, 1,
            $summary->{last_sess_created} );
        my $rate_1min = format_rate( $summary->{rate_1min}, 60,
            $summary->{last_sess_created} );
        my $rate_5min = format_rate( $summary->{rate_5min}, 5 * 60,
            $summary->{last_sess_created} );

        my $rate_blocks_1sec = format_rate( $summary->{rate_blocks_1sec},
            1, $summary->{last_sess_blocked} );
        my $rate_blocks_1min = format_rate( $summary->{rate_blocks_1min},
            60, $summary->{last_sess_blocked} );
        my $rate_blocks_5min = format_rate( $summary->{rate_blocks_5min},
            5 * 60, $summary->{last_sess_blocked} );

        my $field;
        my $value;
        my $indent = 4;

        $field = "Sessions allowed";
        $value = "$summary->{allowed_ct}";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Sessions blocked";
        $value = "$blocked_ct";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Current session counts (estab/half-open/terminating)";
        $value =
          "[$summary->{estab_ct}:" . "$summary->{new_ct}:$summary->{term_ct}]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Max session counts (estab/half-open/terminating)";
        $value = "[$summary->{max_estab_ct}:"
          . "$summary->{max_new_ct}:$summary->{max_term_ct}]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Time since last session created";
        $value = format_secs( $summary->{last_sess_created} );
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Sessions per sec avg (1sec/1min/5mins)";
        $value = "[$rate_1sec:$rate_1min:$rate_5min]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Max sessions per sec avg (1sec/1min/5mins)";
        $value = "[$summary->{max_rate_1sec}:$summary->{max_rate_1min}:"
          . "$summary->{max_rate_5min}]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Time since max sessions per sec (1sec/1min/5mins)";
        $value = "["
          . format_secs( $summary->{max_rate_1sec_time} ) . ":"
          . format_secs( $summary->{max_rate_1min_time} ) . ":"
          . format_secs( $summary->{max_rate_5min_time} ) . "]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Time since last session blocked";
        $value = format_secs( $summary->{last_sess_blocked} );
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        $field = "Max sessions blocked per sec avg (1sec/1min/5mins)";
        $value =
            "[$summary->{max_rate_blocks_1sec}:"
          . "$summary->{max_rate_blocks_1min}:"
          . "$summary->{max_rate_blocks_5min}]";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        my $features = "";
        if ( defined $ratelimit ) {
            $features .= "rate-limit";
        }
        if ( defined $halfopen ) {
            if ( length $features > 0 ) {
                $features .= ", ";
            }
            $features .= "max-halfopen";
        }
        if ( length $features == 0 ) {
            $features = "none";
        }

        $field = "Features";
        $value = "$features";
        printf( "%*s%-*s%*s\n",
            $indent, " ", $WIDTH_COL1 - $indent,
            $field, $WIDTH_COL2, $value );

        #
        # Rate limit
        #
        if ( defined $ratelimit ) {
            printf( "%*s%-*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                "Rate limit" );

            $indent += 4;

            $field = "Rate sessions/second";
            $value = "$ratelimit->{ratelimit_rate}";
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $field = "Max burst";
            $value = "$ratelimit->{ratelimit_burst}";
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $field = "Interval (milliseconds)";
            $value = ( $ratelimit->{ratelimit_burst} * 1000 ) /
              $ratelimit->{ratelimit_rate};
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $field = "Sessions blocked";
            $value = "$ratelimit->{blocked_ct}";
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $indent -= 4;
        }

        #
        # Max half-open
        #
        if ( defined $halfopen ) {
            printf( "%*s%-*s\n",
                $indent, " ",
                $WIDTH_COL1 - $indent,
                "Max half-open sessions" );

            $indent += 4;

            $field = "Maximum";
            $value = "$halfopen->{halfopen_max}";
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $field = "Sessions blocked";
            $value = "$halfopen->{blocked_ct}";
            printf( "%*s%-*s%*s\n",
                $indent, " ", $WIDTH_COL1 - $indent,
                $field, $WIDTH_COL2, $value );

            $indent -= 4;
        }
    }
    printf("\n");
}

# return "default" for the default rule number, else return just the
# rule number
sub rule_or_name {
    my $rule = shift;

    if ( $rule == 10000 ) {
        return "default";
    } else {
        return $rule;
    }
}

sub format_limiter_match {
    my $match = shift;

    my $proto = "any";
    my $param = "";

    # Replace protocol number with a name.
    if ( $match =~ /(^|.* )proto(-final)? ([\S]*)(.*)/ ) {
        $proto = get_proto_name($3);
        $proto = $3 if !defined($proto);
        $match = "${1}proto $proto$4";
    }

    # Extract the param name; Remove the rproc
    if ( $match =~ /(^|.* )(apply session-limiter\(parameter=)([\S]*)(\))(.*)/ )
    {
        $param = $3;
        $match = "${1}";
    }

    my $tname;
    if ( $match =~ /(from) <([\S]+)>/ ) {
        $tname = $2;
    }

    $match =~ s/from (<[\S]+>)/from $tname/g
      if ( defined $tname );

    $tname = undef;
    if ( $match =~ /(to) <([\S]+)>/ ) {
        $tname = $2;
    }

    $match =~ s/to (<[\S]+>)/to $tname/g
      if ( defined $tname );

    return ( $match, $param, $proto );
}

sub print_limiter_rule {
    my ( $rule_num, $rule, $ruleset_type, $rule_hdr_printed, $indent ) = @_;

    my $fmt_str = "%*s%-7s %-10s %-15s %-15s %-15s\n";

    if ( $$rule_hdr_printed == 0 ) {
        $$rule_hdr_printed = 1;
        printf( $fmt_str,
            $indent, " ", "rule", "parameter", "proto", "allowed", "blocked" );
        printf( $fmt_str,
            $indent, " ", "----", "---------", "-----", "-------", "-------" );
    }

    my ( $match, $param, $proto ) = format_limiter_match( $rule->{match} );

    printf( $fmt_str,
        $indent, " ", rule_or_name($rule_num), $param, $proto, $rule->{bytes},
        $rule->{packets} - $rule->{bytes} );

    printf( "%*scondition - $match\n\n", $indent, " " );
}

sub print_limiter_ruleset_group {
    my ( $attach_type, $attach_point, $ruleset_type, $group ) = @_;

    my $rule_hdr_printed = 0;
    my $indent           = 4;
    my $group_class      = $group->{class};

    printf( "Session limit group \"%s\":\n", $group->{name} );
    if ( $group->{name} ne "global" ) {
        printf( "%*sActive on ($attach_point)\n",
            $indent, " " );
    }

    # want the rule header reprinted after each group
    $rule_hdr_printed = 0;
    foreach my $rule_num ( sort { $a <=> $b } keys %{ $group->{rules} } ) {
        print_limiter_rule( $rule_num, $group->{rules}{$rule_num},
            $ruleset_type, \$rule_hdr_printed, $indent, );
    }
}

sub print_limiter_ruleset {
    my ( $ruleset_type, $config, $name, $header_printed, $brief ) = @_;

    foreach my $attach_point ( @{$config} ) {
        foreach my $ruleset ( @{ $attach_point->{rulesets} } ) {
            next if $ruleset->{ruleset_type} ne $ruleset_type;

            foreach my $group ( @{ $ruleset->{groups} } ) {
                next if ( $name ne 'all' && $name ne $group->{name} );
                if ($brief) {
                    print_limiter_ruleset_group(
                        $attach_point->{attach_type},
                        $attach_point->{attach_point},
                        $ruleset_type, $group,
                    );
                } else {
                    print_limiter_ruleset_group(
                        $attach_point->{attach_type},
                        $attach_point->{attach_point},
                        $ruleset_type, $group,
                    );
                }
            }
        }
    }

    print "\n";
}

sub print_limiter_rules {
    my ( $config, $name, $brief ) = @_;

    my $hdr_printed = 0;

    foreach my $ruleset_type ( 'session-rproc' ) {
        print_limiter_ruleset( $ruleset_type, $config, $name, \$hdr_printed,
            $brief );
    }

}

sub process_limiter_rulesets {
    my ( $name, $brief ) = @_;

    # my $cmd = "npf-op show interface:$intf session-rproc";
    my $dp_rsp = vplane_exec_cmd( "npf-op show", $dp_ids, $dp_conns, 1 );
    my $agg_rsp =
      aggregate_npf_responses( $dp_ids, $dp_rsp, "Vyatta::NpfRuleset" );

    return if ( !defined($agg_rsp) || !defined $agg_rsp->{config} );

    print_limiter_rules( $agg_rsp->{config}, $name, $brief );
}

sub show_param_detail {
    my @params;

    @params = list_param_names($opt_name);
    if ( @params == 0 ) {
        return;
    }

    foreach my $param (@params) {
        show_param_one($param);
    }
}

sub show_group_detail {
    my $brief = 0;

    if ( $opt_name eq 'all' ) {
        process_limiter_rulesets( "all", $brief );
    } else {
        process_limiter_rulesets( $opt_name, $brief );
    }
}

sub show_detail {
    if ( $opt_type eq 'all' or $opt_type eq 'param' ) {
        show_param_detail();
    }
    if ( $opt_type eq 'all' or $opt_type eq 'group' ) {
        show_group_detail();
    }
}

#
# show table of session limiter parameters
#
sub show_param_brief_one {
    my $name        = shift;
    my $show_header = shift;

    my $cmd = "npf-op fw show session-limit name $name";

    for my $dp_id ( sort @{$dp_ids} ) {
        my $sock = ${$dp_conns}[$dp_id];

        next unless $sock;

        my $raw_summary = $sock->execute($cmd);

        next if !defined $raw_summary or $raw_summary =~ /^\s*$/;

        my $decoded = decode_json($raw_summary);

        next if !defined $decoded;
        next if !defined $decoded->{'session-limit'};
        next if !defined $decoded->{'session-limit'}->{'parameter'};
        next if !defined $decoded->{'session-limit'}->{'parameter'}->{$name};

        my $summary =
          $decoded->{'session-limit'}->{'parameter'}->{$name}->{'summary'};
        next if !defined $summary;

        my $halfopen  = $summary->{'halfopen'};
        my $ratelimit = $summary->{'ratelimit'};

        my $rate_1min = 0;
        if ( $summary->{last_sess_created} <= 60 ) {
            $rate_1min = $summary->{rate_1min};
        }

        my $counts =
            "[$summary->{estab_ct}"
          . ":$summary->{new_ct}"
          . ":$summary->{term_ct}]";

        my $max =
            "[$summary->{max_estab_ct}"
          . ":$summary->{max_new_ct}"
          . ":$summary->{max_term_ct}]";

        my $ho = "-";
        if ( defined $halfopen ) {
            $ho = "$halfopen->{blocked_ct}";
        }

        my $rl = "-";
        if ( defined $ratelimit ) {
            $rl = "$ratelimit->{blocked_ct}";
        }

        while ( length($name) > $BRIEF_COL1 ) {
            $BRIEF_COL1 += 2;
        }

        while ( length($counts) > $BRIEF_COL2 ) {
            $BRIEF_COL2 += 2;
        }

        while ( length($max) > $BRIEF_COL3 ) {
            $BRIEF_COL3 += 2;
        }

        while ( length($rate_1min) > $BRIEF_COL4 ) {
            $BRIEF_COL4 += 2;
        }

        while ( length($ho) > $BRIEF_COL5 ) {
            $BRIEF_COL5 += 2;
        }

        while ( length($rl) > $BRIEF_COL6 ) {
            $BRIEF_COL6 += 2;
        }

        if ($show_header) {
            printf(
                "%-*s %-*s %-*s %-*s %-*s %-*s\n",
                $BRIEF_COL1, "Name",      $BRIEF_COL2, "Sessions",
                $BRIEF_COL3, "Max",       $BRIEF_COL4, "Rate (1min)",
                $BRIEF_COL5, "HO Blocks", $BRIEF_COL6, "RL Blocks"
            );

            $show_header = 0;
        }

        printf(
            "%-*s %-*s %-*s %-*s %-*s %-*s\n",
            $BRIEF_COL1, $name, $BRIEF_COL2, $counts,
            $BRIEF_COL3, $max,  $BRIEF_COL4, $rate_1min,
            $BRIEF_COL5, $ho,   $BRIEF_COL6, $rl
        );
    }
}

sub show_param_brief {
    my @params;

    @params = list_param_names($opt_name);
    if ( @params == 0 ) {
        return;
    }

    my $show_header;

    $show_header = 1;
    foreach my $param (@params) {
        show_param_brief_one( $param, $show_header );
        $show_header = 0;
    }

    print "\n";
}

sub show_group_brief {
    my $brief = 1;

    if ( $opt_name eq 'all' ) {
        process_limiter_rulesets( "all", $brief );
    } else {
        process_limiter_rulesets( $opt_name, $brief );
    }
}

sub show_brief {
    if ( $opt_type eq 'all' or $opt_type eq 'param' ) {
        show_param_brief();
    }
    if ( $opt_type eq 'all' or $opt_type eq 'group' ) {
        show_group_brief();
    }
}
