# AGENTS.md

Entry point for AI coding agents working on **remote-scrcpy**. This page is
an index. The rules and procedures are under [`docs/`](docs/), written for
people and agents alike, and they win wherever this page seems to differ.

## What this project is

A single Bash executable, `remote-scrcpy.sh`, that runs
[scrcpy](https://github.com/Genymobile/scrcpy) on this computer against an
Android phone plugged into a different, SSH-reachable computer, through a
private SSH connection to that computer's
[ADB](https://developer.android.com/tools/releases/platform-tools) server.
A personal tool with a public mirror: correctness, safety and honesty for
the maintainer's own daily use come first, polish for strangers second.

## Hard stops

Three rules are repeated here because an agent must know them before its
first command. Each is explained in
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

1. Never edit `remote-scrcpy.sh`. It is generated: edit `src/`, run
   `bash src/build.sh`, commit both together.
2. Never run the launcher or its Tab completion against a real host or
   phone. Safe anywhere: `--help`, `--version`, `--prerequisites`,
   `--completion bash`, `--list-hosts`.
3. Never push to `main` and never rewrite published history. Every change
   takes the path in [`docs/workflow.md`](docs/workflow.md).

## Where things are

| You need | Read |
|---|---|
| the rules, the layout, how the documents are kept | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) |
| how the program works: modules, lifecycle, invariants, exit statuses | [`docs/architecture.md`](docs/architecture.md) |
| to run or write tests | [`docs/testing.md`](docs/testing.md) |
| to take a change to `main`: branch, pull request, review, merge, commit messages, versions, what needs the maintainer's request | [`docs/workflow.md`](docs/workflow.md) |
| to add an option or environment variable | [`docs/adding-a-cli-option.md`](docs/adding-a-cli-option.md) |
| to cut a release | [`docs/release.md`](docs/release.md) |
| why something is the way it is | [`docs/decisions.md`](docs/decisions.md) |
| what applies to agents only | [`.agents/rules.md`](.agents/rules.md) |

## Skills

Under `.agents/skills/`, which `.claude/skills` links to: `build-and-test`,
`add-cli-option`, `pull-request`, `release`. Each is a pointer to its page
above.
