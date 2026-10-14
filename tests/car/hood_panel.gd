extends SceneTree

# The sheet under the hood (HoodPanel; Roy 2026-10-14: info, engine, mods,
# power, HP/torque charts, plus the roadside rows).
#
# No game: HoodPanel.fit() on every parts car with a hood puts the sheet GAP
# under the hood's underside at all four corners, inside the hood's footprint,
# facing down (the viewer's side once the hood is up). HoodPanel.dyno() on the
# coupe's spec gives a torque peak at the spec's max_torque, a power peak
# above it in rpm, 49 samples from idle to redline, and a tier.
#
# In the game (the coupe): Y opens the hood and a "Sheet" quad hangs under the
# hinge node, facing the bay camera, its top raised; Up/Down move the cursor
# and the camera's pitch is held; PATCH IT with a hurt radiator patches once
# (radiator under the free band, 20 night minutes gone, PATCHED flag, a second
# patch refused); CALL FERRIS arms then ends the night (night + 1, tank at the
# start level); SHUT IT shuts the hood and the sheet is gone.
#
# Exit code 1 on failure. Run:
#   godot --headless --audio-driver Dummy --path . -s res://tests/car/hood_panel.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
## Every playable car with a parts-built body (the sheet-only cars have no
## hood to hang a sheet under yet); Roy's rule: a change loops over all of them.
func _built_cars() -> Array[String]:
	var out: Array[String] = []
	for id in PlayerCars.ids():
		if ResourceLoader.exists("res://assets/cars/%s/body.glb" % id):
			out.append(id)
	return out

var logger := Harness.ErrorCounter.new()
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _secs(t: float) -> void:
	var until := Engine.get_physics_frames() + int(ceil(t * float(Engine.physics_ticks_per_second)))
	while Engine.get_physics_frames() < until:
		await process_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _secs(0.05)
	Input.action_release(action)
	await _secs(0.05)

## The hood's lowest vertex near a z station (the underside there).
## The hood's lowest vertex y at a z station, interpolated between the
## stations the part has vertices at (a box hood has only its two ends), so a
## corner anywhere along the lid gets the underside under it.
func _under_y(car_id: String, part: String, z: float, _x: float) -> float:
	var by_z := {}
	for mname in CarAssembler.part_arrays(car_id, part):
		for v in (CarAssembler.part_arrays(car_id, part)[mname].v as PackedVector3Array):
			var key := roundi(v.z * 50.0)
			by_z[key] = minf(float(by_z.get(key, INF)), v.y)
	var keys := by_z.keys()
	keys.sort()
	if keys.is_empty():
		return INF
	var lo := int(keys[0])
	var hi := int(keys[-1])
	for k in keys:
		if float(k) / 50.0 <= z:
			lo = int(k)
		if float(k) / 50.0 >= z:
			hi = int(k)
			break
	if lo == hi:
		return float(by_z[lo])
	var t := clampf((z - float(lo) / 50.0) / (float(hi - lo) / 50.0), 0.0, 1.0)
	return lerpf(float(by_z[lo]), float(by_z[hi]), t)

func _fit_checks() -> void:
	var n := 0
	var cars := _built_cars()
	_check(cars.size() >= 8, "expected 8 or more parts-built cars, got %d" % cars.size())
	for id in cars:
		var hinges := CarAssembler.hinges(id)
		if not hinges.has("hinge_hood"):
			continue
		var f := HoodPanel.fit(id, "hinge_hood")
		_check(not f.is_empty(), "%s: no fit for the hood" % id)
		if f.is_empty():
			continue
		n += 1
		var origin: Vector3 = hinges.hinge_hood.origin
		var part := String(hinges.hinge_hood.parts[0])
		var box := CarAssembler.part_aabb(id, part)
		var size: Vector2 = f.size
		var basis: Basis = f.basis
		_check(basis.z.y < -0.9, "%s: the sheet should face down (normal %s)" % [id, basis.z])
		_check(basis.y.z < -0.9, "%s: the sheet's top should point to the nose (up %s)" % [id, basis.y])
		_check(basis.x.x < -0.9, "%s: the sheet's right should be the car's left (x %s)" % [id, basis.x])
		_check(size.x >= 0.3 and size.y >= 0.18, "%s: sheet too small %s" % [id, size])
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner: Vector3 = origin + (f.origin as Vector3) + basis * Vector3(sx * size.x / 2.0, sy * size.y / 2.0, 0.0)
				_check(box.grow(0.001).has_point(Vector3(corner.x, clampf(corner.y, box.position.y, box.end.y), corner.z)), "%s: sheet corner %s outside the hood's footprint %s" % [id, corner, box])
				var uy := _under_y(id, part, corner.z, corner.x)
				_check(is_finite(uy) and corner.y <= uy - 0.012 and corner.y >= uy - 0.08, "%s: sheet corner %s should hang 12-80 mm under the hood underside (%.3f)" % [id, corner, uy])
	_check(n >= 7, "expected 7 or more hoods fitted, got %d" % n)
	print("hood_panel: the sheet fits %d hoods" % n)

