# Tuner redesign proposal (2026-10-06)

Status: **approved by Roy 2026-10-06 15:48, revised same day. Nothing built yet.**
Roy's answers: proposal yes; tyre settings "do all 4" (camber, tyre pressure,
compound and toe all in, so the sim must model camber and pressure, see section 9);
peak torque and redline go to Advanced now and leave when the garage arrives.
Source read: `origin/main` at `bd7957c` (#126). Files: `scripts/ui/tuner_screen.gd`,
`tuner_tabs.gd`, `tuning_panel.gd`, `auto_tune_panel.gd`, `auto_tune_rules.gd`,
`exhaust_panel.gd`, `exhaust_tune.gd`, `tune_params.gd`, `tune_slots.gd`,
`car_spec.gd`, `vendor/gevp/gevp_vehicle.gd`.

## 1. What the Tuner exposes today

One scrolling screen (T opens, Y opens with Auto-Tune expanded, game paused),
plain Godot default controls, self-described in code as a "debug tool".

| Section | Controls | Problem for a player |
|---|---|---|
| Gearing & Power | 13 raw sliders: final drive, gears 1-5, peak torque Nm, redline rpm, turbo bar, low-end torque, peak position, plateau width, torque at redline | Engineer terms, no hints, no units for shape knobs; peak torque/redline are really upgrades, not tuning |
| Readout | Monospace gear table (km/h at cut, step, upshift rpm, % power), peak kW, top-speed estimate | Useful, but a spreadsheet |
| Buttons | Copy values (car_spec.gd snippet to clipboard), Reset | Copy values is a dev tool |
| Exhaust | Loudness, Raspiness, Pops and crackle, Flame (0-1), Reset to car preset | Fine, but heading shows key hints (U/J I/K O/L) |
| Auto-Tune | 4 goal sliders 0-3 (Acceleration, Top speed, Braking, Cornering grip), search budget (30/60/120 runs), Run/Cancel/Apply/Undo, 14 per-parameter Lock checkboxes, result as raw `label 0.123 -> 0.456` lines + before/after table (top speed, 0-100, 100-0 m, peak lateral g) | Weights and per-param locks are for a dev; result is numbers without meaning |
| Tune slots | Name field, Save, list, Load, Delete | OK, buried inside Auto-Tune |
| Header | "TUNER - T or Y or Esc to close, game paused", tabs "Tuner (T)", "Auto-Tune (Y)" | Breaks the no-on-screen-key-hints rule |

Tunable only through Auto-Tune (no slider at all): drag coefficient, downforce
front/rear, brake force, tyre stiffness, tyre friction, lateral grip assist,
longitudinal grip.

## 2. What the sim actually has (GEVP, so what we can honestly expose)

| Real tuning term | Sim field(s) | Tunable today? |
|---|---|---|
| Tyre compound | `coefficient_of_friction/Road`, `tire_stiffnesses/Road`, `longitudinal_grip_ratio/Road` | Auto-Tune only |
| Toe (front/rear) | `front_toe`, `rear_toe` (real steer-angle offset) | No |
| Steering lock | `max_steering_angle` | No |
| Ride height / travel | `front/rear_spring_length` | No |
| Springs | `front/rear_resting_ratio` (GEVP derives spring rate from weight, travel and this) | No |
| Dampers | `front/rear_damping_ratio`; bump/rebound multipliers | No |
| Anti-roll bars | `front/rear_arb_ratio` | No |
| Gearing | `final_drive`, `gear_ratios/0-4` | Yes |
| Boost | `turbo_boost_max` | Yes |
| Power band | `torque_shape/*` (4 knobs) | Yes |
| Differential lock | `front/rear_locking_differential_engage_torque` (lower = locks sooner) | No |
| Brake pressure | `brake_force_multiplier` | Auto-Tune only |
| Brake bias | `front_brake_bias` (-1 = auto) | No |
| Downforce | `aero_downforce_coefficient_front/rear` | Auto-Tune only |
| Drag | `coefficient_of_drag` | Auto-Tune only |
| Assists: traction control, ABS, stability | `traction_control_max_slip`, `*_abs_spin_difference_threshold`, `enable_stability` / `stability_yaw_strength` | No |

**Not simulated today:** camber (GEVP: "camber isn't simulated") and tyre
pressure. Roy wants both, so they get modelled: see section 9.

Technical note: GEVP computes spring rates, damping and ARB stiffness once in
`initialize()`, so suspension knobs need a new `SUSPENSION` re-derive kind in
`CarSpec.set_param()` (like the existing TIRE/BRAKE/ENGINE ones) plus a test that
it matches a freshly built car.

## 3. Proposed design

### Principles
- **Words players know**, each with a one-line hint that says what it does and
  what it costs ("Stiffer: sharper turn-in, but skips over bumps").
- **Notches, not floats.** Each setting is an 11-notch bar with plain end words
  (Soft ... Stiff, Short ... Long). Real units shown only where players know them
  (bar, %, degrees, ratio).
- **See the effect before you drive.** A fixed stat panel with before/after bars.
- **Presets first, details second, raw numbers last (Advanced).**
- Exhaust stays cosmetic and is labelled so.

### Pages (left list, ~20 settings total in the simple view)

1. **Setup** (landing page): preset picker *Stock / Street / Grip / Drift*, your
   saved setups (the existing tune slots, renamed), Save setup, Reset to stock.
2. **Tyres**: Compound (Street / Sport / Semi-slick, moves friction + stiffness +
   traction together), Pressure F/R (bar), Camber F/R (degrees), Toe F/R.
3. **Suspension**: Ride height, Springs F/R, Dampers F/R, Anti-roll bars F/R.
4. **Gearbox**: Gearing (one Short ... Long knob = final drive), shown with
   "top speed in 5th ~ 245 km/h" and "1st gear to ~ 80 km/h".
5. **Engine**: Boost (bar), Power band (Low-end / Balanced / Top-end, maps the
   4 shape knobs).
6. **Differential**: Diff lock (Open ... Locked), Lock on throttle only if the
   sim splits it later (not today: one value per axle).
7. **Brakes**: Brake pressure, Brake bias (front %).
8. **Aero**: Front downforce, Rear wing. Drag follows downforce automatically in
   the simple view (more wing, more drag), raw drag in Advanced.
9. **Assists**: Traction control (Off / Low / High), ABS (On/Off), Stability
   (Off / Low / High), Steering lock.
10. **Auto-Tune** (renamed in the UI to **Mechanic**, see below).
11. **Sound** (cosmetic): Loudness, Rasp, Pops and crackle, Flames, "Car default".

### Stat panel (always on the right)
Bars: **Top speed, Acceleration, Braking, Grip, Balance** (centre-zero bar:
Understeer ... Oversteer). Ghost bar = before you opened the tuner (or the
preset you started from), solid bar = now, small arrow and number for the change.

- Top speed and gearing figures: computed instantly (the existing readout math).
- Acceleration, Braking, Grip, Balance: instant **estimates**, shown with "~".
- **Test run** action on the stat panel: runs the existing hidden test track
  (AutoTuneJob, headless) once on the current setup and replaces "~" with
  measured 0-100 s, 100-0 m, lateral g. Same numbers Auto-Tune already uses.

### Presets
Defined as offsets from each car's Stock spec (so they work on all 6 player cars),
per page:

| Preset | Intent | Main moves |
|---|---|---|
| Stock | Factory | the car's CarSpec |
| Street | Forgiving, comfy | softer springs/dampers, open-ish diff, assists high, slight understeer |
| Grip | Fast laps | sport/semi-slick, stiffer, more downforce, medium diff lock, rear toe-in, assists low |
| Drift | Easy slides | locked rear diff, stiffer rear bar, front toe-out, more steering lock, rear brake bias, TC and stability off |

Picking a preset then changing anything shows "Grip (modified)".

### Mechanic (Auto-Tune, simplified)
- Pick **one** goal from four: Launch, Top speed, Braking, Cornering. (Weights
  0-3 move to Advanced.)
- "Keep" checkboxes per **page** (Keep gearbox, Keep aero, Keep brakes, Keep
  tyres), not per raw parameter.
- Search length fixed at Normal (Quick/Thorough in Advanced).
- Result in plain words, one line per change, with its measured effect:
  - "Shorter gearing (4.10 to 4.45): 0-100 0.4 s quicker, top speed 6 km/h lower."
  - "More rear wing: grip +0.05 g, top speed 3 km/h lower."
  - Then **Apply** / **Discard**. Undo stays.
- Explanation is template text per page plus the measured before/after the job
  already returns; no new physics.

### Advanced (one toggle at the bottom of each page, off by default)
Per-gear ratios + the gear table readout, the 4 torque-shape knobs, peak torque
and redline (to become garage upgrades in Stage E, so dev-only until then), raw
drag, raw tyre friction / stiffness / lateral grip assist / longitudinal grip,
bump and rebound multipliers, Mechanic goal weights, search length and
per-parameter locks, Copy values.

### Keyboard (no hints on screen; goes on the Controls page)
Up/Down move between settings, Left/Right move one notch, Q/E switch page,
Enter picks a preset or button, Esc backs out / closes. T opens on Setup, Y opens
on Mechanic (as today).

### Look
Gritty PS2 night: panel navy #0E1424 (today it is a purple-black), labels silver,
values amber #FFC066, focused row and "after" bars sodium orange #FF8A1F, ghost
"before" bars dim silver. Blocky segmented bars, no glow. Sound page carries a
small "Sound and looks only" tag.

## 4. Wireframe

```
+------------------------------------------------------------------------------+
| TUNER   P1 Coupe                                    Setup: Grip (modified)   |
+--------------+--------------------------------------+------------------------+
|  Setup       |  SUSPENSION                          |  Top speed    ~245 km/h|
|  Tyres       |                                      |  [######### ]      -3  |
|> Suspension  |  Ride height   Low  [####|------] High|  Acceleration          |
|  Gearbox     |> Springs F     Soft [######|----] Stiff|  [#######   ]   +0.1s |
|  Engine      |  Springs R     Soft [#####|-----] Stiff|  Braking   38 m        |
|  Differential|  Dampers F     Soft [######|----] Firm|  [########  ]          |
|  Brakes      |  Dampers R     Soft [#####|-----] Firm|  Grip     ~1.42 g      |
|  Aero        |  Anti-roll F   Soft [#######|---] Stiff|  [######### ]   +0.04 |
|  Assists     |  Anti-roll R   Soft [####|------] Stiff|  Balance               |
|  Mechanic    |                                      |  Under [---|##-] Over  |
|  Sound       |  [ ] Advanced                        |                        |
|              |                                      |  [ Test run ]          |
+--------------+--------------------------------------+------------------------+
| Stiffer front springs: sharper turn-in and less body roll, but the front      |
| washes wide sooner over bumps. Changes balance towards understeer.            |
+------------------------------------------------------------------------------+
```

## 5. Steelman
The current screen is an honest dev tool and a great engine underneath (one write
path, slots, a real measuring track). Players already know this vocabulary from
GT, Forza and NFS Underground; grouping ~40 raw values into ~20 named settings
with presets and live stat bars lets anyone change how the car feels in ten
seconds, while Advanced keeps every number for Roy and for tuning the fleet.

## 6. Premortem (why it fails)
1. **Knobs that do nothing you can feel.** New settings (toe, dampers, diff) may
   barely change the sim. Mitigation: sweep each on the test track and drop any
   whose full range moves no stat more than ~3%.
2. **Stat bars lie.** Instant estimates disagree with how the car drives.
   Mitigation: "~" until measured, Test run on demand, and a test that keeps the
   estimates within a set margin of the track numbers.
3. **Extremes break the physics.** Locked diff + toe-out + no stability can spin
   or flip the car. Mitigation: ranges clamped to sweep-proven bounds in
   TuneParams, same as today's gear constraints.
4. **Presets tuned on the coupe feel wrong on the kei or muscle car.** Mitigation:
   presets are offsets, plus one drive check per car before each car ships.
5. **Clash with the garage (Stage E).** Peak torque and redline on a free tuner
   undercut upgrades. Mitigation: Advanced/dev only now, removed from the player
   tuner when the garage lands.

## 7. Effort

| Part | Size |
|---|---|
| Tyre model: camber and pressure in the shared wheel sim, calibration sweep, tests (section 9) | M |
| New TuneParams entries + SUSPENSION re-derive + slot compatibility + tests (toe, springs, dampers, ARB, diff, brake bias, steering lock, assists) | M |
| New screen: pages, notch control, hint bar, stat panel with estimates, presets, keyboard nav, look | M |
| Mechanic: one goal, page-level keep, plain-language result | S |
| Test run button on the stat panel (reuses AutoTuneJob) | S |
| Preset values + drive check per car | S per car |
| **Total** | **L, now 4 PRs** (was 3): (1) tyre model, (2) other new params, (3) screen + presets, (4) Mechanic + Test run |

Existing panels (TuningPanel, AutoTunePanel, ExhaustPanel) keep their logic and
tests; the new screen sits on top and they become the Advanced views.

## 8. Decisions (answered 2026-10-06)
- **D1 Tyre pressure / camber:** Roy: all four in (camber, pressure, compound,
  toe). Camber and pressure are modelled, section 9.
- **D2 Engine power:** Roy: yes, peak torque and redline go to Advanced now and
  are removed when the garage lands.
- **D3 Name** ("Mechanic" vs "Auto-Tune") and **D4 presets** (add Drag?): still
  open, not blocking; default is "Mechanic" and the 4 presets.

## 9. Modelling camber and tyre pressure (added after Roy's "do all 4")

Where: `scripts/vendor/gevp/gevp_wheel.gd` `process_tires()`. GEVP is open for
editing and has been edited before (tyre load sensitivity, item 10 in that file).
Today each wheel computes one `friction` value (cof x load) and one
`cornering_stiffness` (tyre stiffness x contact patch^2) and uses them for both
directions; `longitudinal_grip_ratio` scales the forward/back part.

### Tyre pressure (per axle, bar; e.g. 1.6 - 2.8, ideal ~2.2 for the coupe)
Real effect: low pressure = longer contact patch, more grip up to a point, slow and
vague response; high pressure = sharp response, less grip, less rolling drag.
Model, computed once when the value changes (no per-tick cost):
- **Response:** `cornering_stiffness` scales up with pressure (~ +/-15% across the range).
- **Peak grip:** a multiplier on `friction` that is 1.0 in an "ideal window"
  around the car's stock pressure and falls off either side (~1.5% per 0.1 bar
  outside it).
