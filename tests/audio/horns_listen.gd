extends SceneTree

# Listen file for the horns (TrafficHorns, second pass for the player's horn on
# J): writes user://horns_listen.wav with, for each horn, a tap, then a 2 s
# hold, then a 1 s gap, cut the way PlayerHorn plays them (the looping take,
# the fade on release). user://horns_listen_traffic.wav has the baked short and
# long takes the traffic uses. Also prints, per horn, what
# tests/traffic/near_miss_cases.gd asserts on (length, peak, zero crossings all
# different) and the size of the step at the loop seam.
#
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/horns_listen.gd

const ORDER: Array[String] = ["beep", "two_tone", "blare", "sharp", "sour", "air"]
const HOLD_S := 2.0
const GAP_S := 1.0
const TAP_GAP_S := 0.5

func _played(take: PackedFloat32Array, secs: float) -> PackedFloat32Array:
	var rate := TrafficHorns.RATE
	var head := int(TrafficHorns.HOLD_HEAD_S * rate)
	var loop_n := take.size() - head
	var n := int(secs * rate)
	var tail := int(PlayerHorn.TAIL_S * rate)
	var out := PackedFloat32Array()
	out.resize(n + tail)
	for i in n + tail:
		var src := i if i < take.size() else head + (i - head) % loop_n
		var g := 1.0 if i < n else 1.0 - float(i - n) / tail
		out[i] = take[src] * g
	return out

func _silence(secs: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(secs * TrafficHorns.RATE))
	return out

func _initialize() -> void:
	var ok := true
	var t0 := Time.get_ticks_msec()
	var all := PackedFloat32Array()
	var traffic := PackedFloat32Array()
	var seen := {}
	for horn in ORDER:
		var take := TrafficHorns.hold_samples(horn)
		var head := int(TrafficHorns.HOLD_HEAD_S * TrafficHorns.RATE)
		# The seam: the step from the loop's last sample to its first, against
		# the biggest step anywhere inside the loop.
		var seam := absf(take[head] - take[take.size() - 1])
		var biggest := 0.0
		for i in range(head + 1, take.size()):
			biggest = maxf(biggest, absf(take[i] - take[i - 1]))
		all.append_array(_played(take, PlayerHorn.TAP_S))
		all.append_array(_silence(TAP_GAP_S))
		all.append_array(_played(take, HOLD_S))
		all.append_array(_silence(GAP_S))
		var long := TrafficHorns.samples(horn, TrafficHorns.LONG_S)
		var peak := 0.0
		var sq := 0.0
		var crossings := 0
		for i in range(1, long.size()):
			peak = maxf(peak, absf(long[i]))
			sq += long[i] * long[i]
			if long[i - 1] < 0.0 and long[i] >= 0.0:
				crossings += 1
		traffic.append_array(TrafficHorns.samples(horn, TrafficHorns.SHORT_S))
		traffic.append_array(_silence(TAP_GAP_S))
		traffic.append_array(long)
		traffic.append_array(_silence(GAP_S))
		var bad := peak < 0.2 or peak > 1.0 or seen.has(crossings) or seam > biggest \
			or long.size() != int(TrafficHorns.LONG_S * TrafficHorns.RATE)
		ok = ok and not bad
		seen[crossings] = horn
		print("  %-9s peak %.2f  rms %.2f  %4d zero crossings  seam step %.4f (largest step in the loop %.4f)%s" % [
			horn, peak, sqrt(sq / long.size()), crossings, seam, biggest, "  <-- BAD" if bad else ""])
	print("horns_listen: built in %d ms" % (Time.get_ticks_msec() - t0))
	for pair in [["user://horns_listen.wav", all], ["user://horns_listen_traffic.wav", traffic]]:
		var err := AudioDsp.to_wav(pair[1], TrafficHorns.RATE, false).save_to_wav(pair[0])
		ok = ok and err == OK
		print("horns_listen: %.1f s -> %s (error %d)" % [pair[1].size() / float(TrafficHorns.RATE), ProjectSettings.globalize_path(pair[0]), err])
	print("horns_listen: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
