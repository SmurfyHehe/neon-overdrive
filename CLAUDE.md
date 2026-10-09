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

## Git from the Claude desktop bridge's Linux shell: read with no locks

A cloud Claude session can reach this folder through the desktop app's Linux
shell (`device_bash`), where **deleting files is blocked**. Git cleans up its
lock files by deleting them, so any git command that writes leaves a stale
lock behind. On 2026-10-04 a plain `git status` there (status refreshes the
index) left `.git/index.lock` in the root checkout for under a minute,
which blocks every other git command in that checkout until it is moved away.

Rules for that shell:

- **Read with `git --no-optional-locks`** (`status`, `diff`), or set
  `GIT_OPTIONAL_LOCKS=0`. `log`, `show` and `cat-file` don't write.
- **No writing git commands there at all**: no `fetch`, `add`, `commit` or
  `worktree add`. Hand over work another way, for example a bundle file plus
  the command for Roy or a Windows-side agent to run.
- **If a stale lock appears, move it out of `.git`** (renaming is allowed,
  deleting is not) and tell Roy.

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

## After pulling: game won't boot? Refresh the class cache

Godot keeps a per-machine cache of `class_name` scripts in
`.godot/global_script_class_cache.cfg`. `.godot/` is gitignored, so when a
pull deletes or moves a script, your cache still points at the old path and
the game fails at parse time with a missing-script or unknown-class error
(issue #42 - PR #3 left `PlayerCar` pointing at a deleted file).

Fix it by running this once from the project folder:

```
powershell -File tools/refresh-godot-cache.ps1
```

or directly: `godot --headless --editor --quit --path .` (on Roy's laptop,
`godot` is `~/Documents/Godot_v4.7.2-stable_win64_console.exe`).

- **Run it after any pull that deletes, renames or moves a `.gd` file**, and
  in a fresh worktree before running the game or tests.
- **If a worker reports "the game doesn't load" after pulling, try this
  first.**
- **Never commit `.godot/`** to "fix" it - the cache is machine-local.

## Workers: the queue is dispatcher-only

`office-queue` is for the queue agent (the dispatcher) only. From a worker,
`.agent-office/bin/office-queue list` returns
`403: Only the agents standing by the boards can use the queue.` That is
expected - do not retry it or work around it (issue #48).

- **The dispatcher checks the queue** and pastes what is in flight into each
  task prompt.
- **Workers use that in-flight list**, plus `gh pr list` and
  `git branch -r`, to avoid duplicating work. Workers do not run
  `office-queue`.
- **If a required check is impossible, say so plainly** - e.g. "the queue
  refused me (403), so I relied on the in-flight list in my prompt". Never
  report it as "no queue found".
- **After each PR, report the actual token and time cost** of the task, not
  just the estimate.

## Searching: never scan the whole disk

On 2026-10-09 eight orphaned `find / -name ...` processes ran for 3-5 hours
each and used about a third of Roy's CPU, long after the sessions that
started them had ended.

Rules:

- **Search the repo, not the drive.** Use the Glob and Grep tools, or
  `git ls-files | grep <name>`. These finish in under a second.
- **Never run `find /`, `find /c`, or search a drive root.** If a file may be
  outside the repo, search one named folder (`C:/SmurfyHehe`,
  `C:/Users/Roy/Documents`) and cap it: `timeout 20 find <folder> -name <x>`.
- **Run any long search in the background with a timeout**, and kill it
  yourself if you stop needing it.
