---
name: ways-of-working
description: >-
  Codifies devantler-tech engineering practices: TDD, CI/CD pipelines,
  GitHub Flow, benchmarking, code quality gates, and Kubernetes workflows
  with ksail. Use when setting up new projects, configuring CI/CD,
  writing tests, or making architectural decisions.
license: Apache-2.0
---

# Ways of Working

## Testing

Follow the [test-driven-development](https://github.com/obra/superpowers/tree/main/skills/test-driven-development) skill rigorously — write the test first, watch it fail, write minimal code to pass.

### Test Types

| Type | Where to write | When to run |
|------|---------------|-------------|
| **Unit tests** | SDK test frameworks (e.g. `go test`, `xunit`, `jest`) | CI on every PR |
| **Integration tests** | SDK test frameworks | CI on every PR |
| **E2E / system tests** | GitHub Actions workflows that exercise the app/binary/service as an end user would | CI on every PR; move to `merge_group` if the suite becomes too heavy |
| **Benchmark tests** | SDK benchmark frameworks (e.g. `BenchmarkDotNet`, `go test -bench`) | CI on every PR |

### Platform Engineering Tests

For platform engineering work the same categories apply, but the tooling shifts to [ksail](https://github.com/devantler-tech/ksail). This lets you develop Kubernetes platforms in the same build → run → publish loop as application code:

| Type | ksail equivalent | What it does |
|------|-----------------|--------------|
| Build / init | `ksail cluster init` | Scaffold a new cluster configuration |
| Run / test | `ksail cluster create` | Spin up the cluster locally (Docker) or on real infrastructure and verify workloads reconcile |
| Publish | `ksail workload push` | Push Kubernetes manifests as OCI artifacts to a container registry |

## Code Quality Gates (CI)

Every pull request **must** pass:

- **Strict linting** — language-specific linters with zero-tolerance for warnings.
- **Strict security scanning** — e.g. CodeQL, Trivy, zizmor.
- **Strict code quality scanning** — e.g. SonarQube, MegaLinter.
- **No code coverage regression** — coverage must not decrease compared to the base branch.
- **No benchmark regression** — benchmark results must not regress compared to the base branch.

## Libraries

Prefer popular, well-maintained third-party libraries over writing custom implementations. Only roll your own when no suitable library exists or when the dependency would be disproportionately heavy.

## Refactoring & Design

Follow <https://refactoring.guru> guidelines for refactoring techniques and design patterns.

## Branching & Flow

Use **GitHub Flow**:

1. Create a feature branch from `main`.
2. Open a pull request.
3. Pass all CI checks.
4. Merge via merge queue (`merge_group`).

## CI/CD Pipeline

### Application / Library Repositories

| Event | What runs |
|-------|-----------|
| `pull_request` | All tests (unit, integration, E2E, benchmarks), linting, security & quality scanning, coverage & benchmark regression checks. Move E2E to `merge_group` only if the suite becomes too heavy. |
| `merge_group` | CD to **dev** environment. |
| `push` to `main` | **Publish** artifacts (packages, container images, etc.). |
| Semver tag (`vX.X.X`) | CD to **prod** environment. |

### Kubernetes / Platform Repositories

| Event | What runs |
|-------|-----------|
| `pull_request` | System test on a local Docker cluster (`ksail cluster create`). Move to `merge_group` if the suite becomes too heavy. |
| `merge_group` | CD to **dev** — deploy to staging infrastructure (e.g. Hetzner). |
| Semver tag (`vX.X.X`) | CD to **prod** — `ksail cluster update`, `ksail workload push`, `ksail workload reconcile`. |

## Data-Driven Improvement

- Use **benchmarking data** to guide performance improvements — don't optimise without numbers.
- Use **code coverage data** to guide where to add tests — target uncovered paths, not a vanity percentage.

## Reference Implementations

- [devantler-tech/ksail](https://github.com/devantler-tech/ksail) — Go CLI built with TDD, full CI/CD pipeline, benchmarks, and E2E system tests in GitHub Actions.
- [devantler-tech/platform](https://github.com/devantler-tech/platform) — Kubernetes platform using ksail for init → create → push OCI workflow, with progressive CI (Docker → Hetzner staging → Hetzner prod).
