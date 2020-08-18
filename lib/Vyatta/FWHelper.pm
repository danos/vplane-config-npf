#
# Copyright (c) 2017-2020, AT&T Intellectual Property.
# All rights reserved.
#
# Copyright (C) 2012-2017, Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only
#
use strict;
use warnings;

package Vyatta::FWHelper;
require Exporter;

our @ISA = qw(Exporter);

our @EXPORT =
  qw(get_rules_mod get_rules_del build_rule build_app_rule get_ether_type print_ether_types validate_npf_rule get_proto_name get_proto_num get_port_name get_port_num get_vrf_default_id is_vrf_available get_vrf_name_from_id action_group_features);

use strict;
use warnings;
use Carp;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Vyatta::DSCP qw(str2dscp);
use Vyatta::Rate qw(parse_rate parse_ppt);
use POSIX qw(strtoul);

use Getopt::Long;
use Vyatta::Config;
use Vyatta::TypeChecker;
use Vyatta::Npf::Warning;

use Module::Load::Conditional qw[can_load];

# return the ID assigned as the default VRF
sub get_vrf_default_id {
    return 1;
}

my $vrf_available =
  can_load( modules => { "Vyatta::VrfManager" => undef }, autoload => "true" );

sub is_vrf_available {
    return defined($vrf_available);
}

sub get_rules_mod {
    my ( $config, $level ) = @_;
    my @roolz;
    my @foo = $config->listNodes($level);
    for my $r (@foo) {
        my $l = $level . " $r";
        push( @roolz, $r )
          if $config->isChanged($l);
    }

    return @roolz;
}

sub get_rules_del {
    my ( $config, $level ) = @_;
    return $config->listDeleted($level);
}

sub check_port_range {
    my ( $port_val, $src_dst ) = @_;

    npf_config_warning( "$src_dst port $port_val: this rule will never match, "
          . "as the start of range is greater than the end" )
      if ( $port_val =~ /^([0-9]+)-([0-9]+)$/ && $1 > $2 );
}

sub add_port {
    my ( $config, $src_dst, $prefix ) = @_;

    my ( $port_type, $port_value ) =
      get_port_type_and_value( $config, $src_dst );

    return '' if ( $port_type eq 'Not-exist' );

    check_port_range( $port_value, $src_dst )
      if ( $port_type eq 'Port-range' );

    return "${prefix}-port-group=$port_value "
      if ( $port_type eq 'Port-group' );

    return "${prefix}-port=$port_value ";
}

# Protocol option to protocol number
my %protnum2stateful = (
    6  => 'tcp',
    17 => 'udp',
    1  => 'icmp',
    58 => 'icmp',
);

