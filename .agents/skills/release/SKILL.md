---
name: release
description: Cut a remote-scrcpy release - the four version locations, the release commit, tag and GitHub release with pinned install URL, and the wording rule for notes.
---

# Release

Full prose version: `docs/release.md`. Short form:

1. Decide the number from the commit types since the last release
   (Versioning in `docs/workflow.md`), and start a `release/X.Y.Z` worktree
   branch as described there. Everything below happens on that branch.
2. Edit the three files where the version lives:
   - `src/core.sh`: `APPLICATION_VERSION=X.Y.Z`
   - `tests/test-maintenance.sh`: the `--version` assertion string
   - `CHANGELOG.md`: `## [Unreleased]` → `## [X.Y.Z] — YYYY-MM-DD`, keep
     `### Compatibility`
3. `bash src/build.sh` (fourth location: the bundle's `--version`).
4. Run the `build-and-test` skill.
5. Commit everything as one
   `release: bump to X.Y.Z and finalize CHANGELOG` commit whose body lists
   the four files; stage them by name.
6. Pull request, review and squash merge as in `docs/workflow.md`; never
   push to `main`. Then `git pull --ff-only` in the main checkout.
7. `gh release create vX.Y.Z --title "vX.Y.Z — <summary>" --notes-file notes.md`
   where the notes contain the pinned install block
   (`https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/vX.Y.Z/remote-scrcpy.sh`),
   the CHANGELOG section, and a "Next" pointer to open issues.
8. `git fetch --tags`.
9. Verify with a fresh `curl` of the pinned URL and `--version`.

Never quote removed example values (old hostnames, serials, device models)
in release notes or changelog entries; describe the change instead.
