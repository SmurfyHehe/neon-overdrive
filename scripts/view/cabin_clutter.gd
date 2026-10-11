class_name CabinClutter
extends Node3D

# What a car's cabin has picked up (MA6): receipts on the dash, dust, a seat
# stain, smeared glass, a crumpled food bag, and the beer cans rolling about
# the passenger footwell. A child of the CockpitFrame, in cockpit space (the
# same as car space). Reads CabinDirt for the level, the can count and the
# receipts; CabinDirt is what gets saved. Looks only.
#
# Levels add up (CabinDirt): Lived-in shows the receipts, Messy adds the dust
# and the stain, Filthy adds the glass smear and the bag. The cans show at any
# level, as many as CabinDirt.cans (CanSim keeps them on the floor).
#
# The cans: CanSim (a 2D model, no rigid bodies), stepped here at the physics
# rate from the car's own acceleration (local velocity over time). It runs only
# while the cockpit view is up or a can is still moving; otherwise it sleeps
# and costs nothing. Each contact clinks, made in code and louder for a harder
# hit; at most MAX_CLINKS play at once, the rest are dropped.
#
# Receipts flutter a little when the window is down and the car is moving.

const PAPER := Color("#E4DCC8")
const DUST := Color(0.62, 0.55, 0.43, 0.20)
const STAIN := Color(0.09, 0.065, 0.045, 0.60)
const SMEAR := Color(0.72, 0.68, 0.60, 0.18)
const BAG := Color("#9B7B4C")
const BAG_DARK := Color("#6E5632")
const BAND := Color("#FF8A1F")
const SMEAR_CONE_DEG := 20.0     # smear stays outside this cone either side of straight ahead
const MAX_CLINKS := 2
const CLINK_SECS := 0.30
const FLUTTER_WINDOW := 0.5
const GRAVITY := 9.81

var frame: Node3D                 # the CockpitFrame
var player: PlayerCar
var cab: Dictionary
var kind := ""
var sim := CanSim.new()
var can_nodes: Array[Node3D] = []
var receipt_nodes: Array[MeshInstance3D] = []
var dust: MeshInstance3D
var stain: MeshInstance3D
var smear: MeshInstance3D
var bag: MeshInstance3D
var tri_count := 0
var floor_top := 0.0              # the floor the cans stand on, car space y
# clinks (tests)
var clinks_played := 0
var clinks_dropped := 0
var max_simultaneous := 0
var _clink_end := [-1.0, -1.0]
var _clink_players: Array[AudioStreamPlayer] = []
var _clock := 0.0
var _prev_lv := Vector3.ZERO
var _have_prev := false
var _rough := 0.0
var _seen_revision := -1
var _receipt_base: Array[Basis] = []
var _slope := 0.0
var _flutter_t := 0.0
var _rng := 4242

func _init(cockpit_frame: Node3D) -> void:
	frame = cockpit_frame
	player = cockpit_frame.get("player")
	cab = cockpit_frame.get("cab")
	kind = PlayerCar.chassis_kind()
	name = "CabinClutter"

