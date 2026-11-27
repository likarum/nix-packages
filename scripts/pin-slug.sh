#!/usr/bin/env bash
# Print the identity of the pin currently in the working tree, as used in a
# branch name. One release, one branch, one pull request: the updater names its
# branch after this, so a new release opens its own pull request instead of
# rewriting the pull request of the previous one and resetting its cooldown.
set -euo pipefail

package="${1:?usage: pin-slug.sh PACKAGE}"

case "$package" in
inputs)
	slug=$(jq -r '[.nodes.nixpkgs.locked.rev, .nodes["nixpkgs-unstable"].locked.rev]
	              | map(.[0:7]) | join("-")' flake.lock)
	;;
claude-desktop | chatgpt-desktop | coroslink)
	slug=$(jq -r .version "pkgs/$package/sources.json")
	;;
*)
	echo "unknown package: $package" >&2
	exit 1
	;;
esac

# The slug lands in a git ref and in a shell argument; refuse anything that
# could reshape either instead of trusting an upstream version string.
if [[ ! $slug =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
	echo "refusing unexpected pin identity: $slug" >&2
	exit 1
fi

printf '%s\n' "$slug"