sub action_group_features {
    my ($config) = @_;
    my @params = ();

    my $val = $config->returnValue("mark pcp");
    if ( defined($val) ) {
        my $inner = $config->exists("mark pcp-inner");
        if ( !defined($inner) ) {
            push @params, "markpcp($val,none)";
        } else {
            push @params, "markpcp($val,inner)";
        }
    } else {
        my $val = $config->returnValue("mark dscp");
        if ( defined($val) ) {
            $val = str2dscp($val);
            push @params, "markdscp($val)";
        }
    }

    # check if both 'pcp' and 'dscp' are configured for same action group
    my $act_grp_name = $config->returnParent("..");
    if ( ( $config->exists("mark pcp") || $config->exists("mark pcp-inner") )
        && $config->exists("mark dscp") ) {
        npf_config_warning( "action group '$act_grp_name' has both"
              . " 'pcp' and 'dscp' marks configured." );
    }

    my $policer = "";

    my $tc_val = $config->returnValue("police tc");
    my $bw_val = $config->returnValue("police bandwidth");
    if ( defined($bw_val) ) {
        my $bps = parse_rate($bw_val) / 8;

        my $police_burst = $config->returnValue("police burst");

        # Default burst size = 4ms in bytes at rate
        $police_burst = int( ( $bps * 4 ) / 1000 )
          unless ( defined($police_burst) );

        $policer = "policer(0,$bps,$police_burst";

        # Default tc in milliseconds for "police bandwidth"
        if ( not defined($tc_val) ) {
            $tc_val = "20";
        }
    }

    $val = $config->returnValue("police ratelimit");
    if ( defined($val) ) {
        my $ppt = parse_ppt($val);
        $policer = "policer($ppt,0,0";

        # Default tc in milliseconds for "police ratelimit"
        if ( not defined($tc_val) ) {
            $tc_val = "1000";
        } else {
            if ( index( $val, "pps" ) != -1 ) {
                if ( $tc_val != "1000" ) {
                    $tc_val = "1000";
                }
            }
        }
    }

    if ( $policer ne "" ) {

        # We only need consider the overhead if bandwidth is configured
        my $overhead = "0";
        if ( defined($bw_val) && $config->exists("police frame-overhead") ) {
            $overhead = $config->returnValue("police frame-overhead");
        }
        my $then_action   = $config->returnValue("police then action");
        my $then_markdscp = $config->returnValue("police then mark dscp");
        my $then_markpcp  = $config->returnValue("police then mark pcp");

        if ( defined($then_action) ) {
            $policer .= ",$then_action,,$overhead,$tc_val)";
        } elsif ( defined($then_markdscp) ) {
            $then_markdscp = str2dscp($then_markdscp);
            $policer .= ",markdscp,$then_markdscp,$overhead,$tc_val)";
        } elsif ( defined($then_markpcp) ) {
            if ( $config->exists("police then mark pcp-inner") ) {
                $policer .= ",markpcp,$then_markpcp,$overhead,$tc_val,inner)";
            } else {
                $policer .= ",markpcp,$then_markpcp,$overhead,$tc_val,none)";
            }
        } else {
            $policer .= ",drop,,$overhead,$tc_val)";
        }
        push @params, $policer;
    }

    return @params;
}

