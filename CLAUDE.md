# CLAUDE.md — ansible-role-corosync

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.corosync` (Ansible Galaxy): Corosync 3 membership and quorum over knet links, one shared authkey, and an optional quorum device whose certificates the role signs on the qnetd host. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`corosync_*`), with its generic default.
- `vars/main.yml` — file paths, the start-only fingerprint (`corosync_static`), the package list, node hosts and the first host.
- `tasks/main.yml` — `validate.yml` (every input asserted, then the same nodelist on every host; `corosync_validate_only` skips that last check for `tests/validate.test.sh`), then for `present`: `qdevice_ca.yml` (the qnetd CA read on the qnetd host, before anything changes), `install.yml` (packages, `pcsd` masked), `authkey.yml`, `config.yml` (start-only change refused, template, stamp, restart of a node not yet managed, one `corosync-cfgtool -R`), `qdevice.yml` or `qdevice_off.yml`; for `absent`: `absent.yml`.
- `templates/corosync.conf.j2` — the whole configuration.
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/shared/` — what every scenario uses: `prepare.yml` (policy-rc.d removed, qnetd installed on the `qnetd` group), `converge.yml`, `run.sh` and `recap.yml` (a rerun from the control node on Molecule's inventory, its recap checked), `quorate.yml`, `links.yml` (knet data counters per link), `qdevice-verify.yml`.
- `molecule/default/` — three nodes, every distribution; `side_effect/` reruns (no change, check mode, token reload, cluster name refused, absent twice).
- `molecule/two-links/` — two nodes on two documentation-range networks, `two_node`; link 1 down and up.
- `molecule/qdevice/`, `molecule/qdevice-lms/` — a qnetd container with two nodes (ffsplit; a left request removed; unreachable qnetd host) and three nodes (lms).
- `molecule/failure/` — failure paths on a built two-node cluster, then verify it is still quorate.
- `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost.
- `run-tests.sh` / `Makefile` — local Molecule entry points; several distros or `all` run in parallel, one log each in `.molecule-logs/`.
- `requirements.yml` (none at runtime), `requirements-dev.txt` (controller tooling, exact pins), `package.json`, `bun.lock`, `.releaserc.json` (semantic-release only).
- `.github/workflows/` — `ci.yml` (lint, Galaxy description length, shellcheck, input tests, default on every distribution, the other scenarios on Debian 13), `pr-title.yml`, `release.yml`.
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset). `feat:` → minor, `fix:` / `perf:` → patch, `!` or `BREAKING CHANGE:` → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act:** dropping a platform, renaming or removing a variable, changing a default that changes the cluster's wire format (crypto, port, link mode).
- **Tags are bare semver** (`1.2.3`), notes in GitHub Releases; no `CHANGELOG.md`.
- **No ruleset or branch protection on `main`:** a ruleset blocks semantic-release. Changes still go through a PR with green CI.
- **Variables:** every user-facing variable starts with `corosync_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR. Internal facts start with `__corosync_`.
- **Every input checked before any change.** Every regex ends in `\Z`, never `$`; classes hold no control character; bad cases feed trailing and embedded newlines.
- **Key material never reaches the output or the controller's disk:** the authkey, request, cluster certificate and PKCS#12 move by `slurp` and a node-side write, each task `no_log`; binary content is decoded on the node (`base64 -d`), never through a text template.
- **A start-only change is refused on a running cluster** unless `corosync_allow_restart`; a reloadable one is one `corosync-cfgtool -R` after every node wrote its file.
- **The role never runs the qnetd daemon:** it only reads the CA and signs on the qnetd host.
- **Examples never copy a real deployment:** `example.com` names, documentation addresses.
- **GitHub Actions pinned by full commit SHA**, tag in a trailing comment. Exact pins for tooling; `renovate.json` identical in the sibling roles: change them together.
- **License:** MIT.

## Supported platforms

`meta/main.yml` `platforms`, the CI matrix, the `README.md` table, `run-tests.sh --help` and the `Makefile` list the same set.

## How releases work

1. A PR is squash-merged into `main` with a Conventional Commit title.
2. When `ci.yml` passes on the push to `main`, `release.yml` runs `bunx semantic-release`: tag, GitHub Release, comments on released PRs.
3. Ansible Galaxy imports each new tag by itself.

## Commands

- Lint: `source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh molecule/shared/*.sh`
- Input tests: `tests/validate.test.sh`
- Molecule: `./run-tests.sh debian13`, `./run-tests.sh -s <scenario> debian13`, `./run-tests.sh all`

## Gotchas

- Debian's and Ubuntu's postinst start corosync at install on a default single-node `corosync.conf` (cluster `debian`, crypto none). Docker images' `policy-rc.d` hid it: `molecule/shared/prepare.yml` removes it, `quorate.yml` checks the running cluster name is the role's.
- A group var whose value extracts other hosts' vars through `hostvars` does not render inside another host's `hostvars` lookup ("'hostvars' is undefined"): `validate.yml` sets each host's view as a fact first, then compares the facts.
- `delegate_to` is templated before `when`: a delegate target from an empty list fails even on a skipped task. Compute the list in a fact, delegate to `first | default(inventory_hostname)`.
- `runtime.config.totem.token` is the token plus `token_coefficient` (650 ms) per node above two: check `totem.token` for the configured value.
- Binary files (authkey, PKCS#12) break through `copy: content=` (UTF-8): written by `base64 -d` on the node.
- corosync-qdevice refuses ffsplit without `quorum.device.votes: 1` set ("50:50 split algorithm works only if quorum.device.votes configuration key is set to 1"): the template sets it for ffsplit; lms computes nodes - 1.
- `corosync-quorumtool -l` lists the qdevice as one more line (`0 <votes> Qdevice`): count members without it.
- Molecule's `side-effect` command has a dash; the sequence step is `side_effect`.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when a variable, platform, file or convention changes, or a trap costs a debugging round (one Gotchas line: symptom, cause, fix). New fact replaces the old clause; never append a changelog.
