class_name HoodPanel
extends Node

# The sheet under the hood (Roy, 2026-10-14: "a UI to pull up on the underside
# of the hood when you pop the hood", 1565: "info, engine, mods, power etc ...
# maybe HP/Torque charts"; notes/hood-sheet-research-2026-10-14.md). A lit
# build card the size of a clipboard, drawn on the hood's underside so it
# swings up with the hood and faces you in the bay view, like the laminated
# spec card show cars carry under the hood:
#
#   top     the car and its tier, the engine line (family, litres, boost)
#   left    PEAK POWER hp @ rpm, PEAK TORQUE Nm @ rpm, redline, weight, Nm/kg
#   middle  the dyno chart: torque (amber) and power (sodium) over rpm, from
#           the car's own torque curve, boost model and saved tune, peaks
#           marked, the boost threshold ticked on a turbo car
#   right   FITTED: the garage's fitted mods by name, or STOCK
#   bottom  the roadside half (notes/roadside-hood-pop-2026-10-11.md section
#           3): heat, fuel, what is hurt, LIMP / PATCHED / TOW flags, and the
#           rows PATCH IT (CarDamage.station_patch once a night, PATCH_MINUTES
#           of the clock), CALL FERRIS (tow, the night ends, first press arms)
#           and SHUT IT (CarLids.shut_all). Rows grey while a cop sees you.
#
# Keys: Up and Down move the cursor (the bay view keeps Left and Right for
# looking round), Enter picks. No key hints on the sheet (Controls page).
#
# How it is drawn: one SubViewport (PX) with a Control that draws the sheet,
# on a QuadMesh under the hood, a child of the hood's hinge node so it moves
# with the lid. The quad lies GAP under the hood's underside, found from the
# hood part's own vertices (fit()), so it fits every car's hood with no
# per-car number. The viewport renders once per refresh (REFRESH_S) and
# nothing between; the chart is 48 curve samples drawn once. Everything is
# freed when the lid shuts, so a driving car carries none of it.

const NODE_NAME := "HoodPanel"
const PX := Vector2i(800, 500)
const GAP := 0.025              # m under the hood's underside
const FILL := 0.80              # of the hood's width and length
const MAX_W := 1.0              # m, a clipboard not a billboard
const ASPECT := 1.6             # quad width / height, PX's
const REFRESH_S := 0.25
const PATCH_MINUTES := 20.0     # night minutes a roadside patch takes
const BRIGHTNESS := 0.85

const NAVY := Color("#0E1424")
const PLATE := Color("#1B2A4A")
const SILVER := Color("#C9CED6")
const AMBER := Color("#FFC066")
const SODIUM := Color("#FF8A1F")
const RED := Color("#E5262B")
const DIM := Color("#7C8598")

const CHART_N := 48
## hp = Nm x rpm / HP_PER_NM_RPM
const HP_PER_NM_RPM := 7127.0
## Engine line per car (display only; the engine-bays doc table). litres, label.
const ENGINES := {
	"p0_beater": [1.6, "AIR-COOLED FLAT FOUR"], "p1_coupe": [3.0, "STRAIGHT SIX"], "p2_hothatch": [2.0, "INLINE FOUR"],
	"p3_tuner": [2.5, "STRAIGHT SIX"], "p4_kei": [0.66, "TRIPLE"], "p5_muscle": [6.6, "PUSHROD V8"],
	"p6_crossover": [2.5, "BOXER FOUR"], "p7_wagon": [1.8, "INLINE FOUR"], "p8_driftcoupe": [1.8, "INLINE FOUR"],
	"p10_truck": [5.7, "PUSHROD V8"], "p17_work_pickup": [4.0, "V6"],
}

const ROW_PATCH := 0
const ROW_TOW := 1
const ROW_SHUT := 2
const ROWS := ["PATCH IT", "CALL FERRIS", "SHUT IT"]

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const BoltOns := preload("res://scripts/car/bolt_ons.gd")

var game_state: GameState
var player: Node
var wallet: Node
var night_clock: NightClock

var open := false
var hinge := ""
var cursor := ROW_SHUT
var tow_armed := false
var message := ""
var viewport: SubViewport
var quad: MeshInstance3D
var sheet: Sheet
var _lids: CarLids
var _refresh_t := 0.0

signal picked(row: int)

