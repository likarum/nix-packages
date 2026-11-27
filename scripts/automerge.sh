#!/usr/bin/env bash
# Merge the update pull requests of one package that cleared the cooldown.
#
# The cooldown is the age of the pull request itself. One pull request carries
# one release, so a newer release never resets it: it gets its own branch and
# its own pull request, which waits its own cooldown. Pull requests are handled
# oldest release first; each one is replayed on top of the current main before
# its turn, so merging one does not leave the next in conflict.
#
# Nothing here reviews a recipe. A green build does not prove that login, the
# keyring or the NPU still work, and this script does not claim otherwise.
set -euo pipefail

package="${1:?usage: automerge.sh PACKAGE}"
cooldown_days="${COOLDOWN_DAYS:?COOLDOWN_DAYS is required}"
dry_run="${DRY_RUN:-false}"

# The one generated file the updater is allowed to change for this package.
case "$package" in
inputs) pinned=flake.lock ;;
claude-desktop | chatgpt-desktop | coroslink) pinned="pkgs/$package/sources.json" ;;
*)
	echo "unknown package: $package" >&2
	exit 1
	;;
esac

bot_name='github-actions[bot]'
bot_mail='41898282+github-actions[bot]@users.noreply.github.com'
cutoff=$(date -u -d "-$cooldown_days days" +%s)
failed=0

# Candidates: open, non-draft pull requests opened by the updater in its own
# branch namespace, without the "hold" label. A human branch, a draft or a
# held pull request is never merged by this job.
candidates=$(gh pr list --state open --base main --limit 100 \
	--json number,createdAt,headRefName,author,isDraft,labels \
	--jq "[ .[]
	        | select(.author.is_bot and .isDraft == false)
	        | select(.headRefName | startswith(\"updates/$package/\"))
	        | select([.labels[].name] | index(\"hold\") == null)
	      ]
	      | sort_by(.createdAt)
	      | .[] | [.number, .createdAt, .headRefName] | @tsv")

if [[ -z $candidates ]]; then
	echo "$package: no automatic update pull request is open"
	exit 0
fi

while IFS=$'\t' read -r number created branch; do
	opened=$(date -u -d "$created" +%s)
	age=$((($(date -u +%s) - opened) / 86400))
	if ((opened > cutoff)); then
		echo "$package: #$number is $age day(s) old, cooldown is $cooldown_days; left open"
		continue
	fi

	# The updater only ever rewrites one generated file. Refuse to merge a
	# branch that carries anything else, whoever pushed it.
	touched=$(gh pr diff "$number" --name-only)
	if [[ $touched != "$pinned" ]]; then
		echo "::warning::$package #$number touches '$touched', not '$pinned' alone; left open"
		failed=1
		continue
	fi

	git fetch --no-tags --quiet origin \
		"+refs/heads/main:refs/remotes/origin/main" \
		"+refs/heads/$branch:refs/remotes/origin/$branch"
	base=$(git rev-parse refs/remotes/origin/main)
	head=$(git rev-parse "refs/remotes/origin/$branch")

	# Replay the pin on top of main rather than rebasing: the pull request
	# replaces one generated file whole, so taking its version of that file is
	# the whole change and cannot conflict. Force-pushing the result keeps the
	# pull request, and therefore its cooldown, intact.
	git switch --detach --quiet "$base"
	git checkout --quiet "$head" -- "$pinned"
	if git diff --quiet --cached HEAD -- "$pinned"; then
		echo "$package: #$number proposes the pin already on main"
		if [[ $dry_run != true ]]; then
			gh pr close "$number" --delete-branch \
				--comment "Superseded: this pin is already on \`main\`. Closed by the Auto-merge job."
		fi
		continue
	fi

	version=$(./scripts/pin-slug.sh "$package")
	if [[ $dry_run == true ]]; then
		echo "$package: #$number ($version, $age day(s) old) would be merged"
		git checkout --quiet HEAD -- "$pinned"
		continue
	fi

	git -c "user.name=$bot_name" -c "user.email=$bot_mail" \
		commit --quiet -m "chore($package): update pin to $version" -- "$pinned"
	if [[ $(git rev-list --count "$head" --not "$base") == 1 &&
		$(git rev-parse "$head^{tree}") == $(git rev-parse 'HEAD^{tree}') ]]; then
		echo "$package: #$number already sits on top of main"
	else
		git push --force-with-lease="refs/heads/$branch:$head" --quiet origin \
			"HEAD:refs/heads/$branch"
		echo "$package: #$number replayed on top of main"
	fi

	# Pull requests opened with GITHUB_TOKEN do not trigger the Check
	# workflow, and this content has never been built as it is now. Build it
	# here, like the updater does before opening a pull request.
	if ! nix flake check --print-build-logs; then
		gh pr comment "$number" --body \
			"Auto-merge held this pull request back: \`nix flake check\` failed on this pin replayed on top of \`main\`. See the Auto-merge run for the build log. The pull request stays open; it needs a look."
		echo "::error::$package #$number failed nix flake check; left open"
		failed=1
		continue
	fi

	merged=false
	for _ in 1 2 3; do
		# GitHub needs a moment to recompute mergeability after the push.
		if gh pr merge "$number" --squash --delete-branch \
			--subject "chore($package): update pin to $version (#$number)" --body ''; then
			merged=true
			break
		fi
		sleep 10
	done
	if [[ $merged == true ]]; then
		echo "$package: merged #$number ($version)"
	else
		echo "::error::$package #$number passed its checks but could not be merged; branch protection or a concurrent push would explain it"
		failed=1
	fi
done <<<"$candidates"

exit "$failed"
