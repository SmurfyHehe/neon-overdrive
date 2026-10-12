class_name PlayerGain
extends RefCounted

# Changing a player's level while it plays, without the crash in issue #567.
#
# Godot 4.7.2 crashes now and then when an AudioStreamPlayer's volume_db is
# written while it plays: every write makes the AudioServer swap that
# playback's bus details and free the old copy a frame later, while the audio
# mix thread may still be reading it (audio_server.cpp, _mix_step, and the
# graveyard in _cleanup_lists). So nothing that runs per frame may write
# volume_db (or bus) on a playing player. Two ways round it here:
#
# - route() / set_db(): a player whose level moves while it plays (a looping
#   layer, a fade) sits on a bus of its own with an AudioEffectAmplify, and
#   its level is the amplifier's volume_db. Writing that changes one number
#   the mix thread reads; nothing is freed. The amplifier ramps from the old
#   to the new gain across each mix block, as Godot does for a player's own
#   volume, so the fades sound the same. (AudioServer.set_bus_volume_db would
#   also be safe, but it jumps at the block edge instead of ramping.) The
#   player's own volume_db stays 0 dB. Its bus sends to the bus the player
#   used to be on, so the sliders, filters and effects there still apply.
#   Buses are made on first need and reused, never removed (indices of the
#   layout's buses never move). A player keeps its bus for its whole life, in
#   the tree or out of it, so its bus is only ever written at route(); the bus
#   goes back to the pool when the player is freed.
# - The bus layout itself is not safe to change while the mix thread runs
#   either (issue #580): AudioServer.add_bus() and set_bus_send() take no lock,
#   and add_bus() grows the server's bus list and its name -> bus map while
#   the mix thread looks buses up in them (thread_find_bus_index, once per
#   playing player per block): a lookup into the freed table segfaults. So
#   every layout change here is made under AudioServer.lock(), which the mix
#   thread holds while it mixes (it is recursive, so the locking calls inside
#   are fine).
# - play_at(): a one-shot gets its level while it is stopped. A player that
#   is still sounding is stopped first (play() would have cut it anyway), or,
#   with max_polyphony above 1, a spare copy that is free plays instead.
#
# Pitch writes are safe: pitch_scale is one atomic number per playback.
# AudioStreamPlayer3D swaps bus details itself every mix while it plays (its
# panning), so the game has none: Sound3D does the same job on a spatial gain
# bus (route(..., true): amplifier, then an AudioEffectPanner and the distance
# high-shelf, each a plain number the mix thread reads).

const PREFIX := "Gain"

static var _free: Array[StringName] = []
static var _free_3d: Array[StringName] = []
static var _made := 0

## Puts `player` on a gain bus of its own that sends to `target`, at `db`.
## Call it while the player is stopped (at spawn): it sets the player's bus.
## From then on use set_db(), never player.volume_db. The gain bus is added
## after every bus there is, so `target` must already exist (a bus only sends
## to one before it; the game's all come from the layout). `spatial`: the bus also
## carries a panner and a high-shelf filter (Sound3D sets them, see pan()).
static func route(player: Node, target: StringName, db := 0.0, spatial := false) -> void:
	player.set_meta(&"gain_target", target)
	player.set_meta(&"gain_spatial", spatial)
	if player.has_meta(&"gain_amp"):
		retarget(player, target)   # routed already: keep its bus
		set_db(player, db)
		return
	player.volume_db = 0.0
	_take(player, db)

## Points a routed player's gain bus at another `target` (Sound3D.bus). Safe
## while it plays: only the bus's send changes, not the player.
static func retarget(player: Node, target: StringName) -> void:
	player.set_meta(&"gain_target", target)
	var idx := AudioServer.get_bus_index(player.bus)
	if idx < 0 or not player.has_meta(&"gain_amp"):
		return   # not routed (yet): route() sends to gain_target
	AudioServer.lock()
	AudioServer.set_bus_send(idx, target)
	AudioServer.unlock()

## The player's level, dB. Safe every frame while it plays.
static func set_db(player: Node, db: float) -> void:
	(player.get_meta(&"gain_amp") as AudioEffectAmplify).volume_db = db

## A spatial player's left/right balance (AudioEffectPanner pan, -1 .. 1) and
## its distance high-shelf (gain as a linear factor, cutoff in Hz).
static func pan(player: Node, balance: float, shelf_gain: float, shelf_hz: float) -> void:
	var fx: Array = player.get_meta(&"gain_fx")
	(fx[0] as AudioEffectPanner).pan = balance
	var shelf := fx[1] as AudioEffectHighShelfFilter
	shelf.gain = shelf_gain
	shelf.cutoff_hz = shelf_hz

