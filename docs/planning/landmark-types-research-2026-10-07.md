# Landmark types: research and proposal (2026-10-07)

Status: proposal, docs only. Roy signs off before anything is built. Story is Roy's to write: every name below is a placeholder hooked to `docs/story-bible.md`. No loan or penalty mechanics anywhere; the debt stays story-only.

Already picked: garage HQ (Dunmore Auto and the Garage back room), diner, scrapyard, hangar (old Airstrip). This note adds 6.

Assumption: the W1-W4 phase definitions are not in the repo. I read them as W1 = first district plus HQ on the existing road, W2 = stops and hubs, W3 = curves and elevation, W4 = set pieces and events. Correct me if that is wrong; only the "when" column changes.

## Steelman and premortem

- Steelman: a landmark is a story beat you can drive past. If each one has a person, a reason to stop, and a silhouette you can read at night from a moving car, the world explains itself without cutscenes.
- Premortem: it fails if landmarks are decoration with no verb, if each needs bespoke art we cannot afford on the i5-1235U 60 fps budget, or if a landmark needs the curves/elevation rework (#37) before it can exist and blocks W1-W2. So every proposal below lists its verb and its earliest buildable phase.

## Rules every landmark follows

1. One person, one verb. A named character and one thing the player does there (tune, rest, tip, listen, read, park).
2. Night readable. One strong silhouette plus one light colour (sodium orange, amber, tungsten white; fluorescent green-white only for interiors). No neon, no magenta or cyan. Police blue #2E4FD8 is reserved for police.
3. Cheap to build. Kit-bash from existing procedural props; baked or cheap shadows only; interior-only landmarks are menu scenes, not world geometry.
4. Names are local. Harlow Bay geography, no real brands.

## New landmarks (6)

| # | Landmark | District | Story hook | Who | Player verb | Look | Type | Earliest |
|---|---|---|---|---|---|---|---|---|
| 1 | **Graveyard TV tower** | Cutter Canyon ridge, visible from most of the map | Dave's pirate station leaks from here; the tower is the thing the cops cannot find | Dave (voice only) | Drive past and the radio gets clearer; later, a tip-off stop | Lattice mast, red aviation blinkers, one lit window in a prefab hut, a broken coffee machine on a milk crate | World feature | W1 |
| 2 | **Ferris Tow Depot** | Docks edge | Ferris knows every road and trades tips for favours; every wreck passes through his yard | Ferris | Take a tip, restart from a wrecked state (free; no fee mechanic) | Chain-link yard, flatbed under a work lamp, stacked tyres, a handwritten price board | World, repeatable stop | W1-W2 |
| 3 | **Okafor Dyno and Data** | Industrial strip behind Downtown | Okafor, ex-factory tester, deals in numbers only; this is where the Tuner screen lives in the fiction | Okafor | Open the Tuner screen, run dyno pulls | Roll-up door, one dyno bay lit by fluorescent tubes, clipboard wall of printouts | Interior-only (menu scene) with a small exterior shell | W2 |
| 4 | **Pike Lending storefront** | Downtown | The debt is held here and Pike is tied to Ledger's crew; the player sees it when it matters | Pike clerk (never speaks) | Read a window sign and a shop ticker (season countdown, story only) | Barred window, buzzing tungsten sign, `CASH TODAY` in amber, parked Ironbridge cars out front after Act 2 turn | World, exterior only | W2 |
| 5 | **Cutter Canyon tunnel** | Cutter Canyon, touge start | Pilar's touge starts at the mouth; echo and sodium strips make the first real set piece | Pilar | Race start and finish line, echo audio | Concrete portal, sodium strips in a repeating rhythm, no sky | World, enclosed (cheap) | W3 |
| 6 | **Ironbridge** | Harbor crossing | The rival crew is named for it; Vance's turf; the Act 3 finale ground | Vance Ledger | Territory gate, rival encounters | Steel truss bridge, rusted, work lights, long skyline reveal | World, needs elevation | W4 |

Why these six: each maps to one named story character (Dave, Ferris, Okafor, Pike, Pilar, Vance) not yet anchored to a place, and between them they cover all five districts without a second diner-style building.

## Gas stations: naming and story fit

Gas stops are a repeatable type, not counted in the landmark total. Four fictional brands keep them story-flavoured:

- `Tidewater Fuel` (port-city standard, most stations)
- `Sully's 24` (family-run, cheap, grimy)
- `Route 9 Petro` (highway only, big canopy)
- `Dunmore Fuel Depot` (one only; Walt's old supplier, used as a story wink)

Running bits for every station: the coffee machine is always `OUT OF ORDER` (Dave's recurring gag), a sticker or poster for Graveyard TV on the window, and a Pike Lending flyer on at least one pump. Pump toppers use amber, not green or blue.

## Priority for W1-W4

| Phase | Build | Reason |
|---|---|---|
| W1 | TV tower, plus HQ already picked | One tall prop and a light; skyline anchor; ties radio to world |
| W2 | Tow depot, Okafor dyno, Pike storefront, gas stations | Hubs and stops that give reasons to pull over; static kit only |
| W3 | Cutter Canyon tunnel | Needs a straight enclosed section; best after curves land |
| W4 | Ironbridge | Needs elevation and curves (#37) |

## How many: 10 by W4, 12 ceiling

- Minimum viable: 8 (one anchor and one hub per district, minus Route 9).
- Recommended: 10 (the 4 already picked plus these 6), reached by W4.
- Ceiling: 12. Past that, extra landmarks dilute the silhouette variety; add side props instead. I did not find a verified source for an exact count from other racing games, so this is a judgment, not a base rate.

Interior-only candidates (cheapest, no road or lighting cost): Okafor dyno, the garage back room (Dave's studio), a possible diner interior. Tunnel and bridge are world features but enclosed or simple, so cheap for shadows.

## Falsification

This proposal is wrong if the world turns out to be one short road: then 10 landmarks over-furnish it and 6 is the right number. The check is total drivable length once W1 lands.

## Open for Roy

1. Confirm the W1-W4 reading above.
2. Approve the 6, trim, or swap.
3. Gas station names: keep the four, or give me your own.
