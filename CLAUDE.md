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

## Git: the root checkout is shared - never move its HEAD

`C:/SmurfyHehe/neon-overdrive` is one working tree that several agents run
commands in at the same time. Worktrees under `.claude/worktrees/` are
private; the root is not.

On 2026-09-29 one agent ran `git reset` to `origin/main` in the root checkout
while another agent was mid-debug there with an unpushed fix commit on `main`.
The commit was orphaned and the working tree reverted to a version of
`road_chunk_builder.gd` that did not parse, so the game stopped booting again
in the middle of diagnosing why it had stopped booting. Nothing was lost only
because the same fix already existed on PR #4.

Rules:

- **Never run a command that moves HEAD in the root checkout.** No
  `git reset`, `git checkout <branch>`, `git switch`, `git stash`, no
  force-pull. Read-only git there is fine: `status`, `log`, `diff`, `show`,
  `fetch`.
- **Do your work in your own worktree.** `git worktree add
  .claude/worktrees/<your-branch> -b <branch> origin/main`, then stay in it.
- **`git pull --ff-only` in the root is for Roy**, or for an agent he has
  just asked to pull a merged PR. Say so before you do it.
- **If the root checkout is on the wrong commit, report it, do not repair
  it.** Another agent may be relying on exactly that state. Tell Roy what you
  see and let him decide.

## Git: remote

`origin` is <https://github.com/SmurfyHehe/neon-overdrive.git>.

## Git: every change goes through a pull request

Roy approves changes before they reach `main` (decided 2026-09-29).

- **Never commit to `main`.** Branch first, in your own worktree under
  `.claude/worktrees/` so you do not switch the branch under other agents.
- **Push your branch and open a PR** with `gh pr create`. Pushing a work
  branch is allowed; the PR description says what changed and why, in plain
  words.
- **Only Roy merges.** Do not merge your own PR, and do not push to `main`.
