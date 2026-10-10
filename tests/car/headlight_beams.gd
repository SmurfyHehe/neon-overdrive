extends SceneTree

# Low beam, high beam, flash, auto-dip and what cops see (lights decision
# list, 2026-10-10), through the real renderer (no --headless: the dummy
# renderer draws no light, so the cut-off could not be seen).
#
#   - defaults: lights on at the low beam (100 m, 1 deg down, cut-off
#     projector), auto-dip armed, J is an action with a key on the Controls
#     page;
#   - J toggles the high beam (150 m, level, no projector); J J flashes and
#     leaves J where it was; flash works with the lights off; J with the
#     lights off turns them on, high;
#   - auto-dip: a car coming at you inside 150 m, or one you follow inside
#     80 m, holds the high beam at low (J stays on), the real traffic list
#     decides; without a car it is high again;
#   - cops: dark 18 m, low beam 140 m, high beam or flash 200 m; a dark
#     driver seen by a cop gains a little heat standing still, a lit one none;
#   - on a wall 30 m ahead the low beam lights the wall below the lamp height
#     and not above it (the cut-off), the high beam lights above it too.
# Writes the frames to user://headlights/ for judging by eye.
#
# Run: <godot> --path . -s res://tests/car/headlight_beams.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

var fails: Array[String] = []
var game: Node
var player: PlayerCar
var cam: Camera3D
var wall: MeshInstance3D

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)

func _initialize() -> void:
	game = Harness.boot(self, 1, 300.0, 11)   # one managed car: the dip scan reads the manager's list
	_run.call_deferred()

func _spot() -> SpotLight3D:
	return player.get_node("Headlights") as SpotLight3D

