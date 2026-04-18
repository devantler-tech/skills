# devantler-tech/skills

A curated collection of generic [agent skills](https://agentskills.io) installable with the [`gh skill`](https://github.com/cli/cli) CLI (v2.90.0+).

## Install

```sh
# Install a single skill
gh skill install devantler-tech/skills <skill-name> --agent github-copilot --scope user

# Example
gh skill install devantler-tech/skills git-commit --agent github-copilot --scope user
```

Run `gh skill --help` for the full flag reference (`--agent`, `--scope`, etc.).

## Automated installation and updates

To adopt these skills in another repository, use any of the following building blocks:

- [`devantler-tech/actions/setup-copilot-skills`](https://github.com/devantler-tech/actions/tree/main/setup-copilot-skills) — composite action that installs skills from a `skills-lock.json` manifest or from an inline list.
- [`devantler-tech/actions/update-copilot-skills`](https://github.com/devantler-tech/actions/tree/main/update-copilot-skills) — composite action that resolves each source's latest tag/default-branch HEAD and writes the new `ref` + `digest` back into `skills-lock.json` for reproducible installs.
- [`devantler-tech/reusable-workflows/.github/workflows/update-copilot-skills.yaml`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml) — reusable workflow that chains the two actions above and opens a PR with any skill updates on a schedule.

All three are generic and work with any `gh skill`-compatible skills repo — not just this one.

## Skills

| Skill | Description |
|-------|-------------|
| [`astro`](astro/SKILL.md) | Skill for building with the Astro web framework. Helps create Astro components and pages, configure SSR adapters, set up content collections, deploy static sites, and manage project structure and CLI commands. Use when the user needs to work with Astro, mentions .astro files, asks about static site generation (SSG), islands architecture, content collections, or deploying an Astro project. |
| [`bubbletea`](bubbletea/SKILL.md) | Build terminal user interfaces with Go and Bubbletea framework. Use for creating TUI apps with the Elm architecture, dual-pane layouts, accordion modes, mouse/keyboard handling, Lipgloss styling, and reusable components. Includes production-ready templates, effects library, and battle-tested layout patterns from real projects. |
| [`copilot-instructions-blueprint-generator`](copilot-instructions-blueprint-generator/SKILL.md) | Technology-agnostic blueprint generator for creating comprehensive copilot-instructions.md files that guide GitHub Copilot to produce code consistent with project standards, architecture patterns, and exact technology versions by analyzing existing codebase patterns and avoiding assumptions. |
| [`copilot-sdk`](copilot-sdk/SKILL.md) | Build agentic applications with GitHub Copilot SDK. Use when embedding AI agents in apps, creating custom tools, implementing streaming responses, managing sessions, connecting to MCP servers, or creating custom agents. Triggers on Copilot SDK, GitHub SDK, agentic app, embed Copilot, programmable agent, MCP server, custom agent. |
| [`find-skills`](find-skills/SKILL.md) | Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill. |
| [`frontend-design`](frontend-design/SKILL.md) | Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications (examples include websites, landing pages, dashboards, React components, HTML/CSS layouts, or when styling/beautifying any web UI). Generates creative, polished code and UI design that avoids generic AI aesthetics. |
| [`gh-cli`](gh-cli/SKILL.md) | GitHub CLI (gh) comprehensive reference for repositories, issues, pull requests, Actions, projects, releases, gists, codespaces, organizations, extensions, and all GitHub operations from the command line. |
| [`gh-stack`](gh-stack/SKILL.md) | Manage stacked branches and pull requests with the gh-stack GitHub CLI extension. Use when the user wants to create, push, rebase, sync, navigate, or view stacks of dependent PRs. Triggers on tasks involving stacked diffs, dependent pull requests, branch chains, or incremental code review workflows. |
| [`git-commit`](git-commit/SKILL.md) | Execute git commit with conventional commit message analysis, intelligent staging, and message generation. Use when user asks to commit changes, create a git commit, or mentions "/commit". Supports: (1) Auto-detecting type and scope from changes, (2) Generating conventional commit messages from diff, (3) Interactive commit with optional type/scope/description overrides, (4) Intelligent file staging for logical grouping |
| [`github-actions-docs`](github-actions-docs/SKILL.md) | Use when users ask how to write, explain, customize, migrate, secure, or troubleshoot GitHub Actions workflows, workflow syntax, triggers, matrices, runners, reusable workflows, artifacts, caching, secrets, OIDC, deployments, custom actions, or Actions Runner Controller, especially when they need official GitHub documentation, exact links, or docs-grounded YAML guidance. |
| [`github-issues`](github-issues/SKILL.md) | Create, update, and manage GitHub issues using MCP tools. Use this skill when users want to create bug reports, feature requests, or task issues, update existing issues, add labels/assignees/milestones, set issue fields (dates, priority, custom fields), set issue types, manage issue workflows, link issues, add dependencies, or track blocked-by/blocking relationships. Triggers on requests like "create an issue", "file a bug", "request a feature", "update issue X", "set the priority", "set the start date", "link issues", "add dependency", "blocked by", "blocking", or any GitHub issue management task. |
| [`gitops-cluster-debug`](gitops-cluster-debug/SKILL.md) | Debug and troubleshoot Flux CD on live Kubernetes clusters (not local repo files) via the Flux MCP server — inspects Flux resource status, reads controller logs, traces dependency chains, and performs installation health checks. Use when users report failing, stuck, or not-ready Flux resources on a cluster, reconciliation errors, controller issues, artifact pull failures, or need live cluster Flux Operator troubleshooting. |
| [`gitops-knowledge`](gitops-knowledge/SKILL.md) | Flux CD and Flux Operator expert — answers questions and generates schema-validated YAML for all Flux CRDs (not repo auditing or live cluster debugging). Use when users ask about Flux concepts, want manifests for HelmRelease, Kustomization, GitRepository, OCIRepository, ResourceSet, FluxInstance, or any Flux resource, or need guidance on GitOps repository structure, multi-tenancy, OCI-based delivery, image tag automation, drift detection, preview environments, notifications, or the Flux Web UI and MCP Server. |
| [`gitops-repo-audit`](gitops-repo-audit/SKILL.md) | Audit and validate Flux CD GitOps repositories by scanning local repo files (not live clusters) — runs Kubernetes schema validation, detects deprecated Flux APIs, reviews RBAC/multi-tenancy/secrets management, and produces a prioritized GitOps report. Use when users ask to audit, analyze, validate, review, or security-check a GitOps repo. |
| [`golang-pro`](golang-pro/SKILL.md) | Implements concurrent Go patterns using goroutines and channels, designs and builds microservices with gRPC or REST, optimizes Go application performance with pprof, and enforces idiomatic Go with generics, interfaces, and robust error handling. Use when building Go applications requiring concurrent programming, microservices architecture, or high-performance systems. Invoke for goroutines, channels, Go generics, gRPC integration, CLI tools, benchmarks, or table-driven testing. |
| [`refactor`](refactor/SKILL.md) | Surgical code refactoring to improve maintainability without changing behavior. Covers extracting functions, renaming variables, breaking down god functions, improving type safety, eliminating code smells, and applying design patterns. Less drastic than repo-rebuilder; use for gradual improvements. |
| [`siderolabs`](siderolabs/SKILL.md) | Deploy and operate Kubernetes clusters using Talos Linux and Omni. Use when generating/applying Talos machine configuration, managing cluster lifecycle in Omni, and troubleshooting common Talos/Omni workflows. |
| [`test-driven-development`](test-driven-development/SKILL.md) | Use when implementing any feature or bugfix, before writing implementation code |
| [`web-design-guidelines`](web-design-guidelines/SKILL.md) | Review UI code for Web Interface Guidelines compliance. Use when asked to "review my UI", "check accessibility", "audit design", "review UX", or "check my site against best practices". |

## Contributing

This repository follows the [`agentskills.io`](https://agentskills.io) spec: skill directories live at the repository root and include a conformant `SKILL.md` at their root. Other top-level directories may exist for repository metadata or supporting content (e.g. `.github/`). Pull requests are validated by [`gh skill publish --dry-run`](.github/workflows/ci.yaml); releases are cut automatically by [semantic-release](https://semantic-release.gitbook.io/) on every push to `main` — [`release.yaml`](.github/workflows/release.yaml) uses [commit conventions](https://www.conventionalcommits.org/) to determine the next version and create a GitHub release, which then triggers [`cd.yaml`](.github/workflows/cd.yaml) to run `gh skill publish` against that tag.

See the [devantler-tech organization guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and general contribution rules.

### Upstream sync

Each skill here is a vendored copy of a third-party skill. Upstream sources are pinned in [`skills-lock.yaml`](skills-lock.yaml) and [`update-skills.yaml`](.github/workflows/update-skills.yaml) runs weekly to open one pull request per changed skill. Change detection uses the tree SHA of the upstream source directory — matching the scheme [`gh skill update`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) uses — so spurious PRs are avoided when the upstream repo commits without touching the skill.

## License

Apache 2.0 — see [`LICENSE`](LICENSE). Individual skills may carry their own notices (e.g. [`frontend-design/LICENSE.txt`](frontend-design/LICENSE.txt)).