func _ready() -> void:
	var cowl: Vector2 = cab.cowl            # (y, z)
	var header: Vector2 = cab.header
	var cluster: Vector2 = cab.cluster
	var eye: Vector3 = cab.eye
	var px := -float(cab.seat_x)            # the passenger's side
	var seat_h := float(cab.seat_h)
	var seat_z := float(cab.seat_z)
	var floor_y := float(cab.floor_y)
	var door_f := minf(float(cab.door_x), float(cab.get("door_x_front", cab.door_x)))
	floor_top = floor_y + 0.04
	var alpha := _alpha_material()
	var solid := CockpitKit.material(0.9, 0.0, 0.05)
	# the dash top is a straight slope from the cowl lip to the cluster
	_slope = atan2(cluster.x - cowl.x, cluster.y - cowl.y)
	# --- receipts (Lived-in): five thin sheets, drawn as many as there are stops
	var k := CockpitKit.new()
	k.box(Vector3(0.056, 0.0012, 0.15), Vector3.ZERO, PAPER)
	k.box(Vector3(0.05, 0.0004, 0.012), Vector3(0.0, 0.0007, -0.05), BAND)   # a printed band
	var receipt_mesh := k.commit(solid)
	tri_count += k.tri_count()
	for i in CabinDirt.MAX_RECEIPTS:
		var along := 0.5 + 0.10 * sin(float(i) * 2.1)
		var x := px + 0.12 - float(i) * 0.085
		var z := lerpf(cowl.y, cluster.y, along)
		var y := lerpf(cowl.x, cluster.x, along) + 0.004 + float(i) * 0.0014
		var yaw_deg := float((i * 37) % 50) - 25.0
		var mi := MeshInstance3D.new()
		mi.name = "Receipt%d" % i
		mi.mesh = receipt_mesh
		mi.position = Vector3(x, y, z)
		_receipt_base.append(Basis(Vector3.RIGHT, -_slope) * Basis(Vector3.UP, deg_to_rad(yaw_deg)))
		mi.basis = _receipt_base[i]
		add_child(mi)
		receipt_nodes.append(mi)
	# --- dust (Messy): a grey-tan film over the dash top, the passenger half and
	# the lip, clear of the driver's gauges
	k = CockpitKit.new()
	var a0 := 0.06
	var a1 := 0.94
	var xa := eye.x + 0.38
	var xb := door_f - 0.04
	var p00 := Vector3(xa, lerpf(cowl.x, cluster.x, a0) + 0.003, lerpf(cowl.y, cluster.y, a0))
	var p01 := Vector3(xa, lerpf(cowl.x, cluster.x, a1) + 0.003, lerpf(cowl.y, cluster.y, a1))
	var p10 := Vector3(xb, p00.y, p00.z)
	var p11 := Vector3(xb, p01.y, p01.z)
	k.quad(p00, p10, p11, p01, DUST)
	k.quad(p00 + Vector3(0.0, 0.0008, 0.0), p10 + Vector3(-0.2, 0.0008, 0.0), p10 + Vector3(-0.2, 0.0008, 0.11), p00 + Vector3(0.0, 0.0008, 0.11), Color(DUST, 0.16))
	tri_count += k.tri_count()
	dust = k.instance(alpha, "Dust")
	add_child(dust)
	# --- seat stain (Messy): two overlapping blots on the passenger cushion
	k = CockpitKit.new()
	k.box(Vector3(0.17, 0.002, 0.12), Vector3(px - 0.02, seat_h + 0.011, seat_z - 0.05), STAIN, Basis(Vector3.UP, deg_to_rad(18.0)))
	k.box(Vector3(0.10, 0.002, 0.20), Vector3(px + 0.03, seat_h + 0.0115, seat_z - 0.02), Color(STAIN, 0.45), Basis(Vector3.UP, deg_to_rad(-12.0)))
	tri_count += k.tri_count()
	stain = k.instance(alpha, "SeatStain")
	add_child(stain)
	# --- smeared glass (Filthy): bands on the inside of the windshield, kept
	# outside SMEAR_CONE_DEG either side of the eye's straight ahead
	k = CockpitKit.new()
	_smear(k, -1.0, cab)
	_smear(k, 1.0, cab)
	tri_count += k.tri_count()
	smear = k.instance(alpha, "GlassSmear")
	add_child(smear)
	# --- the crumpled bag (Filthy): behind the cans' floor, in the back corner
	var bx := door_f - 0.20
	var bz := seat_z - 0.20
	k = CockpitKit.new()
	k.box(Vector3(0.15, 0.10, 0.11), Vector3(bx, floor_top + 0.05, bz), BAG, Basis(Vector3.UP, deg_to_rad(23.0)))
	k.box(Vector3(0.11, 0.08, 0.09), Vector3(bx + 0.05, floor_top + 0.045, bz - 0.06), BAG_DARK, Basis(Vector3.UP, deg_to_rad(-35.0)) * Basis(Vector3.BACK, deg_to_rad(9.0)))
	k.box(Vector3(0.12, 0.012, 0.10), Vector3(bx, floor_top + 0.106, bz), BAG, Basis(Vector3.UP, deg_to_rad(23.0)) * Basis(Vector3.RIGHT, deg_to_rad(14.0)))
	k.box(Vector3(0.152, 0.03, 0.112), Vector3(bx, floor_top + 0.045, bz), BAND, Basis(Vector3.UP, deg_to_rad(23.0)))
	tri_count += k.tri_count()
	bag = k.instance(solid, "FoodBag")
	add_child(bag)
	# --- the cans: lying down, one holder per can (yaw) and the mesh inside it
	var ck := CockpitKit.new()
	IdleProps._can_mesh(ck)
	var can_mesh := ck.commit(solid)
	tri_count += ck.tri_count()
	for i in CanSim.MAX_CANS:
		var holder := Node3D.new()
		holder.name = "Can%d" % i
		var mi := MeshInstance3D.new()
		mi.mesh = can_mesh
		mi.name = "Mesh"
		holder.add_child(mi)
		holder.visible = false
		add_child(holder)
		can_nodes.append(holder)
	# the floor the cans use: the footwell between the tunnel and the door, from
	# the firewall back to just short of the seat, the bag's corner left clear
	var z_front := cowl.y + 0.15
	var z_back := seat_z - 0.34
	sim.configure(0.18, door_f - 0.10, z_front, z_back)
	sim.on_contact = _on_contact
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Clink%d" % i
		p.volume_db = -12.0
		add_child(p)
		_clink_players.append(p)
	_refresh()