func _run() -> void:
	for i in 30:
		await process_frame
	player = game.get("player")
	var b := player.beams
	var spot := _spot()

	# --- defaults -----------------------------------------------------------
	_check(b.mode == HeadlightBeams.Mode.LOW, "default beam %d, wanted low" % b.mode)
	_check(b.auto_dip, "auto-dip not on by default")
	_check(is_equal_approx(spot.spot_range, 100.0), "low beam range %.0f" % spot.spot_range)
	_check(is_equal_approx(spot.rotation_degrees.x, -1.0), "low beam aim %.2f deg" % spot.rotation_degrees.x)
	_check(spot.light_projector != null, "low beam has no cut-off projector")
	# The projector needs shadows on; nothing may be a caster (CPU).
	_check(spot.shadow_enabled and spot.shadow_caster_mask == HeadlightBeams.NO_CASTERS, "low beam shadow pass has casters")
	_check(InputMap.has_action("high_beam") and not InputMap.action_get_events("high_beam").is_empty(), "no key for the high beam")
	_check(PauseMenu.GROUPS[0][1].any(func(a: Array) -> bool: return a[0] == "high_beam"), "high beam missing from the Controls page")

	# --- J, J J, H ----------------------------------------------------------
	player.toggle_high_beam()
	_check(b.mode == HeadlightBeams.Mode.HIGH and is_equal_approx(spot.spot_range, 150.0), "J: not high (%d, %.0f m)" % [b.mode, spot.spot_range])
	_check(spot.light_projector == null and is_equal_approx(spot.rotation_degrees.x, 0.0), "high beam keeps the cut-off or the dip")
	_check(not spot.shadow_enabled, "high beam has shadows on")
	player.toggle_high_beam()   # inside the double window: this is a flash
	_check(b.flashes == 1, "second J did not flash")
	_check(not b.high_on, "J J left the high beam on (was off before)")
	_check(b.mode == HeadlightBeams.Mode.HIGH, "flash is not high")
	b.step(HeadlightBeams.FLASH_SECONDS + 0.05)
	_check(b.mode == HeadlightBeams.Mode.LOW, "flash did not end (mode %d)" % b.mode)
	b.step(1.0)
	player.toggle_high_beam()   # a slow second press is a toggle again
	_check(b.high_on and b.mode == HeadlightBeams.Mode.HIGH, "J after a pause did not toggle high on")
	b.step(1.0)
	player.toggle_high_beam()
	_check(not b.high_on and b.mode == HeadlightBeams.Mode.LOW, "J did not toggle high off")
	b.step(1.0)
	player.set_headlights(false)
	_check(b.mode == HeadlightBeams.Mode.OFF and not spot.visible and not player.headlights_on, "H off: lamp still lit")
	b.flash()
	_check(b.mode == HeadlightBeams.Mode.HIGH and spot.visible, "flash with the lights off did not light")
	b.step(1.0)
	_check(b.mode == HeadlightBeams.Mode.OFF and not spot.visible, "flash left the lamp on")
	player.toggle_high_beam()   # J with the lights off
	_check(player.headlights_on and b.high_on and b.mode == HeadlightBeams.Mode.HIGH, "J with lights off: lights %s high %s mode %d" % [player.headlights_on, b.high_on, b.mode])
	b.step(1.0)
	player.toggle_high_beam()
	b.step(1.0)

	# --- cops see by beam ---------------------------------------------------
	player.set_headlights(false)
	_check(is_equal_approx(PoliceHeat.see_reach_for(player), PoliceHeat.SEE_RANGE_DARK), "dark reach %.0f" % PoliceHeat.see_reach_for(player))
	player.set_headlights(true)
	_check(is_equal_approx(PoliceHeat.see_reach_for(player), PoliceHeat.SEE_RANGE_LIT), "low beam reach %.0f" % PoliceHeat.see_reach_for(player))
	player.toggle_high_beam()
	_check(is_equal_approx(PoliceHeat.see_reach_for(player), PoliceHeat.SEE_RANGE_HIGH), "high beam reach %.0f" % PoliceHeat.see_reach_for(player))
	b.step(1.0)
	player.toggle_high_beam()
	b.step(1.0)
	_check(PoliceHeat.SEE_RANGE_HIGH >= 190.0 and PoliceHeat.SEE_RANGE_LIT >= 100.0, "see ranges off the decision list")
	var heat: PoliceHeat = game.get("police_heat")
	_dark_heat(heat)

	# --- auto-dip against the real traffic list -----------------------------
	await _auto_dip(b)

	# --- the cut-off on a wall ----------------------------------------------
	await _wall_shots(b)

	for f in fails:
		printerr("FAIL: " + f)
	print("headlight_beams: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)

## A cop at 8 m facing the car, car standing still: lights off adds heat, a
## low beam adds none.
func _dark_heat(heat: PoliceHeat) -> void:
	if heat == null:
		_check(false, "no police_heat in the game")
		return
	var cop := Node3D.new()
	game.add_child(cop)
	cop.global_position = player.global_position + Vector3(0.0, 0.0, 8.0)   # behind the car; the car faces -Z
	cop.look_at(player.global_position, Vector3.UP)
	heat.player = player
	heat.reset()
	heat.register_cop(cop)
	player.set_headlights(false)
	heat._look()
	_check(heat.seen, "cop 8 m away did not see the dark car")
	for i in 20:
		heat._update_heat(0.1)
	_check(heat.heat > 0.05 and heat.heat < 0.3, "dark heat after 2 s seen: %.3f, wanted a little (0.05..0.3)" % heat.heat)
	heat.reset()
	player.set_headlights(true)
	heat._look()
	for i in 20:
		heat._update_heat(0.1)
	_check(heat.seen and heat.heat == 0.0, "lit car standing still gained heat %.3f" % heat.heat)
	heat.unregister_cop(cop)
	cop.queue_free()
	heat.reset()

func _auto_dip(b: HeadlightBeams) -> void:
	var traffic: TrafficManager = game.get("traffic")
	Harness.move_player_to_lane(player, Harness.lane_x(3))
	var pz := player.global_position.z
	b.dip_probe = traffic.beam_blocked
	player.toggle_high_beam()
	b.step(1.0)
	var onc: TrafficCar = traffic.cars[0]
	onc.target_speed = 0.0
	onc.place(TrafficManager.lane_centre(1, true), 1.0, pz - 250.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.HIGH, "oncoming car at 250 m: not high (beam %d)" % b.mode)
	onc.place(onc.lane_x, 1.0, pz - 120.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.LOW and b.high_on and b.dipped, "oncoming car at 120 m: beam %d, J %s" % [b.mode, b.high_on])
	_check(traffic.beam_blocked(), "traffic.beam_blocked false with a car at 120 m")
	onc.place(onc.lane_x, 1.0, pz - 190.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.HIGH, "oncoming car at 190 m still dips (beam %d)" % b.mode)
	# Same direction, in front: 60 m dips, 100 m does not.
	onc.place(Harness.lane_x(3), -1.0, pz - 60.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.LOW, "car followed at 60 m: beam %d" % b.mode)
	onc.place(Harness.lane_x(3), -1.0, pz - 100.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.HIGH, "car followed at 100 m still dips (beam %d)" % b.mode)
	# A car BEHIND does not.
	onc.place(Harness.lane_x(3), -1.0, pz + 40.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.HIGH, "car behind dips the beam")
	# Auto-dip off: never dips.
	b.auto_dip = false
	onc.place(onc.lane_x, 1.0, pz - 60.0, onc.rest_y, 0.0)
	await physics_frame
	await physics_frame
	b.step(HeadlightBeams.DIP_EVERY + 0.01)
	_check(b.mode == HeadlightBeams.Mode.HIGH, "auto-dip off but the beam dipped")
	b.auto_dip = true
	b.dip_probe = Callable()
	b.step(1.0)
	player.toggle_high_beam()
	b.step(1.0)

func _wall_shots(b: HeadlightBeams) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://headlights"))
	var lane := Harness.lane_x(3)
	Harness.move_player_to_lane(player, lane)
	player.driver = Callable()
	player.brake_input = 1.0
	var pz := player.global_position.z
	wall = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 6.0, 0.2)
	wall.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.75)
	mat.roughness = 1.0
	wall.material_override = mat
	game.add_child(wall)
	wall.global_position = Vector3(lane, 3.0, pz - 30.0)
	cam = Camera3D.new()
	cam.fov = 50.0
	game.add_child(cam)
	cam.global_position = Vector3(lane + 4.0, 1.4, pz - 12.0)
	cam.look_at(Vector3(lane, 1.6, pz - 30.0))
	cam.make_current()
	player.set_headlights(false)
	var dark := await _shot("wall_lights_off")
	player.set_headlights(true)
	var low := await _shot("wall_low_beam")
	player.toggle_high_beam()
	var high := await _shot("wall_high_beam")
	b.step(1.0)
	player.toggle_high_beam()
	# Before this change: the old lamp's numbers on the same spot.
	var spot := _spot()
	spot.spot_range = CarFx.HEADLIGHT_RANGE
	spot.spot_angle = CarFx.HEADLIGHT_ANGLE
	spot.light_energy = CarFx.HEADLIGHT_ENERGY
	spot.rotation_degrees.x = -CarFx.HEADLIGHT_DIP
	spot.light_projector = null
	await _shot("wall_before")

	var lo_b := Vector3(lane, 0.25, pz - 30.0)    # below the lamp (0.62 m)
	var hi_b := Vector3(lane, 2.2, pz - 30.0)     # well above it
	var d_lo := _lum(dark, lo_b)
	var d_hi := _lum(dark, hi_b)
	var l_lo := _lum(low, lo_b)
	var l_hi := _lum(low, hi_b)
	var h_lo := _lum(high, lo_b)
	var h_hi := _lum(high, hi_b)
	print("headlight_beams: wall luminance  lights off %.3f / %.3f   low %.3f / %.3f   high %.3f / %.3f   (below / above the lamp)" % [d_lo, d_hi, l_lo, l_hi, h_lo, h_hi])
	_check(l_lo > d_lo + 0.03, "low beam does not light the wall below the lamp (%.3f vs %.3f)" % [l_lo, d_lo])
	_check(l_hi < d_hi + 0.015, "low beam lights the wall above the cut-off (%.3f vs %.3f dark)" % [l_hi, d_hi])
	_check(h_hi > d_hi + 0.03, "high beam does not light the wall above the lamp (%.3f vs %.3f)" % [h_hi, d_hi])
	wall.queue_free()
	await _road_shots(b, lane, pz)
	cam.queue_free()

