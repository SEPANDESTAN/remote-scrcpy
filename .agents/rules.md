# Rules for agents only

Everything a person and an agent both need is under [`docs/`](../docs/).
This page holds only what concerns agents and their tools.

- **Agent files stay indexes.** `AGENTS.md` has at most 50 lines and a
  `SKILL.md` at most 15. A new procedure is a page under `docs/` plus a
  skill that points to it: `.agents/skills/<kebab-name>/SKILL.md` with the
  `name` and `description` header of the
  [Agent Skills](https://agentskills.io) format.
- **No `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`**, here or in a
  directory above a checkout. [Claude Code](https://code.claude.com/docs/en/memory)
  reads `AGENTS.md` itself from version 2.1.277 on, but only while none of
  those three exists. It reads nothing under `.agents/` on its own; that is
  why `AGENTS.md` links to this page.
- **`.claude/skills` is a symlink to `.agents/skills`.** Claude Code finds
  skills only under `.claude/skills`; other tools look in `.agents/skills`.
  On Windows, run `git config --global core.symlinks true` before cloning
  (needs Developer Mode), or read `.agents/skills/` directly.
- **`.claude/settings.json` allows read-only and build or test commands
  only.** Do not widen it. Whatever writes, commits, pushes or edits GitHub
  still asks. Per-machine settings go in the ignored `settings.local.json`.
- **When a permission or safety check refuses a command, stop and tell the
  maintainer.** Do not rephrase it, split it, or hand it to another agent.
- **Run a new or changed test script contained the first time:** standard
  input closed and a limit on processes and memory around it, for example
  `systemd-run --user --scope -p TasksMax=200 -p MemoryMax=2G ... < /dev/null`.
  A test written here once forked without end; "Environment" in
  [`docs/testing.md`](../docs/testing.md) has the mechanism.
