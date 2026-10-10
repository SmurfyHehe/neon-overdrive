class_name MenuSfx
extends Node

# Menu sounds (menus A-list, 2026-10-08), on the UI bus, for every menu in the
# game without each screen wiring its own: this node watches the tree and hooks
# any Button, CheckButton, OptionButton or Slider that appears.
#
#   move      focus moves to another control (only when the player moved it,
#             not when a menu opens and grabs focus by itself)
#   select    a button is pressed          back    a Back / No button
#   toggle    a CheckButton flips (our own: a relay-style click)
#   tick      a slider moves a step (our own; at most one per 45 ms)
#   squelch   the pause menu or title opens (our own: a CB radio squelch tail)
#
# Every sound is synthesised here, so nothing is downloaded; no Kenney file is in
# the repo. Dropping res://assets/ui/sfx/<name>.ogg (or .wav) in replaces the
# synthesised one with no code change; record any such file in
# docs/audio-licences.md first.

const MIX_RATE := 44100
const SFX_DIR := "res://assets/ui/sfx/"
const NAMES := ["move", "select", "back", "toggle", "tick", "squelch"]
const LEVEL_DB := {"move": -14.0, "select": -9.0, "back": -9.0, "toggle": -8.0, "tick": -18.0, "squelch": -12.0}
const TICK_GAP_MS := 45
const VOICES := 4

## Buttons whose press sounds like going back.
const BACK_TEXTS := ["Back", "No", "Resume"]

static var _streams := {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_input_ms := -100000
var _last_tick_ms := -100000
## Counts of each sound played, for tests.
var played := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_hook)
	_hook_tree(get_tree().root)

func _hook_tree(n: Node) -> void:
	_hook(n)
	for c in n.get_children():
		_hook_tree(c)

func _hook(n: Node) -> void:
	if n.has_meta("menu_sfx"):
		return
	if n is BaseButton or n is Slider:
		n.set_meta("menu_sfx", true)
	else:
		return
	n.focus_entered.connect(_on_focus)
	if n is CheckButton or n is CheckBox:
		n.toggled.connect(func(_on: bool) -> void: play("toggle"))
	elif n is OptionButton:
		n.item_selected.connect(func(_i: int) -> void: play("select"))
	elif n is BaseButton:
		n.pressed.connect(func() -> void: play("back" if n is Button and n.text in BACK_TEXTS else "select"))
	elif n is Slider:
		n.value_changed.connect(func(_v: float) -> void: _tick())

## Pause menu / title opening.
func squelch() -> void:
	play("squelch")

## Only navigation keys count, so the focus a menu grabs when Esc opens it
## stays silent.
const NAV_ACTIONS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	for a in NAV_ACTIONS:
		if event.is_action(a):
			_last_input_ms = Time.get_ticks_msec()
			return

func _on_focus() -> void:
	if Time.get_ticks_msec() - _last_input_ms < 150:
		play("move")

func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms >= TICK_GAP_MS:
		_last_tick_ms = now
		play("tick")

func play(sound: String) -> void:
	played[sound] = played.get(sound, 0) + 1
	if not is_inside_tree():
		return   # a press that is still being handled as the scene is replaced
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream(sound)
	p.volume_db = LEVEL_DB.get(sound, -10.0)
	p.play()

## A dropped-in file wins; otherwise the synthesised sound (cached).
static func stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStream = null
	for ext in ["ogg", "wav"]:
		var path: String = SFX_DIR + sound + "." + ext
		if ResourceLoader.exists(path):
			s = load(path)
			break
	if s == null:
		s = _wav(synth(sound))
	_streams[sound] = s
	return s

## The samples of a synthesised sound, peak-normalised to 0.9 (levels are set
## per sound in LEVEL_DB, not baked into the samples).
static func synth(sound: String) -> PackedFloat32Array:
	var s := _synth_raw(sound)
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		for i in s.size():
			s[i] *= 0.9 / peak
	return s

static func _synth_raw(sound: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	match sound:
		"move":  # a short, soft blip
			return _tone(0.028, 2400.0, 2400.0, 0.0015, 0.02, rng, 0.0)
		"select":  # two quick rising notes
			var a := _tone(0.045, 880.0, 880.0, 0.002, 0.03, rng, 0.0)
			a.append_array(_tone(0.06, 1320.0, 1320.0, 0.002, 0.045, rng, 0.0))
			return a
		"back":  # the same, falling
			var b := _tone(0.045, 1320.0, 1320.0, 0.002, 0.03, rng, 0.0)
			b.append_array(_tone(0.06, 760.0, 760.0, 0.002, 0.045, rng, 0.0))
			return b
		"toggle":  # relay click: a sharp noise tick over a low thump
			var t := _tone(0.05, 180.0, 90.0, 0.0005, 0.02, rng, 0.0)
			for i in mini(t.size(), int(0.006 * MIX_RATE)):
				t[i] += rng.randf_range(-0.9, 0.9) * (1.0 - float(i) / (0.006 * MIX_RATE))
			return t
		"tick":  # tiny detent
			return _tone(0.012, 4200.0, 3800.0, 0.0003, 0.006, rng, 0.0)
		"squelch":  # CB squelch tail: band-limited hiss that cuts off, a chirp at the end
			var n := int(0.2 * MIX_RATE)
			var out := PackedFloat32Array()
			out.resize(n)
			var lp := 0.0
			var low := 0.0
			for i in n:
				var x := rng.randf_range(-1.0, 1.0)
				lp += 0.35 * (x - lp)     # low-pass, ~3 kHz
				low += 0.03 * (lp - low)  # what's under ~200 Hz, taken out below
				var t := float(i) / MIX_RATE
				var env := minf(t / 0.004, 1.0) * (1.0 if t < 0.15 else maxf(0.0, 1.0 - (t - 0.15) / 0.02))
				out[i] = (lp - low) * 1.4 * env
			out.append_array(_tone(0.035, 1050.0, 1250.0, 0.001, 0.03, rng, 0.0))
			return out
	return PackedFloat32Array()

## A sine sweep from f0 to f1 with a linear attack and exponential decay.
static func _tone(dur: float, f0: float, f1: float, attack: float, decay: float, _rng: RandomNumberGenerator, noise: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := lerpf(f0, f1, t / dur)
		phase += TAU * f / MIX_RATE
		var env := minf(t / attack, 1.0) * exp(-t / decay)
		out[i] = (sin(phase) + noise * _rng.randf_range(-1.0, 1.0)) * env
	return out

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
