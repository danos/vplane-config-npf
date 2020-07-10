share_perl5dir = $(datarootdir)/perl5/Vyatta
share_perl5_npfdir = $(datarootdir)/perl5/Vyatta/Npf
yangdir = /usr/share/configd/yang
vrf_mgr_del_tabledir = $(sysconfdir)/vrf-manager-del-table.d
lib_python_npfdir = /usr/lib/python3/dist-packages/vyatta/npf
tech_support_dir = /opt/vyatta/share/vyatta-op/functions/tech-support.d

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
	cpio -0pd

sbin_SCRIPTS = scripts/vyatta-dp-npf.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-clear
sbin_SCRIPTS += scripts/vyatta-dp-npf-nat-nat44.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-nat-nat64.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-nat-nptv6.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-nat64
sbin_SCRIPTS += scripts/vyatta-dp-npf-nat64-op
sbin_SCRIPTS += scripts/vyatta-dp-npf-op-delete.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-session-log.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-show-nat-trans
sbin_SCRIPTS += scripts/vyatta-dp-npf-show-nptv6
sbin_SCRIPTS += scripts/vyatta-dp-npf-show-rules
sbin_SCRIPTS += scripts/vyatta-dp-npf-show-session-stats
sbin_SCRIPTS += scripts/vyatta-dp-npf-show-sessions
sbin_SCRIPTS += scripts/vyatta-dp-npf-timeouts.pl
sbin_SCRIPTS += scripts/vyatta-dp-npf-snmptrap.pl
sbin_SCRIPTS += scripts/vyatta-ethertype
sbin_SCRIPTS += scripts/allowed-protocols
sbin_SCRIPTS += scripts/set-ping
sbin_SCRIPTS += scripts/set-syn-cookies
sbin_SCRIPTS += scripts/end-fw-groups
sbin_SCRIPTS += scripts/end-fw-ruleset
sbin_SCRIPTS += scripts/end-ippf-ruleset
sbin_SCRIPTS += scripts/vyatta-ippf-rpc
sbin_SCRIPTS += scripts/vyatta-ippf-op
sbin_SCRIPTS += scripts/validate-ippf
sbin_SCRIPTS += scripts/end-global-state-policy
sbin_SCRIPTS += scripts/end-pbr-ruleset
sbin_SCRIPTS += scripts/set-sess-log
sbin_SCRIPTS += scripts/end-npf-interfaces
sbin_SCRIPTS += scripts/loopback-fw-validate
sbin_SCRIPTS += scripts/end-custom-timeout
sbin_SCRIPTS += scripts/end-resource-groups
sbin_SCRIPTS += scripts/rate-check.pl
sbin_SCRIPTS += scripts/syntax-check-port-group-name
sbin_SCRIPTS += scripts/syntax-check-protocols
sbin_SCRIPTS += scripts/validate-fw-groups
sbin_SCRIPTS += scripts/validate-session-usage
sbin_SCRIPTS += scripts/npf-session-limit-clear.pl
sbin_SCRIPTS += scripts/npf-session-limit-show.pl
sbin_SCRIPTS += scripts/npf-session-limit.pl
sbin_SCRIPTS += scripts/end-session-limit-group
sbin_SCRIPTS += scripts/end-session-limit-param
sbin_SCRIPTS += scripts/end-session-limit-global
sbin_SCRIPTS += scripts/end-session-log
sbin_SCRIPTS += scripts/npf-get-nptv6-state
sbin_SCRIPTS += scripts/npf-get-state
sbin_SCRIPTS += scripts/npf-get-state-fw
sbin_SCRIPTS += scripts/npf-get-state-nat
sbin_SCRIPTS += scripts/npf-get-state-pbr
sbin_SCRIPTS += scripts/npf-get-state-zones
sbin_SCRIPTS += scripts/npf-address-group-show
sbin_SCRIPTS += scripts/validate-resource-groups
sbin_SCRIPTS += scripts/validate-fw-protocol-group
sbin_SCRIPTS += scripts/npf-show-logs
sbin_SCRIPTS += scripts/validate-nat-rules.pl
sbin_SCRIPTS += scripts/validate-session-limit.pl
sbin_SCRIPTS += scripts/nat-pool-configuration
sbin_SCRIPTS += scripts/nat-pool-get-state
sbin_SCRIPTS += scripts/vyatta-dp-nat-pool-op
sbin_SCRIPTS += scripts/cgnat-configuration
sbin_SCRIPTS += scripts/cgnat-get-state
sbin_SCRIPTS += scripts/cgnat-get-subscriber-rpc
sbin_SCRIPTS += scripts/cgnat-get-public-rpc
sbin_SCRIPTS += scripts/cgnat-get-sessions-rpc
sbin_SCRIPTS += scripts/cgnat-clear-sessions-rpc
sbin_SCRIPTS += scripts/cgnat-clear-session-stats-rpc
sbin_SCRIPTS += scripts/cgnat-clear-subs-stats-rpc
sbin_SCRIPTS += scripts/cgnat-clear-policy-stats-rpc
sbin_SCRIPTS += scripts/cgnat-clear-errors-rpc
sbin_SCRIPTS += scripts/vyatta-dp-cgnat-sess-op-yang
sbin_SCRIPTS += scripts/vyatta-dp-cgnat-op
sbin_SCRIPTS += scripts/vyatta-dp-cgnat-pub-op
sbin_SCRIPTS += scripts/vyatta-dp-cgnat-subs-op
sbin_SCRIPTS += scripts/vyatta-dp-cgnat-sess-op
sbin_SCRIPTS += scripts/npf-op-dataplane-stats

share_perl5_DATA = lib/Vyatta/Aggregate.pm
share_perl5_DATA += lib/Vyatta/NpfRuleset.pm
share_perl5_DATA += lib/Vyatta/FWHelper.pm
share_perl5_DATA += lib/Vyatta/NPTv6Stats.pm
share_perl5_DATA += lib/Vyatta/SessionStats.pm

share_perl5_npf_DATA = lib/Vyatta/Npf/Warning.pm
share_perl5_npf_DATA += lib/Vyatta/Npf/GetPort.pm
share_perl5_npf_DATA += lib/Vyatta/Npf/GetPortTypeAndValue.pm
share_perl5_npf_DATA += lib/Vyatta/Npf/ValidateNpfRule.pm

lib_python_npf_DATA = lib/python3/npf_traps.py
lib_python_npf_DATA += lib/python3/npf_debug.py
lib_python_npf_DATA += lib/python3/npf_store.py
lib_python_npf_DATA += lib/python3/npf_warning.py
lib_python_npf_DATA += lib/python3/npf_addr_group.py

vrf_mgr_del_table_SCRIPTS = etc/vrf-manager-del-table.d/pbr-groups

install-exec-hook:
	mkdir -p $(DESTDIR)$(yangdir)
	cd yang && $(cpiop) $(DESTDIR)$(yangdir)
	mkdir -p $(DESTDIR)$(tech_support_dir)
	cd scripts/tech-support && $(cpiop) $(DESTDIR)$(tech_support_dir)