func _init(state: GameState, p: Node, bank: Node, clock: NightClock) -> void:
	game_state = state
	player = p
	wallet = bank
	night_clock = clock
	name = NODE_NAME

func _ready() -> void:
	_lids = CarLids.of(player) if player != null else null
	if _lids != null:
		_lids.lid_changed.connect(_on_lid)

static func of(game: Node) -> HoodPanel:
	return game.get_node_or_null(NODE_NAME) as HoodPanel if game != null else null

func _on_lid(h: String, is_open: bool) -> void:
	if h != _lids.engine_lid:
		return
	if is_open:
		_show(h)
	else:
		_hide()

## Where the sheet goes on a lid: {origin, basis, size} in the hinge node's
## own frame (hinge origin at 0, lid shut). The hood's underside is the lowest
## vertex of the hood part at each station along the lid, from the hinge end
## to the nose; a line through those, GAP under it, carries the quad, so it
## never cuts the hood and never leaves its footprint.
static func fit(car_id: String, hinge_name: String) -> Dictionary:
	var h: Dictionary = CarAssembler.hinges(car_id).get(hinge_name, {})
	if h.is_empty() or (h.parts as Array).is_empty():
		return {}
	var part := String(h.parts[0])
	var box := CarAssembler.part_aabb(car_id, part)
	var origin: Vector3 = h.origin
	var at_nose := origin.z < 0.0
	# the lid runs from the hinge toward the car's end
	var z_hinge := origin.z
	var z_end := box.position.z if at_nose else box.end.z
	var n := 8
	var under := PackedFloat32Array()
	under.resize(n)
	under.fill(INF)
	var arrays := CarAssembler.part_arrays(car_id, part)
	for mname in arrays:
		for v in (arrays[mname].v as PackedVector3Array):
			var t := clampf((v.z - z_hinge) / (z_end - z_hinge), 0.0, 1.0)
			var k := mini(int(t * n), n - 1)
			under[k] = minf(under[k], v.y)
	# least squares line y = a + b * t over the stations that have vertices
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	var cnt := 0
	for k in n:
		if is_finite(under[k]):
			var t := (k + 0.5) / n
			sx += t
			sy += under[k]
			sxx += t * t
			sxy += t * under[k]
			cnt += 1
	if cnt < 2:
		return {}
	var b := (cnt * sxy - sx * sy) / maxf(cnt * sxx - sx * sx, 1e-6)
	var a := (sy - b * sx) / cnt
	var width := minf(box.size.x * FILL, MAX_W)
	var length := width / ASPECT
	var span := absf(z_end - z_hinge)
	length = minf(length, span * FILL)
	width = minf(width, length * ASPECT)
	# the sheet's centre along the lid, a little past the middle toward the latch
	var tc := 0.54
	var yc := a + b * tc
	var zc := z_hinge + (z_end - z_hinge) * tc
	# along the underside from the hinge to the lid's end, and its down normal
	var dirz := 1.0 if z_end > z_hinge else -1.0
	var along := Vector3(0.0, b / span, dirz).normalized()
	var down := Vector3.RIGHT.cross(along).normalized()
	if down.y > 0.0:
		down = -down
	var centre := Vector3(0.0, yc, zc) + down * GAP - origin
	# the quad: +x is the viewer's right (standing at the lid's end looking at
	# the hinge: car -x at the nose), +y runs to the lid's end (the top of the
	# sheet is the raised tip), the face (+z, QuadMesh's front) looks down into
	# the bay, so it turns toward the viewer as the lid swings up
	var x_axis := Vector3.LEFT if at_nose else Vector3.RIGHT
	var basis := Basis(x_axis, along, x_axis.cross(along))
	return {"origin": centre, "basis": basis, "size": Vector2(width, length)}

