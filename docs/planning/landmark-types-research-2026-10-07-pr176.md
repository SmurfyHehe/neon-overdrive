# Landmark types research: world anchors and narrative progression (2026-10-07)

Status: **Roy's feedback applied (Pike Lending → liquor store).** Nothing is built; this documents story-world landmarks and their role in progression. Part of Stage C onboarding and district integration.

## What we mean by "landmark"

Not roadside detail or traffic. Landmarks are named, stable locations that anchor the story and progression: the crew's shop, rival hangouts, betting venues, meet spots, mentors' bases. Players learn them by name from texts, broadcasts and map markers. A landmark serves narrative (why you care) and/or gameplay (where you go to progress).

Roy's narrative anchor framework: **each landmark connects to a story beat, crew member, rival or a progression gate.** Remove it and that story beat, crew skill or rivalry loses its place in the world.

## Story spine landmarks

| Landmark | Location | Owner / Operator | Story role | First appears | Map marker |
|---|---|---|---|---|---|
| **Dunmore Auto** | Downtown | Walt Dunmore | The player's base, crew meeting point. Debt is owed here ($60k to liquor store by season end). | Act 1, turn 0 | Player base |
| **Liquor store** (was "Pike Lending") | Docks or Downtown (TBD by Roy) | Unnamed owner (ties to Vance Ledger's crew) | The debt holder, story pivot: reveals mid-Act 2 that it fronts for Ironbridge (Ledger). Visiting it is cosmetic, not a mission; the debt is story-only. | Act 1, mentioned in text | Story marker (visited in cutscene or text context, not active gameplay) |
| **Graveyard TV (the Garage back room)** | Downtown | Dale | Where Dale broadcasts from. Crew members reference it; late-game it's a social hub. No active mission. | Act 1, Scene 2 (first broadcast) | Optional social |

## Crew and rival location anchors

| Type | Landmark | Linked to | Location | Role | First appears |
|---|---|---|---|---|---|
| **Crew base** | Dunmore Auto (shop bay / office) | all crew | Downtown | Meeting point, tuning base, progression tracking | Turn 0 |
| **Crew members** | — | Juno (launches) | TBD (Juno's home or a track) | First win triggers their car availability; crew drama point TBD | Act 1, Scene 3+ |
| — | — | Teo (tuning) | TBD (tuning shop or Juno's house) | Tuning advice, setup presets | Act 1, Scene 3+ |
| — | — | Pilar (touge) | Cutter Canyon (road location) | Mountain runs, rival district 1 (Kasumi Run HQ) | Act 2, Scene 1 |
| — | — | Moose (wrench) | Dunmore Auto or a yard | Damage repairs, car recovery if wrecked | Variable |
| **Rival hangouts** | Ironbridge HQ | Vance Ledger + crew | Unknown (Docks likely, or industrial area) | Personal rival, final boss. Ledger beats you, reveals debt link. | Act 1, Scene 1 (race, not HQ visit) |
| — | Kasumi Run base | TBD (crew leader) | Downtown or near Docks | JDM crew, district 1 leader. Multiple races to take district. | Act 2, Scene 1 |
| — | Gruppe 9 base | TBD (crew leader) | Route 9 or suburbs | Euro crew, district 2 leader. | Act 2, Scene 2 |
| — | Diesel Row base | TBD (crew leader) | Docks (truck culture) | Truck/big-rig crew, district 3 leader. | Act 2, Scene 3 |
| **Legendary racers** | TBD (5 kings' hang-outs, TBD) | 5 unnamed kings | Various | Each king holds one high-difficulty race; beaten in sequence for story climax. | Act 3, Scene 1+ |
| **Mentors** | — | Ferris (tow-truck driver) | Mobile (appears at breakdowns; loose affiliation with a garage or shop) | Trades tips for favours. Non-critical but available. | Act 1 or 2 (TBD) |
| — | — | Okafor (ex-factory tester) | TBD (office, diner, or home) | Data-only analysis; helps with tuning baseline. | Optional, Stage C+ |

## District map anchors (Stage C, turf control)

After defeating a crew's leader (Act 2), the player's crew "owns" a district. Ownership is cosmetic (text references, a flag on the map, crew members visible there) but serves the spine: taking districts builds credibility for the final kingpin races.

| District | Neutral landmark | Rival leader's hangout | Crew hangs there after win | Story significance |
|---|---|---|---|---|---|
| **Downtown** | Dunmore Auto, betting venue (TBD), cafe | Kasumi Run HQ | Crew meets at Auto | Starting base, crew origin |
| **Docks** | Street level (dig/roll strips), fuel depot (TBD) | Ironbridge HQ (Ledger) OR Diesel Row base | Crew visible at strip, fuel stop | Industrial, street racing heartland. Reveals Pike/Ledger link here? |
| **Cutter Canyon** | Mountain pass, overlook rest stop (TBD) | Kasumi Run satellite or Gruppe 9 HQ | Crew meets at overlook | High-skill mountain runs; Pilar's terrain |
| **Route 9** | Freeway on/off ramps, truck stop (TBD) | Gruppe 9 HQ | Crew visible at freeway meets | Long-distance runs, speed focus |
| **Airstrip** | Runway (cosmetic), pits area (TBD) | TBD (neutral zone? final kings race here?) | Crew celebration (end-game) | Top-speed pulls, end-game venue |

## Landmark narrative anchors (Roy's framework)

Each landmark exists because:
1. **Story beat.** A named scene happens there or starts because of it (Ledger beats you → Dunmore Auto; debt reveal → Liquor store in text; first crew win → their intro at a location).
2. **Crew skill gate.** Crew member's specialty anchors to a location (Pilar + Cutter Canyon mountain runs; Teo + tuning workshop).
3. **Rivalry territory.** Rival crew HQ or hangout; defeating them gives the player's crew that territory.
4. **Player progression.** Visible presence there signals story progress (crew members appear in districts after wins; Dale's broadcast reaches more listeners).

**Landmarks to avoid:** generic roadside detail (lamp posts, diners with no named owner, abandoned cars). Only use named, story-connected locations.

## Steelman

Narrative anchors prevent the world from feeling empty or random. Every landmark the player learns by name serves at least one of: story beat, crew progression, rivalry, or progression gate. This keeps the map readable and story progression visible in the world.

## Premortem (why this fails)

1. **Landmark bloat.** Too many named locations overwhelm the player. Mitigation: stick to ~12–15 total across all acts; add new ones only when a story beat or crew member needs a home.
2. **Empty hangouts.** A rival's HQ is named but the player never needs to go there. Mitigation: every landmark appears in at least one progression race, text or crew interaction.
3. **Conflicting meanings.** "Dunmore Auto is the crew base" but crew also hangs at other unnamed locations. Mitigation: anchor each crew member to one place in Act 1; let districts shift the hangout in Act 2.
4. **Liquor store mis-fit.** Changing Pike Lending to a liquor store works as a debt holder, but feels incongruous as a formal finance entity. Mitigation: frame it as a money-lender who operates out of a liquor store (old-school, street-level, fits the gritty tone).

## Implementation notes

- **Map marker types:** Base (Dunmore Auto), Rival (crew HQs), Optional (mentors, Graveyard TV), Social (unlocked after district wins). Districts shown as overlays, not new landmarks.
- **Text references:** Story texts always name the landmark and its operator. "Walt's at the shop" → Dunmore Auto. "Word is Ledger's crew runs the Docks" → Ironbridge presence there, not a mandatory visit.
- **Visuals:** Each landmark gets a 2–3 icon silhouette for the map (warehouse, street corner, mountain rest stop). The actual world geometry is detailed elsewhere (Stage C environment).

## Questions for Roy (defaults if unanswered)

1. **Liquor store location:** Docks or Downtown? (Default: Docks, easier debt-collection story angle.)
2. **Neutral landmarks per district:** Each district needs at least one non-rival meeting spot (betting venue, fuel depot, rest stop). Are these named or generic? (Default: named, e.g. "The Fuel Stop" on Route 9.)
3. **Mentor visit landmarks:** Does Ferris appear at a specific garage, or does he roam? Does Okafor have an office? (Default: mobile/flexible, not a hard anchor.)
4. **King locations:** Do the 5 legendary racers each have a hangout, or do they appear only at race venues? (Default: race venues only, no hangout anchor.)