func _shot(name: String) -> Image:
	for i in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := "user://headlights/%s.png" % name
	img.save_png(path)
	print("headlight_beams: ", ProjectSettings.globalize_path(path))
	return img

## Mean luminance in an 11x11 box round the world point.
func _lum(img: Image, p: Vector3) -> float:
	var s := cam.unproject_position(p)
	var sum := 0.0
	var n := 0
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			var x := int(s.x) + dx
			var y := int(s.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			n += 1
	return sum / maxf(float(n), 1.0)

## Chase view down the road: where the light lands, before and after.
func _road_shots(b: HeadlightBeams, lane: float, pz: float) -> void:
	cam.global_position = Vector3(lane, 2.6, pz + 7.0)
	cam.look_at(Vector3(lane, 0.8, pz - 60.0))
	cam.fov = 60.0
	var spot := _spot()
	var rows: Array = []
	var modes := ["off", "before", "low", "high"]
	var calls := {}
	var prims := {}
	for m in modes:
		match m:
			"off":
				player.set_headlights(false)
			"before":
				player.set_headlights(true)
				spot.visible = true
				spot.spot_range = CarFx.HEADLIGHT_RANGE
				spot.spot_angle = CarFx.HEADLIGHT_ANGLE
				spot.light_energy = CarFx.HEADLIGHT_ENERGY
				spot.rotation_degrees.x = -CarFx.HEADLIGHT_DIP
				spot.light_projector = null
				spot.shadow_enabled = false
			"low":
				# Back to the beams' own values.
				b.attach(spot)
				player.set_headlights(false)
				player.set_headlights(true)
			"high":
				player.toggle_high_beam()
		var img := await _shot("road_" + m)
		calls[m] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims[m] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var line: Array = []
		for d in [15.0, 30.0, 60.0, 90.0, 130.0]:
			line.append(_lum(img, Vector3(lane, 0.0, pz - d)))
		rows.append([m, line])
	for r in rows:
		print("headlight_beams: road luminance %-6s at 15/30/60/90/130 m: %s" % [r[0], ", ".join(r[1].map(func(v: float) -> String: return "%.3f" % v))])
	print("headlight_beams: draw calls in frame  off %d  before %d  low %d  high %d   primitives  off %d  before %d  low %d  high %d" % [
		calls["off"], calls["before"], calls["low"], calls["high"], prims["off"], prims["before"], prims["low"], prims["high"]])
	# CPU: the cut-off's shadow pass has no casters, so the lamp must not add
	# a single draw call or triangle over the old one.
	_check(calls["low"] <= calls["before"], "low beam draws more calls than the old lamp (%d vs %d)" % [calls["low"], calls["before"]])
	_check(prims["low"] <= prims["before"], "low beam draws more primitives than the old lamp (%d vs %d)" % [prims["low"], prims["before"]])
	var low_row: Array = rows[2][1]
	var off_row: Array = rows[0][1]
	_check(low_row[2] > off_row[2] + 0.02, "low beam adds nothing to the road at 60 m (%.3f vs %.3f)" % [low_row[2], off_row[2]])
