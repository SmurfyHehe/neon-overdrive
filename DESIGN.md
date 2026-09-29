# neon-overdrive

> Scope document. Written before implementation, deliberately.
> Nothing here is final until the Open Questions section is empty.

## 1. What this is

A native desktop game. (Decided.)

Genre / core fantasy: **TBD** — see Open Questions.

One-sentence pitch, to be filled in and then held to:

> _neon-overdrive is a game where you ________, and it's fun because ________._

If that sentence can't be written, v1 isn't scoped yet.

## 2. The core loop

The thing the player does over and over. Thirty seconds of play, described
concretely — inputs, what's on screen, what creates tension, what resolves it.

- **TBD**

A game is its core loop. Everything in section 4 exists only to serve this.

## 3. v1 is done when...

A hard, checkable list. This is the anti-scope-drift device: if it's not on
this list, it is not in v1, no matter how good the idea is.

- [ ] TBD
- [ ] TBD
- [ ] TBD

Deliberately NOT in v1 (record these so they stop coming up):

- TBD

## 4. Systems

Only the ones v1 actually needs. Each gets a line on what it owns.

| System | Owns | v1? |
| --- | --- | --- |
| TBD | | |

## 5. Stack

- **Engine/framework:** TBD — see Open Questions
- **Language:** TBD
- **Target platforms:** Windows primary (dev machine); others TBD
- **Rendering:** 2D or 3D — TBD
- **Asset pipeline:** TBD (what makes the art, and what format it lands in)
- **Audio:** TBD

Constraint already known: the dev machine is Windows 11, Node is installed at
`C:\Program Files\nodejs`. Anything chosen must build and run there without a VM.

## 6. Look and feel

The name sets an expectation. Worth writing down what "neon" means concretely
here — palette, contrast, whether it's clean synthwave or grimy cyberpunk —
because it drives shader work, asset sourcing, and UI later.

- **TBD**

## 7. Risks

Things most likely to sink this. Filled in once the stack is chosen.

- **TBD**

## 8. Open questions

Blocking, in priority order:

1. **Genre / core loop.** What is the player actually doing? Everything below
   depends on this.
2. **2D or 3D.** Determines engine shortlist, asset cost, and scope by a
   factor of several.
3. **Language / engine preference.** Whether you want an editor-driven engine
   or a code-only framework.
4. **Scope ambition.** A weekend jam game, a few-month project, or open-ended?
   This decides how much of section 4 is allowed to exist.
