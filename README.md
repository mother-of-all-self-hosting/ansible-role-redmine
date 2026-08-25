<!--
SPDX-FileCopyrightText: 2023 Nikita Chernyi
SPDX-FileCopyrightText: 2026 Slavi Pantaleev
SPDX-FileCopyrightText: 2026 Suguru Hirahara

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Redmine Ansible role

This is an [Ansible](https://www.ansible.com/) role which installs [Redmine](https://redmine.org) to run as a [Docker](https://www.docker.com/) container wrapped in a systemd service.

This role *implicitly* depends on:

- [`com.devture.ansible.role.playbook_help`](https://github.com/devture/com.devture.ansible.role.playbook_help)
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)

Check [`defaults/main.yml`](defaults/main.yml) for the full list of supported options.

💡 For an Ansible playbook which integrates this role and makes it easier to use, see the [Mother-of-All-Self-Hosting Ansible playbook](https://github.com/mother-of-all-self-hosting/mash-playbook).

## After the first installation

### Take over the `admin` account immediately

Redmine's own database setup — `rake db:migrate`, which the container image runs on every start — seeds a single administrator account with the login `admin` and the password `admin`. This role neither creates that account nor can change it: it exists as soon as Redmine has finished starting for the first time.

Redmine flags the account as having to change its password at first login, so whoever logs in first is the one who gets to set the real password. On an instance that is already published at its hostname, that need not be you. **Log in and change the password before pointing anyone at the instance.** If you cannot do that straight away, keep the instance closed off until you can — for example with `redmine_container_labels_traefik_middleware_basic_auth_enabled`.

### Enable the REST API if you need it

Redmine's REST API is disabled by default and is turned on under *Administration → Settings → API*. This role does not manage Redmine's runtime settings, so that remains a manual step.

## Notes on some of the settings

### Ports

`redmine_container_http_port` is the port Redmine listens on *inside* the container. The role passes it to the container as `PORT`, which is what the image's `rails server` command reads, so changing it moves the port the process actually binds — as well as the port that Traefik and `redmine_container_http_host_bind_port` are pointed at.

### Serving Redmine under a path prefix

`redmine_path_prefix` must either be `/` or a path that does not end with a slash (e.g. `/redmine`). When it is not `/`, the reverse-proxy configuration strips the prefix before the request reaches Redmine — Redmine keeps routing at `/` — and the role passes the prefix to the container as `RAILS_RELATIVE_URL_ROOT` so that the URLs Redmine generates (assets, links, redirects) carry it. Without that, Redmine would emit `/assets/…` links which the browser sends back to a path the proxy does not route.

### Database

`redmine_database_type` has to be set explicitly; the role fails validation otherwise. Be aware that the upstream image quietly writes a `config/database.yml` of its own and falls back to a SQLite database whenever it does not find one, so a misconfigured instance still looks perfectly healthy from the outside. The Molecule scenarios assert against exactly that fallback — see [`molecule/README.md`](./molecule/README.md).

## Development

### pre-commit

You can optionally install a Git pre-commit hook (via [mise](https://mise.jdx.dev/) + [prek](https://prek.j178.dev/)) that runs formatting and linting checks before each commit. See [`.pre-commit-config.yaml`](./.pre-commit-config.yaml) for which hooks are to be executed.

To install the hook, run the [`just`](https://github.com/casey/just) command below:

```sh
just prek-install-git-pre-commit-hook
```

### Molecule

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

Refer to [this page](./molecule/README.md) for details about how to utilize it.
