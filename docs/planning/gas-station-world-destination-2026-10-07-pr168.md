# Gas station as a world destination - proposal (2026-10-07)

STATUS: proposal only. No building until Roy signs off. All names are placeholders (story is Roy's to write).
Direction from Roy: the **garage is the primary HQ**. The gas station is one of several **world destinations** that anchor the narrative. The environment is "all of the above and more".
Flag: the DJ is "Dale" in `docs/story-bible.md` but "Dave" in project notes. This doc says **the DJ** until Roy picks.

## Steelman / premortem
- Steelman: one place you return to under pressure (fuel, damage, heat) gives the open world a rhythm and gives the story somewhere to happen. A gas station is the most believable such place at night: lit, open, nobody asks questions.
- Premortem: it fails if it becomes a menu with a pump on it (no reason to care), or a chore (forced stops that break flow). Mitigation: every stop is optional until fuel is low, takes under 10 seconds, and carries one small story beat or one useful thing.

## 1. Mechanical purpose
Ties to Stage C (currency/scoring) and the parked damage/fuel work. Numbers are tunable constants in one file.
| Function | What it does | Notes |
|---|---|---|
| Fuel | Refill at pump; price scales with district | Only matters once fuel exists (parked) |
| Quick repair | Patch body damage, partial only; full repair is the garage | Keeps the garage the HQ |
| Heat cool-down | Parked under the canopy lights, heat drains faster than on the road | Gives police a counterplay, no new system |
| Supplies | Cheap one-run consumables (tyre patch kit, coolant) | Stage E tie-in; optional |
| Save / checkpoint | Autosave on arrival | Cheap, no extra UI |
| Fast-travel node | Unlocks as the player visits each | Anchors the map |
Loop: run -> low fuel/damage/heat -> pick a nearby destination -> short stop -> back out. Loop stays repeatable without the story.

## 2. Narrative anchoring
- Staff: **Marge** (placeholder), night clerk behind glass, 50s, has seen every crew come through. Dry, never impressed. Knows Walt Dunmore from way back.
- Why it matters to the spine: the station sits on neutral ground between Ironbridge and the Garage. Ledger's crew gathers there; the player hears the setup first as overheard talk (Pike Lending's name on a receipt, a crew member paying cash for a debt).
- Dialogue style: 1-3 deadpan lines per visit, text on the HUD, no cutscene. Examples:
  - "Regular's nine-fifty. Premium's ten. You're not getting premium."
  - "Your boss called. Said you'd know why."
  - "Ironbridge was here. Left a mess. Didn't tip."
- The DJ's broadcast plays from the station's cracked radio: the one place the pirate signal is heard "in the world", not only on the HUD radio.
- Story beats (placeholders): first visit (tutorial for fuel, Marge sizes the player up); Act 1 recruit meets crew here; Act 2 overheard Pike Lending lead; Act 3 Ledger leaves a note; ending: Marge's last line depends on win/lose.

## 3. World role and difference from other places
| Place | Role | Mood |
|---|---|---|
| Garage (HQ) | Build, mod, tune, crew, story hub | Home, safe, warm |
| Gas station | Supply, rumour, neutral ground | Lit, exposed, transitional |
| Others (below) | Events, hideouts, lore | Varies |
It is a **service + rumour** point. You never build cars there, and you never decide anything big there. Short visits, many locations, one per district (Docks, Downtown, Route 9 each get their own, with a different clerk or none).

## 4. Environmental feel (Gritty PS2 night, Amber vs. Dusk, no neon)
- Light: one buzzing sodium-orange canopy (#FF8A1F / #FFC066) against navy dusk; a single flickering tube; dead pump with a bag over it.
- Signage: faded price board with one digit missing; hand-painted "NO RESTROOM"; station name in chipped letters. Original brand, no real company.
- Weathering: oil-stained concrete, crushed cups, taped window, grease-black pump handles, a stack of old tyres.
- Life: a parked tow truck (Ferris, optional cameo), one idling NPC car, moths in the lamp, a sleeping dog (cosmetic).
- Sound: canopy hum, pump clunk, distant freeway, the DJ on a cracked radio, a vending machine that rattles.
- PS2 constraints: low-poly props, low-res textures, baked canopy light cone, fog fade. Real light budget: one spot plus emissive sign.

## 5. Design sketch
Footprint ~40 x 30 m, drive-through, so it reads from the road at speed.
```
 road ---------------------------------------->
        [price sign]   [canopy: 2 pumps]   [store + clerk glass]
                           ^ park zone           [vending / payphone]
 back lot: tyre stack, dumpster, tow truck cameo
```
- Interaction: roll into the park zone and stop; a 3-line prompt (Refuel / Patch / Leave), keyboard only, no key hints on screen.
- NPCs: Marge, plus 1 random idler line per visit.
- Mechanics: see section 1.
- Build order if approved: (1) blockout scene + park zone, (2) refuel/patch + heat drain, (3) clerk dialogue data, (4) dressing pass.

## 6. Related destinations (2-3)
1. **The Last Ferry Diner** (Docks): 24h counter. Crew meets, side-job board (extra races), Ferris tips. Warm light, steam, jukebox.
2. **Cutter Canyon Overlook**: touge pull-off. Pilar's turf, time-attack start, rival intros. Quiet, wind, city lights below.
3. **Airstrip Hangar** (old Airstrip): top-speed pulls, Okafor's data bench, Ledger's late-game challenge. Cold, wide, echo.
Optional fourth: **Tow yard** (Ferris): wreck recovery and a one-off find.

## Open questions for Roy
1. Is "Marge" fine as a placeholder clerk, or do you want the clerk unnamed?
2. Should repair at the station be partial-only (recommended) or also full?
3. Is fuel in scope for Stage C, or does the station launch with heat drain and checkpoint only? (Recommended: heat + checkpoint first, fuel when it lands.)
4. Dale or Dave for the DJ?