sub build_rule {
    my ( $level, $tag, $needaction ) = @_;
    my $config       = Vyatta::Config->new($level);
    my $group_config = Vyatta::Config->new('resources group');
    my $rule         = "";
    my $val;

    return $rule
      if $config->exists("disable");

    my $action = $config->returnValue("action");
    if ( !defined($action) ) {

        # default is "drop" for FW, and "accept" for all else
        if ( $level =~ /^security firewall/ ) {
            $action = "drop";
        } else {
            $action = "accept";
        }
    } else {

        # QoS uses "pass" as the value in the CLI instead of "accept"
        $action = "accept"
          if ( $action eq "pass" );
    }
    $rule .= "action=$action "
      if ( !defined($needaction) || $needaction );

    my $tcp_flags = $config->returnValue("tcp flags");
    $rule .= "tcp-flags=$tcp_flags " if defined($tcp_flags);

    my $ipv6_rt = $config->returnValue("ipv6-route type");
    $rule .= "ipv6-route=$ipv6_rt " if defined($ipv6_rt);

    my $proto_num;
    $val = $config->returnValue("protocol-group");
    if ( defined($val) ) {
        $rule .= "protocol-group=$val ";
    } else {
        $val = $config->returnValue("protocol");
        if ( defined($val) ) {
            $proto_num = get_proto_num($val);
            $proto_num = $val if !defined($proto_num);
        } else {

            # Try to infer protocol number if not defined and we have sufficient
            # information
            if ( $config->exists("icmp") ) {
                $proto_num = 1;
            } elsif ( $config->exists("icmpv6") ) {
                $proto_num = 58;
            } elsif ( defined($ipv6_rt) ) {
                $proto_num = 43;
            } elsif ( defined($tcp_flags) ) {
                $proto_num = 6;
            }

        }
        $rule .= "proto-final=$proto_num " if defined($proto_num);
    }

    my $icmp_group   = $config->returnValue("icmp group");
    my $icmp_name    = $config->returnValue("icmp name");
    my @icmp_numbers = $config->listNodes("icmp type");
    my $icmp_type    = $icmp_numbers[0];

    if ( defined($icmp_group) ) {
        $rule .= "icmpv4-group=$icmp_group ";
    } elsif ( defined($icmp_name) ) {
        $rule .= "icmpv4=$icmp_name ";
    } elsif ( defined($icmp_type) ) {
        my $icmp_code = $config->returnValue("icmp type $icmp_type code");
        if ( defined($icmp_code) ) {
            $rule .= "icmpv4=$icmp_type:$icmp_code ";
        } else {
            $rule .= "icmpv4=$icmp_type ";
        }
    }

    my $icmpv6_group   = $config->returnValue("icmpv6 group");
    my $icmpv6_name    = $config->returnValue("icmpv6 name");
    my @icmpv6_numbers = $config->listNodes("icmpv6 type");
    my $icmpv6_type    = $icmpv6_numbers[0];

    if ( defined($icmpv6_group) ) {
        $rule .= "icmpv6-group=$icmpv6_group ";
    } elsif ( defined($icmpv6_name) ) {
        $rule .= "icmpv6=$icmpv6_name ";
    } elsif ( defined($icmpv6_type) ) {
        my $icmpv6_code = $config->returnValue("icmpv6 type $icmpv6_type code");
        if ( defined($icmpv6_code) ) {
            $rule .= "icmpv6=$icmpv6_type:$icmpv6_code ";
        } else {
            $rule .= "icmpv6=$icmpv6_type ";
        }
    }

    my $from_addr = $config->returnValue("source address");
    my $from_ver  = get_addr_version($from_addr);

    my $to_addr = $config->returnValue("destination address");
    my $to_ver  = get_addr_version($to_addr);

    # check for mis-matched addresses, we only care when both are defined.
    carp "Cannot mix ipv4 addresses with ipv6 addresses\n"
      if ( defined($from_ver) && defined($to_ver) && $from_ver ne $to_ver );

    # We consider a rule as desiring stateful if it is explicitly marked as
    # such,  or if not then if it is for a protocol which has been marked
    # as being globally stateful.
    #
    # For user convenience we treat the configuration of stateful icmp as
    # making both IPv4 ICMP and IPv6 ICMP stateful - i.e. treat 'icmp' as
    # a L4 protocol similar to 'tcp'.

    if ( $action eq 'accept' ) {
        my $stateful  = $config->returnValue("state");
        my $session   = $config->exists("session");
        my $old_level = $config->setLevel(".");
        $config->setLevel("");
        if ( ( defined($stateful) && $stateful eq 'enable' ) || $session ) {
            $rule .= "stateful=y ";
        } elsif ( defined($proto_num) ) {
            my $stateful_prot = $protnum2stateful{$proto_num};
            if (
                defined($stateful_prot)
                && $config->exists(
                    "security firewall global-state-policy $stateful_prot")
              )
            {
                $rule .= "stateful=y ";
            }
        }
        $config->setLevel($old_level);
    }

    # XXX this is bogus, setting family in rule has no effect since
    # family is already implicit by rule chain and does not change
    # the type of packet
    $val = $config->returnValue("address-family");
    if ( defined($val) ) {
        if ( $level =~ /^policy route pbr/ ) {
            if ( $val eq "ipv4" ) {
                $rule .= "family=inet ";
            } elsif ( $val eq "ipv6" ) {
                $rule .= "family=inet6 ";
            }
        } else {
            print "address-family must be either ipv4 or ipv6\n";
        }
    }

    $val = $config->returnValue("source mac-address");
    $rule .= "src-mac=$val " if defined($val);

    if ( defined($from_ver) ) {
        $rule .= "src-addr=$from_addr ";
    } else {
        $rule .= "src-addr-group=$from_addr "
          if defined($from_addr);
    }

    $rule .= add_port( $config, "source", "src" );

    $val = $config->returnValue("destination mac-address");
    $rule .= "dst-mac=$val " if defined($val);

    if ( defined($to_ver) ) {
        $rule .= "dst-addr=$to_addr ";
    } else {
        $rule .= "dst-addr-group=$to_addr "
          if defined($to_addr);
    }

    $rule .= add_port( $config, "destination", "dst" );

    $val = $config->returnValue("ethertype");
    if ( defined($val) ) {
        my $eth_num = get_ether_type($val);
        $rule .= "ether-type=$eth_num ";
    }

    $val = $config->returnValue("dscp");
    if ( defined($val) ) {
        $val = str2dscp($val);
        $rule .= "dscp=$val ";
    }

    $val = $config->returnValue("dscp-group");
    $rule .= "dscp-group=$val " if defined($val);

    $val = $config->returnValue("pcp");
    $rule .= "pcp=$val " if defined($val);

    $val = $config->exists("fragment");
    $rule .= "fragment=y " if defined($val);

    # Start of rproc section

    # Note that for multiple rprocs they will be executed in the
    # order that they are added to the rproc= line.

    my @rproc = ();
    my @match = ();
    my @handle = ();

    push @handle, "tag($tag)" if defined($tag);

    $val = $config->returnValue("session application firewall");
    push @rproc, "app-firewall($val)"
      if ( defined($val) );

    $level =~ /[^ ]* ([^ ]*) rule [0-9]*$/;
    my $group = $1;

    $val = ( $config->listNodes("session application name") )[0];
    push @rproc, "app-firewall(_N${group}+$val)"
      if ( defined($val) );

    $val = ( $config->listNodes("session application protocol") )[0];
    push @rproc, "app-firewall(_P${group}+$val)"
      if ( defined($val) );

    $val = $config->returnValue("session application type");
    push @rproc, "app-firewall(_T${group}+$val)"
      if ( defined($val) );

    my @pol_mark = action_group_features($config);
    push @rproc, @pol_mark
      if ( scalar @pol_mark > 0 );

    # action-group {name}
    if ( $config->exists("action-group") ) {
        my $name = $config->returnValue("action-group");
        push @rproc, "action-group($name)";
    }

    my $prefix;
    if ( $level =~ /^security firewall/ ) {
        if ($config->exists("session application")) {
            $prefix = "session application";
        }
    } elsif ($config->exists("application")) {
        $prefix = "application";
    }
    if (defined $prefix) {
        my @values;
        my $value;
        my $engine = "";
        my $name = "";
        my $type = "";
        my @engines = $config->listNodes("$prefix engine");
        if (@engines) {
            $prefix .= " engine $engines[0]";
            $engine = $engines[0];
        } else {
            $engine = "ndpi";
        }

        # new engine-based dpi cli defines names and types
        # as single values
        $value = $config->returnValue("$prefix name");
        if ($value) {
            # New CLI, use the value of name node
            $name = $value;
        } else {
            # Old CLI, use the first name node
            @values = $config->listNodes("$prefix name");
            $name = $values[0]
              if @values;
        }

        $value = $config->returnValue("$prefix type");
        if ($value) {
            # New CLI, use the value of type node
            $type = $value;
        } else {
            # Old CLI, use the first type node
            @values = $config->listNodes("$prefix type");
            $type = $values[0]
              if @values;
        }

        push @match, "dpi($engine,$name,$type)"
          if $name or $type;
    }

    # Path monitor
    #
    my $pathmon_monitor = ( $config->listNodes("path-monitor monitor") )[0];
    if ( defined($pathmon_monitor) ) {
        my $pathmon_policy =
          $config->returnValue("path-monitor monitor $pathmon_monitor policy");
        if ( defined($pathmon_policy) ) {
            push @match, "pathmon($pathmon_monitor,$pathmon_policy)";
        }
    }

    $val = $config->exists("log");
    push @rproc, "log"
      if defined($val);

    # session limiter rproc
    if ( $config->exists("parameter") ) {
        my $param = $config->returnValue("parameter");
        if ($param) {
            my $param_rproc = "session-limiter(parameter=$param)";
            push @handle, $param_rproc;
        }
    }

    # Add the rproc for setting the VRF ID to the rule if required.
    $val = $config->returnValue("routing-instance");
    if ( ( $action eq "accept" ) && is_vrf_available() && defined($val) ) {

        # Convert VRF name to ID.
        my $vrf_id = Vyatta::VrfManager::get_vrf_id($val);
        push @rproc, "setvrf($vrf_id)";
    }

    # User defined app "then" clause.
    if ( $level =~ /^service application/ && $config->exists("then") ) {

        my $user_app_name = $config->returnValue("then name") // "";
        my @user_app_types = $config->listNodes("then type");
        my $user_app_proto = $config->returnValue("then protocol") // "";
        my $user_app_type;

        if (@user_app_types) {
            $user_app_type = $user_app_types[0];
        } else {
            $user_app_type = "";
        }

        # Send the rproc: app(name, type_bitfield, protocol).
        push @rproc, "app($user_app_name,$user_app_type,$user_app_proto)";
    }

    $rule .= "match=" . join( ';', @match ) . " "
      if ( scalar @match > 0 );

    $rule .= "rproc=" . join( ';', @rproc ) . " "
      if ( scalar @rproc > 0 );

    $rule .= "handle=" . join( ';', @handle ) . " "
      if ( scalar @handle > 0 );

    # End of rproc section

    return $rule;
}

