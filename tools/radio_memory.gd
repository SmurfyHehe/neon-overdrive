extends SceneTree

# Radio memory probe (2026-10-10): builds a RadioManager on its own, tunes each
# music station in turn and prints the engine's static memory (OS.get_static_
# memory_usage) after the tracks have settled, plus the longest frame while tuning.
# Used for the "load every song at once" fix: run it before and after.
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tools/radio_memory.gd

const SETTLE_FRAMES := 240

var radio: RadioManager
var steps: Array[int] = [-1, 0, 1, 3, 0, -1]
var step := 0
var frames := 0
var max_dt := 0.0
var base_mb := 0.0

func _initialize() -> void:
	radio = RadioManager.new()
	root.add_child(radio)

func _mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0

func _process(delta: float) -> bool:
	if frames == 0 and step == 0:
		base_mb = _mb()
	frames += 1
	max_dt = maxf(max_dt, delta)
	if frames == 2:
		radio.tune_to(steps[step])
	if frames >= SETTLE_FRAMES:
		print("radio_memory: station %2d  now_playing %-22s  static %.1f MB  (+%.1f)  worst frame %.0f ms" % [
				steps[step], radio.now_playing, _mb(), _mb() - base_mb, max_dt * 1000.0])
		step += 1
		frames = 0
		max_dt = 0.0
		if step >= steps.size():
			quit(0)
			return true
	return false
