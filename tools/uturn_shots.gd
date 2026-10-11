extends SceneTree

# Signed U-turns, shots (T1, 2026-10-11): boots Game.tscn on the loop at night
# and, for the first signed U-turn and the first emergency crossover of the
# lap, photographs the approach from the driver's seat of the inner lane:
# the U-turn from 200 m, 100 m and 40 m out (own side), the same opening from
# the oncoming side at 200 m and 40 m, and the crossover from 200 m and 40 m.
#
# Env: UTURN_SHOT_DIR (output folder, required), NEON_CLOCK (default 23:30),
# NEON_ROAD_SEED as in the game.
# Run (real window):
#   Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy -s res://tools/uturn_shots.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const RoadMap := preload("res://scripts/world/road_map.gd")
const SETTLE := 140
const LANE_X := RoadChunkBuilder.MEDIAN_GAP + 0.5 * RoadChunkBuilder.LANE_W
const EYE_Y := 1.25

var game: Node
var cam: Camera3D
var frame := 0
var wait_until := 120
var out_dir := ""
var shots: Array = []   # [label, s, own_side]
var idx := 0
var hud_hidden := false

func _initialize() -> void:
	OS.set_environment("NEON_COCKPIT", "0")
	OS.set_environment("NEON_TEST", "1")
	OS.set_environment("NEON_CITY_LIGHTS", "1")
	if OS.get_environment("NEON_CLOCK") == "":
		OS.set_environment("NEON_CLOCK", "23:30")
	out_dir = OS.get_environment("UTURN_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = Harness.boot(self, 0, 300.0, 7)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 1200.0
	root.add_child(cam)

## Builds the shot list once the game has set the road up (RoadMap, barriers).
func _plan() -> void:
	var u := -1
	var e := -1
	for c in range(9, RoadMap.period):
		var k := RoadBarriers.gap_kind(c)
		if u < 0 and k == "uturn" and c > 8:
			u = c
		if e < 0 and k == "emergency" and c > 8:
			e = c
	var L := RoadChunkBuilder.CHUNK_LEN
	# the opening runs z -15 .. -40 of its chunk: s = c * L + 15 .. c * L + 40.
	# The advance sign stands 200 m before its near end, so "200 m" is level
	# with the sign; the 245 m shot is the approach to it. The painted arrows
	# are 100 m and 40 m out, shot from 12 m short of them.
	var own0 := float(u) * L + 15.0
	for d in [245.0, 200.0, 112.0, 52.0, 22.0]:
		shots.append(["uturn_own_%03dm" % int(d), own0 - d, true])
	var onc0 := float(u) * L + 40.0
	for d in [245.0, 200.0, 112.0, 52.0, 22.0]:
		shots.append(["uturn_oncoming_%03dm" % int(d), onc0 + d, false])
	if e >= 0:
		var em0 := float(e) * L + 15.0
		for d in [200.0, 60.0, 25.0]:
			shots.append(["emergency_own_%03dm" % int(d), em0 - d, true])
		for d in [60.0, 25.0]:
			shots.append(["emergency_oncoming_%03dm" % int(d), float(e) * L + 40.0 + d, false])
	print("uturn chunk %d, emergency chunk %d, %d shots" % [u, e, shots.size()])

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
	var own: bool = shot[2]
	var z := float(RoadFrame.origin_index) * RoadChunkBuilder.CHUNK_LEN - float(shot[1])
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.freeze = true
	player.visible = false
	var pose := RoadFrame.pose(LANE_X if own else -LANE_X, 0.6, z, 0.0 if own else PI)
	player.global_transform = pose
	player.reset_physics_interpolation()
	cam.global_transform = RoadFrame.pose(LANE_X if own else -LANE_X, EYE_Y, z, 0.0 if own else PI)
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
	print("shot %s at s=%.0f (origin %d)" % [shot[0], shot[1], RoadFrame.origin_index])
	idx += 1
	wait_until = frame + SETTLE
	return false

func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)