func _alpha_material() -> StandardMaterial3D:
	var m := CockpitKit.material(1.0, 0.0, 0.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m

## One side's smear on the windshield's inner face: two bands whose inner edge
## follows the SMEAR_CONE_DEG line from the driver's eye.
func _smear(k: CockpitKit, side: float, c: Dictionary) -> void:
	var cowl: Vector2 = c.cowl
	var header: Vector2 = c.header
	var eye: Vector3 = c.eye
	var foot: Vector3 = c.a_pillar[0]
	var top: Vector3 = c.a_pillar[1]
	var tan_c := tan(deg_to_rad(SMEAR_CONE_DEG))
	var bands := [[0.20, 0.52], [0.55, 0.86]]
	for b in bands:
		var pts: Array[Vector3] = []
		var ok := true
		for t in b:
			var z := lerpf(cowl.y, header.y, t) + 0.02            # a hair inside the glass
			var y := lerpf(cowl.x + 0.09, header.x - 0.03, t)
			var inner := eye.x + side * (tan_c * (eye.z - z) + 0.03)
			var outer := side * (lerpf(foot.x, top.x, t) - 0.07)
			if side * (outer - inner) <= 0.03:   # no room between the cone and the pillar
				ok = false
				break
			pts.append(Vector3(inner, y, z))
			pts.append(Vector3(outer, y, z))
		if not ok:
			continue
		# pts: [inner0, outer0, inner1, outer1], bottom edge then top edge
		var cols := Color(SMEAR, SMEAR.a * (1.0 if b[0] < 0.5 else 0.7))
		if side > 0.0:
			k.quad(pts[0], pts[1], pts[3], pts[2], cols)
		else:
			k.quad(pts[1], pts[0], pts[2], pts[3], cols)

# ---------- state ----------

## Redraws to match CabinDirt (a level change, a fuel stop, a clean, a beer).
func _refresh() -> void:
	_seen_revision = CabinDirt.revision
	var lv := CabinDirt.level(kind)
	var n_rec := CabinDirt.receipts(kind)
	for i in receipt_nodes.size():
		receipt_nodes[i].visible = lv >= CabinDirt.LIVED_IN and i < n_rec
	dust.visible = lv >= CabinDirt.MESSY
	stain.visible = lv >= CabinDirt.MESSY
	smear.visible = lv >= CabinDirt.FILTHY
	bag.visible = lv >= CabinDirt.FILTHY
	var want := CabinDirt.cans(kind)
	if want == 0:
		sim.clear()
	elif sim.count == 0 or want < sim.count:
		sim.scatter(want)
	elif want > sim.count:
		sim.scatter(want)   # a car that came back with more cans than it holds
	_place_cans()

## A beer was finished on L: its can goes on the floor and is counted.
func beer_finished() -> void:
	CabinDirt.beer_drunk(kind)
	_seen_revision = CabinDirt.revision
	var lv := CabinDirt.level(kind)   # a level may have just come up
	for i in receipt_nodes.size():
		receipt_nodes[i].visible = lv >= CabinDirt.LIVED_IN and i < CabinDirt.receipts(kind)
	dust.visible = lv >= CabinDirt.MESSY
	stain.visible = lv >= CabinDirt.MESSY
	smear.visible = lv >= CabinDirt.FILTHY
	bag.visible = lv >= CabinDirt.FILTHY
	# dropped by the seat edge, with a little toss toward the door
	sim.add(lerpf(sim.x0, sim.x1, 0.8), sim.z1, 0.25, -0.2)
	_place_cans()

func _place_cans() -> void:
	for i in CanSim.MAX_CANS:
		var holder := can_nodes[i]
		holder.visible = i < sim.count
		if i >= sim.count:
			continue
		holder.position = Vector3(sim.px[i], floor_top + IdleProps.CAN_R, sim.pz[i])
		holder.rotation = Vector3(0.0, sim.yaw[i], 0.0)
		(holder.get_child(0) as Node3D).basis = Basis(Vector3.BACK, PI / 2.0) * Basis(Vector3.UP, sim.roll[i])

# ---------- clinks ----------

func _on_contact(strength: float) -> void:
	play_clink(strength)

## One clink at `strength` 0..1, unless MAX_CLINKS are already ringing.
func play_clink(strength: float) -> bool:
	var ringing := 0
	var free := -1
	for i in 2:
		if _clink_end[i] > _clock:
			ringing += 1
		elif free < 0:
			free = i
	if ringing >= MAX_CLINKS or free < 0:
		clinks_dropped += 1
		return false
	_clink_end[free] = _clock + CLINK_SECS
	clinks_played += 1
	max_simultaneous = maxi(max_simultaneous, ringing + 1)
	var p := _clink_players[free]
	p.stream = _clink_stream(free + (clinks_played & 1) * 2)
	p.volume_db = -26.0 + 16.0 * clampf(strength, 0.0, 1.0)
	p.pitch_scale = 0.94 + 0.12 * _frand()
	if p.is_inside_tree():
		p.play()
	return true

## Clinks ringing at the clock's now (tests).
func clinks_ringing() -> int:
	var n := 0
	for e in _clink_end:
		if e > _clock:
			n += 1
	return n

func _frand() -> float:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return float(_rng % 10007) / 10006.0

static var _clink_wavs := {}
## A can on can, or on the plastic: short, ringing, thin. Four variants.
static func _clink_stream(variant: int) -> AudioStreamWAV:
	if _clink_wavs.has(variant):
		return _clink_wavs[variant]
	var r := 44100.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant
	var f0 := 2250.0 + 230.0 * float(variant)
	var ratios := [1.0, 1.59, 2.33, 3.41]
	var amps := [1.0, 0.6, 0.38, 0.22]
	var decays := [24.0, 36.0, 55.0, 85.0]
	var n := int(CLINK_SECS * r)
	var s := PackedFloat32Array()
	s.resize(n)
	var click := AudioDsp.bp(r, 5200.0, 2.0)
	for i in n:
		var t := float(i) / r
		var v := 0.0
		for m in 4:
			v += float(amps[m]) * sin(TAU * f0 * float(ratios[m]) * t) * exp(-t * float(decays[m]))
		v += click.step(rng.randf_range(-1.0, 1.0)) * 2.0 * exp(-t * 900.0)
		s[i] = v
	var wav := AudioDsp.to_wav(AudioDsp.normalise(s, 0.85), int(r), false)
	_clink_wavs[variant] = wav
	return wav

# ---------- per tick ----------

func _physics_process(delta: float) -> void:
	_clock += delta
	if player == null or delta <= 0.0:
		return
	var lv: Vector3 = player.local_velocity
	var a := Vector3.ZERO
	if _have_prev:
		a = (lv - _prev_lv) / delta
	_prev_lv = lv
	_have_prev = true
	if CabinDirt.revision != _seen_revision:
		_refresh()
	# only while it matters: the cockpit view, or a can still on the move
	var in_cockpit := bool(frame.get("cockpit"))
	if sim.count == 0 or (sim.asleep and not in_cockpit and absf(a.x) < CanSim.STATIC_A and absf(a.z) < CanSim.STATIC_A):
		return
	# vertical jolts over rough road, low-passed; a jolt is more than ~6 m/s^2 of hop
	var jolt := clampf((absf(a.y) - 6.0) / 12.0, 0.0, 1.0) * clampf(player.current_speed() / 8.0, 0.0, 1.0)
	_rough = maxf(jolt, _rough * exp(-6.0 * delta))
	var was_asleep := sim.asleep
	sim.step(delta, clampf(a.x, -20.0, 20.0), clampf(a.z, -20.0, 20.0), _rough)
	if not (was_asleep and sim.asleep):
		_place_cans()

func _process(delta: float) -> void:
	# the receipts lift a little in the wind with the window down
	var shown := 0
	for r in receipt_nodes:
		if r.visible:
			shown += 1
	if shown == 0 or player == null:
		return
	var window := float(frame.get("window"))
	var speed := absf(player.current_speed())
	if window < FLUTTER_WINDOW or speed < 3.0:
		if _flutter_t > 0.0:
			_flutter_t = 0.0
			for i in receipt_nodes.size():
				receipt_nodes[i].basis = _receipt_base[i]
		return
	_flutter_t += delta
	var amp := clampf(speed / 30.0, 0.0, 1.0)
	for i in receipt_nodes.size():
		if not receipt_nodes[i].visible:
			continue
		var w := sin(_flutter_t * (8.0 + float(i) * 1.7) + float(i)) * 0.09 * amp
		var v := sin(_flutter_t * (6.0 + float(i) * 2.3) + float(i) * 2.0) * 0.05 * amp
		receipt_nodes[i].basis = _receipt_base[i] * Basis(Vector3.BACK, w) * Basis(Vector3.RIGHT, v)
