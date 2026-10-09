# Cabin space audit, 2026-10-09

Roy: "can you make sure that we actually have space in the interior?", then
"we definitely need arms for our user in the car as well, and different body
types, different heights". This audit measures every player car's cabin on
live `main` (0c9bc1b), on PR #326 (per-car cabins, a1237ad) and the muscle car
on PR #329 (rebuilt hardtop body, c8b50de) against a seated manikin of
1.55, 1.78 and 1.95 m.

Everything here comes from real headless Godot 4.7.2 runs of
`tools/fleet_design/interior_space.gd` on Roy's laptop (numbers in
`tables.md`, raw JSON in `user://interior_space/`) and the real renderer for
the pictures (`tools/fleet_design/interior_space_shots.gd`). No car art was
changed.

## Verdict in one line

No cabin fits a 1.78 m driver as built: the head is in the roof liner, the
legs are fully straight to reach the pedals, and the wheel is 15 cm beyond a
straight arm. The cabins are sized for the built driver, who measures as a
1.46 m person. PR #326 fixes the parts-outside-the-body problem but not the
space.

## The manikin (assumption, stated)

The people note (`notes/people-and-player-character-2026-10-09.md`) lives in
the project's shared files and is not on this laptop, so the body is the
standard seated anthropometry (Dreyfuss / SAE J833), scaled with stature S:
hip pivot 0.05 S over the cushion, shoulder 0.33 S, eye 0.44 S, top of head
0.505 S, shoulder breadth 0.265 S, thigh 0.265 S, shin 0.25 S, comfortable
reach 0.31 S, straight arm 0.36 S. A 1.78 m "7 heads" person therefore sits
0.90 m tall over the cushion with the eye at 0.78 m. The torso leans back
12 deg like the seat. The hip sits 8 cm ahead of the cushion centre.

## What was measured, how

- **Headroom**: ray up from the hip to the roof liner (cabin mesh) and to the
  roof skin (body mesh); head-top minus that.
- **Shoulders**: rays left and right from the shoulder point to the first
  cabin or body face; clearance = distance to the door minus half the
  shoulder breadth.
- **Legs**: hip to the throttle pedal (ankle 12 cm under and 5 cm behind the
  pedal pivot) against thigh + shin; two-bone IK gives the knee, rays from
  the knee up and forward give the knee room; "slide for legs" is how far the
  seat would have to move forward for the leg to sit at 85 % of its length.
- **Arms**: shoulder to the wheel's 9 and 3 grips (the real SteeringWheel
  rim) and to the gear knob, against the comfortable and the straight reach.
- **Sightline**: rays from that body's eye in the vertical centre plane,
  pitch -40..+40 in half degrees, against the cabin and the opaque body; the
  clear band around straight ahead and its share of a 62 deg screen.
- **Rear**: cabin length behind the front seatback at hip height and the
  roof over the rear floor 0.55 m further back; **strut bar**: gap behind the
  seatback top.
- **Built driver**: the DriverModel's head mesh top over the cushion.

## Results

The seat does not slide in any car, and the pedals sit 0.86 m ahead of the
cushion centre in every car (the same number on both branches: it is the
cabin formula, not the body). Legs, arms and the built driver are therefore
the same story in all seven cars; headroom and width differ per car.

### Every car, both branches

| | 1.55 m | 1.78 m | 1.95 m |
|---|---|---|---|
| Legs to the throttle | 0.11-0.13 m too short, cannot reach | leg 99-100 % straight, no bend | 91-93 %, OK |
| Seat slide needed for the legs | +0.23 fwd | +0.13 fwd | +0.08 fwd |
| Right hand to the wheel grip | 0.75 (max 0.56): 0.19 short | 0.79 (max 0.64): 0.15 short | 0.82 (max 0.70): 0.12 short |
| Right hand to the gear knob | 0.83 (max 0.56) | 0.86 (max 0.64) | 0.89 (max 0.70) |

The wheel hub is 0.62 m ahead of the hip in every car; a real car puts it
0.40-0.55 m ahead. The lever is 0.46 m ahead of the hip; real 0.25-0.35.
Arms are coming (Roy, 2026-10-09), and as the cabins stand they cannot be
drawn reaching the wheel from a shoulder.

The built DriverModel: head top 0.74 m over the cushion = a **1.46 m**
person; its pelvis floats 10 cm ahead of where a hip sits against the
backrest, which is why its legs reach (0.80 of 0.92).

### Headroom and width, per car (PR #326, the per-car cabins)

Liner and skin are over the cushion top. "Head" is the 1.78 m head top to
the liner; negative means through it.

