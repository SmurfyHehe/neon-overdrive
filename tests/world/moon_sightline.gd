extends SceneTree
# How often is the moon in the clear? Parks the car on every chunk of road
# runs 0..MOON_RUNS-1 (districts.gd: 16 chunks per run) and casts a ray from
# the chase camera's place towards the sky on a grid of elevations and
# azimuths (degrees off world -Z, both sides). Prints, per district, the share
# of stops where nothing solid is in the way, then for tonight's real moon
# path (NEON_NIGHT, at 8 p.m., 1 a.m. and 6 a.m.): sky open, inside the parked
# chase frame, both.
# Measurement only: it always exits 0.
# Run (headless is fine, the rays only need the collision bodies):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/world/moon_sightline.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const Districts := preload("res://scripts/world/districts.gd")
const ELS := [13.0, 16.0, 19.0, 22.0, 25.0, 30.0]
const AZS := [0.0, 10.0, 17.0, 25.0, 33.0]
const PATH_T := [0.0, 0.5, 1.0]
const WAIT := 4            # frames parked on a chunk before the rays
const CAM_BACK := 5.5      # the chase camera's place behind and above the car
const CAM_UP := 1.85

var game: Node
var frame := 0
var parked_frame := 0
var stops := 0
var last_idx := -1
var end_idx := 0
var seen := {}     # district -> stops
var clear := {}    # district -> {key -> clear count}
var headings: PackedFloat32Array = []
var grades: PackedFloat32Array = []

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 7)
	var runs := OS.get_environment("MOON_RUNS")
	end_idx = (int(runs) if runs.is_valid_int() else 12) * Districts.RUN

func _chunk_idx(car: Node3D) -> int:
	var z: float = RoadFrame.unroll(car.global_position).z
	return int(floor(-z / RoadChunkBuilder.CHUNK_LEN)) + int(game.origin_index)

static func _dir(el_deg: float, az_deg: float) -> Vector3:
	var el := deg_to_rad(el_deg)
	var az := deg_to_rad(az_deg)
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))

func _is_clear(car: RigidBody3D, from: Vector3, d: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from + d * 2000.0)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [car.get_rid()]
	return car.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _process(_delta: float) -> bool:
	frame += 1
	var car: RigidBody3D = game.get("player")
	if frame < 20:
		return false
	if frame == 20:
		car.freeze = true
		parked_frame = frame
	car.linear_velocity = Vector3.ZERO
	if frame - parked_frame < WAIT:
		return false
	var idx := _chunk_idx(car)
	if idx != last_idx:
		last_idx = idx
		_sample(car, Districts.name_at(idx))
	if idx >= end_idx:
		_report()
		quit(0)
		return true
	# On to the next chunk, set down on the road and facing along it.
	var u := RoadFrame.unroll(car.global_position)
	car.global_transform = RoadFrame.pose(u.x, 0.6, u.z - RoadChunkBuilder.CHUNK_LEN, 0.0)
	parked_frame = frame
	return false

func _sample(car: RigidBody3D, district: String) -> void:
	var from := car.global_position + car.global_basis * Vector3(0.0, CAM_UP, CAM_BACK)
	if not clear.has(district):
		clear[district] = {}
		seen[district] = 0
	seen[district] += 1
	stops += 1
	var night := int(game.night_clock.night) if game.get("night_clock") != null else 1
	var tally: Dictionary = clear[district]
	for el in ELS:
		for az in AZS:
			var n := 0.0
			for side in ([1.0] if az == 0.0 else [-1.0, 1.0]):
				if _is_clear(car, from, _dir(el, az * side)):
					n += 1.0 if az == 0.0 else 0.5
			var key := "%d/%d" % [int(el), int(az)]
			tally[key] = float(tally.get(key, 0.0)) + n
	var fwd := -car.global_basis.z
	headings.append(rad_to_deg(atan2(-fwd.x, -fwd.z)))
	grades.append(rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))))
	for t in PATH_T:
		var d := NightSky.moon_direction(night, t)
		var open := _is_clear(car, from, d)
		# In the parked chase frame? Its top edge is ~23.8 degrees above the
		# car's own level and it is ~45 degrees wide each side (58 degree
		# vertical FOV at 16:9); the moon's half-width is 1.25.
		var l := car.global_basis.inverse() * d
		var framed := l.z < 0.0 and absf(rad_to_deg(atan2(l.x, -l.z))) < 43.0 and rad_to_deg(asin(clampf(l.y, -1.0, 1.0))) < 22.6
		for k in [["path@%.1f", open], ["frame@%.1f", framed], ["seen@%.1f", open and framed]]:
			if k[1]:
				var key: String = k[0] % t
				tally[key] = float(tally.get(key, 0.0)) + 1.0

func _report() -> void:
	print("moon_sightline: %d stops, share of stops with a clear line to the sky (percent)" % stops)
	var head := "  el\\az      "
	for az in AZS:
		head += "%5d" % int(az)
	for district in clear:
		print(" %s (%d stops)" % [district, seen[district]])
		print(head)
		for el in ELS:
			var row := "  el %2d      " % int(el)
			for az in AZS:
				row += "%5d" % int(round(100.0 * float(clear[district].get("%d/%d" % [int(el), int(az)], 0.0)) / float(seen[district])))
			print(row)
		for label in [["path", "tonight's moon, sky open:      "], ["frame", "tonight's moon, in the frame:  "], ["seen", "tonight's moon, open and framed:"]]:
			var p: String = "  " + label[1]
			for t in PATH_T:
				p += " t=%.1f %d%%" % [t, int(round(100.0 * float(clear[district].get("%s@%.1f" % [label[0], t], 0.0)) / float(seen[district])))]
			print(p)
	var hs := Array(headings)
	var gs := Array(grades)
	print(" road heading off world -Z: %.1f to %.1f degrees; grade: %.1f to %.1f degrees" % [hs.min(), hs.max(), gs.min(), gs.max()])
