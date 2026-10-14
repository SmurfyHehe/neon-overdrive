# Races you find in the world, race pay and bust costs (2026-10-14)

Asked by Roy (1542, 14:15Z): races in the world, race pay and bust costs, before
garage buying. Rule from the same message: **a simulator that plays like an
arcade. Real-life based, but the effects are exaggerated and fun.**

Built from: `notes/simcade-first-plan-2026-10-14.md` (section 5), the race plan
(`races-rivals-plan-2026-10-09`, Roy 84-91), run structure
(`run-structure-2026-10-09`), economy (`economy-2026-10-10` section 3-4), police
build plan F3, free mode design. Checked against the code on build 4
(4164226): `race_controller.gd`, `wallet.gd`, `police_patrol.gd`,
`police_heat.gd`, `freemode.gd`.

## 0. What is there today (checked in code)

| Piece | State on 4164226 |
|---|---|
| Race core | Works: one rival, rolling start beside you, finish line down the road, retry. Only the pause menu starts it ("Race a test rival"). |
| Race pay | A stub counter (`stub_pay`, "nights of wages"). No money moves. |
| Wallet | Real: tonight's cash (at risk) and the bank, banked at 6 a.m., saved. |
| Bust | The ring busts you, heat clears, the screen says "Busted." **Nothing is charged, the clock does not move, a race keeps running.** |
| Escape | Counted, pays nothing. |
| Bad cops | Registered in heat, but a bust by one takes nothing. |
| Meet spots, flyers, marked racers, flash to race | Not built. |
| Free mode | Exists, but only from night 31 and it stops boss races. |

## 1. The loop Roy will see

1. Drive out at night. Some cars on the road carry a **crew sticker and a
   faint halo** (decided). Those are racers.
2. **Flash one from behind** (H, within ~30 m). It answers with its hazards,
   pulls level, three honks, **go**: a rolling race to the next landmark.
3. Or **pull into a meet spot** (the ramp destinations Roy just said yes to:
   truck stop, diner, Docks pier, parking deck, salvage yard). A flyer card
   shows tonight's one to three races there. Pick one: **standing start**, a
   person in the road with a flashlight, three flashes, drop.
4. **Win = cash slams onto the screen.** Cash is tonight's, at risk until
   dawn or home.
5. Racing is loud: two cars side by side at speed draws the cops (the
   side-by-side rule already exists in heat). **A chase does not stop a race**
   (decided).
6. **Escape = paid** by how hot it got. **Busted = you pay**: ticket and tow
   from the bank, an hour lost. A bad cop takes **all tonight's cash** instead.
7. Dawn banks what you kept.

## 2. How a race starts

| Start | Where | How | Race | Pays (act-1 rates) |
|---|---|---|---|---|
| **Rolling challenge** | Anywhere on the road | Flash a marked racer from behind; hazards twice = yes; rolling start, three honks | To the next landmark, 45-90 s | $150-375 |
| **Meet sprint** | Meet spot | Flyer card, standing start (flashlight drop) | 60-120 s to a landmark | $450 |
| **Drag** | Meet spot with a straight | Flyer, standing start, 400 m | 10-15 s | $150-300 |
| **Crew boss** | That crew's meet spot | After you beat the crew's racers a few times, the boss shows on the flyer | Sprint, crew parked at the start | $750 |

- A racer flashed during a chase **always declines**. A rolling challenge you
  lose has no retry: that racer is gone for the night (decided).
- Jumping a standing start = the rival wins (decided).

## 3. Crews

One crew per area, each with its own sticker, car type and a boss. The eight
regulars from free mode (Roy 1207) are drawn from these crews. Crew ladder,
standings and the Season Cup come later; this design only needs "a racer
belongs to a crew, the crew has a boss".

## 4. Money: pay, bust, escape

Act-1 / Weekend Warrior numbers from the economy doc (1 night of wages =
$1,500). Free mode uses these until the season economy is re-checked.

| Event | Money | From / to |
|---|---|---|
| Meet sprint win | +$450 | Tonight's cash |
| Rolling challenge win | +$150 to $375 by racer tier | Tonight's cash |
| Escape, heat 1 / 2 / 3 / 4 / 5 | +$75 / $150 / $225 / $375 / $525 | Tonight's cash |
| Honest bust, heat 1 / 2 / 3 / 4 / 5 | -$120 / $225 / $375 / $600 / $825, clock +1 h | Bank (cash kept) |
| Bad-cop bust | All of tonight's cash | Cash (bank kept) |
| Bust on night one | A warning, no charge (decided) | |
| Difficulty | Bust bills ×0.75 / ×1 / ×1.25 | |

- Heat for bust and escape is **the highest level the chase reached**, not
  the level at the end (heat is cleared the moment the ring fills).
- Busted mid-race = the race is lost (BUSTED) **and** the bust bill.
- No entry fee (decided for retries); side bets come later.
- Tow: the decided rule is "towed back to the start of the road". The first
  step only charges the bill and the hour; the tow drive comes with the meet
  spot step, where there is a place to be towed to.

## 5. Exaggerated arcade effects (Roy's rule)

What "exaggerated" means here, so Roy can correct it:

- **Money stamp:** a big amber "+$450" slams onto the screen oversized and
  snaps to size with a bounce, a quick amber flash over the whole screen, then
  it flies up and fades. Losses slam in silver (bank) with a dark flash.
- **Bust card:** "BUSTED" stamped, then the bill underneath line by line.
- **Starts:** the flashlight glare blooms across the screen; hazards flash
  bigger and brighter than real; three loud honks.
- Later: a cash-register sound for wins, a heavy stamp sound for busts.

## 6. Free mode from night 1

A new save starts in free mode (night 1, the story is off), with marked
racers and meet spots every night and boss races on. `freemode.gd` today
starts at night 31 and stops `boss_races`; that changes in step S5.

## 7. Build steps (one draft PR each)

| Step | What you get | Size |
|---|---|---|
| **S1 Stakes** | Race wins pay real cash; busts charge ticket and tow from the bank by heat, +1 h; bad cops take tonight's cash; night-one warning; escapes pay; a bust ends a race; money stamp effect | S |
| S2 Rolling challenge | Marked racers in traffic (sticker + halo), flash to challenge, hazards, rolling start, finish at the next landmark | M |
| S3 First meet spot | One ramp destination as a meet spot, flyer card, flashlight standing start, tow there after a bust | M |
| S4 Crews and bosses | Crew per area, boss on the flyer after N wins | M |
| S5 Free mode from night 1 | New save starts free, boss races on | S |
| S6 Sounds | Cash register, stamp, honks | S |

## 8. Decided

- **No entry fee for meet races** (Roy 1547, 2026-10-14).

## 9. Built so far

- **S1 Stakes**: built (race pay, escape pay, bust bills, money stamp).
- **S2 Rolling challenge**: built as a first version. One traffic car ahead
  going your way is the racer (sport builds first), with a pulsing amber
  halo within 60 m. Flash it from within 35 m: hazards, halo flare, three
  honks, "GO!", and that car races you to a line 1.5 km down the road
  ($250 a win). With cops on you it waves you off. Placeholders: fixed
  distance instead of the next landmark, no crew sticker yet.
