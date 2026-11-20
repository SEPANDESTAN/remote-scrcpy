# Project history

What happened to this repository and when, so that nobody has to reconstruct
it from `git log` or from chat transcripts that no longer exist.

## Before the GitHub import

remote-scrcpy was developed as a personal tool for viewing and controlling an
Android phone that stays plugged into a different computer. The design
history before 2026-11-05 is not recorded anywhere; the code, its comments
and the pre-import entries in `decisions.md` are the only record. The initial
import commit carries version 3.0.1, so at least three major iterations
preceded it, including one that used the `gum` TUI tool and an embedded
payload (both later removed; see the regression guards in
`tests/test-maintenance.sh`).

## 2026-11-04: version 3.0.1

Internal variables were renamed from the opaque `RS_*` prefix to the
namespaces documented in `architecture.md`, and the bundle's file header and
module contracts were expanded. No public interface change.

## 2026-11-05: import, restructure, cleanup, version 3.0.2

The repository was created under https://github.com/SEPANDESTAN/remote-scrcpy
and the history was built as small commits, leaf files first:

| Commit | Purpose |
|---|---|
| `50c8455` | Initial import of 3.0.1 (modules still at the root). |
| `ed4e484` | Move the nine modules and `build.sh` under `src/`; README leads with Install and Usage. |
| `ca6df2d` | LICENSE copyright attributed to the organization. |
| `f65b2e0` | Brand-specific example SSH alias replaced by `remote-host` everywhere. |
| `5e3adc7` | Corrective commit: a local tool settings file had slipped in; ignore and untrack it. |
| `23baf38` | Realistic device serial and OEM model strings replaced by synthetic placeholders. |
| `ddc0cf6` | README completion example updated for the new alias. |
| `8f4deb6` | README links every external tool on first mention. |
| `dae5b34` | README explains that any directory on `PATH` works as install target. |
| `7c47480` | `--prerequisites` and README point at issue #1 for site-specific setup. |
| `12af264` | CI token limited to `contents: read`; manual runs enabled. |
| `f623525` | Version 3.0.2, CHANGELOG finalized, tag `v3.0.2`, GitHub release published. |

Issue #1 was opened the same day. It holds a 20-question questionnaire the
maintainer still needs to answer before the `[TODO]` markers in
`src/prerequisites.sh` and the matching README section can become real
instructions. **It is the one open reminder carried over from the original
author's notes.**

## 2026-11-06: adversarial review

The whole repository was reviewed against the standard "personal tool with a
public mirror" by five independent reviewer passes (runtime, security,
documentation, tests, newcomer onboarding) plus dynamic checks: every commit
replayed with build and tests, the suites run under environment variations,
mutation spot-checks, shellcheck, live install-recipe runs and URL checks.
Verdict: approve with reservations, no blocker. The full report is
`review-2026-11-06.md`; each actionable finding became a GitHub issue on
2026-11-19.

## 2026-11-19: onboarding files and context offload

The maintainer was moving to another machine, so everything a future human
or AI agent needs was moved into the repository: `AGENTS.md` (with `CLAUDE.md`
linked to it), `.agents/skills/` (linked from `.claude/skills`), a shared
`.claude/settings.json`, this `docs/` directory, a README "Developing"
section, and GitHub issues for every open review finding. The three trivial
findings (changelog and release note wording, README install recipe) were
fixed in the same pass.

## How the work was done

Most commits were produced with an AI coding agent (Claude Code) working from
the maintainer's instructions; they carry a `Co-Authored-By` trailer saying
so. The chat sessions themselves are not preserved. Everything from them that
matters to the project is in `decisions.md`, `review-2026-11-06.md`,
`testing.md`, `release.md` and `AGENTS.md`.
