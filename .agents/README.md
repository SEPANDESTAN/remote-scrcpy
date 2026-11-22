# .agents/

Shared, tool-neutral material for AI coding agents working on this
repository. The entry point for any agent is [`../AGENTS.md`](../AGENTS.md);
this directory holds the skills it refers to, each of which points to a
procedure under `docs/`.

```
.agents/
  README.md              this file
  skills/
    build-and-test/      points to docs/testing.md
    add-cli-option/      points to docs/adding-a-cli-option.md
    release/             points to docs/release.md
```

Each skill is a directory with a `SKILL.md` that starts with a YAML header
(`name`, `description`) followed by a pointer to the procedure, the format used by the
[Agent Skills](https://agentskills.io) convention and by Claude Code.

## How tool-specific locations map here

| Tool location | Points to |
|---|---|
| `CLAUDE.md` | symlink → `AGENTS.md` |
| `.claude/skills` | symlink → `.agents/skills` |
| `.claude/settings.json` | tracked; read-only and build/test command allowlist |
| `.claude/settings.local.json`, `.agents/**/*.local.*`, `.agents/local/` | per-machine, ignored by git |

Symlinks are committed as such. On Windows, run `git config --global
core.symlinks true` before cloning (needs Developer Mode or an elevated
shell); otherwise the two links check out as small text files containing the
target path, and `AGENTS.md` and `.agents/skills/` can be read directly.

## Adding a skill

Write the procedure as a page under `docs/`, so that a newcomer can follow
it without the chat that produced it, then create
`.agents/skills/<kebab-name>/SKILL.md` with the header and a pointer to
that page.
Nothing else is needed: Claude Code sees it through the `.claude/skills`
link.
