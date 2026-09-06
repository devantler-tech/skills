#!/usr/bin/env bash
#
# Publish a skills release, and make the publish step re-runnable.
#
# `gh skill publish --tag <tag>` creates the tag itself and refuses a tag that
# already exists. That refusal is correct when two runs race for one version —
# the release workflow's `concurrency: {group: release, queue: max}` exists for
# exactly that — but it also makes a run whose publish SUCCEEDED impossible to
# re-run: every later step in that job is unreachable, because the first thing a
# re-run does is re-attempt a publish that is already done.
#
# That is not hypothetical. On `main` at d76f727f7c the publish succeeded and the
# post-publish topic check failed; by the time the underlying condition was fixed
# the run could no longer be re-run, so `main` carried a red release workflow with
# no way to clear it (devantler-tech/agent-skills#106).
#
# So this script decides whether the publish is already done before attempting it:
#
#   already published  -> report it and succeed, so the caller's later steps run
#   not published yet  -> publish
#   ambiguous          -> FAIL, and say what is ambiguous
#
# "Already published" is deliberately narrow: the tag exists AND a non-draft
# release exists for it. A tag with no release is a half-finished publish, not a
# finished one, so it fails rather than skipping — the caller must never read
# "skipped" as "published". A failure to READ either fact is likewise a failure,
# never a skip: an unreadable precondition proves nothing.
#
# Usage: publish-skills-release.sh --tag <tag> [--repo <owner/repo>]
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: publish-skills-release.sh --tag <tag> [--repo <owner/repo>]

  --tag   the release tag to publish (required), e.g. v1.2.3
  --repo  the repository to inspect; defaults to $GITHUB_REPOSITORY

Exit codes:
  0  the release is published (by this run, or already)
  1  the publish failed, or its precondition could not be established
  2  usage error
USAGE
}

die_usage() {
  printf 'publish-skills-release: %s\n\n' "$1" >&2
  usage
  exit 2
}

tag=''
repo="${GITHUB_REPOSITORY:-}"

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
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$tag" ] || die_usage "--tag is required"
[ -n "$repo" ] || die_usage "--repo is required when GITHUB_REPOSITORY is unset"

# Does a git tag of this name exist on the remote? A read failure is fatal: it
# leaves the publish precondition unknown, and an unknown precondition must never
# be resolved by guessing in either direction.
tag_ref_status=0
gh api "repos/${repo}/git/ref/tags/${tag}" >/dev/null 2>&1 || tag_ref_status=$?

if [ "$tag_ref_status" -eq 0 ]; then
  tag_exists=yes
else
  # Distinguish "no such tag" (a clean 404) from an auth/network failure. Only the
  # former means the tag is absent; anything else leaves the answer unknown.
  probe=$(gh api "repos/${repo}/git/ref/tags/${tag}" 2>&1 || true)
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
  printf 'publish-skills-release: %s is not published yet; publishing.\n' "$tag"
  gh skill publish --tag "$tag"
  exit 0
fi

# The tag exists. Only a real, non-draft release for it proves the publish
# finished; a tag without one is a half-finished publish that needs a human.
release_json=$(gh release view "$tag" --repo "$repo" --json tagName,isDraft 2>&1) || {
  printf 'publish-skills-release: tag %s exists on %s but its release could not be read, so the publish state is unknown; refusing to publish or skip.\n' \
    "$tag" "$repo" >&2
  printf '%s\n' "$release_json" >&2
  exit 1
}

is_draft=$(printf '%s' "$release_json" | jq -r '.isDraft')

if [ "$is_draft" != false ]; then
  printf 'publish-skills-release: tag %s exists on %s but its release is a draft, so the publish is unfinished. Publish or delete it, then re-run.\n' \
    "$tag" "$repo" >&2
  exit 1
fi

printf 'publish-skills-release: %s is already published on %s; leaving it alone so the remaining steps can run.\n' \
  "$tag" "$repo"
