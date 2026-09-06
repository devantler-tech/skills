#!/usr/bin/env bash
#
# Publish validated skills at an explicit commit, with safe completed reruns.
#
#   already published  -> report it and succeed, so the caller's later steps run
#   not published yet  -> bind the checkout, validate, publish, verify
#   ambiguous          -> FAIL, and say what is ambiguous
#
# "Already published" is deliberately narrow: the tag targets the expected
# release commit AND a non-draft release exists for that tag. A tag with no release
# is a half-finished publish, not a finished one, so it fails rather than skipping — the caller must never read
# "skipped" as "published". A failure to READ either fact is likewise a failure,
# never a skip: an unreadable precondition proves nothing.
#
# Usage: publish-skills-release.sh --tag <tag> [--repo <owner/repo>] [--expected-commit <sha>]
set -euo pipefail

# Print the supported arguments and exit-code contract to stderr without exiting.
usage() {
  cat >&2 <<'USAGE'
Usage: publish-skills-release.sh --tag <tag> [--repo <owner/repo>] [--expected-commit <sha>]

  --tag   the release tag to publish (required), e.g. v1.2.3
  --repo  the github.com repository to publish; defaults to $GITHUB_REPOSITORY
  --expected-commit  full release commit SHA; defaults to $GITHUB_SHA

Exit codes:
  0  the release is published (by this run, or already)
  1  the publish failed, or its precondition could not be established
  2  usage error
USAGE
}

# Report an invalid invocation, print usage, and exit with the usage-error status.
# The first argument is the diagnostic to show before the usage text.
die_usage() {
  printf 'publish-skills-release: %s\n\n' "$1" >&2
  usage
  exit 2
}

tag=''
repo="${GITHUB_REPOSITORY:-}"
expected_commit="${GITHUB_SHA:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      [ "$#" -ge 2 ] || die_usage "--tag needs a value"
      tag="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || die_usage "--repo needs a value"
      repo="$2"
      shift 2
      ;;
    --expected-commit)
      [ "$#" -ge 2 ] || die_usage "--expected-commit needs a value"
      expected_commit="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$tag" ] || die_usage "--tag is required"
[[ "$tag" != -* ]] || die_usage "--tag must not begin with '-'"
[ -n "$repo" ] || die_usage "--repo is required when GITHUB_REPOSITORY is unset"
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || die_usage "--expected-commit (or GITHUB_SHA) must be a full commit SHA"

# Origin verification below supports github.com. Keep every API, validation,
# and release call on that same host even when the caller sets GH_HOST.
export GH_HOST=github.com

# Ref names can contain URL syntax such as # or %. Encode the tag component
# once for API paths; release commands and JSON comparisons keep the literal tag.
tag_path=$(jq -rn --arg tag "$tag" '$tag | @uri') || exit 1

# Verify the requested remote tag resolves to the expected commit. The commits
# endpoint handles annotated tags; qualifying tags/ prevents branch collisions.
verify_tag_commit() {
  local tag_commit
  tag_commit=$(gh api "repos/${repo}/commits/tags/${tag_path}" --jq '.sha') || {
    printf 'publish-skills-release: could not resolve tag %s to a commit; publication is unverified.\n' "$tag" >&2
    return 1
  }
  if ! [[ "$tag_commit" =~ ^[0-9a-f]{40}$ ]] || [ "$tag_commit" != "$expected_commit" ]; then
    printf 'publish-skills-release: tag %s does not resolve to the expected release commit; publication is unverified.\n' "$tag" >&2
    return 1
  fi
}

# Does a git tag of this name exist on the remote? A read failure is fatal: it
# leaves the publish precondition unknown, and an unknown precondition must never
# be resolved by guessing in either direction.
tag_ref_status=0
gh api "repos/${repo}/git/ref/tags/${tag_path}" >/dev/null 2>&1 || tag_ref_status=$?

if [ "$tag_ref_status" -eq 0 ]; then
  tag_exists=yes
else
  # Distinguish "no such tag" (a clean 404) from an auth/network failure. Only the
  # former means the tag is absent; anything else leaves the answer unknown.
  probe=$(gh api "repos/${repo}/git/ref/tags/${tag_path}" 2>&1 || true)
  case "$probe" in
    *"Not Found"* | *"HTTP 404"*) tag_exists=no ;;
    *)
      printf 'publish-skills-release: could not determine whether tag %s exists on %s; refusing to publish or skip.\n' \
        "$tag" "$repo" >&2
      printf '%s\n' "$probe" >&2
      exit 1
      ;;
  esac
fi