## The amplifier that carries the player's level (to tween its volume_db).
static func amp(player: Node) -> AudioEffectAmplify:
	return player.get_meta(&"gain_amp")

static func get_db(player: Node) -> float:
	var amp: AudioEffectAmplify = player.get_meta(&"gain_amp", null)
	return amp.volume_db if amp != null else float(player.volume_db)

## The bus the player's sound ends up on: route()'s target, or its own bus.
static func target(player: Node) -> StringName:
	return player.get_meta(&"gain_target", player.bus)

## Plays a one-shot at `db` (and `pitch` when > 0) without writing the level of
## a player that is sounding. Returns the player that plays it.
static func play_at(player: AudioStreamPlayer, db: float, pitch := -1.0, from := 0.0) -> AudioStreamPlayer:
	var v := player
	if player.playing and player.max_polyphony > 1:
		v = _spare(player)
	# stop() also drops playbacks that ended but are still listed, so the
	# write below reaches no playback at all (play() stops them anyway)
	v.stop()
	v.volume_db = db
	if pitch > 0.0:
		v.pitch_scale = pitch
	v.play(from)
	return v

## A stopped player with `p`'s stream and bus: `p`'s spare copies, made on
## first need, up to its max_polyphony in all. When every one is sounding the
## spare that started first is stopped, much as play() itself would have cut
## its oldest voice.
static func _spare(p: AudioStreamPlayer) -> AudioStreamPlayer:
	var spares: Array = p.get_meta(&"gain_spares", [])
	for s: AudioStreamPlayer in spares:
		if not s.playing:
			s.stream = p.stream
			return s
	if spares.size() + 1 < p.max_polyphony:
		var s := AudioStreamPlayer.new()
		s.name = "%sSpare%d" % [p.name, spares.size() + 1]
		s.stream = p.stream
		s.bus = p.bus
		s.max_polyphony = 1
		p.add_sibling(s)
		spares.append(s)
		p.set_meta(&"gain_spares", spares)
		return s
	var oldest: AudioStreamPlayer = spares.pop_front()
	spares.append(oldest)
	oldest.stop()
	oldest.stream = p.stream
	return oldest

static func _take(player: Node, db: float) -> void:
	var spatial: bool = player.get_meta(&"gain_spatial", false)
	var pool := _free_3d if spatial else _free
	var name: StringName
	# the mix thread reads the bus list, the name map and each bus's send
	# while it mixes: change them only while it is held off (#580)
	AudioServer.lock()
	if pool.is_empty():
		name = StringName("%s%s%d" % [PREFIX, "3D" if spatial else "", _made])
		_made += 1
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.add_bus_effect(i, AudioEffectAmplify.new(), 0)
		if spatial:
			AudioServer.add_bus_effect(i, AudioEffectPanner.new(), 1)
			# AudioStreamPlayer3D's own distance filter: a one-stage high shelf
			# with resonance 1 (AudioServer._mix_step_for_channel)
			var shelf := AudioEffectHighShelfFilter.new()
			shelf.resonance = 1.0
			shelf.db = AudioEffectFilter.FILTER_6DB
			shelf.gain = 1.0
			AudioServer.add_bus_effect(i, shelf, 2)
	else:
		name = pool.pop_back()
	var idx := AudioServer.get_bus_index(name)
	AudioServer.set_bus_send(idx, player.get_meta(&"gain_target"))
	AudioServer.unlock()
	var amp := AudioServer.get_bus_effect(idx, 0) as AudioEffectAmplify
	amp.volume_db = db
	player.set_meta(&"gain_amp", amp)
	if spatial:
		player.set_meta(&"gain_fx", [AudioServer.get_bus_effect(idx, 1), AudioServer.get_bus_effect(idx, 2)])
	player.bus = name   # the player is stopped: route() is called at spawn
	# Freed with the player (its metadata goes with it): the bus is free again.
	player.set_meta(&"gain_lease", _Lease.new(name, spatial))

## Holds a gain bus for one player; gives it back to the pool when the player
## is freed. A player that leaves the tree and comes back (a pooled car, the
## speed-trap cop) keeps its bus, so nothing writes the bus of a player that
## may be sounding again.
class _Lease extends RefCounted:
	var bus: StringName
	var spatial: bool

	func _init(b: StringName, s: bool) -> void:
		bus = b
		spatial = s

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			(PlayerGain._free_3d if spatial else PlayerGain._free).append(bus)
