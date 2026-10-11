extends SceneTree

# Ring sites, shots (R1 + R2, 2026-10-11): boots Game.tscn on the loop at
# night and photographs exit 3 (a highway district, a stop) from the driver's
# seat: the 1 km and 400 m gantries, 200 m and 40 m before the gore, on the
# ramp, round the ring, from a bridge looking down the road, the way back
# down, and the ring seen from the road 300 m, 150 m and 50 m before it.
#
# Env: RING_SHOT_DIR (output folder, required), RING_SHOT_EXIT (ring number,
# default 3), NEON_CLOCK (default 23:30), NEON_ROAD_SEED as in the game.
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/ring_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const RoadRamps := preload("res://scripts/world/road_ramps.gd")
const SETTLE := 140
const LANE_X := 11.6     # the outside lane
const EYE_Y := 1.25

var game: Node
var cam: Camera3D
var frame := 0
var wait_until := 120
var out_dir := ""
var shots: Array = []   # [label, x across, height above the road, s, yaw, (pitch)]
var idx := 0
var hud_hidden := false

func _initialize() -> void:
	OS.set_environment("NEON_COCKPIT", "0")
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "23:30")
	out_dir = OS.get_environment("RING_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = Harness.boot(self, 0, 300.0, 7)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 1200.0
	root.add_child(cam)

func _plan() -> void:
	var number := int(OS.get_environment("RING_SHOT_EXIT")) if OS.get_environment("RING_SHOT_EXIT").is_valid_int() else 3
	var centre := -1.0
	for r in RoadMap.rings():
		if int(r.number) == number:
			centre = float(r.s)
	if centre < 0.0:
		print("no ring site numbered %d" % number)
		quit(1)
		return
	var gore := centre - RoadMap.RING_GORE
	var slip := RoadRamps.X_LANE + RoadRamps.HALF
	shots.append(["gantry_1km", LANE_X - 3.2, EYE_Y, gore - 1000.0 - 38.0, 0.0])
	shots.append(["gantry_400m", LANE_X - 3.2, EYE_Y, gore - 400.0 - 38.0, 0.0])
	shots.append(["gore_200m_before", LANE_X, EYE_Y, gore - 200.0, 0.0])
	shots.append(["gore_40m_before", slip, EYE_Y, gore - 40.0, 0.0])
	shots.append(["nose", slip, EYE_Y, gore + 8.0, 0.0])
	for v in [140.0, 90.0]:
		shots.append(["ramp_%03dm_to_go" % int(v), RoadRamps.x_at(v), RoadRamps.y_at(v) + EYE_Y, centre - v, 0.0])
	var top: float = RoadRamps.RAMP_H + EYE_Y
	var mid: float = RoadRamps.X_TOP
	shots.append(["ring_arriving", mid, top, centre - 32.0, 0.0])
	# on the ring: at an angle round it from the +x point, facing the way round
	for deg in [20.0, 80.0, 170.0, 250.0, 330.0]:
		var a := deg_to_rad(deg)
		shots.append(["ring_at_%03d_deg" % int(deg), mid * cos(a), top, centre + mid * sin(a), a])
	shots.append(["bridge_looking_down_the_road", -6.0, top + 0.4, centre + mid, PI, -0.22])
	shots.append(["ring_leaving", mid, top, centre + 4.0, 0.0])
	shots.append(["ramp_down", RoadRamps.x_at(120.0), RoadRamps.y_at(120.0) + EYE_Y, centre + 120.0, 0.0])
	shots.append(["merge", slip, EYE_Y, centre + 185.0, 0.0])
	shots.append(["from_the_road_300m_before", LANE_X - 6.4, EYE_Y, centre - 300.0, 0.0])
	shots.append(["from_the_road_150m_before", LANE_X - 6.4, EYE_Y, centre - 150.0, 0.0])
	shots.append(["from_the_road_050m_before", LANE_X - 6.4, EYE_Y, centre - 50.0, 0.0])
	shots.append(["under_the_ring", LANE_X - 6.4, EYE_Y, centre - 12.0, 0.0])
	shots.append(["from_the_other_side", -(LANE_X - 3.2), EYE_Y, centre + 120.0, PI])
	print("exit %d at %.0f m, %d shots" % [number, centre, shots.size()])

func _process(_delta: float) -> bool:
	frame += 1
	var player: PlayerCar = game.get("player")
	if shots.is_empty() and frame >= 5 and RoadMap.is_loop():
		_plan()
	if shots.is_empty():
		return false
	if idx >= shots.size():
		print("done")
		quit(0)
		return true
	var shot: Array = shots[idx]
	var z := float(RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - float(shot[3])
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.freeze = true
	player.visible = false
	# the car stands on the road beside the camera, so the chunk pool is there
	player.global_transform = RoadFrame.pose(signf(float(shot[1])) * LANE_X, 0.6, z, 0.0)
	player.reset_physics_interpolation()
	cam.global_transform = RoadFrame.pose(float(shot[1]), float(shot[2]), z, float(shot[4]))
	if shot.size() > 5:
		cam.global_transform = cam.global_transform * Transform3D(Basis(Vector3.RIGHT, float(shot[5])), Vector3.ZERO)
	cam.current = true
	if frame < wait_until:
		return false
	if not hud_hidden:
		_hide_hud(root)
		hud_hidden = true
		wait_until = frame + 10
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%02d_%s.png" % [idx, shot[0]]))
	print("shot %s at s=%.0f (origin %d)" % [shot[0], shot[3], RoadFrame.origin_index])
	idx += 1
	wait_until = frame + SETTLE
	return false

func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