sub build_app_rule {
    my ($level) = @_;
    my $config = Vyatta::Config->new($level);
    my ( $rule, $value, @values );

    $value = $config->returnValue("action");
    $rule = "action=$value ";

    $value = $config->returnValue("group");
    if (defined($value)) {
        $rule .= "group=$value ";
    } else {
        @values = $config->listNodes("engine");
        if (@values) {
            $rule .= "engine=$values[0] ";
            $config = Vyatta::Config->new("${level} engine $values[0]");
        } else {
            $rule .= "engine=ndpi "; # Maintain backwards compatibility
        }
    }

    # new engine-based dpi cli defines protos, names and types
    # as single values
    $value = $config->returnValue("protocol");
    $rule .= "protocol=$value "
      if $value;

    $value = $config->returnValue("name");
    $rule .= "name=$value "
      if $value;

    $value = $config->returnValue("type");
    $rule .= "type=$value "
      if $value;

    # Old CLI, use the first node
    @values = $config->listNodes("protocol");
    $rule .= "protocol=$values[0] "
      if @values;

    @values = $config->listNodes("name");
    $rule .= "name=$values[0] "
      if @values;

    @values = $config->listNodes("type");
    $rule .= "type=$values[0] "
      if @values;

    return $rule;
}

sub get_addr_version {
    my ($address) = @_;

    if ( defined($address) ) {

        # remove "!" and masks, if they exist
        $address =~ s/!//;
        $address =~ s/\/.*//;

        return 4 if is_ipv4($address);
        return 6 if is_ipv6($address);
    }
    return;    # undef
}

