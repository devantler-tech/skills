#!/usr/bin/env bash
#
# Verify every UPSTREAM skill row in the README index still resolves to a real
# skill on its source repo. This is the network half of the index→source
# lockstep: `check-readme-index.sh` proves the in-house `devantler-tech/agent-skills`
# self-pointers resolve on disk (offline), but it explicitly CANNOT verify that
# each upstream `gh skill install <owner/repo> <skill>` target still exists —
# that needs network + auth. A typo'd, renamed, or upstream-deleted repo/skill
# slug passes the offline count-lockstep gate and only fails at *consume* time,
# rippling across every consumer — the highest-blast-radius failure for this
# shared library — so it is worth catching proactively.
#
# For each non-in-house `## Skills` row it parses the `Upstream` tree URL
# (https://github.com/<owner>/<repo>/tree/<ref>/<path>) and confirms via the
# GitHub API that <path>/SKILL.md exists on <ref> — i.e. the skill that
# `gh skill install` would fetch is still present at the pointer the index
# advertises.
#
# Because it depends on third-party availability, this is intentionally NOT part
# of the PR-blocking `lint-scripts`/`CI - Required Checks` gate (an upstream
# outage must never flake an unrelated contributor PR). It runs on a schedule
# (see .github/workflows/check-upstream-skills.yaml) and fails visibly on real
# drift. To keep a transient GitHub blip from reporting *false* drift, network /
# rate-limit / 5xx errors are retried and, if still failing, downgraded to a
# ::warning:: (non-fatal). HTTP 404 is hard drift; a successful response that
# does not identify the requested file is a separate hard verification failure.
#
# Assumes upstream tree URLs pin a single-segment ref (e.g. `main`), which every
# current index row does; the ref is the first path segment after `/tree/`.
#
# Usage: ./scripts/check-upstream-skills.sh   (requires gh auth / GH_TOKEN)
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
cd "$repo_root"

if ! command -v gh >/dev/null 2>&1; then
  echo "::error::'gh' is required to resolve upstream skill targets." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "::error::'jq' is required to validate upstream skill file responses." >&2
  exit 1
fi

# Backoff command between transient-failure retries. Defaults to the real `sleep`
# (production behaviour unchanged); the offline self-test overrides it to a no-op so
# the persistent-transient → warning path runs without real backoff.
UPSTREAM_RETRY_SLEEP=${UPSTREAM_RETRY_SLEEP:-sleep}

# Resolve one upstream skill target. Echoes nothing on success; on a definitive
# miss returns 1 (hard drift); on persistent transport failure returns 2 (warn);
# on an invalid successful response returns 3 (verification failure).
resolve_target() {
  local owner=$1 repo=$2 ref=$3 path=$4
  local attempt err
  for attempt in 1 2 3; do
    if err=$(gh api "repos/$owner/$repo/contents/$path/SKILL.md?ref=$ref" 2>&1); then
      # Validate after the API call so a directory or malformed payload cannot be
      # mistaken for a transport error and downgraded to a transient warning.
      if printf '%s' "$err" | jq -es --arg path "$path/SKILL.md" '
        length == 1 and (.[0] | type == "object"
          and .type == "file" and .name == "SKILL.md" and .path == $path)
      ' >/dev/null 2>&1; then
        return 0
      fi
      return 3
    fi
    # HTTP 404 = the path/skill genuinely no longer exists at this pointer.
    if printf '%s' "$err" | grep -q 'HTTP 404'; then
      return 1
    fi
    # Anything else (network, 5xx, secondary-rate-limit/403) may be transient —
    # back off and retry before deciding.
    "$UPSTREAM_RETRY_SLEEP" $((attempt * 2))
  done
  printf '%s' "$err"
  return 2
}

# Scope to the `## Skills` section, keep only table rows that carry an Upstream
# github tree URL, and drop the in-house `devantler-tech/agent-skills` self-pointers
# (covered offline by check-readme-index.sh).
rows=$(awk '/^## Skills[[:space:]]*$/{in_skills=1; next} /^## /{in_skills=0} in_skills' README.md \
  | grep -E '^\| ' \
  | grep 'https://github.com/' \
  | grep -v 'devantler-tech/agent-skills' || true)

if [ -z "$rows" ]; then
  echo "::error::No upstream skill rows parsed from the README '## Skills' index — the tables or parser drifted."
  exit 1
fi

checked=0
drift=0
warned=0
invalid=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  url=$(printf '%s' "$row" | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/tree/[^ )]+' | head -n1)
  if [ -z "$url" ]; then
    echo "::error::could not parse an Upstream tree URL from index row: $row"
    drift=1
    continue
  fi
  rest=${url#https://github.com/}
  owner=${rest%%/*}
  rest=${rest#*/}
  repo=${rest%%/*}
  rest=${rest#*/tree/}
  ref=${rest%%/*}
  path=${rest#*/}
  if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$ref" ] || [ -z "$path" ] || [ "$path" = "$rest" ]; then
    echo "::error::malformed Upstream tree URL '$url' in index row: $row"
    drift=1
    continue
  fi

  checked=$((checked + 1))
  if detail=$(resolve_target "$owner" "$repo" "$ref" "$path"); then
    echo "  ok    $owner/$repo @ $ref :: $path/SKILL.md"
  else
    case $? in
      1)
        echo "::error::upstream skill target '$owner/$repo $path' (ref $ref) no longer resolves — no '$path/SKILL.md' on $ref. The README row points at a renamed/deleted upstream skill; every consumer's 'gh skill install' will fail."
        drift=1
        ;;
      3)
        echo "::error::could not establish upstream skill file '$owner/$repo $path/SKILL.md' (ref $ref): successful API response does not identify the expected file."
        invalid=$((invalid + 1))
        ;;
      *)
        echo "::warning::could not verify '$owner/$repo $path' (ref $ref) after retries — treating as transient (network/rate-limit), not drift. Last error: ${detail//$'\n'/ }"
        warned=$((warned + 1))
        ;;
    esac
  fi
done <<<"$rows"

echo
echo "Checked $checked upstream target(s); drift=$drift, transient-warnings=$warned, invalid-responses=$invalid."
if [ "$drift" -ne 0 ]; then
  echo "::error::Upstream skill drift detected — fix the broken README index row(s) above."
  exit 1
fi
if [ "$invalid" -ne 0 ]; then
  echo "::error::Upstream skill verification failed — inspect the invalid file responses above."
  exit 1
fi
