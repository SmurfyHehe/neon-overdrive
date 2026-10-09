extends SceneTree

# CPU cost probe (frame-rate pass, 2026-10-08): wall-clock ms per rendered
# frame of the real game, headless, so it is the CPU side only.
#
# --fixed-fps 60 makes every frame exactly one 60 fps frame of game time: two
# 120 Hz physics ticks plus one _process. Headless runs those back to back with
# no pacing and no GPU, so the gap between two frames is what the CPU spends on
# one frame. Below 16.7 ms the CPU can hold 60 fps; the GPU is measured
# separately (benchmark.bat).
#
# The game is the default one: 16 traffic cars at the 150 m draw distance, the
# player held in lane 3 at up to 120 km/h by the test lane driver.
#
# PROBE_CARS / PROBE_DETAIL override the traffic; PROBE_SECS the measured time.
#
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path . -s res://tests/core/perf_probe.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")

const WARMUP_FRAMES := 120
var measure_frames := 60 * 20

var game: Node
var frame := 0
var last_us := 0
var samples := PackedFloat64Array()

func _initialize() -> void:
	var cars := int(_env("PROBE_CARS", str(TrafficSettings.CAR_COUNT_DEFAULT)))
	var detail := float(_env("PROBE_DETAIL", str(TrafficSettings.DETAIL_DEFAULT)))
	measure_frames = int(float(_env("PROBE_SECS", "20")) * 60.0)
	game = Harness.boot(self, cars, detail, 777)
	process_frame.connect(_tick)

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _tick() -> void:
	frame += 1
	if frame == 2:
		var p: Vehicle = game.get("player")
		p.set("driver", Harness.lane_driver(Harness.lane_x(3), 1.0, 33.0))
	var now := Time.get_ticks_usec()
	if frame > WARMUP_FRAMES:
		samples.append((now - last_us) / 1000.0)
	last_us = now
	if samples.size() >= measure_frames:
		_report()
		quit(0)

func _report() -> void:
	var s := Array(samples)
	s.sort()
	var n := s.size()
	var sum := 0.0
	for x in s:
		sum += x
	var p: Vehicle = game.get("player")
	print("PROBE cars=%d detail=%d ticks=%d  cpu ms/frame mean=%.2f p50=%.2f p95=%.2f p99=%.2f  speed=%.0f km/h  bodies=%d pairs=%d islands=%d" % [
		TrafficSettings.car_count, roundi(TrafficSettings.detail_distance), Engine.physics_ticks_per_second,
		sum / n, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], p.linear_velocity.length() * 3.6,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
