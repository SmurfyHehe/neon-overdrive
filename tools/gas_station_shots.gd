extends SceneTree

# Gas stations on Loop 1 from the driver's seat (2026-10-11): District 3, both
# directions, so the fake GAS building signs and the two real stations (own
# side 2,225 m, oncoming side 1,825 m) can be compared before and after.
# Needs the real renderer (no --headless). Writes PNGs to
# <out dir>/<tag>_<view>.png.
#
#   <godot> --path . --audio-driver Dummy -s res://tools/gas_station_shots.gd -- <tag> [out dir]
#
# NEON_CURVES=0 NEON_HILLS=0 NEON_TRAFFIC=0 NEON_POLICE=0 keep the road straight and empty.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const SaveDirector := preload("res://scripts/save/save_director.gd")

## [name, metres along the loop, road-space x, yaw]: x +1.9 past the median
## gap is the own lane (driving up the s numbers), x -1.9 the oncoming lane
## (driving down them, yaw PI).
const VIEWS := [
	["up_1700", 1700.0, 1, 0.0],
	["up_1765_before_oncoming_station", 1765.0, 1, 0.0],
	["up_2165_before_own_station", 2165.0, 1, 0.0],
	["up_2300_past_station", 2300.0, 1, 0.0],
	["down_2285_before_oncoming_side", 2285.0, -1, PI],
	["down_1885_before_station", 1885.0, -1, PI],
	["down_1760_past_station", 1760.0, -1, PI],
]

var game: Node

func _initialize() -> void:
	game = Harness.boot(self, 0, 300.0, 3)
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var tag := "shot"
	var out := "C:/SmurfyHehe/review-shots/gas-1"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = args[0]
	if args.size() > 1:
		out = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	var p: PlayerCar = game.get("player")
	var gap := RoadChunkBuilder.MEDIAN_GAP + 1.9
	for v in VIEWS:
		var s: float = v[1]
		var x: float = gap * float(v[2])
		var z := float(RoadFrame.origin_index) * RoadFrame.L - s
		var y := RoadFrame.unroll(p.global_position).y
		var t := RoadFrame.pose(x, y, z, float(v[3]))
		game.saver.restore_car(p, {"xform": SaveDirector.xform_to_array(t), "lin_vel": [0.0, 0.0, 0.0], "ang_vel": [0.0, 0.0, 0.0], "gear": 1})
		game.call("_update_chunk_pool", z)
		game.call("flush_rebuilds")
		for i in 12:
			p.set("linear_velocity", Vector3.ZERO)
			await process_frame
		# the road frame may have moved its origin: aim from where the car is now
		z = float(RoadFrame.origin_index) * RoadFrame.L - s
		cam.global_transform = RoadFrame.pose(x, y + 1.25, z, float(v[3]))
		cam.make_current()
		for i in 6:
			await process_frame
		var path := "%s/%s_%s.png" % [out, tag, v[0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("gas_station_shots: ", path)
	quit(0)
