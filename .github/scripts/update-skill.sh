#!/usr/bin/env bash
# Update a single skill from its upstream source declared in skills-lock.yaml.
#
# Usage: .github/scripts/update-skill.sh <skill-name>
#
# Behaviour:
#   1. Read {repo, path, ref, sha} for <skill-name> from skills-lock.yaml.
#   2. Resolve HEAD commit SHA of <ref> on <repo> via `gh api`.
#   3. If new SHA == current SHA, exit 0 with no changes.
#   4. Download the tarball at the new SHA, mirror <path>/ into ./<skill-name>/.
#   5. Bump the `sha` field in skills-lock.yaml.
#   6. Emit GitHub Actions outputs (`changed`, `old_sha`, `new_sha`, `repo`) if
#      $GITHUB_OUTPUT is set.
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

repo=$(yq -r ".skills.\"$skill\".repo // \"\"" "$lock")
path=$(yq -r ".skills.\"$skill\".path // \"\"" "$lock")
ref=$(yq  -r ".skills.\"$skill\".ref  // \"\"" "$lock")
old_sha=$(yq -r ".skills.\"$skill\".sha  // \"\"" "$lock")

if [[ -z "$repo" || -z "$path" || -z "$ref" ]]; then
  echo "skill '$skill' missing from $lock or has empty fields" >&2
  exit 1
fi

echo "==> $skill: $repo@$ref ($path)"
new_sha=$(gh api "/repos/$repo/commits/$ref" -q '.sha')
echo "    old: ${old_sha:-<none>}"
echo "    new: $new_sha"

emit_output() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

emit_output repo "$repo"
emit_output old_sha "$old_sha"
emit_output new_sha "$new_sha"

if [[ "$new_sha" == "$old_sha" ]]; then
  echo "    up to date"
  emit_output changed "false"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "    fetching tarball"
gh api "/repos/$repo/tarball/$new_sha" > "$tmp/src.tar.gz"

# Tarball root is "<owner>-<repo>-<short-sha>/"; discover it and strip.
root=$(tar -tzf "$tmp/src.tar.gz" | head -1 | cut -d/ -f1)
[[ -n "$root" ]] || { echo "    empty tarball" >&2; exit 1; }

src="$tmp/src/$path"
mkdir -p "$tmp/src"
tar -xzf "$tmp/src.tar.gz" -C "$tmp/src" --strip-components=1 "$root/$path"

[[ -d "$src" ]] || { echo "    path '$path' not found in tarball" >&2; exit 1; }

dest="$repo_root/$skill"
echo "    mirroring $path -> $skill/"
rm -rf "$dest"
mkdir -p "$dest"
# Copy contents (including dotfiles) while excluding the directory self-link.
( cd "$src" && tar -cf - . ) | ( cd "$dest" && tar -xf - )

echo "    bumping lock file"
SKILL="$skill" NEW_SHA="$new_sha" yq -i '.skills[strenv(SKILL)].sha = strenv(NEW_SHA)' "$lock"

emit_output changed "true"
echo "    done"
