extends SceneTree

# Listen pack for the starter, catch and shutdown (StarterAudio): writes every
# take as a .wav, at each car's playback speed, to user://listen/starter, and
# prints how long the takes took to build (they are built once, then cached).
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/audio/starter_listen.gd

const StarterAudio := preload("res://scripts/audio/starter_audio.gd")
const CARS := {"kei_3cyl": 3, "four_cyl": 4, "six_cyl": 6, "v8": 8}

func _initialize() -> void:
	var dir := "user://listen/starter"
	DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	var takes := {}
	for i in StarterAudio.CRANK_TAKES:
		takes["crank%d" % i] = StarterAudio.make_crank(9127 + i * 31)
	for i in StarterAudio.CATCH_TAKES:
		takes["catch%d" % i] = StarterAudio.make_catch(417 + i * 53)
	for i in StarterAudio.STOP_TAKES:
		takes["shutdown%d" % i] = StarterAudio.make_shutdown(2203 + i * 17)
	print("starter_listen: %d takes built in %d ms" % [takes.size(), Time.get_ticks_msec() - t0])
	var peak_ok := true
	for take_name in takes:
		var wav := takes[take_name] as AudioStreamWAV
		peak_ok = peak_ok and wav.data.size() > 1000
		for car in CARS:
			var copy := wav.duplicate() as AudioStreamWAV
			copy.mix_rate = int(wav.mix_rate * StarterAudio.pace(CARS[car]))
			copy.save_to_wav("%s/%s_%s.wav" % [dir, car, take_name])
	print("starter_listen: %s, written to %s" % ["PASS" if peak_ok else "FAIL", ProjectSettings.globalize_path(dir)])
	quit(0 if peak_ok else 1)