func _show(h: String) -> void:
	_hide()
	var body := CarAssembler.body_of(player as Vehicle)
	if body == null or _lids == null or not _lids.lids.has(h):
		return
	var node := _lids.lids[h].node as Node3D
	if node == null or not is_instance_valid(node):
		return
	var f := fit(String(body.get_meta("car_id")), h)
	if f.is_empty():
		return
	hinge = h
	viewport = SubViewport.new()
	viewport.name = "SheetViewport"
	viewport.size = PX
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	sheet = Sheet.new()
	sheet.panel = self
	sheet.size = Vector2(PX)
	viewport.add_child(sheet)
	add_child(viewport)
	var mesh := QuadMesh.new()
	mesh.size = f.size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.albedo_color = Color(BRIGHTNESS, BRIGHTNESS, BRIGHTNESS)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad = MeshInstance3D.new()
	quad.name = "Sheet"
	quad.mesh = mesh
	quad.material_override = mat
	quad.layers = body.layers
	quad.transform = Transform3D(f.basis, f.origin)
	node.add_child(quad)
	open = true
	cursor = ROW_SHUT
	tow_armed = false
	message = ""
	_refresh_t = 0.0
	_set_camera_keys(true)
	refresh()

func _hide() -> void:
	if quad != null and is_instance_valid(quad):
		quad.queue_free()
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
	quad = null
	viewport = null
	sheet = null
	open = false
	hinge = ""
	_set_camera_keys(false)

func _set_camera_keys(taken: bool) -> void:
	var game := get_parent()
	var cam: Variant = game.get("camera") if game != null else null
	if cam != null:
		cam.set("bay_menu_up", taken)

## The hood panel takes Up and Down while it is up (Left and Right still look).
func _process(delta: float) -> void:
	if not open:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_S
		refresh()
	if Input.is_action_just_pressed("look_up"):
		move(-1)
	elif Input.is_action_just_pressed("look_down"):
		move(1)
	elif Input.is_action_just_pressed("ui_accept"):
		pick()

func move(dir: int) -> void:
	cursor = wrapi(cursor + dir, 0, ROWS.size())
	tow_armed = false
	refresh()

## True while a cop sees you: no patch, no tow (the pump's rule).
static func locked() -> bool:
	return SaveStore.chase_active

func can_patch() -> bool:
	var d: CarDamage = player.get("damage")
	if d == null or locked() or night_clock == null or d.patched_night == night_clock.night:
		return false
	return d.parts[CarDamage.Part.RADIATOR] >= CarDamage.FREE_BELOW or d.totalled >= CarDamage.TOTALLED_PATCH_AT

func can_tow() -> bool:
	return not locked()

func row_enabled(row: int) -> bool:
	match row:
		ROW_PATCH:
			return can_patch()
		ROW_TOW:
			return can_tow()
	return true

func pick() -> void:
	if not open or not row_enabled(cursor):
		return
	match cursor:
		ROW_PATCH:
			patch()
		ROW_TOW:
			tow()
		ROW_SHUT:
			_lids.shut_all()
	picked.emit(cursor)
	refresh()

## The free roadside patch, once a night: PATCH_MINUTES of the night go by.
func patch() -> bool:
	var d: CarDamage = player.get("damage")
	if d == null or not can_patch():
		return false
	if not d.station_patch(night_clock.night):
		return false
	night_clock.advance(PATCH_MINUTES * NightClock.REAL_SECONDS_PER_HOUR / 60.0)
	var hp: Variant = player.get("health")
	if hp != null and hp.get("engine_temp") != null and float(hp.engine_temp) > 100.0:
		hp.engine_temp = 95.0   # the top-up takes the boil out of it
	message = "Patched. %d minutes gone, it's %s." % [int(PATCH_MINUTES), night_clock.text()]
	return true

## Ferris: first press arms, the second ends the night (PumpPanel.tow rules).
func tow() -> void:
	if not can_tow():
		return
	if not tow_armed:
		tow_armed = true
		return
	tow_armed = false
	var d: CarDamage = player.get("damage")
	if d != null:
		d.tow(wallet, locked())
	var cash: int = wallet.cash if wallet != null else 0
	if night_clock != null:
		night_clock.advance((NightClock.NIGHT_MINUTES - night_clock.minutes) * NightClock.REAL_SECONDS_PER_HOUR / 60.0 + 0.01)
	var fuel: Variant = player.get("fuel")
	if fuel != null:
		fuel.litres = maxf(float(fuel.litres), FuelTank.CAPACITY_L * FuelTank.START_FRACTION)
	message = "Ferris towed you in. Night over, %s banked." % Wallet.money(cash)

func refresh() -> void:
	if sheet != null and is_instance_valid(sheet):
		sheet.queue_redraw()
	if viewport != null and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## What the sheet shows, read fresh each refresh (tests read it too).
