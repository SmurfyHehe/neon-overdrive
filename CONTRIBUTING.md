# Contributing to Neon Overdrive

Neon Overdrive is a Godot 4.7 simcade night-driving game. Roy owns the project
and approves every change. The full working rules for agents are in
[CLAUDE.md](CLAUDE.md); this page is the short version.

## Workflow

1. **Branch from `main`.** Never commit to `main` directly. If several people or
   agents share one checkout, work in your own worktree:
   `git worktree add .claude/worktrees/<branch> -b <branch> origin/main`.
2. **Stage by explicit path** (`git add scripts/foo.gd tests/foo.gd`), never
   `git add -A` or `git add .`. Commit only what you changed and can explain.
3. **Push your branch and open a pull request.** Fill in the template: what
   changed, why, and how you tested it.
4. **Roy reviews and merges.** Nobody else merges, and nobody pushes to `main`.

## Code style

- GDScript, following the [official Godot style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  tabs for indentation, `snake_case` for functions and variables,
  `PascalCase` for `class_name`, typed variables and return types.
- Comments say *why*, not *what*. When you change a vendored file under
  `scripts/vendor/`, mark the edit with a `DEVIATION` comment.
- Every car runs the same physics; cars differ only by `CarSpec` data.
- Art follows the "Amber vs. Dusk" palette (no magenta or cyan).

## Tests

- Tests live in `tests/` as standalone scripts that print PASS/FAIL and exit
  non-zero on failure.
- New behaviour gets a test, and the test is added to `tests/run_tests.bat`.
- Before opening a PR, run the suite with real Godot:

  ```
  tests\run_tests.bat quick    headless tests, about 15 s
  tests\run_tests.bat          everything, opens a game window
  ```

- After a pull that deletes or moves a `.gd` file, refresh Godot's class cache
  first: `powershell -File tools/refresh-godot-cache.ps1`.
- The quick suite runs automatically on every pull request (see
  `.github/workflows/test.yml`).

## Commit messages

- First line: what changed, in plain words, under about 70 characters.
- Body: why it changed, and anything a reviewer should know.
- Reference the issue or PR number when there is one (`Fixes #42`).

## Assets and licences

Code in this repo is under the [MIT licence](LICENSE). Third-party art, music
and code keep their own licences: add a row to [CREDITS.md](CREDITS.md) (and to
`docs/audio-licences.md` for audio) **before** adding the file. No
non-commercial, no-derivatives or share-alike assets.
