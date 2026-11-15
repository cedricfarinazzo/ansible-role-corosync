#!/usr/bin/env bash
# The role's input checks: each bad input fails before anything changes, the good ones pass.
# Runs tasks/validate.yml on localhost; needs ansible-playbook on PATH, no host.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/roles"
ln -s "$REPO" "$WORK/roles/corosync"
cat > "$WORK/play.yml" <<'PLAY'
- name: Validate corosync inputs
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Validate
      ansible.builtin.include_role:
        name: corosync
        tasks_from: validate.yml
PLAY
fails=0
run() { ANSIBLE_ROLES_PATH=$WORK/roles ansible-playbook -i localhost, -c local -e "{\"corosync_validate_only\": true}" -e "$1" "$WORK/play.yml" > "$WORK/out" 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; tail -5 "$WORK/out" >&2; fails=$((fails + 1)); fi; }
# Rejected by an assert, never by a templating crash: that would pass for the wrong reason.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: ' "$WORK/out"; then echo "ok   rejected: $1"
  else echo "FAIL failed without an assertion: $1" >&2; grep -m3 -E 'ERROR|fatal' "$WORK/out" >&2; fails=$((fails + 1)); fi
}


# A good cluster; each bad case changes one input of it (JSON objects merge left to right in -e)
N='"corosync_cluster_name": "c1", "corosync_nodes": [{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}, {"name": "b", "nodeid": 2, "addrs": ["192.0.2.2"]}, {"name": "c", "nodeid": 3, "addrs": ["192.0.2.3"]}]'
N2='"corosync_cluster_name": "c1", "corosync_links": [{"linknumber": 0, "knet_link_priority": 10}, {"linknumber": 1, "knet_link_priority": 20, "mcastport": 5407}], "corosync_nodes": [{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1", "198.51.100.1"], "host": "node-a.example.com"}, {"name": "b", "nodeid": 2, "addrs": ["192.0.2.2", "198.51.100.2"]}]'
Q='"corosync_qdevice": true, "corosync_qdevice_host": "qnetd.example.com"'
nodes() { printf '"corosync_cluster_name": "c1", "corosync_nodes": [%s]' "$1"; }
good "a three-node cluster" "{$N}"
good "absent needs no cluster" '{"corosync_state": "absent"}'
good "two links, priorities, a port, a host" "{$N2}"
good "active links, crypto off, consensus, wait_for_all" "{$N2, \"corosync_link_mode\": \"active\", \"corosync_crypto_cipher\": \"none\", \"corosync_crypto_hash\": \"none\", \"corosync_token\": 5000, \"corosync_consensus\": 6000, \"corosync_wait_for_all\": false}"
good "two_node" "{$N2, \"corosync_two_node\": true}"
good "a qdevice, lms, a nodeid tie breaker, an address" "{$N, $Q, \"corosync_qdevice_algorithm\": \"lms\", \"corosync_qdevice_tie_breaker\": 2, \"corosync_qdevice_address\": \"2001:db8::10\", \"corosync_qdevice_tls\": \"required\"}"
good "IPv6 and name addresses" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["2001:db8::1"]}, {"name": "b", "nodeid": 2, "addrs": ["node-b.example.com"]}')}"
good "extra packages, restart allowed" "{$N, \"corosync_packages_extra\": [\"pacemaker\"], \"corosync_allow_restart\": true}"
bad "an unknown state" '{"corosync_state": "latest"}'
bad "no cluster name" '{"corosync_nodes": [{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}]}'
bad "a cluster name with a trailing newline" "{$N, \"corosync_cluster_name\": \"c1\\n\"}"
bad "a cluster name with an embedded newline" "{$N, \"corosync_cluster_name\": \"c\\n1\"}"
bad "a cluster name with a CR" "{$N, \"corosync_cluster_name\": \"c\\r1\"}"
bad "a cluster name with a space" "{$N, \"corosync_cluster_name\": \"c 1\"}"
bad "a cluster name over 32 characters" "{$N, \"corosync_cluster_name\": \"$(printf 'a%.0s' {1..33})\"}"
bad "no node" '{"corosync_cluster_name": "c1"}'
bad "nodes as a mapping" '{"corosync_cluster_name": "c1", "corosync_nodes": {"name": "a"}}'
bad "a node name with a trailing newline" "{$(nodes '{"name": "a\n", "nodeid": 1, "addrs": ["192.0.2.1"]}')}"
bad "a node name with an embedded newline" "{$(nodes '{"name": "a\nb", "nodeid": 1, "addrs": ["192.0.2.1"]}')}"
bad "a node name with a tab" "{$(nodes '{"name": "a\tb", "nodeid": 1, "addrs": ["192.0.2.1"]}')}"
bad "an address with a trailing newline" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1\n"]}')}"
bad "an address with an embedded newline" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1\nring1_addr: x"]}')}"
bad "an address with a CR" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0\r.2.1"]}')}"
bad "an address with a brace" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1}"]}')}"
bad "a host with a trailing newline" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"], "host": "h\n"}')}"
bad "a nodeid with a trailing newline" "{$(nodes '{"name": "a", "nodeid": "1\n", "addrs": ["192.0.2.1"]}')}"
bad "nodeid 0" "{$(nodes '{"name": "a", "nodeid": 0, "addrs": ["192.0.2.1"]}')}"
bad "a nodeid out of range" "{$(nodes '{"name": "a", "nodeid": 2147483648, "addrs": ["192.0.2.1"]}')}"
bad "a duplicate nodeid" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}, {"name": "b", "nodeid": 1, "addrs": ["192.0.2.2"]}')}"
bad "a duplicate node name" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}, {"name": "a", "nodeid": 2, "addrs": ["192.0.2.2"]}')}"
bad "a duplicate address" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}, {"name": "b", "nodeid": 2, "addrs": ["192.0.2.1"]}')}"
bad "a node without addresses" "{$(nodes '{"name": "a", "nodeid": 1}')}"
bad "addresses as a string" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": "192.0.2.1"}')}"
bad "fewer addresses than links" "{$N, \"corosync_links\": [{\"linknumber\": 0}, {\"linknumber\": 1}]}"
bad "a node with an unknown key" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"], "ring0_addr": "x"}')}"
bad "a link number over 7" "{$(nodes '{"name": "a", "nodeid": 1, "addrs": ["192.0.2.1"]}'), \"corosync_links\": [{\"linknumber\": 8}]}"
bad "a link number twice" "{$N2, \"corosync_links\": [{\"linknumber\": 0}, {\"linknumber\": 0}]}"
bad "a link priority over 255" "{$N, \"corosync_links\": [{\"linknumber\": 0, \"knet_link_priority\": 256}]}"
bad "a link priority with a trailing newline" "{$N, \"corosync_links\": [{\"linknumber\": 0, \"knet_link_priority\": \"1\\n\"}]}"
bad "a link port out of range" "{$N, \"corosync_links\": [{\"linknumber\": 0, \"mcastport\": 70000}]}"
bad "a link with an unknown key" "{$N, \"corosync_links\": [{\"linknumber\": 0, \"bindnetaddr\": \"x\"}]}"
bad "no link" "{$N, \"corosync_links\": []}"
bad "udpu transport" "{$N, \"corosync_transport\": \"udpu\"}"
bad "an unknown link mode" "{$N, \"corosync_link_mode\": \"rr\"}"
bad "a token with a trailing newline" "{$N, \"corosync_token\": \"3000\\n\"}"
bad "a token under 100 ms" "{$N, \"corosync_token\": 50}"
bad "consensus not above the token" "{$N, \"corosync_consensus\": 3000}"
bad "an unknown cipher" "{$N, \"corosync_crypto_cipher\": \"des\"}"
bad "a cipher without a hash" "{$N, \"corosync_crypto_hash\": \"none\"}"
bad "two_node as a string" "{$N, \"corosync_two_node\": \"yes\"}"
bad "two_node with a qdevice" "{$N2, $Q, \"corosync_two_node\": true}"
bad "a qdevice without its host" "{$N, \"corosync_qdevice\": true}"
bad "a qdevice host with a trailing newline" "{$N, \"corosync_qdevice\": true, \"corosync_qdevice_host\": \"q\\n\"}"
bad "a qdevice host with an embedded newline" "{$N, \"corosync_qdevice\": true, \"corosync_qdevice_host\": \"q\\nx\"}"
bad "a qdevice host that is a node" "{$N, \"corosync_qdevice\": true, \"corosync_qdevice_host\": \"a\"}"
bad "a qdevice address with a trailing newline" "{$N, $Q, \"corosync_qdevice_address\": \"192.0.2.10\\n\"}"
bad "a qdevice address with a CR" "{$N, $Q, \"corosync_qdevice_address\": \"192.0.2\\r.10\"}"
bad "a qdevice port out of range" "{$N, $Q, \"corosync_qdevice_port\": 0}"
bad "an unknown qdevice algorithm" "{$N, $Q, \"corosync_qdevice_algorithm\": \"2nodelms\"}"
bad "a tie breaker with a trailing newline" "{$N, $Q, \"corosync_qdevice_tie_breaker\": \"lowest\\n\"}"
bad "an unknown qdevice tls" "{$N, $Q, \"corosync_qdevice_tls\": \"yes\"}"
bad "restart allowed as a string" "{$N, \"corosync_allow_restart\": \"yes\"}"
bad "an extra package with a trailing newline" '{"corosync_packages_extra": ["pacemaker\n"]}'
bad "an extra package with an embedded newline" '{"corosync_packages_extra": ["pace\nmaker"]}'
bad "extra packages as a string" '{"corosync_packages_extra": "pacemaker"}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
