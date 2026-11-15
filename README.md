# 🫀 Ansible Role: corosync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.corosync-blue)](https://galaxy.ansible.com/cedricfarinazzo/corosync)

> **[Corosync](https://corosync.github.io/corosync/) 3 cluster membership and quorum over knet links, one shared authkey, and an optional quorum device (corosync-qdevice) whose certificates the role signs on the qnetd host.**

The role renders `corosync.conf` itself from a template (no `pcs`, `pcsd` masked), on every node of the cluster in one play. It is what Pacemaker runs on; Pacemaker itself is out of its scope.

## 🚀 Quick Start

Install from Ansible Galaxy ([cedricfarinazzo.corosync](https://galaxy.ansible.com/cedricfarinazzo/corosync)), pinned to a release:

```yaml
# requirements.yml
roles:
  - name: cedricfarinazzo.corosync
    version: 1.0.0
```

```bash
ansible-galaxy role install -r requirements.yml
```

```yaml
- hosts: cluster
  become: true
  roles:
    - role: cedricfarinazzo.corosync
      vars:
        corosync_cluster_name: example
        corosync_nodes:
          - {name: node-a, nodeid: 1, addrs: [192.0.2.11]}
          - {name: node-b, nodeid: 2, addrs: [192.0.2.12]}
          - {name: node-c, nodeid: 3, addrs: [192.0.2.13]}
```

The role will:
- ✅ Check every input before any change: names, node IDs and addresses unique, one address per link, the same nodelist on every host of the play, every node in the play, `two_node` refused with a quorum device
- ✅ With a quorum device: read the qnetd host's CA first, so an unreachable qnetd host stops the role before any package, file or restart
- ✅ Install `corosync` (and `corosync-qdevice`), mask `pcsd`
- ✅ Make one authkey on the first node with `corosync-keygen` when no node holds one, and copy it to the nodes without one through the controller's memory (`no_log`, never written on the controller); a key on a node is kept, never regenerated; keys that differ stop the role
- ✅ Write `corosync.conf`; restart corosync on a node still on the package's default configuration (Debian's postinst starts it at install); reload every node with one `corosync-cfgtool -R` for a change Corosync can reload; refuse a change it reads at start only (cluster name, crypto, transport, link ports) on a running cluster, with nothing changed
- ✅ With a quorum device: on every node an NSS database trusting the qnetd CA; the first node's certificate request signed on the qnetd host, imported on the first node and exported as PKCS#12, imported on the other nodes; a node holding the cluster certificate is skipped
- ✅ Enable and start `corosync` and `corosync-qdevice`

## 📋 Requirements

- Ansible 2.15+, `become: true`
- Every node of `corosync_nodes` in the play (it renders one nodelist on all of them); never `--limit` part of a cluster
- With a quorum device: `corosync_qdevice_host` in the inventory with `corosync-qnetd` installed (its package creates the CA and the NSS database in `/etc/corosync/qnetd/nssdb`), reachable by Ansible and by the nodes on `corosync_qdevice_port` (TCP 5403)
- Firewall: knet on UDP `mcastport` (5405 by default) of every link, between every pair of nodes; the role opens no port

### Supported Distributions

| Distribution | Version | Status |
|--------------|---------|--------|
| Debian       | 13 (trixie) | ✅ Tested |
| Ubuntu       | 24.04 (noble) | ✅ Tested |
| Ubuntu       | 26.04 (resolute) | ✅ Tested |

The scenarios beyond the default one run on Debian 13.

## ⚙️ Configuration

### Cluster

```yaml
corosync_state: present            # absent: stop, purge, remove config, authkey and certificates
corosync_cluster_name: ""          # required: 1-32 of [A-Za-z0-9_-], also the qdevice certificate's name
corosync_nodes: []                 # [{name, nodeid, addrs: [one per link], host: inventory name (default name)}]
corosync_links:
  - linknumber: 0                  # 0-7; knet_link_priority 0-255, mcastport (5405)
corosync_link_mode: passive        # passive: one link at a time, the highest priority first; active: all
corosync_transport: knet           # only knet
corosync_token: 3000               # ms
corosync_consensus: null           # null: Corosync's 1.2 x token
corosync_crypto_cipher: aes256     # none|aes256|aes192|aes128
corosync_crypto_hash: sha256       # none|md5|sha1|sha256|sha384|sha512; not none with a cipher
corosync_two_node: false           # never with a quorum device
corosync_wait_for_all: null        # null: Corosync's default
corosync_allow_restart: false      # true: a start-only change restarts every node (an outage)
corosync_logging_to_syslog: true
corosync_logging_debug: false
corosync_packages_extra: []
```

`addrs` lists one address per entry of `corosync_links`, in that order: `addrs[i]` is `ring<corosync_links[i].linknumber>_addr`. A `nodeid` never changes once set. Adding a node: add it to `corosync_nodes` and run the role on every node, the new one included: the running nodes reload, the new node starts on the new nodelist.

### Quorum device

```yaml
corosync_qdevice: false
corosync_qdevice_host: ""          # inventory name of the qnetd host, never a node
corosync_qdevice_address: ""       # what the nodes connect to (default corosync_qdevice_host)
corosync_qdevice_port: 5403
corosync_qdevice_algorithm: ffsplit  # ffsplit (even-sized clusters) or lms
corosync_qdevice_tie_breaker: lowest # lowest, highest or a nodeid
corosync_qdevice_tls: "on"         # on, off or required
```

The qdevice is one more vote: two nodes and a qdevice make three votes, majority two. The role signs the cluster certificate on the qnetd host (`corosync-qnetd-certutil -s`); the qnetd daemon itself is yours to install and run.

### Start-only settings

Corosync reads the cluster name, crypto, transport and link ports at start only. The role keeps their fingerprint in `/etc/corosync/.corosync-static`; a change of one on a running cluster is refused before any file changes. To apply one: stop corosync on every node (its dependants, such as Pacemaker, stop with it), run the role, or set `corosync_allow_restart: true` for that run.

## 🎯 Usage Examples

### Two nodes, two links, a quorum device

```yaml
corosync_cluster_name: example
corosync_links:
  - {linknumber: 0, knet_link_priority: 10}   # fallback
  - {linknumber: 1, knet_link_priority: 20}   # preferred in passive mode
corosync_nodes:
  - {name: node-a, nodeid: 1, addrs: [192.0.2.11, 198.51.100.11]}
  - {name: node-b, nodeid: 2, addrs: [192.0.2.12, 198.51.100.12]}
corosync_qdevice: true
corosync_qdevice_host: qnetd.example.com
corosync_qdevice_address: 198.51.100.10
```

### Two nodes without a quorum device

```yaml
corosync_two_node: true   # each node stays quorate alone once both have met (wait_for_all)
```

## ⚠️ Security notes

- The authkey (wire encryption and authentication) and the qdevice PKCS#12 pass through the controller's memory only; every task that holds one is `no_log`. They are never written on the controller.
- `crypto_cipher: none` sends cluster traffic in clear and unauthenticated: only on a network you trust.
- The qnetd host signs any request the role sends it under the cluster name: keep Ansible's access to it as tight as to the nodes.

## 🔍 Check

```bash
corosync-quorumtool -s          # Quorate: Yes, the expected and total votes; Flags Qdevice with a quorum device
corosync-cfgtool -n             # every peer on every link, "enabled connected"
corosync-cmapctl -m stats stats.knet.node2.link1.tx_data_packets   # which link carries the data
corosync-qnetd-tool -l -v -c <cluster>   # on the qnetd host: every node, TLS active, vote ACK
```

## ↩️ Rollback

`corosync_state: absent` stops and disables `corosync-qdevice` and `corosync`, purges the packages, removes `corosync.conf`, the authkey, the stamp, `/etc/corosync/qdevice`, `/var/lib/corosync` and the `pcsd` mask. It leaves `/etc/corosync/qnetd` (a qnetd server) alone. On the qnetd host, `cluster-<name>.crt` and the request stay.

## 🧪 Testing

```bash
./run-tests.sh                     # default scenario on Debian 13
./run-tests.sh all                 # every distribution, in parallel
./run-tests.sh -s two-links debian13
./run-tests.sh -s qdevice debian13
./run-tests.sh -s qdevice-lms debian13
./run-tests.sh -s failure debian13
tests/validate.test.sh             # the input checks, on localhost
```

Scenarios: `default` (three nodes: check mode on a fresh host, converge, quorate on the role's cluster, not the package's, one authkey 0400, crypto on, `pcsd` masked, idempotence; reruns: no change, check mode with no change, a token change reloaded with no restart, a cluster name change refused with nothing changed, absent and nothing left), `two-links` (link 1 preferred; its interface down: link 0 carries the data, still quorate; up: link 1 again), `qdevice` (two nodes and a qnetd container: certificates, ffsplit, Flags Qdevice, A,V,NMW, qnetd lists both over TLS with ACK; a rerun imports nothing; an unreachable qnetd host stops the role before anything changes), `qdevice-lms` (three nodes, lms), `failure` (node lists that differ, a duplicate nodeid, `two_node` with a qdevice, control characters; authkeys that differ refused; a node without the authkey receives the cluster's).

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI), a merge commit lands each branch commit, so both must follow the convention. Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; Ansible Galaxy imports the new tag from the repository. [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in); no collection
- ✅ **OS packages** `corosync`, `corosync-qdevice` (quorum device); `corosync-qnetd` on the qnetd host, set up beforehand

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*

## 📄 License

MIT, see [LICENSE](LICENSE).
