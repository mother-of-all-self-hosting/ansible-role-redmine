#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh
#
# Tags look like `v<redmine version>-<release>`, which is what this repository
# has published since v6.0.5-1:
#
# - if defaults/main.yml points at a Redmine version that has never been
#   released, the release counter restarts at 0 (`v7.0.1-0`)
# - otherwise the counter is incremented (`v7.0.1-1`), but only if something
#   that actually affects the role has changed since the last release
#
# Determining the version from defaults/main.yml, rather than from the commit
# message of the pull request that got merged, makes the result independent of
# the order in which pull requests get merged, and lets any change to the role
# (bugfix, feature, dependency bump) release itself without a human tagging.
#
# The commit-message approach this replaced got it wrong the last time it
# fired: Renovate's subject for the 6.1.3 -> 7.0.0 bump reads "Update redmine
# Docker tag to v7", because Renovate names a major bump after its major, and
# the workflow published a `v7-0` tag off that string while defaults/main.yml
# said 7.0.0. Renovate's `loose` versioning, which mash-playbook resolves
# these tags with, sorts a longer release higher when the shared components
# are equal (`v7.0.0-0` > `v7-0`), so that stray tag does not stand in the way
# of the correctly named ones - but it is still counted by nothing here.

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

defaults_path='defaults/main.yml'

# Paths that shape the behavior of the role for its consumers. A commit
# touching only other paths (a README fix, CI configuration, Molecule tests)
# does not change what a playbook run does, and releasing it would only create
# churn in the repositories that consume this role.
role_defining_paths=(
	'defaults'
	'meta'
	'tasks'
	'templates'
)

# Anchored on `redmine_version:` so that neither a commented-out example nor
# `redmine_container_image_tag`, which is derived from it, can be mistaken for
# it. This is the same literal that the `# renovate:` annotation directly
# above it in defaults/main.yml points Renovate at.
version="$(sed -nE 's|^redmine_version:[[:space:]]*"?([^"[:space:]]+)"?.*$|\1|p' "$defaults_path" | head -n1)"

if [ -z "$version" ]; then
	echo >&2 "Could not determine the Redmine version from $defaults_path"
	exit 1
fi

# Redmine's own version is carried without a leading `v` (the tags have one),
# but tolerate one so that a future change of convention does not produce a
# doubled prefix.
tag_prefix="v${version#v}-"

# Of all releases of this version, the highest release number. Sorted
# numerically, so that -10 is recognized as newer than -9.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

if git diff --quiet "$previous_tag" HEAD -- "${role_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the role has changed since $previous_tag"
	exit 0
fi

echo >&2 "The role has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
