extends SceneTree

# Listen pack for the sound fixes (2026-10-08, sound research section 5: "each
# audio PR should also render a short listen pack"). Not a pass/fail test: it
# boots the game, sweeps each new sound through its range on its own (other
# buses muted, the radio always muted), records the real mix off the Master
# bus and writes one WAV per clip, plus a list of what each one is.
#
# The car sounds are driven through CarAudio.forced / CrashAudio.impact() so
# every clip is the same every run; the shift clip is a real drive.
#
# Run (works on the silent Dummy driver too: it still mixes; takes ~2 min):
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/sound_listen_pack.gd
# Set LISTEN_DIR=<folder> to choose where the clips go
# (default user://listen_pack_sound_fixes).

const GAP := 0.6   # s of unrecorded settling between clips

# [file name, seconds, description]
const CLIPS := [
	["01_wind_chase_0-245kmh", 10.0, "Wind only, chase view, 0 to 245 km/h: buffet first, rush takes over, mirror whistle from ~140 km/h, gusts."],
	["02_wind_cockpit_window_up_0-245kmh", 10.0, "Wind only, cockpit, window closed, same sweep: sealed hush, seal whistle from ~100 km/h."],
	["03_window_down_at_126kmh", 10.0, "Cockpit at 126 km/h, wind + road, window from closed to fully open: cracked throb, then the full buffet."],
	["04_road_chase_0-215kmh", 10.0, "Road roar only, 0 to 215 km/h: louder and brighter, barely higher."],
	["05_tyre_scrub", 7.0, "Scrub (understeer) at 72 km/h: fade in on both sides, then left only, right only."],
	["06_tyre_squeal", 7.0, "Squeal (drift) at 72 km/h: fade in on both sides, then left only, right only."],
	["07_tyre_wheelspin", 7.0, "Wheelspin at 30 km/h: fade in on both sides, then left only, right only."],
	["08_tyre_lockup", 7.0, "Lock-up at 72 km/h: fade in on both sides, then left only, right only."],
	["09_tyre_chirps", 4.0, "Three launch chirps (wheelspin snapping on)."],
	["10_shifts_real_drive", 16.0, "Real drive, engine on: full throttle through the gears, then hard braking down through them."],
	["11_crashes", 9.0, "Hits every second: tap, tap, thud, thud, crunch, crunch, crunch + glass, crunch + glass (random variants)."],
	["12_scrape_0-108kmh", 7.0, "Metal scrape along a wall, 0 to 108 km/h."],
	["13_effects_slider", 8.0, "Drift squeal + wind at 144 km/h with the Effects slider at 100%, 50%, 25%, 0%."],
	["14_highway_joints_50-100-150kmh", 9.0, "Road + highway joints (da-dum every 15 m) at 50, 100 and 150 km/h, 3 s each."],
	["15_bridge_deck_hum", 7.0, "Road at 72 km/h, onto a steel bridge deck for 4 s and off again."],
	["16_manholes", 5.0, "Road at 90 km/h, two manhole covers (front then rear wheel each)."],
	["17_radio_tunnel_and_bridge", 14.0, "Radio only, cockpit: clear 3 s, into a tunnel (signal fades, drops, hiss), out again, then under a bridge (breaking up)."],
	["18_engine_cooling_ticks", 25.0, "Hot engine switched off: 15 s just after stopping, then 10 s from 40 s later (slower, quieter)."],
]

var game: Node
var p: PlayerCar
var car: CarAudio
var crash: CrashAudio
var persp: PerspectiveAudio
var radio: RadioManager
var drive: DrivelineAudio
var record: AudioEffectRecord
var dir := ""
var clip := -1
var clip_t := 0.0
var gap_t := 0.0
var recording := false
var throttle := 0.0
var brake := 0.0
var fired := {}
var quit_in := 0
var manifest := PackedStringArray()

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CURVES", "0")
	OS.set_environment("NEON_HILLS", "0")
	dir = OS.get_environment("LISTEN_DIR")
	if dir == "":
		dir = "user://listen_pack_sound_fixes"
	DirAccess.make_dir_recursive_absolute(dir)
	record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.handbrake_input = 0.0
	c.steering_input = TrafficCar.lane_steer(c, 0.0, -1.0, 2.5) if c.current_speed() > 2.0 else 0.0