func _dyno_checks() -> void:
	# every playable car gets a sane sheet: an engine row, peaks, a tier
	for id in PlayerCars.ids():
		var sp := CarSpec.player_spec(id)
		var dd := HoodPanel.dyno(sp, id)
		_check(HoodPanel.ENGINES.has(id), "%s: no engine row for the sheet" % id)
		_check(float(dd.peak_hp) > 30.0 and float(dd.peak_nm) > 50.0 and float(dd.peak_hp_rpm) >= float(dd.peak_nm_rpm) and String(dd.tier) != "", "%s: dyno %.0f hp @ %.0f, %.0f Nm @ %.0f, tier %s" % [id, float(dd.peak_hp), float(dd.peak_hp_rpm), float(dd.peak_nm), float(dd.peak_nm_rpm), String(dd.tier)])
	var spec := CarSpec.player_spec("p1_coupe")
	var d := HoodPanel.dyno(spec, "p1_coupe")
	_check(d.rpm.size() == HoodPanel.CHART_N + 1, "49 samples, got %d" % d.rpm.size())
	_check(absf(float(d.peak_nm) - float(spec.max_torque) * ModTree.boost_mult(spec)) < 0.5, "peak Nm %.1f should be the spec's %.1f" % [float(d.peak_nm), float(spec.max_torque) * ModTree.boost_mult(spec)])
	_check(float(d.peak_hp) > 0.0 and float(d.peak_hp_rpm) >= float(d.peak_nm_rpm), "power peaks after torque (%.0f @ %.0f vs %.0f @ %.0f)" % [float(d.peak_hp), float(d.peak_hp_rpm), float(d.peak_nm), float(d.peak_nm_rpm)])
	_check(absf(float(d.peak_hp) - float(d.peak_nm) * float(d.peak_hp_rpm) / HoodPanel.HP_PER_NM_RPM) < float(d.peak_hp) * 0.5, "hp follows Nm x rpm")
	_check(String(d.tier) != "" and float(d.nm_per_kg) > 0.2, "tier %s, %.2f Nm/kg" % [String(d.tier), float(d.nm_per_kg)])
	_check(String(d.engine).begins_with("3.0 STRAIGHT SIX"), "engine line: %s" % String(d.engine))
	_check(d.rpm[0] == float(spec.idle_rpm) and d.rpm[-1] == float(spec.max_rpm), "rpm runs idle to redline")
	# a turbo on the same engine lifts the peak and marks the threshold
	var t := spec.duplicate(true)
	t.turbo_boost_max = 0.8
	t.turbo_gain = 0.4
	t.turbo_rpm_thresh = 3000.0
	t.boost_kind = "single"
	var dt := HoodPanel.dyno(t, "p1_coupe")
	# a single turbo reaches full boost only at the redline (ForcedInduction._flow),
	# so the peak rises but stays under max_torque x the full multiplier
	_check(float(dt.peak_nm) > float(d.peak_nm) * 1.1 and float(dt.peak_nm) <= float(t.max_torque) * ModTree.boost_mult(t) + 0.5, "a turbo should lift the peak (%.0f vs %.0f, under x%.2f)" % [float(dt.peak_nm), float(d.peak_nm), ModTree.boost_mult(t)])
	_check(absf(float(dt.torque[-1]) - float(d.torque[-1]) * ModTree.boost_mult(t)) < 0.5, "at the redline the turbo makes its full boost (%.0f vs %.0f x %.2f)" % [float(dt.torque[-1]), float(d.torque[-1]), ModTree.boost_mult(t)])
	_check(String(dt.engine).contains("TURBO 0.8 BAR"), "turbo engine line: %s" % String(dt.engine))
	_check(dt.torque[0] <= d.torque[0] + 0.5, "under the threshold the turbo adds nothing")
	print("hood_panel: coupe dyno %.0f hp @ %.0f, %.0f Nm @ %.0f, %s" % [float(d.peak_hp), float(d.peak_hp_rpm), float(d.peak_nm), float(d.peak_nm_rpm), String(d.tier)])

