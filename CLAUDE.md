# Neon Overdrive - working agreements

## Git: staging is not shared scratch space

Multiple agents work this repo concurrently, sometimes in worktrees under
`.claude/worktrees/`. The index is per-worktree but shared by everything
running in the same checkout, so a staged change is visible to - and
committable by - an agent that knows nothing about it.

Commit `3125489` is the warning: one agent wrote a commit message over
another agent's staged `DESIGN.md` deletion. The message happened to
describe it accurately. That was luck, not process.

Rules:

- **Stage by explicit path.** `git add ROADMAP.md scripts/foo.gd` - never
  `git add -A`, `git add .`, or `git commit -a`. An untracked file you did
  not create is not yours to commit.
- **Commit promptly.** Stage and commit in the same step. Never end a turn
  with a dirty index.
- **Check before you stage.** `git status --short` first. If something is
  already staged that you did not stage, stop and say so - do not fold it
  into your commit and do not unstage it blindly.
- **Describe only what you staged.** If the diff you are about to commit
  contains a change you cannot explain, you are committing someone else's
  work.

## Git: remote

`origin` is <https://github.com/SmurfyHehe/neon-overdrive.git>. Pushing is
Roy's call - ask, do not push on your own initiative.
