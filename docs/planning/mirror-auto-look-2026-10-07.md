# Cockpit mirrors without extra keys: automatic head look (proposal, 2026-10-07)

Status: **proposal, docs only. Replaces the hold-to-glance keys in PR #174.**
Geometry facts (right mirror 58° off-axis, off screen at every allowed FOV) are from
`mirror-usability-head-rotation-2026-10-07.md` on PR #174 and are not repeated here.

Roy (2026-10-07): "we need a different solution than manually pressing keys. Player
should be able to one-hand the game, max two (remember you have keyboard and
controller configurations)."

## 1. The rule

**The driver's head looks for you.** No look keys. The game already knows what the
player would want to see: where the car is turning, where it is about to move, and
what is beside it. The head turns on its own, the way a real driver's does.

One-hand budget, keyboard: steer, throttle, brake, shift up/down. Everything else
(radio, camera, pause) is occasional. Mirrors add **zero** keys.
Controller: the same, with the right stick as an optional free look (section 4).

## 2. Three automatic looks

| Look | Trigger | Head yaw | Timing |
|---|---|---|---|
| **Into the turn** | Steering angle and yaw rate | Up to 12° toward the inside of the turn | Smoothed, follows the corner |
| **Mirror check before a lane change** | Steering held one way at speed (> 40 km/h) past a small threshold for 0.15 s, while the car is still in its lane | To that side's mirror: 40° left, 58° right | 0.35 s turn, 0.4 s hold, 0.35 s back; 2 s cooldown per side |
| **Something beside you** | A traffic car or cop enters the side blind-spot zone (behind the B-pillar, within 1 lane) | Glance to that side's mirror | Same glance; once per car, never while braking hard or above 0.8 g lateral |

- Priority: blind-spot glance > lane-change check > into-the-turn. Only one glance at a time.
- The glance is **head only**: the eye position moves with a small neck offset, the
  road stays in the lower part of the view, so the player never loses the road.
- The rearview mirror is already on screen at 36.7°; it needs no look.

## 3. Why this and not the alternatives

| Option | Verdict | Why |
|---|---|---|
| Hold-to-glance keys (PR #174) | Rejected by Roy | Needs a third hand on keyboard |
| Auto look (this doc) | **Recommended** | Zero inputs; it is what real drivers do; tells the player something is beside them |
| Picture-in-picture mirror inset on screen | Fallback | Works, but it is a HUD element in a view meant to feel physical; could be an accessibility toggle later |
| Widen the FOV to fit the right mirror | Rejected | Needs ~80°+, outside the signed-off 55-78 range, and fisheyes the road |
| Move the mirror into view | Rejected | Fake geometry; breaks the interior |

## 4. Controller and settings

- **Right stick: free look**, up to 70° each way, springs back to centre when released.
  Overrides the automatic looks while held. Optional; the game never needs it.
- Keyboard gets no look keys.
- Settings: "Head look" **Auto (default) / Subtle (into-the-turn only) / Off**.
- Chase cam is unchanged; this is cockpit view only.

## 5. Steelman and premortem

- **Strongest case:** zero inputs, and the glance itself becomes information: if the
  head turns right and you did not steer, something is beside you.
- **How it fails:** the head moves when the player did not want it to, and it feels
  like losing control of the camera, or it causes motion sickness.
  Prevented by: short, eased glances (0.35 s), the road always stays in view, a cooldown,
  no glances in hard braking or high lateral g, and the Subtle/Off setting.
- **Second failure:** false lane-change triggers on a long curve. Prevented by
  measuring steering **relative to the road's curve**, not raw steering. Today's road
  is straight, so this only matters once curves land (proposal PR #165).

## 6. Build (after sign-off): three small PRs, each checked in real Godot runs

1. Head-look rig in `chase_camera.gd`: one yaw value fed by the three triggers,
   eased and capped. Test: scripted steering produces the expected yaw curve.
2. Blind-spot zone from `traffic_manager.gd` positions. Test: a traffic car placed
   beside the player triggers exactly one glance.
3. Right-stick free look plus the Head look setting. Also skip rendering a door mirror
   while it is off screen (the waste PR #174 found). Test: render count drops with the
   head centred.

## 7. Decisions for Roy

1. Automatic head look instead of look keys: **Yes (recommended)** / picture-in-picture inset
2. Blind-spot glance when a car is beside you: **Yes (recommended)** / only lane-change and turn looks
3. Right-stick free look on controller: **Yes (recommended)** / none