func _in_game() -> void:
	OS.set_environment("NEON_CAR", "p1_coupe")
	var game := Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	var panel := HoodPanel.of(game)
	var clock: NightClock = game.get("night_clock")
	_check(p != null and cam != null and panel != null and clock != null, "the game did not boot with a player, camera, HoodPanel and night clock")
	if p == null or cam == null or panel == null or clock == null:
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 1.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.CHASE)
	await _secs(1.5)
	var lids := CarLids.of(p)
	_check(lids != null and lids.can_open(), "the stopped coupe cannot open a lid")
	if lids == null:
		return
	_check(not panel.open, "the sheet should be down with the hood shut")
	await _tap(CarLids.ACTION)
	await _frames(4)
	_check(lids.is_open("hinge_hood") and panel.open, "Y should open the hood and raise the sheet (open %s)" % panel.open)
	var node := lids.lids.get("hinge_hood", {}).get("node") as Node3D
	var quad := node.get_node_or_null("Sheet") as MeshInstance3D if node != null else null
	_check(quad != null and quad.mesh is QuadMesh, "no Sheet quad under the hood's hinge node")
	await _secs(CarLids.OPEN_TIME + 0.3)
	if quad != null:
		var to_cam := (cam.global_position - quad.global_position).normalized()
		_check(quad.global_transform.basis.z.dot(to_cam) > 0.3, "the sheet should face the bay camera (dot %.2f)" % quad.global_transform.basis.z.dot(to_cam))
		_check(quad.global_transform.basis.y.y > 0.3, "the sheet's top should be raised with the hood (up.y %.2f)" % quad.global_transform.basis.y.y)
		var mat := quad.material_override as StandardMaterial3D
		_check(mat != null and mat.albedo_texture is ViewportTexture, "the sheet should show the viewport")
	var r := panel.readout()
	_check(float(r.peak_hp) > 100.0 and String(r.tier) != "" and r.mods is Array, "readout in game: %s hp, tier %s" % [str(r.get("peak_hp")), str(r.get("tier"))])
	# keys: Up/Down move the cursor, the camera stops pitching
	_check(panel.cursor == HoodPanel.ROW_SHUT and cam.bay_menu_up, "the cursor should start on SHUT IT with the camera's pitch held")
	await _tap("look_up")
	_check(panel.cursor == HoodPanel.ROW_TOW, "Up should move to CALL FERRIS (%d)" % panel.cursor)
	await _tap("look_up")
	_check(panel.cursor == HoodPanel.ROW_PATCH, "Up again should reach PATCH IT (%d)" % panel.cursor)
	_check(absf(cam.look_pitch) < 0.5, "the bay camera should not pitch on the menu keys (%.1f)" % cam.look_pitch)
	# patch: nothing to patch -> greyed; a hurt radiator -> once
	_check(not panel.row_enabled(HoodPanel.ROW_PATCH), "PATCH IT should be greyed with nothing hurt")
	p.damage.parts[CarDamage.Part.RADIATOR] = 0.6
	_check(panel.row_enabled(HoodPanel.ROW_PATCH), "a hurt radiator should offer the patch")
	var minutes := clock.minutes
	panel.pick()
	_check(p.damage.parts[CarDamage.Part.RADIATOR] < CarDamage.FREE_BELOW, "the patch should bring the radiator under the free band (%.2f)" % p.damage.parts[CarDamage.Part.RADIATOR])
	_check(absf((clock.minutes - minutes) - HoodPanel.PATCH_MINUTES) < 0.5, "the patch should take %d night minutes (%.1f)" % [int(HoodPanel.PATCH_MINUTES), clock.minutes - minutes])
	_check(panel.readout().patched and not panel.row_enabled(HoodPanel.ROW_PATCH), "a second patch tonight should be refused")
	# tow: arm, then the night ends
	await _tap("look_down")
	_check(panel.cursor == HoodPanel.ROW_TOW, "Down should reach CALL FERRIS")
	var night := clock.night
	panel.pick()
	_check(panel.tow_armed and clock.night == night, "the first press only arms the tow")
	p.fuel.litres = 5.0
	panel.pick()
	_check(clock.night == night + 1, "the tow should end the night (%d -> %d)" % [night, clock.night])
	_check(p.fuel.litres >= FuelTank.CAPACITY_L * FuelTank.START_FRACTION - 0.01, "the tow should leave the starting tank")
	# shut: the sheet goes
	await _tap("look_down")
	_check(panel.cursor == HoodPanel.ROW_SHUT, "Down should reach SHUT IT")
	panel.pick()
	await _secs(CarLids.SHUT_TIME + 0.5)
	_check(not lids.is_open("hinge_hood") and not panel.open and not cam.bay_menu_up, "SHUT IT should shut the hood and drop the sheet")
	_check(node == null or not is_instance_valid(node) or node.get_node_or_null("Sheet") == null, "the Sheet quad should be freed with the hood shut")
	OS.set_environment("NEON_CAR", "")
	game.queue_free()
	await _frames(2)

func _run() -> void:
	_fit_checks()
	_dyno_checks()
	await _in_game()
	print("hood_panel: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
