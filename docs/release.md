# Releasing

The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Which part of
the version moves is decided by the commit types since the last release, as
described under Versioning in [`workflow.md`](workflow.md). The release
commit reaches `main` like every other change: through a pull request.

## The version lives in four places

| Location | What to change |
|---|---|
| `src/core.sh` | `APPLICATION_VERSION=X.Y.Z` |
| `tests/test-maintenance.sh` | every `--version` assertion (`check contains "$(... --version)" 'X.Y.Z'`; find them with `grep -n -e --version tests/test-maintenance.sh`) |
| `CHANGELOG.md` | promote `## [Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD`; keep the `### Compatibility` subsection |
| `remote-scrcpy.sh` | regenerate with `bash src/build.sh` so `--version` reports the new number |

Bumping only `src/core.sh` fails CI: the test assertion still expects the
old string.

## Steps

1. Make sure `main` is green, then start a `release/X.Y.Z` branch in a
   worktree as in [`workflow.md`](workflow.md).
2. Edit the three files above, then `bash src/build.sh`.
3. Run everything in [`testing.md`](testing.md).
4. One commit:
   `release: bump to X.Y.Z and finalize CHANGELOG` with a body that lists the
   four files and summarizes the release (see `git show f623525` for the
   worked example).
5. Take it through the pull request, review and squash merge of
   `workflow.md`, then `git pull --ff-only` in the main checkout so that
   `main` is the release commit.
6. Create the tag and release on GitHub in one step, from the main checkout.
   Check first that it is at the merged release commit (`git log -1` shows
   the `release:` subject and `git status -sb` shows nothing ahead or
   behind), and name that commit as the target, because `gh` otherwise tags
   whatever the default branch points to at that moment:

   ```bash
   gh release create vX.Y.Z --target "$(git rev-parse HEAD)" \
       --title "vX.Y.Z — <one-line summary>" --notes-file notes.md
   ```

   The notes carry an install block that pins the tag, so the link keeps
   working after `main` moves on:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/vX.Y.Z/install.sh \
       | bash -s -- --ref vX.Y.Z
   ```

   followed by the CHANGELOG section for the version and a "Next" pointer to
   open issues. The rule on example values in
   [`CONTRIBUTING.md`](CONTRIBUTING.md) applies to the notes as well:
   describe a removed value, never quote it.
7. `git fetch --tags` so the local clone sees the tag `gh` created.
8. Verify: the pinned install command, run with a scratch `HOME`, reports
   the new version.

Tags are `vX.Y.Z`, unsigned, created by `gh release create`. Releases are
not drafts and not pre-releases. The README's install command points at
`main` on purpose, so users who follow it get the latest bundle; `--ref
vX.Y.Z` on the installer pins a release.
