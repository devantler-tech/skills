#!/usr/bin/env bash
#
# Self-test for check-upstream-skills.sh — the *network half* of the index→source
# lockstep. The real script resolves each upstream `gh skill install` target
# against its source repo, so it cannot run in the PR-blocking gate (a third-party
# outage must never flake a contributor PR). But its parsing + control flow — which
# `## Skills` rows it scopes to, how it extracts owner/repo/ref/path from an Upstream
# tree URL, which failures are *hard drift* (HTTP 404), invalid file responses, or
# *transient warnings*, and that it fails closed when the parser finds nothing — is pure
# offline logic that a refactor can silently break, rippling a wrong/skipped check
# across every consumer of this shared library. This pins that logic.
#
# The script's ONLY network dependency is `gh api`, so each case runs against a
# deterministic offline `gh` STUB (prepended to PATH) that decides success / 404 /
# 5xx purely from the requested repo slug — no gh auth, no network. Mirrors the
# sibling check-readme-index.test.sh / install.test.sh idiom: check-upstream-skills.sh
# resolves its repo root as `scripts/..` and `cd`s there (no env override), so every
# case is a self-contained fixture tree (<case>/scripts/check-upstream-skills.sh +
# <case>/README.md) into which the REAL script is copied and run. Wired into the
# `lint-scripts` CI gate so a refactor that silently weakens the guard is caught here.
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

# A deterministic, offline `gh` stub. The script invokes only
# `gh api repos/<owner>/<repo>/contents/<path>/SKILL.md?ref=<ref>`. The stub keys its
# verdict off the repo slug embedded in the fixtures: a slug containing 'deleted'
# returns a definitive 404 (hard drift); one containing 'flaky' returns a 5xx (a
# persistent transient → retried then downgraded to a warning); anything else
# returns a file response. It also supports the old inline jq form so the new
# regression cases reproduce the old guard's false successes. It mimics `gh`'s real error shape so the script's
# `grep -q 'HTTP 404'` discriminator is exercised for real.
stub_bin="$tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
target=""
filter=""
for a in "$@"; do
  case "$a" in repos/*/contents/*) target="$a" ;; esac
done
if [ "${3:-}" = --jq ]; then filter="$4"; fi
printf '%s\n' "$target" >> "$UPSTREAM_CALL_LOG"
path=${target#*/contents/}
path=${path%%\?*}
case "$target" in
  *deleted*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *flaky*)   echo "gh: Service Unavailable (HTTP 503)" >&2; exit 1 ;;
  *limited*) echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1 ;;
  *recover*)
    if [ "$(grep -cF "$target" "$UPSTREAM_CALL_LOG")" -lt 3 ]; then
      echo "gh: Service Unavailable (HTTP 503)" >&2; exit 1
    fi ;;
esac
case "$target" in
  *directory*) body='[]' ;;
  *null-body*) body='null' ;;
  *empty-body*) body='' ;;
  *malformed*) body='not json' ;;
  *wrong-name*) body=$(jq -nc --arg path "$path" '{type:"file",name:"OTHER.md",path:$path}') ;;
  *wrong-path*) body='{"type":"file","name":"SKILL.md","path":"elsewhere/SKILL.md"}' ;;
  *symlink*) body=$(jq -nc --arg path "$path" '{type:"symlink",name:"SKILL.md",path:$path}') ;;
  *missing-type*) body=$(jq -nc --arg path "$path" '{name:"SKILL.md",path:$path}') ;;
  *) body=$(jq -nc --arg path "$path" '{type:"file",name:"SKILL.md",path:$path}') ;;
esac
if [ -n "$filter" ]; then
  printf '%s\n' "$body" | jq -r "$filter"
else
  printf '%s\n' "$body"
fi
STUB
chmod +x "$stub_bin/gh"
export PATH="$stub_bin:$PATH"

# No-op the guard's transient-retry backoff so the persistent-5xx case runs
# instantly (the script defaults this to the real `sleep`).
export UPSTREAM_RETRY_SLEEP=true
export UPSTREAM_CALL_LOG="$tmp/calls"

run_guard() { # root
  bash "$1/scripts/check-upstream-skills.sh"
}

pass_case() { # name root
  if run_guard "$2" >/dev/null 2>&1; then
    printf '  ✅ %s — passed as expected\n' "$1"
  else
    printf '  ❌ %s — expected PASS but the guard FAILED\n' "$1"; fail=1
  fi
}

fail_case() { # name root
  if run_guard "$2" >/dev/null 2>&1; then
    printf '  ❌ %s — expected FAIL but the guard PASSED\n' "$1"; fail=1
  else
    printf '  ✅ %s — failed as expected\n' "$1"
  fi
}

# Build a fixture repo root at $1: the REAL guard in scripts/, and a README whose
# `## Skills` table body is read from stdin. A trailing `## Installing` section
# carries an Upstream tree URL pointing at a *would-404* target that must NOT be
# checked — proving the parser stays scoped to `## Skills` (if it leaked, the
# healthy case would fail).
make_root() { # root  <<rows
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/scripts"
  cp "$here/check-upstream-skills.sh" "$root/scripts/"
  {
    printf '# Test catalogue\n\n## Skills\n\n'
    printf '| Skill | Upstream | Install |\n|-------|----------|---------|\n'
    cat
    # The backticks below are literal markdown, not a command substitution.
    # shellcheck disable=SC2016
    printf '\n## Installing\n\nExample (must NOT be resolved): [`x/deleted-oos`](https://github.com/x/deleted-oos/tree/main/skills/zzz)\n'
  } > "$root/README.md"
}

