# devantler-tech/skills

A curated index of generic [agent skills](https://agentskills.io) installable with the [`gh skill`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) CLI (v2.90.0+).

This repo is a **pointer list**, not a publisher. Each row below installs directly from its original upstream so `gh skill` records the true source in the skill's `SKILL.md` frontmatter (`metadata.github-repo`, `github-path`, `github-ref`, `github-tree-sha`) and `gh skill update --all` works natively — no lockfile, no sync bot, no custom metadata.

## Skills

<details open>
<summary>GitOps &amp; Kubernetes</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `gitops-cluster-debug` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/gitops-cluster-debug) | `gh skill install fluxcd/agent-skills gitops-cluster-debug` |
| `gitops-knowledge` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/gitops-knowledge) | `gh skill install fluxcd/agent-skills gitops-knowledge` |
| `gitops-repo-audit` | [`fluxcd/agent-skills`](https://github.com/fluxcd/agent-skills/tree/main/skills/gitops-repo-audit) | `gh skill install fluxcd/agent-skills gitops-repo-audit` |
| `siderolabs` | [`siderolabs/docs`](https://github.com/siderolabs/docs/tree/main/skills/siderolabs) | `gh skill install siderolabs/docs siderolabs` |

</details>

<details open>
<summary>GitHub</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `gh-cli` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/gh-cli) | `gh skill install github/awesome-copilot gh-cli` |
| `gh-stack` | [`github/gh-stack`](https://github.com/github/gh-stack/tree/main/skills/gh-stack) | `gh skill install github/gh-stack gh-stack` |
| `github-actions-docs` | [`xixu-me/skills`](https://github.com/xixu-me/skills/tree/main/skills/github-actions-docs) | `gh skill install xixu-me/skills github-actions-docs` |
| `github-issues` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/github-issues) | `gh skill install github/awesome-copilot github-issues` |

</details>

<details open>
<summary>Copilot</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `copilot-instructions-blueprint-generator` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/copilot-instructions-blueprint-generator) | `gh skill install github/awesome-copilot copilot-instructions-blueprint-generator` |
| `copilot-sdk` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/copilot-sdk) | `gh skill install github/awesome-copilot copilot-sdk` |
| `find-skills` | [`vercel-labs/skills`](https://github.com/vercel-labs/skills/tree/main/skills/find-skills) | `gh skill install vercel-labs/skills find-skills` |

</details>

<details open>
<summary>Go</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `bubbletea` | [`ggprompts/tfe`](https://github.com/ggprompts/tfe/tree/main/.claude/skills/bubbletea) | `gh skill install ggprompts/tfe bubbletea` |
| `golang-pro` | [`Jeffallan/claude-skills`](https://github.com/Jeffallan/claude-skills/tree/main/skills/golang-pro) | `gh skill install Jeffallan/claude-skills golang-pro` |

</details>

<details open>
<summary>Git</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `git-commit` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/git-commit) | `gh skill install github/awesome-copilot git-commit` |

</details>

<details open>
<summary>Engineering Practices</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `refactor` | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/skills/refactor) | `gh skill install github/awesome-copilot refactor` |
| `test-driven-development` | [`obra/superpowers`](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) | `gh skill install obra/superpowers test-driven-development` |

</details>

<details open>
<summary>Frontend &amp; Design</summary>

| Skill | Upstream | Install |
|-------|----------|---------|
| `astro` | [`astrolicious/agent-skills`](https://github.com/astrolicious/agent-skills/tree/main/skills/astro) | `gh skill install astrolicious/agent-skills astro` |
| `frontend-design` | [`anthropics/skills`](https://github.com/anthropics/skills/tree/main/skills/frontend-design) | `gh skill install anthropics/skills frontend-design` |
| `web-design-guidelines` | [`vercel-labs/agent-skills`](https://github.com/vercel-labs/agent-skills/tree/main/skills/web-design-guidelines) | `gh skill install vercel-labs/agent-skills web-design-guidelines` |

</details>

Each `gh skill install` accepts `--agent <name>`, `--scope user|project`, and `--pin <ref>` (or `@ref` suffix on the skill name) — see `gh skill install --help`.

## Automated installation and updates

To adopt these skills in another repository:

- [`devantler-tech/actions/setup-copilot-skills`](https://github.com/devantler-tech/actions/tree/main/setup-copilot-skills) — composite action that installs a newline list of `<owner/repo> <skill>[@pin]` entries.
- [`devantler-tech/actions/update-copilot-skills`](https://github.com/devantler-tech/actions/tree/main/update-copilot-skills) — composite action that runs `gh skill update --all` against the checked-in skills.
- [`devantler-tech/reusable-workflows/.github/workflows/update-copilot-skills.yaml`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml) — reusable workflow that opens a PR when any skill's upstream has drifted.

All three rely on the `github-*` metadata that `gh skill install` injects into each `SKILL.md`, so no lockfile or external manifest is required.

## Contributing

This repository follows the [`agentskills.io`](https://agentskills.io) spec: skill directories live at the repository root and include a conformant `SKILL.md` at their root. Pull requests are validated by [`gh skill publish --dry-run`](.github/workflows/ci.yaml); releases are cut automatically by [semantic-release](https://semantic-release.gitbook.io/) on every push to `main` — [`release.yaml`](.github/workflows/release.yaml) uses [commit conventions](https://www.conventionalcommits.org/) to determine the next version, and [`cd.yaml`](.github/workflows/cd.yaml) then runs `gh skill publish` against the resulting tag.

The publish pipeline is retained for future in-house skills; until one is added, releases are no-ops.

See the [devantler-tech organization guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and general contribution rules.

## License

Apache 2.0 — see [`LICENSE`](LICENSE).