## Mutes these buses and unmutes the rest; the radio (Music) stays muted
## unless `radio` is true.
func _mute(buses: Array, radio_on := false) -> void:
	for b in [&"Engine", &"Tires", &"World", &"Music", &"UI"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, (b == &"Music" and not radio_on) or b in buses)

func _process(delta: float) -> bool:
	if quit_in > 0:
		quit_in -= 1
		if quit_in == 0:
			quit(0)
		return false
	if game == null:
		return false
	if p == null:
		p = game.get("player")
		if p == null:
			return false
		p.driver = _drive
		for c in p.get_children():
			if c is CarAudio: car = c
			if c is CrashAudio: crash = c
			if c is DrivelineAudio: drive = c
		persp = (game.get("camera") as ChaseCamera).perspective
		radio = game.get("radio")
		radio.next_station()   # tune now, so the tracks have loaded by the radio clip
		gap_t = 1.5   # let the game settle first
		return false
	if not recording:
		gap_t -= delta
		if gap_t <= 0.0:
			_start(clip + 1)
		return false
	clip_t += delta
	_run(CLIPS[clip][0], clip_t, CLIPS[clip][1])
	if clip_t >= CLIPS[clip][1]:
		_stop()
	return false

func _start(i: int) -> void:
	if i >= CLIPS.size():
		_done()
		return
	clip = i
	clip_t = 0.0
	fired.clear()
	recording = true
	record.set_recording_active(true)

func _stop() -> void:
	record.set_recording_active(false)
	recording = false
	var wav := record.get_recording()
	var path := dir.path_join(CLIPS[clip][0] + ".wav")
	var err := wav.save_to_wav(path) if wav != null else FAILED
	print("%-36s %4.1f s -> %s" % [CLIPS[clip][0], CLIPS[clip][1], "ok" if err == OK else "error %d" % err])
	manifest.append("%s.wav  (%.0f s)  %s" % [CLIPS[clip][0], CLIPS[clip][1], CLIPS[clip][2]])
	# back to neutral for the next clip
	car.forced = {"speed": 0.0, "on_road": 0.0}
	crash.forced_scrape_speed = -1.0
	persp.set_cockpit(false)
	persp.window = 0.0
	AudioSettings.set_volume("Effects", 1.0)
	radio.forced_reception = -1.0
	p.engine_running = true
	throttle = 0.0
	brake = 0.0
	gap_t = GAP