# 0. Healthy index → PASS. One resolving upstream row (alpha) plus an in-house
#    devantler-tech/agent-skills self-pointer (beta) that must be SKIPPED (its
#    on-disk resolution is the offline check-readme-index.sh's job, never the
#    network here — so the stub is never asked about it). Guards against a guard
#    that fails-closed on a correct index, and the `## Installing` would-404 URL
#    staying unresolved proves `## Skills` scoping.
good="$tmp/good"
make_root "$good" <<'EOF'
| `alpha` | [`fluxcd/present`](https://github.com/fluxcd/present/tree/main/skills/alpha) | `gh skill install fluxcd/present alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
EOF
pass_case "healthy upstream index (in-house row skipped, ## Installing not resolved)" "$good"

# 1. No upstream rows parsed → FAIL closed. Only an in-house row is present, so
#    after the in-house filter the parser yields nothing — the script must error
#    rather than vacuously pass (models a drifted Skills table / parser).
c="$tmp/no-upstream"
make_root "$c" <<'EOF'
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
EOF
fail_case "no upstream rows parsed (fails closed on parser drift)" "$c"

# 2. Upstream target deleted/renamed (HTTP 404) → hard drift, FAIL. The core
#    purpose: a pointer that no longer resolves must break the build.
c="$tmp/drift-404"
make_root "$c" <<'EOF'
| `alpha` | [`fluxcd/present`](https://github.com/fluxcd/present/tree/main/skills/alpha) | `gh skill install fluxcd/present alpha` |
| `gamma` | [`fluxcd/deleted`](https://github.com/fluxcd/deleted/tree/main/skills/gamma) | `gh skill install fluxcd/deleted gamma` |
EOF
fail_case "upstream target 404 (renamed/deleted) is hard drift" "$c"

# 3. Row carries a github URL but no `/tree/` segment → unparseable Upstream tree
#    URL → FAIL. Pins the per-row "could not parse an Upstream tree URL" branch.
c="$tmp/no-tree-url"
make_root "$c" <<'EOF'
| `alpha` | [`fluxcd/present`](https://github.com/fluxcd/present) | `gh skill install fluxcd/present alpha` |
EOF
fail_case "Upstream URL without /tree/ segment is unparseable" "$c"

# 4. Tree URL present but missing the <path> after <ref> → malformed → FAIL. Pins
#    the owner/repo/ref/path decomposition's malformed-URL guard.
c="$tmp/malformed-url"
make_root "$c" <<'EOF'
| `alpha` | [`fluxcd/present`](https://github.com/fluxcd/present/tree/main) | `gh skill install fluxcd/present alpha` |
EOF
fail_case "Upstream tree URL missing the path segment is malformed" "$c"

# 5. Persistent non-404 error (5xx) → transient WARNING, not drift → PASS. Pins
#    the HTTP-404-only-is-hard discrimination: an upstream blip retries then
#    downgrades to ::warning:: and the script still exits 0 (a third-party outage
#    never reports false drift). (Exercises the script's retry/backoff path.)
c="$tmp/transient-5xx"
make_root "$c" <<'EOF'
| `alpha` | [`fluxcd/present`](https://github.com/fluxcd/present/tree/main/skills/alpha) | `gh skill install fluxcd/present alpha` |
| `delta` | [`fluxcd/flaky`](https://github.com/fluxcd/flaky/tree/main/skills/delta) | `gh skill install fluxcd/flaky delta` |
EOF
pass_case "persistent 5xx is a transient warning, not drift (still exits 0)" "$c"

# Successful transport must prove the requested file, not merely yield a zero status.
# Each invalid target is accompanied by a real file to prove one bad response does not
# hide the independent healthy result. Invalid payloads must not enter the retry loop.
for shape in directory null-body empty-body malformed wrong-name wrong-path symlink missing-type; do
  c="$tmp/$shape"
  make_root "$c" <<EOF
| alpha | [test/present](https://github.com/test/present/tree/main/skills/alpha) | install |
| bad | [test/$shape](https://github.com/test/$shape/tree/main/skills/bad) | install |
EOF
  : > "$UPSTREAM_CALL_LOG"
  rc=0
  output=$(run_guard "$c" 2>&1) || rc=$?
  if [ "$rc" -eq 1 ] && [[ "$output" == *'invalid-responses=1'* ]] \
    && [[ "$output" == *'ok    test/present'* ]] \
    && [[ "$output" != *"ok    test/$shape"* ]] \
    && [ "$(grep -cF "repos/test/$shape/" "$UPSTREAM_CALL_LOG")" -eq 1 ]; then
    printf '  ✅ %s response rejected without retry or false health\n' "$shape"
  else
    printf '  ❌ %s response was not rejected correctly (exit %s)\n%s\n' "$shape" "$rc" "$output"
    fail=1
  fi
done

for transport in flaky limited recover; do
  c="$tmp/retry-$transport"
  make_root "$c" <<EOF
| alpha | [test/$transport](https://github.com/test/$transport/tree/main/skills/alpha) | install |
EOF
  : > "$UPSTREAM_CALL_LOG"
  rc=0
  output=$(run_guard "$c" 2>&1) || rc=$?
  expected='transient-warnings=1'
  [ "$transport" != recover ] || expected='transient-warnings=0'
  if [ "$rc" -eq 0 ] && [[ "$output" == *"$expected"* ]] \
    && [ "$(wc -l < "$UPSTREAM_CALL_LOG" | tr -d ' ')" -eq 3 ]; then
    printf '  ✅ %s transport retains bounded retry behavior\n' "$transport"
  else
    printf '  ❌ %s transport retry contract failed\n%s\n' "$transport" "$output"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  printf '❌ check-upstream-skills self-test FAILED\n' >&2
  exit 1
fi
printf '✅ check-upstream-skills self-test passed (17 cases)\n'
