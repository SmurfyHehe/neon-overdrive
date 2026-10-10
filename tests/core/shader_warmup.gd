extends SceneTree

# Shader warm-up (graphics setup, 2026-10-10). Boots Game.tscn, runs the
# splash's warm-up (scripts/core/shader_warmup.gd) and checks
# - it finds hidden things to draw (flames, smoke, cockpit parts) and draws a
#   stand-in for each
# - it finishes on its own, well inside its time limit, and reports busy()
#   false afterwards
# - it leaves nothing behind: no stand-in holder under the camera, no node
# - the splash would wait for it (busy() is true while it runs)
# Headless there is no renderer, so the pipeline count stays 0; with the real
# renderer the line also says how many pipelines it compiled. Exit 1 on failure.
# Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/core/shader_warmup.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const ShaderWarmup := preload("res://scripts/core/shader_warmup.gd")

var game: Node
var frame := 0
var warm: Node
var was_busy := false
var t := 0.0
var fails := 0

func _initialize() -> void:
	game = Harness.boot(self, 4, 150.0, 7)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _process(delta: float) -> bool:
	frame += 1
	if frame < 30:
		return false
	if warm == null and not was_busy:
		warm = ShaderWarmup.new()
		game.add_child(warm)
		return false
	if ShaderWarmup.busy():
		was_busy = true
		t += delta
		if t > ShaderWarmup.MAX_SECS + 2.0:
			_check(false, "the warm-up ends inside its time limit")
			quit(1)
			return true
		return false
	var last: Dictionary = ShaderWarmup.last
	print("shader_warmup: %d stand-ins, %d pipelines, %.2f s" % [last.proxies, last.pipelines, last.secs])
	_check(was_busy, "busy() is true while it runs")
	_check(int(last.proxies) > 0, "hidden meshes were found and drawn")
	_check(float(last.secs) < ShaderWarmup.MAX_SECS, "it settled before the time limit")
	_check(root.find_child("ShaderWarmupProxies", true, false) == null, "the stand-ins are gone")
	_check(not is_instance_valid(warm) or warm.is_queued_for_deletion(), "the node freed itself")
	print("PASS shader_warmup" if fails == 0 else "FAILED shader_warmup (%d)" % fails)
	quit(0 if fails == 0 else 1)
	return true
