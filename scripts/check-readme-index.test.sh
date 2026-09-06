#!/usr/bin/env bash
#
# Self-test for check-readme-index.sh — proves the README-index lockstep guard
# PASSES a fully-consistent fixture and FAILS each individual drift scenario it
# exists to catch:
#   • the parser yields zero entries (the Skills tables / parser drifted);
#   • check 2: the parsed install count disagrees with the Skills-table rows;
#   • check 3: an in-house skill on disk is missing from the index;
#   • check 4: an in-house index entry resolves to no on-disk skill dir;
#   • check 5: each cross-column desync — link-text repo vs URL repo, install
#     repo vs Upstream repo, install slug vs skill name, URL tail vs skill name.
# Run as part of the `lint-scripts` CI gate so a refactor that silently weakens
# any check is caught here — not by a broken `gh skill install` command
# shipping to every consumer of this shared library.
#
# check-readme-index.sh resolves its repo root as `scripts/..` and `cd`s there
# (it has no env override), so every case is a self-contained fixture tree —
# <case>/scripts/{check-readme-index.sh,install.sh} + <case>/README.md +
# <case>/<skill>/SKILL.md — into which the REAL scripts are copied and run. The
# test therefore exercises the live script content and never touches the real
# repo (no gh, network, or skill checkout needed).
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

run_guard() { # root
  bash "$1/scripts/check-readme-index.sh"
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

# Build a fixture repo root at $1: the REAL guard + parser in scripts/, the
# in-house skill dirs named in $2 (space-separated) each with a SKILL.md, a
# README whose `## Skills` table body is read from stdin, and an example
# install command in a SEPARATE `## Installing` section that must NOT be parsed
# (it proves the parser stays scoped to `## Skills`).
make_root() { # root  skills_csv  <<rows
  local root="$1" skills="$2" s
  rm -rf "$root"
  mkdir -p "$root/scripts"
  cp "$here/check-readme-index.sh" "$here/install.sh" "$root/scripts/"
  # Intentional word-splitting over the space-separated skill list.
  # shellcheck disable=SC2086
  for s in $skills; do
    mkdir -p "$root/$s"
    printf '# %s\n\nfixture skill body.\n' "$s" > "$root/$s/SKILL.md"
  done
  {
    printf '# Test catalogue\n\n## Skills\n\n'
    printf '| Skill | Upstream | Install |\n|-------|----------|---------|\n'
    cat
    # The backticks below are literal markdown, not a command substitution.
    # shellcheck disable=SC2016
    printf '\n## Installing\n\nExample (must NOT be parsed): `gh skill install foo/bar example`\n'
  } > "$root/README.md"
}

# 0. Fully-consistent fixture → pass. One UPSTREAM row (alpha, no on-disk dir)
#    and one IN-HOUSE row (beta, with beta/SKILL.md); guards against a guard
#    that fails-closed on a correct index, and proves the `## Installing`
#    example stays unparsed (count == 2, not 3).
good="$tmp/good"
make_root "$good" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
EOF
pass_case "fully-consistent fixture" "$good"

# Individually consistent columns must not hide two upstreams targeting one
# installed directory. The shared parser rejects this before the count check.
c="$tmp/colliding-names"
make_root "$c" "" <<'EOF'
| `alpha` | [`fixture/one`](https://github.com/fixture/one/tree/main/alpha) | `gh skill install fixture/one alpha` |
| `alpha` | [`fixture/two`](https://github.com/fixture/two/tree/main/alpha) | `gh skill install fixture/two alpha` |
EOF
fail_case "distinct upstreams cannot share an installed skill name" "$c"

# 1. Parser yields zero entries → the lockstep fails closed (install.sh --list
#    exits non-zero, so the guard dies before its own checks). Models a Skills
#    table whose only row has no valid `gh skill install` command.
c="$tmp/zero-parse"
make_root "$c" "" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | (install command missing) |
EOF
fail_case "parser yields zero entries (lockstep fails closed)" "$c"

# 2. Count mismatch (check 2): a third table row (matches the row regex) whose
#    install command is malformed → parsed count (2) < table rows (3).
c="$tmp/count-mismatch"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `gamma` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/gamma) | install command typo'd |
EOF
fail_case "check 2: parsed count != Skills-table rows" "$c"

# 3. In-house skill missing from index (check 3): an extra on-disk in-house
#    skill (orphan/SKILL.md) with no matching index row. Count/rows still
#    match, so only check 3 fires.
c="$tmp/missing-from-index"
make_root "$c" "beta orphan" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
EOF
fail_case "check 3: in-house skill on disk missing from index" "$c"

# 4. Unresolved in-house entry (check 4): an in-house index row (ghost) with no
#    on-disk skill dir. The row is internally consistent, so only check 4 fires.
c="$tmp/unresolved-entry"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `ghost` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/ghost) | `gh skill install devantler-tech/agent-skills ghost` |
EOF
fail_case "check 4: in-house index entry with no on-disk dir" "$c"

# 5a. Cross-column (check 5): link-text repo != URL repo. Install matches the
#     link text, so only the link-vs-URL assert fires.
c="$tmp/x-link-vs-url"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `delta` | [`fluxcd/agent-skills`](https://github.com/fluxcd/other-repo/tree/main/skills/delta) | `gh skill install fluxcd/agent-skills delta` |
EOF
fail_case "check 5: Upstream link-text repo != URL repo" "$c"

# 5b. Cross-column (check 5): install repo != Upstream repo. Link text and URL
#     agree, so only the install-vs-Upstream assert fires.
c="$tmp/x-install-vs-upstream"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `delta` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/delta) | `gh skill install fluxcd/wrong delta` |
EOF
fail_case "check 5: install repo != Upstream repo" "$c"

# 5c. Cross-column (check 5): install slug != skill name. Repos and URL tail
#     all agree, so only the slug-vs-name assert fires.
c="$tmp/x-slug-vs-name"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `delta` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/delta) | `gh skill install fluxcd/agent-skills delta-typo` |
EOF
fail_case "check 5: install slug != skill name" "$c"

# 5d. Cross-column (check 5): Upstream URL trailing segment != skill name.
#     Repos and install slug agree, so only the URL-tail-vs-name assert fires.
c="$tmp/x-urltail-vs-name"
make_root "$c" "beta" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
| `delta` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/delta-wrong) | `gh skill install fluxcd/agent-skills delta` |
EOF
fail_case "check 5: Upstream URL tail != skill name" "$c"

if [ "$fail" -ne 0 ]; then
  printf '❌ check-readme-index self-test FAILED\n' >&2
  exit 1
fi
printf '✅ check-readme-index self-test passed (10 cases)\n'
