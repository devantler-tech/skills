#!/usr/bin/env bash
#
# Exercise release creation, completed reruns, and refusal boundaries using real
# Git checkouts and an offline GitHub stub. Each case observes both exit status
# and creation attempts, including the explicit repository, host, and SHA target.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script="$script_dir/publish-skills-release.sh"

[ -x "$script" ] || {
  printf 'publish-skills-release.test: %s is missing or not executable\n' "$script" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Real repositories exercise checkout identity, dirty files, and detached HEAD.
# Only GitHub is replaced: no test can create a remote release.
git init -q "$work/fixture"
printf 'fixture\n' >"$work/fixture/README.md"
git -C "$work/fixture" add README.md
git -C "$work/fixture" -c user.name=Fixture -c user.email=fixture@example.test \
  -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture --allow-empty
fixture_commit=$(git -C "$work/fixture" rev-parse HEAD)

failures=0
cases=0

# make_stub <case> <tag-ref-behaviour> <release-behaviour> <publish-behaviour> <target>
#
# Writes a `gh` stub that records publication in "$case_dir/published" and
# answers the tag, commit, release, and validation paths as the case requires.
make_stub() {
  local release_tag="${6:-v1.0.0}" release_tag_path="${7:-v1.0.0}"
  case_dir="$work/$1"
  mkdir -p "$case_dir/bin"
  : >"$case_dir/published"
  git clone -q --no-hardlinks "$work/fixture" "$case_dir/repo"
  git -C "$case_dir/repo" remote set-url origin https://github.com/owner/repo.git

  cat >"$case_dir/bin/gh" <<STUB
#!/usr/bin/env bash
[ "\${GH_HOST:-}" = github.com ] || { echo 'wrong publication host' >&2; exit 1; }
case "\$1 \$2" in
  "api repos/owner/repo/commits/$release_tag_path")
    # An unqualified ref can resolve a same-named branch at the expected commit.
    echo '$fixture_commit'
    ;;
  "api repos/owner/repo/commits/tags/$release_tag_path")
    case "$5" in
      match) echo '$fixture_commit' ;;
      mismatch|branch-collision) echo '2222222222222222222222222222222222222222' ;;
      unreadable) echo 'gh: connection refused' >&2; exit 1 ;;
      malformed) echo 'null' ;;
    esac
    ;;
  "api repos/owner/repo/git/ref/tags/$release_tag_path")
    case "$2" in
      found) exit 0 ;;
      missing) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      broken) echo "gh: connection refused" >&2; exit 1 ;;
    esac
    ;;
  "release view")
    [ "\$3" = '$release_tag' ] || exit 1
    case "$3" in
      published) echo '{"tagName":"$release_tag","isDraft":false}' ;;
      draft) echo '{"tagName":"v1.0.0","isDraft":true}' ;;
      wrong-tag) echo '{"tagName":"v2.0.0","isDraft":false}' ;;
      ambiguous) printf '%s\n' '{"tagName":"v1.0.0","isDraft":false}' '{"tagName":"v1.0.0","isDraft":false}' ;;
      absent) echo "release not found" >&2; exit 1 ;;
    esac
    ;;
  "skill publish")
    if [ "\$*" = 'skill publish --tag v1.0.0' ]; then
      echo 'unsafe branch-targeted publish' >>"$case_dir/published"
      [ "$4" != fails ] || exit 1
      exit 0
    fi
    [ "\$*" = 'skill publish --dry-run' ] || exit 1
    [ "$4" != invalid ] || exit 1
    echo 'Validated'
    ;;
  "release create")
    [ "\$*" = 'release create $release_tag --repo owner/repo --target $fixture_commit --generate-notes' ] || exit 1
    echo "publish \$*" >>"$case_dir/published"
    case "$4" in
      ok) echo "Published" ;;
      fails) echo "gh: publish exploded" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected gh command: \$*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$case_dir/bin/gh"
  printf '%s' "$case_dir"
}

