#!/usr/bin/env bash
#
# Self-test for install.sh — pins the load-bearing contracts of the user-facing
# installer that check-readme-index.sh does NOT assert. The index guard calls
# `install.sh --list` only to count entries and resolve in-house rows; it never
# pins install.sh's OWN behaviour, and the `lint-scripts` CI gate runs entirely
# WITH gh present — so a regression in any of the properties below would ship
# undetected and break the installer for every consumer of this shared library:
#   • `--list` (and its `-l` alias) print exactly `<owner/repo> <skill>` per
#     entry, sorted and de-duplicated, parsed only from the `## Skills` section;
#   • `--list` needs NEITHER gh NOR network — it must run cleanly even when gh is
#     absent or broken (the explicitly-documented property; CI alone can't prove
#     it because CI always has gh — a refactor that moved the gh check before the
#     `--list` early-exit would pass CI yet break the documented offline path);
#   • a missing README index and an index that parses to zero entries each fail
#     loudly (non-zero exit), never silently installing nothing.
#
# install.sh resolves its README as `scripts/../README.md` (no env override), so
# every case is a self-contained fixture tree — <case>/scripts/install.sh +
# <case>/README.md — into which the REAL install.sh is copied and run. The test
# therefore exercises the live script content and never touches the real repo or
# needs gh/network. Run as part of the `lint-scripts` CI gate.
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

# Build a fixture repo root at $1: the REAL install.sh in scripts/, and a README
# whose `## Skills` table body is read from stdin, followed by a SEPARATE
# `## Installing` section carrying an example install command that must NEVER be
# parsed (it proves the parser stays scoped to `## Skills`).
make_root() { # root  <<skills_table_body
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/scripts"
  cp "$here/install.sh" "$root/scripts/"
  {
    printf '# Test catalogue\n\n## Skills\n\n'
    printf '| Skill | Upstream | Install |\n|-------|----------|---------|\n'
    cat
    # Literal markdown backticks, not a command substitution.
    # shellcheck disable=SC2016
    printf '\n## Installing\n\nExample (must NOT be parsed): `gh skill install out/of-scope example`\n'
  } > "$root/README.md"
}

# Assert `install.sh --list` for fixture $2 prints exactly $3.
expect_list() { # name root expected
  local got
  if got=$(bash "$2/scripts/install.sh" --list 2>/dev/null); then
    if [ "$got" = "$3" ]; then
      printf '  ✅ %s — listed as expected\n' "$1"
    else
      printf '  ❌ %s — output mismatch\n     expected: %s\n     got:      %s\n' \
        "$1" "${3//$'\n'/ | }" "${got//$'\n'/ | }"; fail=1
    fi
  else
    printf '  ❌ %s — expected exit 0 but install.sh --list FAILED\n' "$1"; fail=1
  fi
}

# Assert `install.sh $3...` for fixture $2 exits non-zero (fails loudly).
expect_fail() { # name root args...
  local name="$1" root="$2"; shift 2
  if bash "$root/scripts/install.sh" "$@" >/dev/null 2>&1; then
    printf '  ❌ %s — expected non-zero exit but it SUCCEEDED\n' "$name"; fail=1
  else
    printf '  ✅ %s — failed loudly as expected\n' "$name"
  fi
}

