#!/usr/bin/env bash
# Update a single skill from its upstream source declared in skills-lock.yaml.
#
# Usage: .github/scripts/update-skill.sh <skill-name>
#
# Behaviour:
#   1. Read {repo, path, ref, commit, tree} for <skill-name> from skills-lock.yaml.
#   2. Resolve the upstream tree SHA for <path> at <ref> via `gh api`.
#   3. If the tree SHA matches the lock, exit 0 with no changes — the skill's
#      content is unchanged even if new commits landed on the upstream repo.
#   4. Otherwise resolve the new commit SHA, download that tarball, mirror
#      <path>/ into ./<skill-name>/, and bump `commit` + `tree` in the lock.
#   5. Emit GitHub Actions outputs (`changed`, `repo`, `old_commit`, `new_commit`,
#      `old_tree`, `new_tree`) if $GITHUB_OUTPUT is set.
#
# This mirrors the content-addressed change detection used by `gh skill update`
# (see https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/).
#
# Dependencies: gh, yq (mikefarah), jq, tar.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <skill-name>" >&2
  exit 2
fi

skill="$1"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
lock="${repo_root}/skills-lock.yaml"

for bin in gh yq jq tar; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 127; }
done

[[ -f "$lock" ]] || { echo "skills-lock.yaml not found at $lock" >&2; exit 1; }

get() { yq -r ".skills.\"$skill\".$1 // \"\"" "$lock"; }
repo=$(get repo); path=$(get path); ref=$(get ref)
old_commit=$(get commit); old_tree=$(get tree)

if [[ -z "$repo" || -z "$path" || -z "$ref" ]]; then
  echo "skill '$skill' missing from $lock or has empty fields" >&2
  exit 1
fi

echo "==> $skill: $repo@$ref ($path)"

# Resolve the tree SHA of `path` at the tip of `ref`. For nested paths, the
# contents API on the parent directory is the cheapest single-call option.
parent=$(dirname "$path"); leaf=$(basename "$path")
if [[ "$parent" == "." ]]; then
  new_tree=$(gh api "repos/$repo/git/trees/$ref" -q ".tree[] | select(.path==\"$leaf\") | .sha")
else
  new_tree=$(gh api "repos/$repo/contents/$parent?ref=$ref" \
    -q ".[] | select(.name==\"$leaf\") | .sha")
fi

if [[ -z "$new_tree" ]]; then
  echo "    path '$path' not found on $repo@$ref" >&2
  exit 1
fi

echo "    old tree: ${old_tree:-<none>}"
echo "    new tree: $new_tree"

emit_output() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

emit_output repo "$repo"
emit_output old_commit "$old_commit"
emit_output old_tree "$old_tree"
emit_output new_tree "$new_tree"

if [[ "$new_tree" == "$old_tree" ]]; then
  echo "    up to date (content unchanged)"
  emit_output changed "false"
  exit 0
fi

new_commit=$(gh api "repos/$repo/commits/$ref" -q '.sha')
emit_output new_commit "$new_commit"
echo "    new commit: $new_commit"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "    fetching tarball"
gh api "repos/$repo/tarball/$new_commit" > "$tmp/src.tar.gz"

root=$(tar -tzf "$tmp/src.tar.gz" | head -1 | cut -d/ -f1)
[[ -n "$root" ]] || { echo "    empty tarball" >&2; exit 1; }

mkdir -p "$tmp/src"
tar -xzf "$tmp/src.tar.gz" -C "$tmp/src" --strip-components=1 "$root/$path"
src="$tmp/src/$path"
[[ -d "$src" ]] || { echo "    path '$path' not found in tarball" >&2; exit 1; }

dest="$repo_root/$skill"
echo "    mirroring $path -> $skill/"
rm -rf "$dest"
mkdir -p "$dest"
( cd "$src" && tar -cf - . ) | ( cd "$dest" && tar -xf - )

echo "    bumping lock file"
SKILL="$skill" COMMIT="$new_commit" TREE="$new_tree" yq -i '
  .skills[strenv(SKILL)].commit = strenv(COMMIT)
  | .skills[strenv(SKILL)].tree = strenv(TREE)
' "$lock"

emit_output changed "true"
echo "    done"