# get the ethernumber of the given ethertype
# and convert it in to decimal value to parse
sub get_ether_type {
    my ($etype) = @_;

    return if ( $etype eq '' );    # undefined for empty string
    return
      if ( $etype =~ /^0/ && $etype !~ /^0x/ );    # undefined for octal numbers

    my ( $num, $unparsed ) = strtoul($etype);
    if ( $unparsed == 0 ) {
        if ( $num > 0xFFFF ) {
            return;                                # undefined for out of range
        } else {
            return $num;
        }
    }

    open my $file, '<', '/etc/ethertypes'
      or croak "/etc/ethertypes: $!";

    while (<$file>) {
        next if /^#/;

        my ( $ethername, $ethernumber ) = split;
        if ( uc($etype) =~ /^$ethername$/i ) {
            close $file;
            return hex($ethernumber);
        }
    }
    close $file;
    return;    #undefined if not found
}

# print acceptable ether type values
sub print_ether_types {

    open my $file, '<', '/etc/ethertypes'
      or croak "/etc/ethertypes: $!";

    while (<$file>) {
        next if /^#|^$/;

        my ( $ethername, $ethernumber ) = split;
        print "$ethername ";
    }
    close $file;
}

# looks up protocols and stores information in arrays, if not done already
my %proto_num_to_name;
my %proto_name_to_num;

sub _store_protos {
    return if %proto_num_to_name;
    while ( ( my $name, my $aliases, my $num ) = getprotoent() ) {
        $proto_num_to_name{$num} = "$name"
          unless defined( $proto_num_to_name{$num} );
        $proto_name_to_num{"$name"} = $num
          unless defined( $proto_name_to_num{"$name"} );
    }
}