# assert_case <name> <tag-ref> <release> <publish> <expected-exit> <expected-published:yes|no>
# Run the release gate against one isolated stub and compare its exit status and
# publish marker, accumulating failures so every case is exercised.
assert_case() {
  name=$1
  expected_exit=$5
  expected_published=$6
  cases=$((cases + 1))

  test_tag=${10:-v1.0.0}
  case_dir=$(make_stub "$name" "$2" "$3" "$4" "${7:-match}" "$test_tag" "${11:-v1.0.0}")
  invocation_dir="$case_dir/repo"
  case "${9:-match}" in
    wrong-repo) git -C "$case_dir/repo" remote set-url origin https://github.com/other/repo.git ;;
    no-origin) git -C "$case_dir/repo" remote remove origin ;;
    wrong-commit)
      git -C "$case_dir/repo" -c user.name=Fixture -c user.email=fixture@example.test \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm other --allow-empty ;;
    dirty) printf 'untracked skill\n' >"$case_dir/repo/SKILL.md" ;;
    tracked-dirty) printf 'changed\n' >>"$case_dir/repo/README.md" ;;
    assume-unchanged|skip-worktree)
      git -C "$case_dir/repo" update-index "--${9}" README.md
      printf 'hidden change\n' >>"$case_dir/repo/README.md" ;;
    staged-dirty)
      printf 'changed\n' >>"$case_dir/repo/README.md"
      git -C "$case_dir/repo" add README.md ;;
    subdirectory)
      mkdir -p "$case_dir/repo/nested"
      invocation_dir="$case_dir/repo/nested" ;;
    detached) git -C "$case_dir/repo" checkout -q --detach HEAD ;;
    ssh) git -C "$case_dir/repo" remote set-url origin git@github.com:owner/repo.git ;;
    ssh-url) git -C "$case_dir/repo" remote set-url origin ssh://git@github.com/owner/repo.git ;;
    mixed-https) git -C "$case_dir/repo" remote set-url origin https://GitHub.com/Owner/Repo.git ;;
    mixed-ssh) git -C "$case_dir/repo" remote set-url origin git@GitHub.com:Owner/Repo.git ;;
    mixed-ssh-url) git -C "$case_dir/repo" remote set-url origin ssh://git@GitHub.com/Owner/Repo.git ;;
    foreign-host) git -C "$case_dir/repo" remote set-url origin https://example.test/owner/repo.git ;;
  esac

  actual_exit=0
  (cd "$invocation_dir" && GITHUB_SHA="${8-$fixture_commit}" GH_REPO=other/selection GH_HOST=example.test \
    PATH="$case_dir/bin:$PATH" "$script" --tag "$test_tag" --repo owner/repo \
    >"$case_dir/out" 2>"$case_dir/err") || actual_exit=$?

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

  if grep -q 'unsafe branch-targeted publish' "$case_dir/published"; then
    printf 'FAIL %s: publication did not explicitly target the expected commit\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi

  printf 'ok   %s (exit %s, published=%s)\n' "$name" "$actual_exit" "$actual_published"
}

# The ordinary release: nothing published yet, so it publishes.
assert_case unpublished-publishes missing published ok 0 yes
assert_case fragment-tag-publishes missing published ok 0 yes match "$fixture_commit" match 'v1.2.3#retry' 'v1.2.3%23retry'
assert_case fragment-tag-rerun found published ok 0 no match "$fixture_commit" match 'v1.2.3#retry' 'v1.2.3%23retry'
assert_case percent-tag-publishes missing published ok 0 yes match "$fixture_commit" match 'v1.2.3%23retry' 'v1.2.3%2523retry'
assert_case slash-tag-publishes missing published ok 0 yes match "$fixture_commit" match 'release/v1.2.3' 'release%2Fv1.2.3'
assert_case option-like-tag-refuses missing published ok 2 no match "$fixture_commit" match '--draft' '--draft'
assert_case option-like-tag-rerun-refuses found published ok 2 no match "$fixture_commit" match '--draft' '--draft'
assert_case target-option-tag-refuses missing published ok 2 no match "$fixture_commit" match '--target=main' '--target%3Dmain'
assert_case detached-checkout-publishes missing published ok 0 yes match "$fixture_commit" detached
assert_case ssh-origin-publishes missing published ok 0 yes match "$fixture_commit" ssh
assert_case ssh-url-origin-publishes missing published ok 0 yes match "$fixture_commit" ssh-url
assert_case mixed-https-origin-publishes missing published ok 0 yes match "$fixture_commit" mixed-https
assert_case mixed-ssh-origin-publishes missing published ok 0 yes match "$fixture_commit" mixed-ssh
assert_case mixed-ssh-url-origin-publishes missing published ok 0 yes match "$fixture_commit" mixed-ssh-url
assert_case wrong-checkout-repo-refuses missing published ok 1 no match "$fixture_commit" wrong-repo
assert_case unresolved-checkout-repo-refuses missing published ok 1 no match "$fixture_commit" no-origin
assert_case foreign-host-refuses missing published ok 1 no match "$fixture_commit" foreign-host
assert_case wrong-checkout-commit-refuses missing published ok 1 no match "$fixture_commit" wrong-commit
assert_case dirty-checkout-refuses missing published ok 1 no match "$fixture_commit" dirty
assert_case tracked-dirty-checkout-refuses missing published ok 1 no match "$fixture_commit" tracked-dirty
assert_case staged-dirty-checkout-refuses missing published ok 1 no match "$fixture_commit" staged-dirty
assert_case assume-unchanged-refuses missing published ok 1 no match "$fixture_commit" assume-unchanged
assert_case skip-worktree-refuses missing published ok 1 no match "$fixture_commit" skip-worktree
assert_case subdirectory-refuses missing published ok 1 no match "$fixture_commit" subdirectory
assert_case invalid-skills-refuse missing published invalid 1 no