func readout() -> Dictionary:
	var d: CarDamage = player.get("damage")
	var hp: Variant = player.get("health")
	var fuel: Variant = player.get("fuel")
	var limp: Variant = player.get("limp")
	var kind := PlayerCar.chassis_kind()
	var out := {
		"title": PlayerCars.title(kind),
		"temp": float(hp.engine_temp) if hp != null else 0.0,
		"fuel": float(fuel.fraction()) if fuel != null else 0.0,
		"limp": limp != null and int(limp.get("cause")) != LimpMode.Cause.NONE,
		"patched": d != null and night_clock != null and d.patched_night == night_clock.night,
		"totalled": float(d.totalled) if d != null else 0.0,
		"lamps_out": 0,
		"bars": [],
	}
	if d != null:
		for b in d.lamps:
			if b:
				out.lamps_out += 1
		var groups := [
			["RADIATOR", [CarDamage.Part.RADIATOR]],
			["STEERING", [CarDamage.Part.STEER_FL, CarDamage.Part.STEER_FR, CarDamage.Part.RACK]],
			["SUSPENSION", [CarDamage.Part.SUSP_RL, CarDamage.Part.SUSP_RR, CarDamage.Part.DAMPER_FL, CarDamage.Part.DAMPER_FR, CarDamage.Part.DAMPER_RL, CarDamage.Part.DAMPER_RR, CarDamage.Part.SAG_FL, CarDamage.Part.SAG_FR]],
			["BRAKES", [CarDamage.Part.BRAKE_FL, CarDamage.Part.BRAKE_FR, CarDamage.Part.BRAKE_RL, CarDamage.Part.BRAKE_RR]],
			["BODY", [CarDamage.Part.BODY]],
		]
		for g in groups:
			var worst := 0.0
			for i in g[1]:
				worst = maxf(worst, float(d.parts[i]))
			out.bars.append({"name": g[0], "level": worst, "hurt": worst >= CarDamage.FREE_BELOW})
	out.merge(dyno(player.get("spec") if player.get("spec") is Dictionary else {}, kind))
	out["mods"] = fitted_names(kind)
	return out

## The dyno: torque and power over rpm from the car's own curve, boost model
## and tune. {rpm: [], torque: [], power: [], peak_nm, peak_nm_rpm, peak_hp,
## peak_hp_rpm, redline, idle, mass, nm_per_kg, tier, boost_bar, boost_kind,
## thresh, engine, gears, final_drive}
static func dyno(spec: Dictionary, kind: String) -> Dictionary:
	var out := {"rpm": PackedFloat32Array(), "torque": PackedFloat32Array(), "power": PackedFloat32Array(),
		"peak_nm": 0.0, "peak_nm_rpm": 0.0, "peak_hp": 0.0, "peak_hp_rpm": 0.0, "redline": 0.0, "idle": 0.0,
		"mass": 0.0, "nm_per_kg": 0.0, "tier": "", "boost_bar": 0.0, "boost_kind": "", "thresh": 0.0,
		"engine": "", "gears": 0, "final_drive": 0.0}
	if spec.is_empty() or not spec.has("max_torque") or not spec.has("max_rpm"):
		return out
	var max_nm := float(spec.max_torque)
	var redline := float(spec.max_rpm)
	var idle := float(spec.get("idle_rpm", 1000.0))
	var shape: Dictionary = spec.get("torque_shape", {"low_end": 0.45, "peak_pos": 0.45, "plateau": 0.0, "falloff": 0.75})
	var curve := CarSpec.build_torque_curve(float(shape.get("low_end", 0.45)), float(shape.get("peak_pos", 0.45)), float(shape.get("plateau", 0.0)), float(shape.get("falloff", 0.75)))
	var boost_max := float(spec.get("turbo_boost_max", 0.0))
	var gain := float(spec.get("turbo_gain", 0.0))
	var thresh := float(spec.get("turbo_rpm_thresh", 2500.0))
	var bkind := String(spec.get("boost_kind", "single")) if boost_max > 0.0 else ""
	var full_mult := ModTree.boost_mult(spec)
	for i in CHART_N + 1:
		var rpm := idle + (redline - idle) * float(i) / CHART_N
		var nm := max_nm * curve.sample_baked(rpm / redline)
		if boost_max > 0.0:
			# steady-state boost: the share of full boost the engine makes at this rpm (ForcedInduction)
			var flow := 0.0
			match bkind:
				"roots":
					flow = 0.35 + 0.65 * rpm / redline
				"twin":
					flow = clampf((rpm - thresh * 0.8) / maxf(redline - thresh * 0.8, 1.0), 0.0, 1.0)
					flow = flow * flow * (3.0 - 2.0 * flow)
				_:
					flow = clampf((rpm - thresh) / maxf(redline - thresh, 1.0), 0.0, 1.0)
			nm *= 1.0 + (full_mult - 1.0) * flow
		var hp := nm * rpm / HP_PER_NM_RPM
		out.rpm.append(rpm)
		out.torque.append(nm)
		out.power.append(hp)
		if nm > float(out.peak_nm):
			out.peak_nm = nm
			out.peak_nm_rpm = rpm
		if hp > float(out.peak_hp):
			out.peak_hp = hp
			out.peak_hp_rpm = rpm
	out.redline = redline
	out.idle = idle
	out.mass = float(spec.get("vehicle_mass", 0.0))
	out.nm_per_kg = ModTree.nm_per_kg(spec) if out.mass > 0.0 else 0.0
	out.tier = ModTree.tier_of(spec) if out.mass > 0.0 else ""
	out.boost_bar = boost_max
	out.boost_kind = bkind
	out.thresh = thresh
	out.gears = (spec.get("gear_ratios", []) as Array).size()
	out.final_drive = float(spec.get("final_drive", 0.0))
	var e: Array = ENGINES.get(kind, [0.0, "ENGINE"])
	var line := ("%.1f %s" % [float(e[0]), String(e[1])]) if float(e[0]) > 0.0 else String(e[1])
	if boost_max > 0.0:
		var what: String = {"single": "TURBO", "twin": "TWIN TURBO", "roots": "SUPERCHARGED", "sequential": "SEQUENTIAL TURBOS", "twincharger": "TWINCHARGED"}.get(bkind, "TURBO")
		line += " · %s %.1f BAR" % [what, boost_max]
	else:
		line += " · NATURALLY ASPIRATED"
	out.engine = line
	return out

