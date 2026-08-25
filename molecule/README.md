<!--
SPDX-FileCopyrightText: 2018-2025 Slavi Pantaleev
SPDX-FileCopyrightText: 2019-2022 Aaron Raimist
SPDX-FileCopyrightText: 2019-2023 MDAD project contributors
SPDX-FileCopyrightText: 2023 QEDeD
SPDX-FileCopyrightText: 2024 Fabio Bonelli
SPDX-FileCopyrightText: 2024 Nikita Chernyi
SPDX-FileCopyrightText: 2024-2026 Suguru Hirahara
SPDX-FileCopyrightText: 2026 spatterlight

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Molecule Testing

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

## Prerequisites

To utilize Molecule you need to prepare several requirements:

- **x86** computer running one of these operating systems that make use of [systemd](https://systemd.io/):
  - **Archlinux**
  - **CentOS**, **Rocky Linux**, **AlmaLinux**, or possibly other RHEL alternatives (although your mileage may vary)
  - **Debian** (10/Buster or newer)
  - **Ubuntu** (18.04 or newer, although [20.04 may be problematic](https://github.com/mother-of-all-self-hosting/mash-playbook/blob/main/docs/ansible.md#supported-ansible-versions) if you run the Ansible playbook on it)
- `root` access on the computer which Molecule runs against
- [Ansible](http://ansible.com/) program
- [Python](https://www.python.org/)
  - Most distributions install Python by default, but some don't (e.g. Ubuntu 18.04) and require manual installation (something like `apt-get install python3`)
- [Docker](https://www.docker.com)
  - Access to Docker UNIX socket (`/var/run/docker.sock`) is required by default

## Installation

To set up the environment for using Molecule, run the command below on the terminal:

```bash
python3 -m venv ./molecule/venv
source ./molecule/venv/bin/activate
pip3 install -r ./molecule/requirements.txt
```

## Scenarios

Currently these testing scenarios are available:

### `default`

Tests a standard Redmine installation, storing its data in SQLite.

### `mariadb`

Tests a standard Redmine installation with the MariaDB database, connected over a Unix socket.

### `postgres`

Tests a standard Redmine installation with the Postgres database, connected over a Unix socket.

This is also the scenario that runs Redmine on a container port other than the default one, so that `redmine_container_http_port` is under test rather than merely configured.

## What the scenarios check

The checks every scenario runs live in [`resources/tasks/verify_redmine.yml`](resources/tasks/verify_redmine.yml); each scenario's own `verify.yml` adds what proves its particular database backend is the one carrying the data.

They are built around what an *unconfigured* Redmine image does, which was established by running `docker.io/redmine:7.0.0-alpine` by hand with no role involved:

- the image's entrypoint writes a `config/database.yml` of its own whenever it does not find one, falls back to SQLite, runs `rake db:migrate` and then serves a perfectly healthy site. `GET /` answers `200` with `<title>Redmine</title>`;
- so neither "the systemd unit is active" (the unit carries `Restart=always`) nor "something answered 200" says anything about whether this role configured anything at all.

What the scenarios therefore assert instead:

- the container runs the image `redmine_version`/`redmine_distro` add up to, and the booted application reports that same version;
- the role's `configuration.yml` reached the process, by reading back a `max_concurrent_ajax_uploads` that differs both from Redmine's own built-in default and between scenarios;
- the role's env file reached the container, including the `PORT` that decides which port Redmine binds and a marker passed through `redmine_environment_variables_additional_variables`;
- the live ActiveRecord connection uses the adapter, socket, user and database the scenario configured;
- a project created inside the running Redmine is served back over HTTP *and* is found in the database server itself - and, for the MariaDB and Postgres scenarios, that no SQLite fallback file was written alongside it;
- the seeded `admin` account is still flagged as having to change its password at first login.

## Running

By default it is configured to run the scenarios on Ubuntu 26.04.

```bash
molecule test --scenario-name default
```

You can utilize other distributions by setting one to the `MOLECULE_DISTRO` environment variable:

```bash
# Ubuntu 24.04
MOLECULE_DISTRO=ubuntu2404 molecule test --scenario-name default

# Debian 13
MOLECULE_DISTRO=debian13 molecule test --scenario-name default

# Debian 12
MOLECULE_DISTRO=debian12 molecule test --scenario-name default
```