# 1. --list output contract: exactly `<owner/repo> <skill>` per entry, sorted,
#    parsed only from `## Skills` (the `## Installing` example is excluded — the
#    output is the two Skills rows, NOT three). devantler-tech sorts before
#    fluxcd, so the order is deterministic.
two="$tmp/two"
make_root "$two" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `beta` | [`devantler-tech/agent-skills`](https://github.com/devantler-tech/agent-skills/tree/main/beta) | `gh skill install devantler-tech/agent-skills beta` |
EOF
expected=$'devantler-tech/agent-skills beta\nfluxcd/agent-skills alpha'
expect_list "--list prints sorted <repo> <skill>, scoped to ## Skills" "$two" "$expected"

# 2. The `-l` short flag is equivalent to `--list`.
if got=$(bash "$two/scripts/install.sh" -l 2>/dev/null) && [ "$got" = "$expected" ]; then
  printf '  ✅ -l is an alias for --list — equivalent output\n'
else
  printf '  ❌ -l alias — expected the same output as --list\n'; fail=1
fi

# 3. De-duplication: the same install command twice collapses to one entry
#    (the `sort -u` in the parser), so a copy-pasted row never double-installs.
dup="$tmp/dup"
make_root "$dup" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
EOF
expect_list "duplicate rows de-duplicate to one entry" "$dup" "fluxcd/agent-skills alpha"

# GitHub repository identities are case-insensitive. An alias is still the same
# source, not a destination collision, and must not cause two installations.
alias_root="$tmp/repo-alias"
make_root "$alias_root" <<'EOF'
| `alpha` | [`Fixture/One`](https://github.com/Fixture/One/tree/main/alpha) | `gh skill install Fixture/One alpha` |
| `alpha` | [`fixture/one`](https://github.com/fixture/one/tree/main/alpha) | `gh skill install fixture/one alpha` |
EOF
expect_list "repository casing aliases de-duplicate to one source" "$alias_root" 'Fixture/One alpha'

# Locale-aware awk implementations distinguish I/i in Turkish. Exercise the
# real parser under that locale when installed; hosts without it report a skip.
locale_root="$tmp/locale-alias"
make_root "$locale_root" <<'EOF'
| `alpha` | [`OWNER/I`](https://github.com/OWNER/I/tree/main/alpha) | `gh skill install OWNER/I alpha` |
| `alpha` | [`owner/i`](https://github.com/owner/i/tree/main/alpha) | `gh skill install owner/i alpha` |
EOF
turkish_locale=''
if available_locales=$(locale -a 2>/dev/null); then
  turkish_locale=$(printf '%s\n' "$available_locales" | LC_ALL=C awk 'tolower($0) ~ /^tr_tr\.(utf-8|utf8)$/ {print; exit}')
fi
if [ -n "$turkish_locale" ]; then
  LC_ALL="$turkish_locale" expect_list "repository aliases are locale-independent" "$locale_root" 'OWNER/I alpha'
else
  printf '  SKIP Turkish locale is not installed; locale alias case not exercised\n'
fi

# 4. --list needs NEITHER gh NOR network. Run it with a gh shim on PATH that
#    records its own invocation and exits non-zero: --list must still exit 0 with
#    the right output AND never touch gh. This is the property CI alone can't
#    prove (CI always has a real, working gh), so a refactor that moved the gh
#    check ahead of the `--list` early-exit would pass CI yet break the
#    documented offline path — this case catches exactly that.
ghbin="$tmp/ghbin"
mkdir -p "$ghbin"
cat > "$ghbin/gh" <<'STUB'
#!/usr/bin/env bash
touch "$GH_CALLED_MARKER"
echo "gh must not be invoked in --list mode" >&2
exit 99
STUB
chmod +x "$ghbin/gh"
marker="$tmp/gh-was-called"
rm -f "$marker"
if got=$(GH_CALLED_MARKER="$marker" PATH="$ghbin:$PATH" \
      bash "$two/scripts/install.sh" --list 2>/dev/null) \
    && [ "$got" = "$expected" ] && [ ! -e "$marker" ]; then
  printf '  ✅ --list is gh-free — correct output and gh never invoked\n'
else
  printf '  ❌ --list gh-free — expected exit 0, correct output, and no gh call'
  [ -e "$marker" ] && printf ' (gh WAS called)'
  printf '\n'; fail=1
fi

# 5. A missing README index fails loudly (never silently installs nothing).
nordme="$tmp/no-readme"
make_root "$nordme" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | `gh skill install fluxcd/agent-skills alpha` |
EOF
rm -f "$nordme/README.md"
expect_fail "missing README index exits non-zero" "$nordme" --list

# 6. A `## Skills` section that parses to zero entries fails loudly — even though
#    a valid-looking install command exists in `## Installing`, the scoped parser
#    must not pick it up, so the result is still zero and the script exits 1.
empty="$tmp/no-skills"
make_root "$empty" <<'EOF'
| `alpha` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/alpha) | (install command missing) |
EOF
expect_fail "zero parsed entries exits non-zero (## Installing not parsed)" "$empty" --list

# Record argument boundaries, not a shell command that could expand wildcards.
cat > "$ghbin/gh" <<'STUB'
#!/usr/bin/env bash
printf '<%s>' "$@" >> "$GH_CALLS"
printf '\n' >> "$GH_CALLS"
printf '%s\n' "${GH_HOST:-unset}" >> "$GH_HOSTS"
if [ "$*" = 'skill --help' ]; then
  exit "${GH_UNAVAILABLE:-0}"
fi
if [ "${GH_FAIL_SKILL:-}" = "${4:-}" ]; then
  echo 'fixture download failed' >&2
  exit 1
fi
STUB
export PATH="$ghbin:$PATH"
export GH_CALLS="$tmp/calls"
export GH_HOSTS="$tmp/hosts"
unset AGENTS

run_install() {
  local root="$1"; shift
  : > "$GH_CALLS"
  : > "$GH_HOSTS"
  rc=0
  bash "$root/scripts/install.sh" "$@" > "$tmp/stdout" 2> "$tmp/stderr" || rc=$?
}

check() {
  local name="$1"; shift
  if "$@"; then
    printf '  ✅ %s\n' "$name"
  else
    printf '  ❌ %s\n' "$name"
    fail=1
  fi
}

for help in --help -h; do
  run_install "$nordme" "$help"
  check "$help works without a README" test "$rc" -eq 0
  check "$help prints usage" grep -q '^Usage:' "$tmp/stdout"
  check "$help never calls gh" test ! -s "$GH_CALLS"
done

for invalid in --unknown '' 'two agents'; do
  run_install "$two" cursor "$invalid"
  check "invalid trailing argument is a usage error: '$invalid'" test "$rc" -eq 2
  check 'invalid arguments print usage' grep -q '^Usage:' "$tmp/stderr"
  check 'all arguments are checked before gh' test ! -s "$GH_CALLS"
done
for mode in --list -l --help -h; do
  run_install "$two" "$mode" cursor
  check "$mode rejects extra agents" test "$rc" -eq 2
  check "$mode with extra agents never calls gh" test ! -s "$GH_CALLS"
  run_install "$two" cursor "$mode"
  check "trailing $mode is rejected before gh" test "$rc" -eq 2
  check "trailing $mode never calls gh" test ! -s "$GH_CALLS"
done
run_install "$two" --list --help
check 'help and listing cannot be combined' test "$rc" -eq 2
check 'conflicting modes never call gh' test ! -s "$GH_CALLS"

run_install "$alias_root" codex
check 'repository casing aliases install successfully' test "$rc" -eq 0
printf '<skill><--help>\n<skill><install><Fixture/One><alpha><--agent><codex><--scope><user><--force><--allow-hidden-dirs>\n' > "$tmp/expected"
check 'repository casing aliases install only once' diff -u "$tmp/expected" "$GH_CALLS"

# Different upstreams with the same destination name must be rejected before
# even the gh preflight: --force would otherwise replace the first installation.
collision="$tmp/collision"
make_root "$collision" <<'EOF'
| `alpha` | [`fixture/one`](https://github.com/fixture/one/tree/main/alpha) | `gh skill install fixture/one alpha` |
| `alpha` | [`fixture/two`](https://github.com/fixture/two/tree/main/alpha) | `gh skill install fixture/two alpha` |
EOF
for mode in --list -l codex; do
  run_install "$collision" "$mode"
  check "colliding skill names fail in $mode mode" test "$rc" -eq 1
  check 'collision reports the destination name' grep -q 'alpha' "$tmp/stderr"
  check 'collision names the first upstream' grep -q 'fixture/one' "$tmp/stderr"
  check 'collision names the second upstream' grep -q 'fixture/two' "$tmp/stderr"
  check 'ambiguous catalogue never calls gh' test ! -s "$GH_CALLS"
  check 'ambiguous catalogue emits no successful result' test ! -s "$tmp/stdout"
done

# Expected calls pin user scope and every existing install flag. The fixture has
# two entries; positional arguments determine agents, not cwd filenames or AGENTS.
expected_calls() {
  printf '<skill><--help>\n'
  local agent
  for agent in "$@"; do
    printf '<skill><install><devantler-tech/agent-skills><beta><--agent><%s><--scope><user><--force><--allow-hidden-dirs>\n' "$agent"
    printf '<skill><install><fluxcd/agent-skills><alpha><--agent><%s><--scope><user><--force><--allow-hidden-dirs>\n' "$agent"
  done
}
expected_calls github-copilot claude-code > "$tmp/expected"
run_install "$two"
check 'default agents install successfully' test "$rc" -eq 0
check 'defaults make exactly four intended installs' diff -u "$tmp/expected" "$GH_CALLS"
GH_HOST=github.enterprise.test run_install "$two"
check 'enterprise-default environment installs successfully' test "$rc" -eq 0
check 'enterprise-default environment preserves installation arguments' diff -u "$tmp/expected" "$GH_CALLS"
printf 'github.com\ngithub.com\ngithub.com\ngithub.com\ngithub.com\n' > "$tmp/expected-hosts"
check 'preflight and every install target github.com' diff -u "$tmp/expected-hosts" "$GH_HOSTS"
AGENTS='' run_install "$two"
check 'empty AGENTS preserves defaults' diff -u "$tmp/expected" "$GH_CALLS"

expected_calls codex cursor > "$tmp/expected"
AGENTS=ignored run_install "$two" codex cursor
check 'positional agents override environment' diff -u "$tmp/expected" "$GH_CALLS"
AGENTS=$'codex\t\n cursor' run_install "$two"
check 'environment supports tabs and newlines' diff -u "$tmp/expected" "$GH_CALLS"

# A wildcard must remain one literal agent argument even when files match it.
expected_calls '*' > "$tmp/expected"
AGENTS='*' run_install "$two"
check 'environment agents do not undergo pathname expansion' diff -u "$tmp/expected" "$GH_CALLS"
AGENTS=$' \t\n ' run_install "$two"
check 'whitespace-only AGENTS is a usage error' test "$rc" -eq 2
check 'empty agent selection never calls gh' test ! -s "$GH_CALLS"
AGENTS='cursor --help' run_install "$two"
check 'environment options are not agents' test "$rc" -eq 2
check 'invalid environment never calls gh' test ! -s "$GH_CALLS"

expected_calls codex cursor > "$tmp/expected"
GH_FAIL_SKILL=beta run_install "$two" codex cursor
check 'partial installation returns failure' test "$rc" -eq 1
check 'partial failure still attempts every install' diff -u "$tmp/expected" "$GH_CALLS"
check 'original failure diagnostic is preserved' grep -q 'fixture download failed' "$tmp/stderr"
check 'failure count includes both affected agents' grep -q 'Done with 2 failure(s).' "$tmp/stderr"
check 'unaffected skills still succeed' grep -q 'ok   \[cursor\] fluxcd/agent-skills alpha' "$tmp/stdout"

GH_UNAVAILABLE=1 run_install "$two" codex
check 'unavailable gh skill fails' test "$rc" -eq 1
printf '<skill><--help>\n' > "$tmp/expected"
check 'unsupported gh never reaches install' diff -u "$tmp/expected" "$GH_CALLS"

if [ "$fail" -ne 0 ]; then
  printf '❌ install.sh self-test FAILED\n' >&2
  exit 1
fi
printf '✅ install.sh self-test passed\n'