## The garage's fitted mods by name (the tree's nodes, the Workshop items, the
## ladder rungs); a test build lists what ModTree fitted. [] when stock.
func fitted_names(kind: String) -> Array[String]:
	var ids: Array = []
	var mb: Variant = player.get("mod_build")
	if mb is Dictionary and not (mb as Dictionary).is_empty():
		ids = (mb as Dictionary).get("nodes", []).duplicate()
		for b in (mb as Dictionary).get("bolt_ons", []):
			ids.append(b)
	else:
		ids = SaveStore.load_mod_tree().cars.get(kind, {}).get("installed", [])
	var names: Array[String] = []
	var bolt := {}
	for it in BoltOns.items():
		bolt[String(it.id)] = String(it.get("label", it.id))
	for id in ids:
		var sid := String(id)
		var node := ModTree.node(kind, sid)
		if not node.is_empty():
			names.append(String(node.get("name", sid)).to_upper())
		elif bolt.has(sid):
			names.append(String(bolt[sid]).to_upper())
		else:
			names.append(sid.replace("_", " ").to_upper())
	return names

## The sheet itself: navy plate, the engine line, big numbers, the dyno, the
## fitted list, the roadside strip and its rows.
class Sheet:
	extends Control
	var panel: HoodPanel

	func _draw() -> void:
		var r := panel.readout() if panel != null else {}
		if r.is_empty():
			return
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), NAVY)
		draw_rect(Rect2(Vector2(8, 8), size - Vector2(16, 16)), PLATE)
		draw_rect(Rect2(Vector2(8, 8), size - Vector2(16, 16)), SILVER, false, 2.0)
		var menu := UiTheme.font("menu")
		var strong := UiTheme.font("menu_strong")
		var mono := UiTheme.font("numbers")
		var display := UiTheme.font("display")
		# ---- header: the car, the engine line
		draw_string(display, Vector2(24, 48), String(r.title).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, AMBER)
		draw_string(mono, Vector2(24, 72), String(r.engine), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, SILVER)
		var flags := ""
		if r.limp:
			flags += "LIMP  "
		if r.patched:
			flags += "PATCHED TONIGHT  "
		if float(r.totalled) >= CarDamage.TOW_AT:
			flags += "TOW  "
		if flags != "":
			draw_string(mono, Vector2(w - 24 - mono.get_string_size(flags.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 48), flags.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED)
		# ---- left: the big numbers
		var lx := 24.0
		var y := 112.0
		_big(display, mono, Vector2(lx, y), "%d" % int(round(float(r.peak_hp))), "HP", "@ %d RPM" % int(round(float(r.peak_hp_rpm) / 50.0) * 50))
		y += 62
		_big(display, mono, Vector2(lx, y), "%d" % int(round(float(r.peak_nm))), "NM", "@ %d RPM" % int(round(float(r.peak_nm_rpm) / 50.0) * 50))
		y += 52
		draw_string(mono, Vector2(lx, y), "REDLINE %d" % int(r.redline), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SILVER)
		y += 20
		draw_string(mono, Vector2(lx, y), "%d KG   %.2f NM/KG" % [int(r.mass), float(r.nm_per_kg)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SILVER)
		y += 20
		if int(r.gears) > 0:
			draw_string(mono, Vector2(lx, y), "%d-SPEED   FD %.2f" % [int(r.gears), float(r.final_drive)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SILVER)
		# ---- middle: the dyno chart
		var chart := Rect2(Vector2(236, 96), Vector2(316, 196))
		_chart(mono, chart, r)
		# ---- right: fitted
		var rx := 572.0
		draw_string(strong, Vector2(rx, 112), "FITTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, AMBER)
		var mods: Array = r.mods
		var my := 136.0
		if mods.is_empty():
			draw_string(mono, Vector2(rx, my), "STOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
		for i in mini(mods.size(), 8):
			draw_string(mono, Vector2(rx, my), String(mods[i]), HORIZONTAL_ALIGNMENT_LEFT, int(w - rx - 24), 14, SILVER)
			my += 19
		if mods.size() > 8:
			draw_string(mono, Vector2(rx, my), "+%d MORE" % (mods.size() - 8), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
		# ---- bottom strip: heat, fuel, what is hurt
		var sy := 318.0
		draw_line(Vector2(24, sy - 12), Vector2(w - 24, sy - 12), SILVER, 1.0)
		var col_w := 300.0
		_bar(menu, Vector2(24, sy), col_w, "ENGINE", clampf((float(r.temp) - 60.0) / 70.0, 0.0, 1.0), "%d C" % int(r.temp), float(r.temp) > 110.0)
		_bar(menu, Vector2(24, sy + 26), col_w, "FUEL", float(r.fuel), "%d%%" % int(float(r.fuel) * 100.0), float(r.fuel) < 0.12)
		var by := sy + 52
		var bx := 24.0
		var k := 0
		for b in r.bars:
			_bar(menu, Vector2(bx, by), 300.0 if k % 2 == 0 else 300.0, String(b.name), float(b.level), "", bool(b.hurt))
			if k % 2 == 0:
				bx = 24.0 + 300.0 + 24.0
			else:
				bx = 24.0
				by += 24
			k += 1
		if k % 2 == 1:
			by += 24
		_bar(menu, Vector2(bx, by), 300.0, "WRECK", float(r.totalled), "%d%%" % int(float(r.totalled) * 100.0), float(r.totalled) >= CarDamage.TOW_AT)
		if int(r.lamps_out) > 0:
			draw_string(mono, Vector2(24.0 + 324.0, by + 14), "%d LAMP%s OUT" % [int(r.lamps_out), "" if int(r.lamps_out) == 1 else "S"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED)
		# ---- the rows, bottom right
		var rrx := 572.0
		var ry := sy + 8
		for i in HoodPanel.ROWS.size():
			var label: String = HoodPanel.ROWS[i]
			if i == HoodPanel.ROW_TOW and panel.tow_armed:
				label = "SURE? NIGHT ENDS"
			var on := panel.row_enabled(i)
			var sel := i == panel.cursor
			var box := Rect2(Vector2(rrx - 10, ry - 20), Vector2(w - rrx - 14, 30))
			if sel:
				draw_rect(box, SODIUM if on else DIM)
			draw_string(strong, Vector2(rrx, ry), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, (NAVY if sel else (SILVER if on else DIM)))
			ry += 38
		if panel.message != "":
			draw_string(menu, Vector2(24, h - 18), panel.message, HORIZONTAL_ALIGNMENT_LEFT, int(w - 48), 14, AMBER)

	func _big(display: Font, mono: Font, at: Vector2, num: String, unit: String, note: String) -> void:
		draw_string(display, at, num, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, SODIUM)
		var nw := display.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		draw_string(mono, at + Vector2(nw + 8, 0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, AMBER)
		draw_string(mono, at + Vector2(0, 20), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SILVER)

	## Torque (amber) and power (sodium) over rpm, each to its own peak.
	func _chart(mono: Font, rc: Rect2, r: Dictionary) -> void:
		draw_rect(rc, NAVY)
		draw_rect(rc, SILVER, false, 1.0)
		var rpm: PackedFloat32Array = r.rpm
		if rpm.size() < 2 or float(r.peak_nm) <= 0.0 or float(r.peak_hp) <= 0.0:
			draw_string(mono, rc.position + Vector2(12, 24), "NO DYNO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
			return
		var r0 := float(r.idle)
		var r1 := float(r.redline)
		# grid: every 1000 rpm
		var g := ceilf(r0 / 1000.0) * 1000.0
		while g < r1:
			var gx := rc.position.x + rc.size.x * (g - r0) / (r1 - r0)
			draw_line(Vector2(gx, rc.position.y), Vector2(gx, rc.end.y), Color(SILVER.r, SILVER.g, SILVER.b, 0.18), 1.0)
			draw_string(mono, Vector2(gx - 8, rc.end.y + 14), "%d" % int(g / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
			g += 1000.0
		if float(r.boost_bar) > 0.0:
			var tx := rc.position.x + rc.size.x * clampf((float(r.thresh) - r0) / (r1 - r0), 0.0, 1.0)
			draw_dashed_line(Vector2(tx, rc.position.y), Vector2(tx, rc.end.y), SODIUM, 1.0, 4.0)
			draw_string(mono, Vector2(tx + 4, rc.position.y + 14), "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SODIUM)
		var tq := PackedVector2Array()
		var pw := PackedVector2Array()
		var torque: PackedFloat32Array = r.torque
		var power: PackedFloat32Array = r.power
		var pad := 10.0
		for i in rpm.size():
			var x := rc.position.x + rc.size.x * (rpm[i] - r0) / (r1 - r0)
			tq.append(Vector2(x, rc.end.y - pad - (rc.size.y - 2.0 * pad) * torque[i] / float(r.peak_nm)))
			pw.append(Vector2(x, rc.end.y - pad - (rc.size.y - 2.0 * pad) * power[i] / float(r.peak_hp)))
		draw_polyline(tq, AMBER, 2.5, true)
		draw_polyline(pw, SODIUM, 2.5, true)
		# the peaks
		var ix := rc.position.x + rc.size.x * (float(r.peak_nm_rpm) - r0) / (r1 - r0)
		draw_circle(Vector2(ix, rc.position.y + pad), 3.5, AMBER)
		var px := rc.position.x + rc.size.x * (float(r.peak_hp_rpm) - r0) / (r1 - r0)
		draw_circle(Vector2(px, rc.position.y + pad), 3.5, SODIUM)
		draw_string(mono, rc.position + Vector2(8, rc.size.y - 6), "NM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, AMBER)
		draw_string(mono, rc.position + Vector2(36, rc.size.y - 6), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SODIUM)
		draw_string(mono, Vector2(rc.end.x - 30, rc.end.y + 14), "x1000", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)

	func _bar(font: Font, at: Vector2, width: float, label: String, level: float, value: String, hot: bool) -> void:
		draw_string(font, at + Vector2(0, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SILVER)
		var bx := at.x + 96
		var bw := width - 96 - (52 if value != "" else 0)
		draw_rect(Rect2(Vector2(bx, at.y), Vector2(bw, 14)), NAVY)
		draw_rect(Rect2(Vector2(bx, at.y), Vector2(bw * clampf(level, 0.0, 1.0), 14)), RED if hot else AMBER)
		draw_rect(Rect2(Vector2(bx, at.y), Vector2(bw, 14)), SILVER, false, 1.0)
		if value != "":
			draw_string(UiTheme.font("numbers"), Vector2(bx + bw + 6, at.y + 13), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, RED if hot else SILVER)