## One clip, at `t` seconds of `dur`.
func _run(name: String, t: float, dur: float) -> void:
	var k := clampf(t / (dur - 1.0), 0.0, 1.0)  # a sweep, holding the end for the last second
	match name.substr(0, 2):
		"01":
			_mute([&"Engine", &"Tires"])
			persp.set_cockpit(false)
			car.forced = {"speed": 68.0 * k, "on_road": 0.0}
		"02":
			_mute([&"Engine", &"Tires"])
			persp.set_cockpit(true)
			car.forced = {"speed": 68.0 * k, "on_road": 0.0}
		"03":
			_mute([&"Engine"])
			persp.set_cockpit(true)
			persp.window = clampf((t - 1.0) / (dur - 2.0), 0.0, 1.0)
			car.forced = {"speed": 35.0, "on_road": 1.0}
		"04":
			_mute([&"Engine", &"World"])
			persp.set_cockpit(false)
			car.forced = {"speed": 60.0 * k, "on_road": 1.0}
		"05", "06", "07", "08":
			_mute([&"Engine", &"World"])
			var kind: String = {"05": "scrub", "06": "squeal", "07": "spin", "08": "lock"}[name.substr(0, 2)]
			var level := clampf(t / 3.0, 0.0, 1.0)
			var left := level if t < 4.5 else 0.0
			var right := level if t < 3.0 or (t >= 4.5 and t < 6.0) else 0.0
			if t >= 6.0:
				left = 0.0
				right = 0.0
			car.forced = {"speed": 8.0 if kind == "spin" else 20.0, "on_road": 0.0, kind + "_l": left, kind + "_r": right}
		"09":
			_mute([&"Engine", &"World"])
			var on := fmod(t, 1.3) < 0.5 and t < 3.9
			car.forced = {"speed": 0.0, "on_road": 0.0, "spin_l": 1.0 if on else 0.0, "spin_r": 1.0 if on else 0.0}
		"10":
			_mute([])
			car.forced = {}
			throttle = 1.0 if t < 10.0 else 0.0
			brake = 0.0 if t < 10.0 else 0.8
		"11":
			_mute([&"Engine", &"World"])
			car.forced = {"speed": 0.0, "on_road": 0.0}
			var hits := [2.0, 2.0, 5.0, 5.0, 9.0, 9.0, 14.0, 14.0]
			var i := int(t)
			if t >= 0.5 and i < hits.size() and not fired.has(i):
				fired[i] = true
				crash.impact(hits[i])
		"12":
			_mute([&"Engine", &"World"])
			car.forced = {"speed": 0.0, "on_road": 0.0}
			crash.forced_scrape_speed = 30.0 * clampf(t / (dur - 1.0), 0.0, 1.0) if t < dur - 0.5 else -1.0
		"13":
			_mute([&"Engine"])
			persp.set_cockpit(false)
			car.forced = {"speed": 40.0, "on_road": 1.0, "squeal_l": 0.7, "squeal_r": 0.7}
			AudioSettings.set_volume("Effects", [1.0, 0.5, 0.25, 0.0][mini(int(t / 2.0), 3)])
		"14":
			_mute([&"Engine", &"World"])
			car.forced = {"speed": [14.0, 28.0, 42.0][mini(int(t / 3.0), 2)], "on_road": 1.0, "concrete": 1.0}
		"15":
			_mute([&"Engine", &"World"])
			car.forced = {"speed": 20.0, "on_road": 1.0, "concrete": 0.0, "deck": 1.0 if t > 1.5 and t < 5.5 else 0.0}
		"16":
			_mute([&"Engine", &"World"])
			car.forced = {"speed": 25.0, "on_road": 1.0, "concrete": 0.0}
			for at in [0.8, 0.9, 3.0, 3.1]:
				if t >= at and not fired.has(at):
					fired[at] = true
					car.hit_manhole(25.0)
		"17":
			_mute([&"Engine", &"Tires", &"World"], true)
			car.forced = {"speed": 0.0, "on_road": 0.0}
			persp.set_cockpit(true)   # the radio as you hear it in the car
			var rx := 1.0
			if t >= 3.0 and t < 7.5:
				rx = 0.0      # the tunnel
			elif t >= 10.0:
				rx = 0.35     # under a bridge
			radio.forced_reception = rx
		"18":
			_mute([&"Tires", &"World"])
			car.forced = {"speed": 0.0, "on_road": 0.0}
			if not fired.has("off"):
				fired.off = true
				p.engine_running = false
				drive.heat = 1.0
				drive.cooling = 0.0
			if t >= 15.0 and not fired.has("later"):
				fired.later = true
				drive.cooling = 40.0

func _done() -> void:
	var f := FileAccess.open(dir.path_join("listen_pack.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("Sound fixes listen pack (2026-10-08). Every sound is generated in code; nothing recorded.\n\n" + "\n".join(manifest) + "\n")
		f.close()
	print("listen pack: %d clips in %s" % [manifest.size(), ProjectSettings.globalize_path(dir)])
	for b in [&"Engine", &"Tires", &"World", &"Music", &"UI"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, false)
	game.queue_free()
	game = null
	quit_in = 30
