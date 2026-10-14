extends SceneTree

# PlayerGain's gain buses (issues #567, #580), headless, no game scene:
# - route() puts a stopped player on a gain bus of its own that sends to the
#   target, at the asked level
# - a routed player that leaves the tree while it plays and comes back keeps
#   its bus and its amplifier: nothing writes the bus of a sounding player
# - while it lives its bus is no one else's; once it is freed the bus is reused
#   (the layout does not grow per player)
# - Sound3D.bus moves the send of its gain bus, not the player's bus
# - routing and freeing players every frame while others play (the bus layout
#   changes under AudioServer.lock(): add_bus() unlocked crashed the mix thread
#   in thread_find_bus_index, #580) leaves every player where it was put
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/audio/player_gain.gd

const STRESS_FRAMES := 120

var failures: Array[String] = []
var frame := 0
var wav: AudioStreamWAV
var loud: Array[AudioStreamPlayer] = []
var keeper: AudioStreamPlayer
var keeper_bus: StringName
var churn: Array[AudioStreamPlayer] = []
var peak_buses := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _initialize() -> void:
	wav = AudioStreamWAV.new()
	var d := PackedByteArray()
	d.resize(4410 * 2)
	for i in 4410:
		d.encode_s16(i * 2, int(6000.0 * sin(float(i) * 0.1)))
	wav.data = d
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 4410

func _player(target: StringName, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = wav
	PlayerGain.route(p, target, db)
	root.add_child(p)
	return p

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_first()
	elif frame == 2:
		_back_in()
	elif frame < 3 + STRESS_FRAMES:
		_churn()
	elif frame == 3 + STRESS_FRAMES:
		_finish()
		return true
	return false

func _first() -> void:
	keeper = _player(&"Master", -6.0)
	keeper_bus = keeper.bus
	var idx := AudioServer.get_bus_index(keeper_bus)
	_check(String(keeper_bus).begins_with(PlayerGain.PREFIX), "route() should put the player on a gain bus, is on %s" % keeper_bus)
	_check(idx > 0 and AudioServer.get_bus_send(idx) == &"Master", "the gain bus should send to the target")
	_check(is_equal_approx(PlayerGain.get_db(keeper), -6.0) and keeper.volume_db == 0.0, "the level should be on the amplifier, the player at 0 dB")
	keeper.play()
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.stream = wav
		p.volume_db = -30.0
		root.add_child(p)
		p.play()
		loud.append(p)
	# out of the tree and back while it plays (a pooled car, the trap cop)
	var amp := PlayerGain.amp(keeper)
	root.remove_child(keeper)
	_check(keeper.bus == keeper_bus, "a player out of the tree should keep its gain bus")
	root.add_child(keeper)
	_check(keeper.bus == keeper_bus and PlayerGain.amp(keeper) == amp, "a player back in the tree should have the same bus and amplifier")

func _back_in() -> void:
	_check(keeper.playing, "the player that went out and back should still play")
	var other := _player(&"Master", 0.0)
	_check(other.bus != keeper_bus, "a live player's gain bus must not be handed to another")
	var s := Sound3D.new()
	root.add_child(s)
	var out := s.get_child(0, true) as AudioStreamPlayer
	var bus_before := out.bus
	s.bus = &"Master"
	s.bus = StringName(keeper_bus)   # any existing bus will do as a target here
	_check(out.bus == bus_before, "Sound3D.bus should not move its player's bus")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(out.bus)) == StringName(keeper_bus), "Sound3D.bus should move its gain bus's send")
	_check(PlayerGain.target(out) == StringName(keeper_bus), "Sound3D.bus should be the gain target")
	s.free()
	other.free()

func _churn() -> void:
	# a few players come and go every frame while two dozen others play
	for p in churn:
		p.free()
	churn.clear()
	for i in 4:
		var p := _player(&"Master", -12.0)
		p.play()
		churn.append(p)
	peak_buses = maxi(peak_buses, AudioServer.bus_count)
	_check(keeper.bus == keeper_bus, "the long-lived player's bus should never move")

func _finish() -> void:
	# keeper, 4 churned, and at most a couple more from _back_in: freed buses
	# are reused, the layout does not grow every frame
	var gain_buses := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with(PlayerGain.PREFIX):
			gain_buses += 1
	_check(gain_buses <= 8, "freed players' buses should be reused: %d gain buses after %d frames" % [gain_buses, STRESS_FRAMES])
	print("gain buses %d, peak bus count %d, keeper on %s" % [gain_buses, peak_buses, keeper_bus])
	for p in churn:
		p.free()
	for p in loud:
		p.free()
	keeper.free()
	if failures.is_empty():
		print("player_gain: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)
