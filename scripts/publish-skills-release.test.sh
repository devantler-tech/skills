#!/usr/bin/env bash
#
# Self-test for publish-skills-release.sh — pins the one property the script
# exists for and the three ways it must refuse to guess.
#
# The script decides whether `gh skill publish` should run at all. Getting that
# decision wrong is expensive in both directions: skipping a publish that never
# happened ships nothing while reporting success, and re-attempting a publish that
# already happened is exactly the unrecoverable red run this script was written to
# end (devantler-tech/agent-skills#106). Neither direction is observable from CI,
# which always has a real gh and a real repository, so every case below drives the
# script against a stubbed `gh` on PATH and asserts BOTH the exit status and
# whether `gh skill publish` was actually invoked.
#
# Each case builds its own PATH-first stub directory and a marker file the stub
# appends to, so "did it publish?" is a fact recorded by the stub rather than an
# inference from output text.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script="$script_dir/publish-skills-release.sh"

[ -x "$script" ] || {
  printf 'publish-skills-release.test: %s is missing or not executable\n' "$script" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
cases=0

# make_stub <case> <tag-ref-behaviour> <release-behaviour> <publish-behaviour> <target>
#
# Writes a `gh` stub that records every `gh skill publish` invocation to
# "$case_dir/published" and answers the two read paths as the case requires.
make_stub() {
  case_dir="$work/$1"
  mkdir -p "$case_dir/bin"
  : >"$case_dir/published"

  cat >"$case_dir/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "api repos/owner/repo/commits/v1.0.0")
    case "$5" in
      match) echo '1111111111111111111111111111111111111111' ;;
      mismatch) echo '2222222222222222222222222222222222222222' ;;
      unreadable) echo 'gh: connection refused' >&2; exit 1 ;;
      malformed) echo 'null' ;;
    esac
    ;;
  "api repos/"*)
    case "$2" in
      found) exit 0 ;;
      missing) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      broken) echo "gh: connection refused" >&2; exit 1 ;;
    esac
    ;;
  "release view")
    case "$3" in
      published) echo '{"tagName":"v1.0.0","isDraft":false}' ;;
      draft) echo '{"tagName":"v1.0.0","isDraft":true}' ;;
      wrong-tag) echo '{"tagName":"v2.0.0","isDraft":false}' ;;
      absent) echo "release not found" >&2; exit 1 ;;
    esac
    ;;
  "skill publish")
    echo "publish \$*" >>"$case_dir/published"
    case "$4" in
      ok) echo "Published" ;;
      fails) echo "gh: publish exploded" >&2; exit 1 ;;
    esac
    ;;
esac
STUB
  chmod +x "$case_dir/bin/gh"
  printf '%s' "$case_dir"
}

# assert_case <name> <tag-ref> <release> <publish> <expected-exit> <expected-published:yes|no>
assert_case() {
  name=$1
  expected_exit=$5
  expected_published=$6
  cases=$((cases + 1))

  case_dir=$(make_stub "$name" "$2" "$3" "$4" "${7:-match}")

  set +e
  GITHUB_SHA="${8-1111111111111111111111111111111111111111}" \
    PATH="$case_dir/bin:$PATH" "$script" --tag v1.0.0 --repo owner/repo \
    >"$case_dir/out" 2>"$case_dir/err"
  actual_exit=$?
  set -e

  if [ -s "$case_dir/published" ]; then
    actual_published=yes
  else
    actual_published=no
  fi

  if [ "$actual_exit" -ne "$expected_exit" ]; then
    printf 'FAIL %s: exit %s, want %s\n' "$name" "$actual_exit" "$expected_exit" >&2
    sed 's/^/     /' "$case_dir/err" >&2
    failures=$((failures + 1))
    return
  fi

  if [ "$actual_published" != "$expected_published" ]; then
    printf 'FAIL %s: published=%s, want %s\n' "$name" "$actual_published" "$expected_published" >&2
    failures=$((failures + 1))
    return
  fi

  printf 'ok   %s (exit %s, published=%s)\n' "$name" "$actual_exit" "$actual_published"
}

# The ordinary release: nothing published yet, so it publishes.
assert_case unpublished-publishes missing absent ok 0 yes

# The property this script exists for: a re-run of a job whose publish already
# succeeded must SUCCEED WITHOUT re-publishing, so the steps after it can run.
assert_case already-published-skips found published ok 0 no

# A release for a different commit must never satisfy this run's publication.
assert_case different-commit-refuses found published ok 1 no mismatch
assert_case unreadable-commit-refuses found published ok 1 no unreadable
assert_case malformed-commit-refuses found published ok 1 no malformed
assert_case different-release-tag-refuses found wrong-tag ok 1 no
assert_case missing-expected-commit-refuses found published ok 2 no match ''
assert_case abbreviated-expected-commit-refuses found published ok 2 no match 1111111

# A publish that genuinely fails must still fail. The skip path must never be
# reachable in a way that masks a real publish error.
assert_case publish-failure-propagates missing absent fails 1 yes

# A tag with no release is a half-finished publish, not a finished one. Refuse
# rather than skip: skipping here would report success for a release that does
# not exist.
assert_case tag-without-release-fails found absent ok 1 no

# A draft release is likewise unfinished.
assert_case draft-release-fails found draft ok 1 no

# An unreadable precondition proves nothing. It must not resolve to either
# "publish" or "skip" — both would be guesses.
assert_case unreadable-tag-state-fails broken absent ok 1 no

# Usage errors are distinguishable from publish failures.
cases=$((cases + 1))
set +e
"$script" --repo owner/repo >/dev/null 2>&1
usage_exit=$?
set -e
if [ "$usage_exit" -eq 2 ]; then
  printf 'ok   missing-tag-is-usage-error (exit 2)\n'
else
  printf 'FAIL missing-tag-is-usage-error: exit %s, want 2\n' "$usage_exit" >&2
  failures=$((failures + 1))
fi

printf '\n%s case(s), %s failure(s)\n' "$cases" "$failures"
[ "$failures" -eq 0 ]