| car | liner / skin | head 1.55 | head 1.78 | head 1.95 | shoulders 1.78 to door | hips | behind seatback / rear roof | verdict |
|---|---|---|---|---|---|---|---|---|
| p0 beater | 0.90 / 0.98 | +0.13 | +0.02 | -0.07 | +0.05 (1.55: -0.13, the door card is at the elbow) | -0.05: the seat is narrower than a hip | 1.61 / 0.73 | headroom OK to 1.72 m; cabin only 1.09 m wide at the shoulders (a Beetle has 1.25); rear seat space exists but the body's rear roof is 0.73 over the floor |
| p1 coupe | 0.80 / 0.84 | +0.03 | -0.08 | -0.17 | +0.13 | +0.04 | 0.18 / 0.73 | head in the liner above 1.55 m; no rear seat, no 2+2 |
| p2 hot hatch | 0.84 / 0.88 | +0.08 | -0.04 | -0.12 | -0.05 (door at the shoulder) | +0.02 | 0.82 / 1.11 | head in the liner above 1.60 m; rear seat fits (0.82 behind the seatback, 1.11 roof over the rear floor) |
| p3 tuner | 0.92 / 0.96 | +0.16 | +0.04 | -0.04 | -0.03 | +0.03 | 0.18 / 0.73 | headroom OK to 1.76 m; shoulders touch the door; **a sedan with no room for a rear seat** (bulkhead 0.18 behind the seatback) |
| p4 kei (open) | header 0.80 | head over the header: 1.55 just under, 1.78 +0.10 above | | | no skin above the belt; door card at -0.06 (hips) | -0.06 to -0.10: the seat is narrower than a hip | 0.12 / none | shoulders 0.94 m wide, hips do not fit between the bolsters; header bar crosses the 1.55 and 1.78 m eye line |
| p5 muscle | 0.82 / 0.86 | +0.05 | -0.06 | -0.15 | +0.02 | +0.04 | 0.18 / 0.71 | head in the liner above 1.56 m; bench with no rear seat room |
| p6 crossover | 0.90 / 0.93 | +0.14 | +0.02 | -0.06 | -0.03 | +0.04 | 0.94 / 1.21 | headroom OK to 1.72 m; shoulders touch the door; rear seat fits |

