# Installing skills

A skill is a set of instructions your coding assistant loads for a particular task. Choose an installer below, then copy the command for the skill you want from the [catalogue](../README.md#skills). Skills whose source is `devantler-tech/agent-skills` are maintained here; other rows point to the repositories that maintain them.

| CLI | Reaches | Best for |
|-----|---------|----------|
| [`gh skill`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) | Every catalogue entry, using its listed command | Records the source so `gh skill update --all` can fetch updates. Copy the command from the catalogue. |
| [`npx skills`](https://github.com/vercel-labs/skills) | Skills hosted in the repository you name | Choose several skills or agents interactively. For a skill maintained elsewhere, name its source repository (for example, `npx skills add fluxcd/agent-skills`). |

> [!NOTE]
> There is no registry to sign up for and no package to publish — both CLIs resolve `owner/repo` straight from GitHub.

## With `npx skills`

[`npx skills`](https://github.com/vercel-labs/skills) needs no install of its own and prompts for which skills and which agents you want. Pointed at this repo it offers the skills maintained here; for other catalogue entries, name the skill's source repository.

> [!NOTE]
> Requires **Node.js ≥ 22.20.0** (the `skills` package's declared `engines.node`). On an older Node this fails before any skill is fetched. `gh skill` has no Node dependency.

```sh
# Browse what's on offer without installing anything
npx skills add devantler-tech/agent-skills --list

# Install specific skills for specific agents
npx skills add devantler-tech/agent-skills --skill ways-of-working --agent claude-code

# Install every in-house skill, for EVERY supported agent, no prompts.
# Note --all is not scoped to agents you have installed — pass --agent to limit it.
npx skills add devantler-tech/agent-skills --all
```

Add `-g` to install to your user directory instead of the current project.

The [skills.sh](https://skills.sh) directory has no submission step — it lists a repo off **anonymous install telemetry** from this CLI. That telemetry is opt-out (`DISABLE_TELEMETRY` or `DO_NOT_TRACK`) and is disabled automatically in CI, so only telemetry-enabled installs contribute to a listing.

## With `gh skill`

Each `gh skill install` accepts `--agent <name>`, `--scope user|project`, and `--pin <ref>` (or an `@ref` suffix on the skill name) — see `gh skill install --help` for the full list of supported agents.

The install commands in the [catalogue tables](../README.md#skills) use the default agent (GitHub Copilot) at project scope. To install for **Claude Code** instead, or for **both agents at once at user scope** (so the skill is available everywhere), add `--agent` / `--scope`:

```sh
# GitHub Copilot, user scope -> ~/.copilot/skills/<skill>/
gh skill install devantler-tech/agent-skills ways-of-working --agent github-copilot --scope user

# Claude Code, user scope -> ~/.claude/skills/<skill>/
gh skill install devantler-tech/agent-skills ways-of-working --agent claude-code --scope user
```

## Install everything for both Copilot and Claude

[`scripts/install.sh`](../scripts/install.sh) installs every skill listed in the [catalogue](../README.md#skills) for the agents you name (default: `github-copilot` and `claude-code`) at user scope:

Run these commands from a clone of this repository:

```sh
./scripts/install.sh --help                   # usage, without reading the catalogue or calling gh
./scripts/install.sh --list                   # preview the catalogue without installing
./scripts/install.sh                          # both Copilot + Claude Code (user scope)
./scripts/install.sh claude-code              # just Claude Code
AGENTS="github-copilot claude-code cursor" ./scripts/install.sh   # any gh skill agents
```

The script reads its install commands directly from the README catalogue. `--help` (`-h`) and
`--list` (`-l`) are standalone modes and need no authentication or network access. Do not combine
them with agent names.

All catalogue sources are on github.com. The script sets `GH_HOST=github.com` for
its GitHub CLI calls, so an enterprise host in your environment does not redirect
these installations. For a catalogue command run directly, prefix it with
`GH_HOST=github.com` if your default host is an enterprise instance.

Each installed skill name must identify one source repository. If the catalogue
lists the same name from different repositories, installation and `--list` exit 1
and name both sources before calling GitHub CLI. Repeated entries for the same
repository and skill, including repository casing aliases, are installed once.

Positional agent names override `AGENTS`. An unset or empty `AGENTS` uses the two default agents;
otherwise, spaces, tabs, and newlines separate names without expanding wildcard characters into
filenames. Unknown options, empty names, and whitespace-only `AGENTS` values fail with usage and
exit code 2 before any installation starts. Supported agent names come from `gh skill install --help`.

Installation uses user scope and replaces existing copies with `--force`. If an individual skill
fails, the script prints its error, attempts the remaining installations, and exits 1 with the total
failure count. A successful installation or preview exits 0.

## Automated installation and updates

To adopt these skills in another repository:

- [`devantler-tech/actions/setup-agent-skills`](https://github.com/devantler-tech/actions/tree/main/setup-agent-skills) — composite action that installs a newline list of `<owner/repo> <skill>[@pin]` entries, for one or more agents.
- [`devantler-tech/actions/update-agent-skills`](https://github.com/devantler-tech/actions/tree/main/update-agent-skills) — composite action that runs `gh skill update --all` against the checked-in skills.
- [`devantler-tech/actions/.github/workflows/update-agent-skills.yaml`](https://github.com/devantler-tech/actions/blob/main/.github/workflows/update-agent-skills.yaml) — reusable workflow that opens a PR when any skill's upstream has drifted.

All three rely on the `github-*` metadata that `gh skill install` injects into each `SKILL.md`, so no lockfile or external manifest is required.
