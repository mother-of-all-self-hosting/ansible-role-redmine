#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Exercises bin/compute-next-tag.sh against throwaway git repositories.
#
# Usage: bin/test-compute-next-tag.sh
#
# Every scenario creates a repository in a temporary directory, gives it role
# files and a release history, and then replays a series of merges through the
# real script, tagging as it goes just like the autotag workflow does. This
# repository is never touched and no network access is needed.

set -euo pipefail

script_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/compute-next-tag.sh"

failures=0
workdir=''

cleanup() {
	cd /
	if [ -n "$workdir" ]; then
		rm -rf "$workdir"
		workdir=''
	fi
}

trap cleanup EXIT

# Starts a scenario with a repository at Redmine 7.0.0 which has already seen
# two releases of it (v7.0.0-0 and v7.0.0-1).
#
# The defaults file deliberately carries the traps this role's real one has:
# the Renovate annotation that has to stay attached to the version line, a
# commented-out example of the version variable, and the two image variables
# derived from it. None of those may be picked up as the version. Note that
# the real `redmine_version` carries no leading `v` while the tags do.
scenario() {
	echo "$1"

	cleanup
	workdir="$(mktemp -d)"

	mkdir -p "$workdir/bin" "$workdir/defaults" "$workdir/meta" "$workdir/tasks" "$workdir/templates"
	cp "$script_under_test" "$workdir/bin/"
	cd "$workdir"

	git init -q -b main .
	git config user.email 'test@example.com'
	git config user.name 'Test'
	git config commit.gpgsign false

	cat > defaults/main.yml <<-'YAML'
		# redmine_version: 9.9.9
		# renovate: datasource=docker depName=redmine versioning=semver
		redmine_version: 7.0.0
		redmine_distro: alpine
		redmine_container_image_tag: "{{ redmine_version }}-{{ redmine_distro }}"
		redmine_container_image_customized: "localhost/redmine:{{ redmine_container_image_tag }}-customized"
	YAML
	printf 'placeholder\n' > meta/main.yml
	printf 'placeholder\n' > tasks/main.yml
	printf 'placeholder\n' > templates/env.j2
	printf 'placeholder\n' > README.md

	git add -A
	git commit -qm 'Initial commit'

	local release_number
	for release_number in 0 1; do
		git tag "v7.0.0-$release_number"
	done
}

# Applies a change, commits it, and tags whatever the script says it should be.
# Prints the tag, or nothing when the script decided against a release.
merge() {
	local change="$1" tag

	eval "$change"
	git add -A
	git commit -qm 'Merge'

	tag="$(bin/compute-next-tag.sh 2>/dev/null)"

	if [ -n "$tag" ]; then
		git tag "$tag"
	fi

	printf '%s' "$tag"
}

expect() {
	local description="$1" expected="$2" actual="$3"

	if [ "$actual" = "$expected" ]; then
		printf '  ok   | %s -> %s\n' "$description" "${actual:-no release}"
	else
		printf '  FAIL | %s -> expected %s, got %s\n' "$description" "${expected:-no release}" "${actual:-no release}"
		failures=$((failures + 1))
	fi
}

bump_version="sed -i 's|^redmine_version: 7.0.0|redmine_version: 7.0.1|' defaults/main.yml"
revert_version="sed -i 's|^redmine_version: 7.0.1|redmine_version: 7.0.0|' defaults/main.yml"
bump_distro="sed -i 's|^redmine_distro: alpine|redmine_distro: bookworm|' defaults/main.yml"
edit_task="printf 'a task\n' >> tasks/main.yml"
edit_template="printf 'a line\n' >> templates/env.j2"
edit_meta="printf 'a line\n' >> meta/main.yml"
edit_readme="printf 'documentation\n' >> README.md"
edit_script="printf '# a comment\n' >> bin/compute-next-tag.sh"

# The two merge orders below apply the same updates and must each end up with
# every update released exactly once, whichever order they arrive in.

scenario 'A version bump merged before other role changes'
expect 'version bump' v7.0.1-0 "$(merge "$bump_version")"
expect 'task edit'    v7.0.1-1 "$(merge "$edit_task")"
expect 'template'     v7.0.1-2 "$(merge "$edit_template")"

scenario 'A version bump merged after other role changes'
expect 'task edit'    v7.0.0-2 "$(merge "$edit_task")"
expect 'version bump' v7.0.1-0 "$(merge "$bump_version")"

scenario 'Commits that do not affect the role'
expect 'README'   ''         "$(merge "$edit_readme")"
expect 'a script' ''         "$(merge "$edit_script")"
expect 'meta'     v7.0.0-2   "$(merge "$edit_meta")"

# The image tag is built from `redmine_distro` as well, so a change of flavour
# ships a different image without touching `redmine_version`. It has to be
# released, and under the version that is still in the file.
scenario 'A distro change, which moves the image but not the version'
expect 'distro change' v7.0.0-2 "$(merge "$bump_distro")"

scenario 'Release numbers past 9'
for release_number in 2 3 4 5 6 7 8 9 10; do
	git tag "v7.0.0-$release_number"
done
expect 'a task' v7.0.0-11 "$(merge "$edit_task")"

# This repository carries tags from before the current naming settled, among
# them the bare `v7-0` that the commit-message-driven workflow published for
# the 7.0.0 bump. Counting releases of 7.0.0 must not be confused by them.
scenario 'Legacy tags that predate the current naming'
git tag 'v7-0'
git tag 'v6.1.3-1'
expect 'a task' v7.0.0-2 "$(merge "$edit_task")"

# A tag under this version that is not a release number at all must be ignored
# rather than counted or parsed as one.
scenario 'A non-numeric release suffix under the same version'
git tag 'v7.0.0-rc1'
expect 'a task' v7.0.0-2 "$(merge "$edit_task")"

scenario 'Reverting to an already released version'
merge "$bump_version" > /dev/null
# The role is now identical to what v7.0.0-1 already published, so there is
# nothing new to release.
expect 'a revert' ''       "$(merge "$revert_version")"

scenario 'Reverting to an already released version, with a change'
merge "$bump_version" > /dev/null
expect 'a revert' v7.0.0-2 "$(merge "$revert_version && $edit_task")"

if [ "$failures" -gt 0 ]; then
	echo >&2 "$failures scenario(s) behaved unexpectedly"
	exit 1
fi

echo 'All scenarios behaved as expected'