if [ "$tag_exists" = no ]; then
  # The skill CLI validates the working directory and resolves its own origin.
  # Bind those bytes to this release before validation or any publication. Use
  # the effective URL (including Git's insteadOf rewrites), not gh's default repo.
  checkout_root=$(git --no-replace-objects rev-parse --show-toplevel) || exit 1
  [ "$(pwd -P)" = "$checkout_root" ] || {
    printf 'publish-skills-release: run from the repository root; refusing partial skill validation.\n' >&2
    exit 1
  }
  origin_url=$(git remote get-url -- origin) || {
    printf 'publish-skills-release: origin is unresolved; refusing publication.\n' >&2
    exit 1
  }
  origin_url=$(printf '%s' "$origin_url" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case "$origin_url" in
    https://github.com/*) origin_repo=${origin_url#https://github.com/} ;;
    https://github.com:443/*) origin_repo=${origin_url#https://github.com:443/} ;;
    git@github.com:*) origin_repo=${origin_url#git@github.com:} ;;
    ssh://git@github.com/*) origin_repo=${origin_url#ssh://git@github.com/} ;;
    ssh://git@github.com:22/*) origin_repo=${origin_url#ssh://git@github.com:22/} ;;
    *)
      printf 'publish-skills-release: origin must identify the expected GitHub repository.\n' >&2
      exit 1
      ;;
  esac
  origin_repo=${origin_repo%.git}
  if [ "$origin_repo" != "$(printf '%s' "$repo" | LC_ALL=C tr '[:upper:]' '[:lower:]')" ]; then
    printf 'publish-skills-release: origin differs from --repo; refusing publication.\n' >&2
    exit 1
  fi
  checkout_commit=$(git --no-replace-objects rev-parse --verify 'HEAD^{commit}') || exit 1
  [ "$checkout_commit" = "$expected_commit" ] || {
    printf 'publish-skills-release: HEAD differs from the expected release commit; refusing publication.\n' >&2
    exit 1
  }
  # These index flags hide modified or absent tracked files from status. Reject
  # them rather than validating disk bytes that differ from the release commit.
  # NUL-delimited records preserve filenames containing whitespace or newlines.
  if ! git --no-replace-objects ls-files -v -z | while IFS= read -r -d '' entry; do
    case "${entry:0:1}" in
      S | [a-z]) exit 1 ;;
    esac
  done; then
    printf 'publish-skills-release: hidden or unreadable index flags prevent checkout verification; refusing publication.\n' >&2
    exit 1
  fi
  checkout_status=$(git --no-replace-objects -c core.fsmonitor= --no-optional-locks \
    status --porcelain=v1 --untracked-files=all --ignored) || exit 1
  [ -z "$checkout_status" ] || {
    printf 'publish-skills-release: checkout has uncommitted or ignored files; refusing publication.\n' >&2
    exit 1
  }

  # gh skill publish --tag targets a branch name, or the default branch for a
  # detached checkout. Validate with the skill CLI, then name the immutable
  # commit explicitly when creating the GitHub release. The topic check remains
  # the caller's responsibility, as on the skill CLI's non-interactive path.
  gh skill publish --dry-run
  # Create-only ref reservation loses atomically if another publisher wins the
  # tag after our absence probe. Never publish against that writer's tag. A
  # failed release leaves the reserved tag for explicit operator recovery.
  gh api "repos/${repo}/git/refs" --method POST \
    -f "ref=refs/tags/${tag}" -f "sha=${expected_commit}" >/dev/null || {
    printf 'publish-skills-release: could not reserve tag %s; refusing release creation.\n' "$tag" >&2
    exit 1
  }
  verify_tag_commit
  printf 'publish-skills-release: %s is not published yet; publishing.\n' "$tag"
  gh release create "$tag" --repo "$repo" --target "$expected_commit" --generate-notes --verify-tag
fi

# Recheck after creation, and apply the same postcondition to completed reruns.
verify_tag_commit

# The tag exists. Only a real, non-draft release for it proves the publish
# finished; a tag without one is a half-finished publish that needs a human.
release_json=$(gh release view "$tag" --repo "$repo" --json tagName,isDraft 2>&1) || {
  printf 'publish-skills-release: tag %s exists on %s but its release could not be read, so the publish state is unknown; refusing to publish or skip.\n' \
    "$tag" "$repo" >&2
  printf '%s\n' "$release_json" >&2
  exit 1
}

if ! printf '%s' "$release_json" | jq -es --arg tag "$tag" \
  'length == 1 and (.[0] | type == "object" and .tagName == $tag and .isDraft == false)' >/dev/null; then
  printf 'publish-skills-release: tag %s exists on %s but a matching non-draft release was not established; publication is unverified.\n' \
    "$tag" "$repo" >&2
  exit 1
fi

printf 'publish-skills-release: verified %s is published on %s at the expected commit.\n' \
  "$tag" "$repo"
