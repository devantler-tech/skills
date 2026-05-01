---
name: ways-of-working
description: >-
  Codifies engineering ways of working including TDD, CI/CD pipeline design,
  testing strategy, code quality gates, and branching model. Use when setting
  up a new project, configuring CI/CD pipelines, choosing a testing strategy,
  or making decisions about code quality enforcement.
---

# Ways of Working

## Testing Strategy

Follow **Test-Driven Development** — see the [`test-driven-development`](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) skill for the full TDD workflow.

### Test Layers

| Layer | Where | Tooling |
|-------|-------|---------|
| **Unit tests** | In-repo alongside source code | SDK test framework (e.g. `go test`, `dotnet test`, `pytest`, `jest`) |
| **Integration tests** | In-repo alongside source code | SDK test framework |
| **E2E / System tests** | GitHub Actions workflows | Exercise the app/binary/service as an end user would |
| **Benchmark tests** | In-repo alongside source code | SDK benchmark framework (e.g. `go test -bench`, `BenchmarkDotNet`) |

### Guidance from Data

- Use **code coverage data** to identify gaps and guide where to add tests — not as a vanity metric.
- Use **benchmarking data** to guide performance improvements — don't optimise without data.

## Code Quality Gates (CI)

Every CI pipeline **must** enforce:

| Gate | Purpose |
|------|---------|
| Strict linting | Catches style and correctness issues early |
| Strict security scanning | Prevents known vulnerabilities from shipping |
| Strict code quality scanning | Enforces maintainability and complexity standards |
| No code-coverage regression | Coverage must not decrease — ratchet only upward |
| No benchmark regression | Performance must not regress without explicit justification |

## Library Selection

Prefer **popular, well-maintained third-party libraries** over writing custom implementations. Custom code is a liability — someone else's well-tested library is an asset.

## Refactoring & Design

Follow [refactoring.guru](https://refactoring.guru) guidelines for refactoring techniques and design patterns.

## Branching Model

Use **GitHub Flow**:

1. Branch from `main`.
2. Open a pull request.
3. Merge to `main` after review and CI passes.

## CI/CD Pipeline Design

### Standard Products (apps, CLIs, libraries)

| Event | What runs |
|-------|-----------|
| `pull_request` | CI — all tests (unit, integration, E2E/system). If the E2E suite becomes too heavy, move it to `merge_group`. |
| `merge_group` | CD to dev environment (if E2E was moved here, it runs here too). |
| `push` to `main` | Publish (e.g. package registry, container registry). |
| `v*` tag (`vX.X.X`) | CD to production. |

### Kubernetes / Platform Engineering (via KSail)

For Kubernetes-based projects, [KSail](https://github.com/devantler-tech/ksail) maps the standard development lifecycle to cluster operations:

| Standard lifecycle | KSail equivalent | Description |
|--------------------|------------------|-------------|
| Build | `ksail cluster init` | Initialise the cluster configuration |
| Run / Test | `ksail cluster create` | Create and validate the cluster locally |
| Publish | `ksail workload push` | Push OCI artifacts to the registry |

This lets platform engineers work with the same TDD-driven, branch-and-PR workflow used for application code.

### Reference Implementations

- [`devantler-tech/ksail`](https://github.com/devantler-tech/ksail) — Go CLI with unit tests, integration tests, benchmarks, system tests in workflows, and GoReleaser-based CD on `v*` tags.
- [`devantler-tech/platform`](https://github.com/devantler-tech/platform) — Kubernetes platform repo with system tests on `pull_request`, dev deploy on `merge_group`, and prod deploy on `v*` tags.
