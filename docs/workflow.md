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
   files by name; `git add -A` once leaked a local settings file. Keep
   message drafts and other scratch files outside the worktree.

3. **Open a draft pull request** while the work is in progress.

   ```bash
   git push -u origin <type>/<slug>
   gh pr create --draft --title "<type>(<scope>): <summary>" \
       --body-file <body-file> --label <label>
   ```

   The body follows [Issue and pull request bodies](#issue-and-pull-request-bodies).

4. **Review it yourself.** Read the whole diff as if someone else wrote it,
   rebuild, and run the bundle parity check and the fast suites from
   [`testing.md`](testing.md). Run the integration suite described there as
   well when the change touches the connection lifecycle
   (`src/transport.sh`, the traps in `src/main.sh`) or its fixtures. Fix
   what you find with new commits.

5. **Mark it ready and get an independent review** (`gh pr ready <number>`),
   as described under [Reviewing](#reviewing).

6. **Settle the review** as described under
   [From findings to merge](#from-findings-to-merge): discuss each finding,
   implement what was agreed, and have the same reviewer go over the result.
   An agent reviewer is resumed, so that it keeps the context of its own
   review.

7. **Squash-merge** once the last review approves, every review thread is
   resolved and CI is green, then clean up from the main checkout. The message file holds the squash commit body
   described under [Commit and pull request messages](#commit-and-pull-request-messages),
   not the pull request body. The branch is deleted by hand because it is
   still checked out in the worktree when the merge happens.

   ```bash
   gh pr checks <number> --watch
   gh pr merge <number> --squash \
       --subject "<type>(<scope>): <summary>" --body-file <message-file>
   git worktree remove .worktrees/<slug>
   git branch -D <type>/<slug>
   git push origin --delete <type>/<slug>
   git pull --ff-only
   ```

Start the next change only after the previous one is merged. Work that
spans several pull requests is ordered from leaf to root: what the others
depend on is merged first.

## Stacked pull requests

A change too large to review in one sitting may be split into pull requests
that are open at the same time, each built on the one before. They are
still reviewed and merged in order, and still without rebasing.

```bash
# start the next branch from the previous one and target it
git worktree add .worktrees/<next> -b <type>/<next> <type>/<previous>
git push -u origin <type>/<next>
gh pr create --draft --base <type>/<previous> ...

# whenever the previous branch gains commits, in the next worktree
git merge <type>/<previous>
git push

# after the previous pull request is squash-merged, in the next worktree
git fetch origin
git merge origin/main
git push
gh pr edit <number> --base main
gh pr view <number> --json closingIssuesReferences
```

Merging `origin/main` is clean at that point because both sides hold the
same content for the previous change. It only stays clean if the next
branch merged the previous one's last commits before the squash.

Closing keywords take effect only on a pull request that targets the default
branch. If the last command lists no issue although the body names one, save
the body again (`gh pr edit <number> --body-file <body-file>`) and check
once more.

## What does not belong to the change

While working you will notice a defect somewhere else, or think of an
improvement that has nothing to do with the task. Do not fold it in and do
not leave it in your head: open an issue at once and carry on.

```bash
gh issue create --title "<summary>" --body-file <body-file> --label <label>
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
- **Link what a pull request resolves.** Name every issue it resolves with a
  [closing keyword](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)
  in the body, one per issue (`Fixes #2`), so the issue closes when the pull
  request merges and nothing stays open after its work is done. An issue
  that is only partly resolved is referenced (`Refs #7`) with a note on what
  remains; the pull request that resolves the last part closes it.
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
and `chore` do not call for a release by themselves; when such changes are
released without a `feat` or a breaking change, the release is a patch.
Cutting the release, itself a pull request of type `release`, is described
in [`release.md`](release.md).

## Reviewing

The reviewer is someone who did not write the change. For a change written by
an AI agent, that is a separate agent started with a fresh context: it gets
the pull request number and this section, never the author's reasoning or
conclusions. A reviewer reads, builds, runs the suites and writes its
review, and does not edit, commit or push.

What to check:

- The change does what its title and body say, and nothing else.
- Every rule in [`CONTRIBUTING.md`](CONTRIBUTING.md) still holds.
- The bundle is rebuilt and the suites named in step 4 pass. Never run the
  launcher against a real host or phone to find out.
- New behaviour is tested, or the message says plainly why it is not.
- Documentation states each fact in one place and every link resolves.
- Commit messages, the pull request body and its label meet the sections
  above, the issues it links are the ones it resolves, and the proof at the
  end of the body gives the same results when you run it.

### The review

A review is one submission: a summary, and one comment per finding attached
to the file and line the finding is about. It is not a single long comment.

- **Each comment is atomic:** one problem, why it is a problem, and what
  would resolve it, marked `blocking` or `nit`. Only blocking findings
  prevent approval.
- **Comments attach to the diff.** GitHub accepts them only on lines that
  are part of the pull request's diff. A finding about anything else goes in
  the summary with its path and line.
- **The summary starts with the verdict,** `VERDICT: APPROVE` or
  `VERDICT: REQUEST CHANGES` on its first line. After that it says what was
  verified and how, which proof commands were run again with what result,
  and what could not be verified. It does not repeat the comments.
- **Say who is speaking.** When author and reviewer share a GitHub account,
  every comment and reply starts with `**Reviewer:**` or `**Author:**`.

Summary and comments are submitted together:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews --method POST --input <review-file>
```

```json
{
  "commit_id": "<head commit of the pull request>",
  "event": "COMMENT",
  "body": "VERDICT: REQUEST CHANGES\n\n<what was verified and how>",
  "comments": [
    {"path": "docs/workflow.md", "line": 45, "side": "RIGHT",
     "body": "**Reviewer:** blocking. <problem, reason, resolution>"},
    {"path": "src/cli.sh", "start_line": 10, "line": 12, "side": "RIGHT",
     "body": "**Reviewer:** nit. <problem, reason, resolution>"}
  ]
}
```

GitHub does not let an account approve its own pull request, so when author
and reviewer share an account the event is `COMMENT` and the verdict line is
the approval. A reviewer with a different account sets the event to `APPROVE`
or `REQUEST_CHANGES` instead.

### From findings to merge

1. **Discuss first.** The author answers every thread before changing
   anything. Accepting the proposed resolution as written settles the
   thread. A different solution, or a disagreement, is argued in the thread
   and needs the reviewer's answer; it goes back and forth until both agree.
   Nothing contested is implemented before that.

   ```bash
   gh api repos/<owner>/<repo>/pulls/<number>/comments      # comments and their ids
   gh api repos/<owner>/<repo>/pulls/<number>/comments/<id>/replies \
       -f body='**Author:** ...'
   ```

2. **Implement what was agreed** with new commits, push, and name the commit
   in each thread.

3. **Final review.** The reviewer goes over the whole pull request again,
   not only the threads: it checks each agreed resolution against the files,
   resolves the threads it accepts, runs the proof again, and submits a new
   review with a verdict. Anything new it finds starts again at 1.

   ```bash
   gh api graphql -f query='query { repository(owner:"<owner>", name:"<repo>") {
     pullRequest(number:<number>) { reviewThreads(first:100) { nodes {
       id isResolved comments(first:1) { nodes { path body } } } } } } }'
   gh api graphql -f query='mutation { resolveReviewThread(
     input:{threadId:"<thread id>"}) { thread { isResolved } } }'
   ```

4. **Merge** when the last verdict is an approval, every thread is resolved
   and CI is green, as in step 7 of the procedure.

## What still needs the maintainer

Pushing branches, opening issues and pull requests, and squash-merging after
an approving review are the normal path and need no further permission.
Commenting on an issue or correcting its label is fine too. Starting or
publishing a release, and closing or rewriting an existing issue by hand
instead of through a closing keyword, happen only when the maintainer asked
for it in the current task.
