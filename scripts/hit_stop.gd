extends Node
class_name HitStop

# Hit-stop (driving-feel pass, 2026-10-08; Roy's pick: "freeze yes"). A big
# crash holds the world almost still for a blink, so the hit lands like a
# punch instead of sliding past. Only big hits (BIG_DV, the glass tier of
# CrashAudio): scrapes, taps and kerbs never freeze. The sound keeps playing
# through it (audio ignores Engine.time_scale), so the crunch carries the
# moment.
#
# How: Engine.time_scale drops to SCALE for FREEZE_S..FREEZE_MAX_S of real
# time, then snaps back. That makes the physics steps shorter, not fewer;
# tests/hit_stop.gd checks a wall crash ends the same with and without it.
# Real time comes from the clock, because every delta is scaled during it.
# A cooldown keeps a pile-up from stuttering. FxSettings "hit_stop" is the
# off switch.

const BIG_DV := 10.0          # m/s of velocity change in one hit (CrashAudio's glass tier)
const HUGE_DV := 20.0         # at and over this, the freeze is longest
const SCALE := 0.05           # world speed while frozen
const FREEZE_S := 0.06        # real seconds at BIG_DV
const FREEZE_MAX_S := 0.11    # real seconds at HUGE_DV
const COOLDOWN_S := 1.0       # real seconds before another freeze

var freeze_count := 0         # tests
var enabled := true

var _until_us := 0
var _ready_us := 0
var _fired_this_hit := false
var _crash: CrashAudio

func _init(crash: CrashAudio) -> void:
	name = "HitStop"
	_crash = crash

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crash.hit_building.connect(_on_hit_building)

## The hit so far, every tick of an open hit window. Fires once per window,
## as soon as the hit is big enough.
func _on_hit_building(dv_so_far: float, first: bool) -> void:
	if first:
		_fired_this_hit = false
	if _fired_this_hit or dv_so_far < BIG_DV:
		return
	_fired_this_hit = true
	trigger(dv_so_far)

## Freezes for a hit of this size (m/s). Public for tests.
func trigger(dv: float) -> void:
	if not enabled or not FxSettings.is_on("hit_stop") or dv < BIG_DV:
		return
	var now := Time.get_ticks_usec()
	if now < _ready_us or is_frozen():
		return
	var t := clampf((dv - BIG_DV) / (HUGE_DV - BIG_DV), 0.0, 1.0)
	_until_us = now + int(lerpf(FREEZE_S, FREEZE_MAX_S, t) * 1e6)
	_ready_us = _until_us + int(COOLDOWN_S * 1e6)
	freeze_count += 1
	Engine.time_scale = SCALE

func is_frozen() -> bool:
	return _until_us > 0

func _process(_delta: float) -> void:
	if _until_us == 0:
		return
	# Pausing mid-freeze (or the window closing) ends it at once.
	if Time.get_ticks_usec() >= _until_us or get_tree().paused:
		_release()

func _release() -> void:
	_until_us = 0
	Engine.time_scale = 1.0

func _exit_tree() -> void:
	if _until_us != 0:
		_release()