- **Rolling drag:** `current_rolling_resistance` scales down slightly with pressure
  (a few km/h of top speed at most).

### Camber (per axle, degrees; e.g. -4.0 to +1.0)
Real effect: some negative camber keeps the outside tyre flat when the body rolls
in a corner (more cornering grip); too much, and the tyre stands on its edge in a
straight line (worse launch and braking).
Model:
- **Effective camber** per wheel each tick = static camber + body roll x a camber
  gain, with the sign by side (the outside wheel gains positive camber as the car
  rolls). Body roll is read once per car per tick from the chassis basis.
- **Cornering grip:** lateral force multiplier that peaks at a small negative
  effective camber (about -1 deg) and falls off around it.
- **Launch and braking grip:** longitudinal multiplier that falls with static
  |camber| (~1% per degree).
- **Visual:** wheel meshes tilt by the static camber (stance), cosmetic only.
- New spec fields (e.g. `front_static_camber_deg`) kept separate from GEVP's own
  `front_camber`, which only angles the raycast "for stability" and stays as is.

### Risk to the shared raycast-wheel sim (player, traffic, cops, NPCs all use it)
| Risk | Mitigation |
|---|---|
| Every car changes feel, Stage A sign-off undone | Factors are normalised so each car's stock values give exactly 1.0; traffic and cops keep stock. Existing tests (chassis targets, tyres, Auto-Tune baselines) must pass unchanged on stock specs |
| Effect too small to feel, or too big | Calibration sweep on the hidden test track: full range of each setting should move lateral g / 0-100 / 100-0 by roughly 3-8%, no more |
| Instability at extremes (snap oversteer, jitter from roll feedback) | Clamped ranges; roll value smoothed; sweep includes worst-case combos (max negative camber + low pressure + locked diff) |
| Physics cost at 120 Hz with many cars | Pressure is precomputed; camber adds a few multiplies per wheel and one roll read per car. Measure fps with full traffic before/after |
| Auto-Tune search gets slower | Camber and pressure stay out of Auto-Tune until after the sweep, then join with locks |
| No tyre temperature or wear, so camber has no long-term cost | Accepted for now; wear can arrive with the damage/fuel stage |

### Updated PR split
1. **Tyre model** (M): camber + pressure in the wheel sim, spec fields, stock
   = 1.0 normalisation, calibration sweep, tests, wheel tilt.
2. **Other new settings** (M): toe, springs, dampers, anti-roll bars, ride
   height, diff lock, brake bias, steering lock, assists, SUSPENSION re-derive.
3. **New Tuner screen + presets** (M).
4. **Mechanic + Test run** (S).

Total stays **L**, now 4 PRs instead of 3; the extra PR is an M of physics work.
All of it needs the laptop session (Godot runs, PRs).
