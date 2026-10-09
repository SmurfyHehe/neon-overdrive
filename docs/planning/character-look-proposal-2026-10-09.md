# People in Neon Overdrive: how they should look (proposal)

Roy, 2026-10-09: "design what people will look like in game so do research,
we will need to build the user character". This is the proposal to sign off
before anything is built. Nothing here is coded.

Where it comes from: web research on 2026-10-09 (thin: mostly forum claims,
listed at the end), what the game already does (DriverModel: gloved hands,
no arms, legs on the pedals, torso and head seen through the glass in the
chase view), and the decisions already taken: gritty PS2 night, Amber vs Dusk
palette, no neon, keyboard only, integrated graphics, Roy writes the story,
the cast (Pike the mechanic, rival Vance Ledger, Dale the DJ) are placeholders.

## Where people are seen

| Place | What shows | Needs |
|---|---|---|
| Cockpit view | right hand on the wheel, knob, radio, handbrake; left hand on the wheel, window; legs on the pedals | hands and boots only (built) |
| Chase view, photo mode | the driver through the glass: head, shoulders, torso, hands | a seated bust at a few hundred tris |
| Future: garage, "Graveyard TV", story beats | Pike, Vance, Dale and bystanders at full length, close up | a full character, a face, idle animation, maybe lip movement |
| Future: street life | pedestrians, cops out of the car, spectators at a meet | a crowd figure, cheap, many at once |

The player never sees their own face unless the story shows Pike in a
cutscene or a mirror. So the "user character" is really two things: the
seated driver (cheap, seen often) and the story cast (costly, seen rarely).

## Proposal: "block people", PS2 silhouettes, painted faces

One style for everyone, so a pedestrian and Pike read as the same world:

- **Silhouette first.** Chunky low-poly figures, 800 to 1,500 triangles for
  the cast, 300 to 600 for crowd figures, hard edges, no smooth normals on the
  clothes (the car and cabin already look like this, see CockpitKit). Heads
  are a rounded box, hair a separate shell. Hands are the mittens we have
  (DriverModel.hand_boxes); fingers never articulate.
- **Faces painted, not modelled.** One 64x64 face texture per character:
  eyes, brows and a mouth line, no modelled nose or lips. Expression by
  swapping the face texture (four or five per cast member: neutral, talk,
  grin, angry, tired for Dale). PS1/PS2 indie practice, forum-backed; it
  reads at a distance and never looks like a bad attempt at realism.
- **Lit by the palette.** Vertex colour and flat materials, same roughness
  as the cabin trim. Skin tones from the sodium light, not photo colours:
  the existing SKIN #B9896A on the driver is the reference. Clothes in
  navy, oil black, dull amber, silver zips and chains. One accent per
  character (Pike: orange jacket trim already on the driver; Vance: silver;
  Dale: a faded band tee).
- **Textures small and sharp.** 128x128 for a cast member's clothes, 64x64
  face, nearest filtering. No normal maps.
- **Motion is posed, not performance.** Idle sway, head turns, a few hand
  gestures, loops of 2 to 4 seconds. No walk cycles until there is somewhere
  to walk. Talking is a face swap on a timer plus a head nod, like PS2
  dialogue scenes, not lip sync.
- **The seated driver** stays as now (Roy's "no forearms" call stands for the
  cockpit): it gains a proper bust for the chase view and photo mode, the
  cap, the jacket, the bracelet, in the same style as the cast so Pike in the
  car is Pike in the garage.

### Why this and not the alternatives

- *Realistic humans (MakeHuman, VRoid, Mixamo bodies)*: fight the car art,
  uncanny at PS2 budgets, licence homework (Mixamo files cannot be
  redistributed, VRoid terms unclear), and a smooth 10k-tri human next to a
  3k-tri hard-edged car looks wrong. Rejected.
- *CC0 packs (KayKit, Quaternius, Kenney)*: usable and Godot-ready (KayKit
  lists Godot), but their style is bright, rounded, cartoon, which breaks
  "gritty PS2 night". Useful only as a rig and proportion reference, or for
  a crowd placeholder behind glass.
- *2D stills or comic panels for story*: the cheapest route for cutscenes
  and very PS2 (several racers of the era told the story in stills with a
  voice-over). Keep it as the fallback for story beats if full characters
  take too long. Pairs well with Dale narrating over "Graveyard TV".

## Build plan (after sign-off, not now)

1. One sheet: Pike, Vance, Dale and two crowd figures as front/side proxies,
   same pipeline as the car fleet sheet (`tools/fleet_design`), so Roy picks
   from a 360 view before any rig exists.
2. Driver bust for chase view and photo mode (replaces the current torso and
   head box): one task, tests check tri count and that nothing crosses the
   sightline cap.
3. Face texture set and the swap rig.
4. Cast models and garage idle loops, when the garage (Stage E) exists.
5. Crowd figures, when street life has a stage.

Tooling: code-built kits (CockpitKit style) for the driver bust and crowd
figures; Blender for the cast if hand-painted faces are wanted, otherwise
code-built too. No third-party character packs shipped.

## Questions for Roy

1. Is Pike seen at all (cutscenes, a mirror), or is the player faceless like
   most PS2 racers? That decides whether the cast comes before the driver bust.
2. Story beats: full 3D characters in the garage, or stills with Dale's
   voice-over (cheaper, more PS2)? Recommended: stills first, 3D later.
3. Cast size for the first pass: Pike, Vance, Dale only?
4. Crowd and cops on foot: in scope for Stage F, or never?
5. Faces: painted with swaps (recommended) or no faces at all (helmet, cap
   shadow, sunglasses) for the street cast?

## Sources (2026-10-09 search, forum-level unless marked)

- PS1/PS2 indie spec conventions (textures to 256x256, models under about
  1,400 tris, vertex colour): https://itch.io/post/2026099 ,
  https://itch.io/post/15542442 , https://itch.io/post/1241197
- Polygon budgets on PS2 (Rumble Roses about 10k per character, a record;
  MGS2 Snake about 3.8k, fan estimate): https://en.wikipedia.org/wiki/Rumble_Roses ,
  https://itch.io/jam/32-bit-jam/topic/981913/texture-resolution-polygon-count
- First-person arm handling, IK on the wheel and stick (patent summary and
  the Halo 2 animation notes): https://patents.justia.com/patent/20250099852 ,
  https://learn.microsoft.com/en-us/halo-master-chief-collection/h2/art/animation/animationsfpanims
- CC0 character packs: KayKit (lists Godot) https://kaylousberg.itch.io/kaykit-adventurers ,
  Quaternius https://quaternius.itch.io/lowpoly-robot ,
  Kenney https://kenney.itch.io/kenney-character-assets
- Mixamo terms (forum summary, read Adobe's own FAQ before shipping):
  https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400
- Not found and stated from memory: how NFS Underground, Midnight Club 3 and
  Tokyo Xtreme Racer drew drivers (mostly hidden or dark behind glass) and told
  story (stills, in-engine scenes). Treat as unverified.