# converts a protocol number to a name - returns undef if not found
sub get_proto_name {
    _store_protos();
    return $proto_num_to_name{ $_[0] };
}

# converts a protocol name to a number - returns undef if not found
sub get_proto_num {
    _store_protos();
    return $proto_name_to_num{ $_[0] };
}

# looks up ports and stores information in arrays, if not done already
my %port_num_to_name;
my %port_name_to_num;

sub _store_ports {
    return if %port_num_to_name;
    while ( ( my $name, my $aliases, my $num, my $proto ) = getservent() ) {
        $port_num_to_name{$num} = "$name"
          unless defined( $port_num_to_name{$num} );
        $port_name_to_num{"$name"} = $num
          unless defined( $port_name_to_num{"$name"} );
    }
}

# converts a port number to a name - returns undef if not found
sub get_port_name {
    _store_ports();
    return $port_num_to_name{ $_[0] };
}

# converts a port name to a number - returns undef if not found
sub get_port_num {
    _store_ports();
    return $port_name_to_num{ $_[0] };
}

# The function validate_npf_rule() below validates a FW, PBR, or QoS
# NPF rule. The other functions below are internal functions used
# by validate_npf_rule().

# Handling for both 'source' and 'destination'
my %src_dst_hash = (
    'source'      => 'Source',
    'destination' => 'Destination',
);

# Takes parameter 'source' or 'destination' and gives the type
# and value for the current rule. For type it returns "Port", "Port-range",
# "Services", "Port-group", "Not-exist".
sub get_port_type_and_value {
    my ( $config, $src_dst ) = @_;
    my $port_val = $config->returnValue("$src_dst port");

    return ( "Not-exist", $port_val )
      if ( !defined($port_val) );
    return ( "Port", $port_val )
      if ( $port_val =~ /^[0-9]+$/ );
    if ( $port_val =~ /^([0-9]+)-([0-9]+)$/ ) {
        return ( "Port-range", $port_val )
          if ( $1 >= 1 && $1 <= 65535 && $2 >= 1 && $2 <= 65535 );
    }
    my $port_num = get_port_num($port_val);
    return ( "Services", $port_num )
      if ( defined($port_num) );
    return ( "Port-group", $port_val );
}

# Validates a single NPF rule under FW, PBR, or QoS
# Note that most validation is now done in Yang "must" statements.
# Parameter 1: should be Vyatta::Config at the node containing NPF CLI
# Parameter 2: should be Vyatta::Config at "resources group"
# Parameter 3: should be the error function to call
sub validate_npf_rule {
    my ( $config, $group_config, $err_fn ) = @_;

    my %port_type  = ();
    my %port_value = ();

    # For 'source' and 'destination' ports
    for my $src_dst ( keys %src_dst_hash ) {
        ( $port_type{$src_dst}, $port_value{$src_dst} ) =
          get_port_type_and_value( $config, $src_dst );

        $err_fn->(
            $config,
"$src_dst_hash{$src_dst} port-group '$port_value{$src_dst}' does not exist"
          )
          if ( $port_type{$src_dst} eq "Port-group"
            && !$group_config->exists("port-group $port_value{$src_dst}") );
    }

    return;
}

sub get_vrf_name_from_id {
    my ($vrf_id) = @_;

    # Access $VRFNAME_NONE again to prevent perl warning:
    #    Name "Vyatta::VrfManager::VRFNAME_NONE" used only once: possible typo
    my $dummy = $Vyatta::VrfManager::VRFNAME_NONE;

    if ( is_vrf_available() ) {
        my $vrf_name = Vyatta::VrfManager::get_vrf_name($vrf_id);
        return "($vrf_id)"
          if ( $vrf_name eq $Vyatta::VrfManager::VRFNAME_NONE );

        return $vrf_name;
    } else {
        return "default"
          if ( $vrf_id == get_vrf_default_id() );
        return "($vrf_id)";
    }
}

1;
