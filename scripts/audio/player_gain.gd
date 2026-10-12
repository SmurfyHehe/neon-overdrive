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
#   layout's buses never move).
# - play_at(): a one-shot gets its level while it is stopped. A player that
#   is still sounding is stopped first (play() would have cut it anyway), or,
#   with max_polyphony above 1, a spare copy that is free plays instead.
#
# Pitch writes are safe: pitch_scale is one atomic number per playback.
# AudioStreamPlayer3D swaps bus details itself every mix while it plays (its
# panning), so a 3D player cannot be made safe from here.

const PREFIX := "Gain"

static var _free: Array[StringName] = []
static var _made := 0

## Puts `player` on a gain bus of its own that sends to `target`, at `db`.
## Call it while the player is stopped (at spawn): it sets the player's bus.
## From then on use set_db(), never player.volume_db.
static func route(player: Node, target: StringName, db := 0.0) -> void:
	player.set_meta(&"gain_target", target)
	player.volume_db = 0.0
	_take(player, db)
	player.tree_entered.connect(func() -> void:
		if not player.has_meta(&"gain_amp"):
			_take(player, player.get_meta(&"gain_last", db)))
	player.tree_exited.connect(func() -> void: _give(player))

## The player's level, dB. Safe every frame while it plays.
static func set_db(player: Node, db: float) -> void:
	(player.get_meta(&"gain_amp") as AudioEffectAmplify).volume_db = db

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
	var name: StringName
	if _free.is_empty():
		name = StringName("%s%d" % [PREFIX, _made])
		_made += 1
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.add_bus_effect(i, AudioEffectAmplify.new(), 0)
	else:
		name = _free.pop_back()
	var idx := AudioServer.get_bus_index(name)
	AudioServer.set_bus_send(idx, player.get_meta(&"gain_target"))
	var amp := AudioServer.get_bus_effect(idx, 0) as AudioEffectAmplify
	amp.volume_db = db
	player.set_meta(&"gain_amp", amp)
	player.bus = name

static func _give(player: Node) -> void:
	if not player.has_meta(&"gain_amp"):
		return
	player.set_meta(&"gain_last", (player.get_meta(&"gain_amp") as AudioEffectAmplify).volume_db)
	player.remove_meta(&"gain_amp")
	_free.append(player.bus)