# A successful publisher exit is not evidence that the requested release exists.
# Verify the same remote postconditions as a rerun before reporting success.
assert_case published-wrong-commit-fails missing published ok 1 yes mismatch
assert_case published-unreadable-commit-fails missing published ok 1 yes unreadable
assert_case published-malformed-commit-fails missing published ok 1 yes malformed
assert_case published-missing-release-fails missing absent ok 1 yes
assert_case published-draft-release-fails missing draft ok 1 yes
assert_case published-wrong-release-tag-fails missing wrong-tag ok 1 yes
assert_case published-ambiguous-release-fails missing ambiguous ok 1 yes

# The property this script exists for: a re-run of a job whose publish already
# succeeded must SUCCEED WITHOUT re-publishing, so the steps after it can run.
assert_case already-published-skips found published ok 0 no
assert_case published-rerun-needs-no-checkout-identity found published ok 0 no match "$fixture_commit" wrong-repo

# A retry must reach the caller's remaining verification and preserve its result.
# The child shell uses errexit, as the Actions runner does for successive steps.
for verification_exit in 0 1; do
  cases=$((cases + 1))
  case_dir=$(make_stub "post-publish-$verification_exit" found published ok match)
  actual_exit=0
  GITHUB_SHA="$fixture_commit" \
    PATH="$case_dir/bin:$PATH" bash -ec '
      "$1" --tag v1.0.0 --repo owner/repo
      printf "verified\\n" >"$2/verified"
      exit "$3"
    ' _ "$script" "$case_dir" "$verification_exit" \
    >"$case_dir/out" 2>"$case_dir/err" || actual_exit=$?
  if [ "$actual_exit" -eq "$verification_exit" ] &&
    [ -s "$case_dir/verified" ] && [ ! -s "$case_dir/published" ]; then
    printf 'ok   post-publish-verification (exit %s, reached=yes, published=no)\n' "$actual_exit"
  else
    printf 'FAIL post-publish-verification: exit %s, want %s with verification reached and no publish\n' \
      "$actual_exit" "$verification_exit" >&2
    failures=$((failures + 1))
  fi
done

# A release for a different commit must never satisfy this run's publication.
assert_case different-commit-refuses found published ok 1 no mismatch
assert_case branch-tag-collision-refuses found published ok 1 no branch-collision
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
usage_exit=0
"$script" --repo owner/repo >/dev/null 2>&1 || usage_exit=$?
if [ "$usage_exit" -eq 2 ]; then
  printf 'ok   missing-tag-is-usage-error (exit 2)\n'
else
  printf 'FAIL missing-tag-is-usage-error: exit %s, want 2\n' "$usage_exit" >&2
  failures=$((failures + 1))
fi

printf '\n%s case(s), %s failure(s)\n' "$cases" "$failures"
[ "$failures" -eq 0 ]