Main (the coupe's cabin moved into each body): liner 0.82-0.83 over the
cushion on all seven, so every car fails the 1.78 m head by 0.06 m; the beater
and the kei have the coupe's 1.5 m-wide cabin inside a 1.22 / 1.10 m body, so
the shoulders are in the door skin (beater -0.05) or outside the car (kei:
the head is 0.66-0.85 m outside the shell); the muscle's dash blocks the
road straight ahead from the game eye (clear band starts at +5 deg). PR #329's
hardtop body fixes that last one (clear from -2.5 deg; roof skin 0.90 over the
cushion, 1.78 m head +0.02 to the skin, -0.06 to the coupe liner it still
carries).

### Sightline per stature (PR #326, clear band straight ahead, share of a 62 deg screen)

| car | game eye | 1.55 m | 1.78 m | 1.95 m |
|---|---|---|---|---|
| p0 beater | -5..+37 (58 %) | -8..+8 (25 %) | header at -2.5, blocked (15 %) | -2.5..+3.5 (10 %) |
| p1 coupe | -7..+32 (61 %) | -6.5..+13.5 (32 %) | -8.5..+1 (15 %) | eye in the roof (0 %) |
| p2 hot hatch | -6..+37 (60 %) | -8..+13 (34 %) | -10.5..+3 (22 %) | 1 % |
| p3 tuner | -4..+40 (56 %) | -6.5..+26 (52 %) | -9..+15 (39 %) | -10.5..+6.5 (27 %) |
| p4 kei | -7..+15.5 (36 %) | -9.5..+1.5 (18 %) | -3.5..0 (6 %) | over the screen: -11.5..+40 (69 %) |
| p5 muscle | +4.5..+34.5 blocked | -4.5..+15 (31 %) | -6.5..+3 (15 %) | 1 % |
| p6 crossover | -6..+39 (60 %) | -7.5..+23.5 (50 %) | -10..+12.5 (36 %) | -11.5..+4 (25 %) |

The game eye sits 0.61 m over the cushion (a 1.40 m person's eye). The
spec's clear band (-14 to +24, 55 %) holds only for that eye. Note the
cluster hood: straight ahead over the wheel the first thing from the game
eye is the binnacle hood at -5 to -8 deg on every car; the existing
`cockpit_interior` test skips the binnacle column on purpose, so this is by
design, but it is a 6-9 deg bite out of the road band at the driver's centre.

PR #326's muscle cabin on the old body still has the dash outside the
windshield from the game eye (straight ahead blocked from +4.5 deg); #329's
body is what fixes it, and #326's p5 CABIN was measured on the old body.

### Parts planned for the cabin

- **Gauge pod** on the pillar or dash top: room on every car; it must stay
  under the dash line of whichever eye height is chosen.
- **Trinket** on the mirror: the mirror sits 0.12-0.16 m under the header on
  every car; fine.
- **Strut bar behind the seats**: gap behind the seatback top is 0.84-1.7 m
  on every closed car (it is the parcel shelf / rear bulkhead distance);
  fine everywhere except the kei (open, nothing behind) and it would sit in
  the rear passengers' space on the hatch and crossover.
- **Bucket seats**: the coupe's seat is 0.50 m wide with bolsters 0.32 m
  apart; a 1.78 m hip is 0.37 m wide, so the bolsters already pinch and the
  beater (seat 0.39 m wide between door and console) and the kei (0.34 m)
  cannot take a bucket at all.
- **Rear seat for Moose**: fits in the hot hatch (0.82 m behind the
  seatback, 1.11 m roof) and the crossover (0.94 / 1.21) only. The tuner
  sedan and the muscle have a bulkhead 0.18 m behind the front seatback: no
  rear seat is possible without moving `rear_z` back (the tuner's rear glass
  starts at z 0.74, so its body is also short in the greenhouse). The beater
  has 1.61 m of floor behind the seat but the rear roof is 0.73 m over it,
  so only a child or a dog fits there.

### Does anything poke out of the shell?

PR #326's own `tests/fleet/interior_fit.gd` passed for me on 5 of 7 cars;
on the hot hatch and the crossover one gear-lever vertex reads 0.43 / 0.67 m
outside (a single vertex at the lever's top, which is a ray through a seam in
the body mesh, not a lever outside the car; the PR author should look). Main
fails that test on every car but the coupe (the PR's own before/after table
matches what I saw). With the manikin, a 1.78 m head is 0.04-0.12 m through
the roof skin on the coupe, hatch and muscle, and 0.02-0.08 on the others at
1.95 m.

## What to change (recommendation, no art touched)

1. **Pick the driver scale first.** Either the player is 1.46 m tall (the
   built driver, the game eye, every cabin number) or the cabins grow. Given
   Roy's call for 1.55-1.95 m bodies with arms, the cabins must grow: the
   cabin formula in `cabin_measure.gd` puts the eye at `seat_h + 0.62` and
   everything else off that; make it `seat_h + 0.44 S` for the car's design
   driver and re-measure.
2. **Headroom**: lower the cabin floor and seat, not the roof. The body floor
   skins sit 0.24-0.34 m over the road; a real floor pan is 0.15-0.20 m up.
   Dropping `floor_y` and `seat_h` by 0.08-0.10 m (the undercarriage plate
   with them) gives every closed car except the coupe 1.78 m headroom; the
   coupe (roof skin 1.36 m over the road) needs its roof 5-8 cm higher as
   well, or a 1.70 m cap on its driver, which is a body change.
3. **Seat slide + telescoping wheel**: 0.25 m of seat travel (pedals fixed)
   covers 1.55-1.95 m legs; move the wheel hub back from 0.62 to 0.45-0.50 m
   ahead of the hip (it then rises in the view: re-run the -15 deg rim rule
   with the new eye) and the lever back to 0.30 m ahead of the hip.
4. **Width**: the beater (1.22 m at the belt) and the kei (1.10 m) bodies are
   too narrow for an adult's shoulders by 0.15-0.25 m; that is a body-sheet
   change (a Beetle tub is 1.4 m at the belt, a kei roadster 1.3). Everything
   else is 1.6-1.74 m: fine.
5. **Rear seats**: tuner and muscle need `rear_z` moved back 0.6-0.7 m (the
   tuner body's rear glass is at 0.74, so its greenhouse is short: a sheet
   change); the beater needs its rear roof raised or Moose stays in the hatch
   and the crossover.
6. **Tests**: `interior_fit.gd` checks parts against the shell; add the
   manikin numbers (headroom at the design stature, leg reach, wheel reach,
   shoulder clearance) to it once the driver scale is decided. The tool is
   in `tools/fleet_design/interior_space.gd`; it is not in `run_tests.bat`
   because every car fails it today.

## Pictures

`main_<car>.jpg`, `pr326_<car>.jpg`, `pr329_p5_muscle.jpg`: top row the
cockpit view from the game eye and from a 1.55, 1.78 and 1.95 m eye on the
cushion; bottom row the side cutaway (door and glass clipped away) with the
built driver and the three manikins (silver 1.55, amber 1.78, sodium 1.95).
