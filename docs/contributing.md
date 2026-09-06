# Contributing skills

Suggest a skill by opening an issue, or add it to the [catalogue](../README.md#skills) in a pull request. For a skill maintained elsewhere, link to its original repository. Add a local skill directory only for skills maintained by devantler-tech.

Read [AGENTS.md](../AGENTS.md#validation) for the validation commands, release process, and repository conventions. The catalogue drives automated installation, so every row must keep its skill name, source link, and install command consistent.

## Inclusion criteria

Before adding a row, check the skill clears the bar this index is curated to. These criteria are
already applied in review — they are written here so every contributor (and the autonomous
assistant) applies the same bar:

- **Generic & reusable.** Index a skill only if it is useful **beyond a single project or person** —
  a general capability (a framework, a workflow, a language toolchain, an engineering practice).
  Project- or repo-specific knowledge belongs in *that* project, not here.
- **Upstream pointer by default.** Prefer a row that installs **directly from the skill's canonical
  upstream** (`gh skill install <owner/repo> <skill>`) so `gh skill update --all` tracks the true
  source — no fork, no copy. Add an in-house directory **only** for skills devantler-tech genuinely
  authors and maintains (e.g. `ways-of-working`).
- **Spec-conformant & agent-neutral.** The skill's `SKILL.md` must follow the
  [`agentskills.io`](https://agentskills.io) spec and stay **tool-neutral** — no Copilot/Claude-only
  assumptions — so it works across every agent `gh skill` supports.
- **Quality upstream.** Point only at an **actively-maintained, good-quality** source with a precise
  `description` (the field agents match on to trigger the skill). Avoid abandoned or low-signal
  upstreams.
- **Naming & category.** The row's skill slug matches the upstream skill name; place it under the
  best-fitting `## Skills` category, adding a new category only when a skill clearly fits none of the
  existing ones. Each skill name identifies one source repository across the catalogue: two
  upstreams with the same name would replace each other during batch installation, so the index
  check rejects that collision. Choose one canonical source rather than listing both.
- **Lockstep.** Every change updates the README `## Skills` tables — the **single source of truth**
  that `install.sh` and the `setup-`/`update-agent-skills` consumers parse. Never hand-maintain a
  parallel list; run [`./scripts/check-readme-index.sh`](../scripts/check-readme-index.sh) — the same gate CI enforces — before
  opening a PR.

See the [devantler-tech organization guidelines](https://github.com/devantler-tech/.github) for PR/issue templates and general contribution rules.
