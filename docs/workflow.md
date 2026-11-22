# Workflow: from a change to `main`

Every change reaches `main` through a reviewed pull request that is
squash-merged. Nobody, human or AI agent, pushes to `main` directly, and
published history is never rewritten: no amend, rebase or force-push of
anything that has been pushed. This page is the only copy of the procedure;
other documents link here.

It needs [git](https://git-scm.com/) with
[worktrees](https://git-scm.com/docs/git-worktree) and the
[GitHub CLI](https://cli.github.com/) (`gh`).

## One change, one pull request

1. **Branch in a worktree.** The main checkout stays on `main`; each change
   gets its own directory under `.worktrees/`, which git ignores.

   ```bash
   git fetch origin
   git worktree add .worktrees/<slug> -b <type>/<slug> origin/main
   ```

2. **Commit there.** Keep the change atomic: one purpose, and everything that
   purpose needs (source, regenerated bundle, tests, documentation). Stage
   files by name; `git add -A` once leaked a local settings file.

3. **Open a draft pull request** while the work is in progress.

   ```bash
   git push -u origin <type>/<slug>
   gh pr create --draft --title "<type>(<scope>): <summary>" \
       --body-file <file> --label <label>
   ```

   The body follows [Issue and pull request bodies](#issue-and-pull-request-bodies).

4. **Review it yourself.** Read the whole diff as if someone else wrote it,
   rebuild, and run everything in [`testing.md`](testing.md). Fix what you
   find with new commits.

5. **Mark it ready and get an independent review** (`gh pr ready <number>`),
   as described under [Reviewing](#reviewing).

6. **Address the review.** Read the findings on GitHub, fix them with new
   commits, push, and ask the same reviewer to look again. Repeat until the
   verdict is an approval.

7. **Squash-merge** once the review approves and CI is green, then clean up
   from the main checkout. The branch is deleted by hand because it is still
   checked out in the worktree when the merge happens.

   ```bash
   gh pr checks <number> --watch
   gh pr merge <number> --squash \
       --subject "<type>(<scope>): <summary>" --body-file <file>
   git worktree remove .worktrees/<slug>
   git branch -D <type>/<slug>
   git push origin --delete <type>/<slug>
   git pull --ff-only
   ```

Start the next change only after the previous one is merged. A change too
large to review in one sitting is split into stacked pull requests: each
branch starts from the previous one, and they are reviewed and merged in
order.

## What does not belong to the change

While working you will notice a defect somewhere else, or think of an
improvement that has nothing to do with the task. Do not fold it in and do
not leave it in your head: open an issue at once and carry on.

```bash
gh issue create --title "<summary>" --body-file <file> --label <label>
```

Write the issue for someone who has none of your context and should be able
to start immediately: what is wrong or wanted, where (files, functions,
commands), the evidence or reproduction with exact output, why it matters, a
proposed approach or the options, measurable acceptance criteria, and what is
out of scope.

## Issue and pull request bodies

The skeletons are [`.github/ISSUE_TEMPLATE.md`](../.github/ISSUE_TEMPLATE.md)
and [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md).
GitHub fills them in on the web; with `gh ... --body-file`, start from the
file. The rules behind them:

- **Open with a short summary** a human can read in half a minute.
- **Make critical points stand out** with a
  [GitHub alert](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
  (`> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`). Keep them for what is
  major; an alert on everything marks nothing.
- **Add a collapsed block for AI agents** right after the summary:
  `<details><summary>Context for AI agents</summary>`. It holds what a
  newcomer lacks and a human can skip: constraints, decisions already taken
  and why, what was tried and rejected, the files and functions involved,
  links to docs, issues and upstream sources.
- **List open items as checkboxes** (`- [ ]`): outstanding tasks, and
  anything the reviewer or reader has to decide or verify.
- **End every pull request body with proof.** The last section pairs each
  deliverable with the exact command that demonstrates it and the result
  that was observed, so that anyone can run it again from a clean checkout
  and compare. A claim without a command is not proof.
- **Label it.** See [Labels](#labels).

## Labels

Every issue and pull request carries one type label, which mirrors the
commit type, so that work can be picked and reported by kind
(`gh issue list --label bug`).

| Label | Commit types | Use for |
|---|---|---|
| `bug` | `fix` | wrong behaviour |
| `enhancement` | `feat` | new behaviour |
| `documentation` | `docs` | documentation only |
| `tests` | `test` | test suites and fixtures |
| `ci` | `ci` | the GitHub workflow |
| `maintenance` | `build`, `refactor`, `chore`, `release` | everything that changes no behaviour |

Two more describe state: `question` marks something waiting on a decision
from the maintainer, and `wontfix` marks an issue closed as declined, with
the reason in its last comment.

## Commit and pull request messages

Subjects and pull request titles follow
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`<type>(<scope>): <summary>`, scope optional, `!` after the type or scope for
a breaking change. Types in use: `feat`, `fix`, `docs`, `test`, `ci`,
`build`, `refactor`, `chore`, `release`.

The body is documentation. Write it as prose that lets a reader who has only
`git log` understand what the change is for, what it does, why it was needed
and how it works, without labelling those parts. The squash commit is what
remains on `main`, so write its body for that reader instead of accepting the
concatenated branch commits.

Commits authored by an AI agent carry a
`Co-Authored-By: <agent name> <noreply@...>` trailer.

## Versioning

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and the commit type says which part moves: `fix` is a patch, `feat` a minor,
a breaking change (`!`) a major. `docs`, `test`, `ci`, `build`, `refactor`
and `chore` do not call for a release by themselves. Cutting the release is
described in [`release.md`](release.md).

## Reviewing

The reviewer is someone who did not write the change. For a change written by
an AI agent, that is a separate agent started with a fresh context: it gets
the pull request number and this section, never the author's reasoning or
conclusions. A reviewer reads, builds and runs the suites, and does not edit,
commit or push.

What to check:

- The change does what its title and body say, and nothing else.
- Every rule in [`CONTRIBUTING.md`](CONTRIBUTING.md) still holds.
- The bundle is rebuilt and the suites in [`testing.md`](testing.md) pass.
  Never run the launcher against a real host or phone to find out.
- New behaviour is tested, or the message says plainly why it is not.
- Documentation states each fact in one place and every link resolves.
- Commit messages, the pull request body and its label meet the sections
  above, and the proof at the end of the body gives the same results when
  you run it.

The review is posted on the pull request. Its first line is the verdict,
`VERDICT: APPROVE` or `VERDICT: REQUEST CHANGES`. Each finding names the file
and line, what is wrong, and what would resolve it, and is marked `blocking`
or `nit`; only blocking findings prevent approval.

```bash
gh pr review <number> --comment --body-file <file>
```

GitHub does not let an account approve its own pull request, so when author
and reviewer share an account the verdict line in a comment is the approval.
A reviewer with a different account uses `--approve` or `--request-changes`.

## What still needs the maintainer

Pushing branches, opening issues and pull requests, and squash-merging after
an approving review are the normal path and need no further permission.
Creating a release and closing or rewriting existing issues by hand happen
only when the maintainer asked for it in the current task. A closing keyword
in a pull request body (`Fixes #2`) is fine.
