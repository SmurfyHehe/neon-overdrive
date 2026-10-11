extends Node

# Tunnel echo (TN1). While the player's car is under cover its own sounds
# (engine and exhaust, tyres and road noise, the turbo) get a short concrete
# room around them; the echo comes up over the first WET_RAMP metres inside a
# mouth and goes down over the last WET_RAMP before the other one.
#
# Godot's buses have one send each, so there is no side chain to feed a
# reverb from three buses. Instead a "Tunnel" bus sits between those three
# and Master, with one reverb on it that is switched off outside a tunnel
# (an effect that is off costs nothing). The bus is added here at run time,
# next to Master, so default_bus_layout.tres is not touched; the three buses
# keep their names, volumes and effects and only send somewhere else.
#
# How far inside comes from the map (RoadMap.tunnel_depth), not from a box
# in the world, so it is the same on every lap and needs no node per tunnel.
# No class_name on purpose: preload it, so no class cache refresh is needed.

const RoadMap := preload("res://scripts/world/road_map.gd")

const BUS := &"Tunnel"
## The buses that echo: the car's own noise. Music, voices, UI, sirens and
## the other traffic stay dry.
const SENDS: Array[StringName] = [&"Engine", &"Tires", &"Turbo"]
## Metres inside a mouth over which the echo comes up.
const WET_RAMP := 20.0
## The reverb at full: a short, hard room.
const WET := 0.32
const ROOM := 0.5
const DAMPING := 0.35
const PREDELAY_MS := 28.0
const PREDELAY_FEEDBACK := 0.12
## 1/s: how fast the echo follows where the car is (a teleport or a restart
## does not click).
const RATE := 8.0

var listener: Node3D
## 0 outside .. 1 fully inside; what the reverb's wet level follows.
var amount := 0.0
## Tests: >= 0 overrides where the car is.
var forced_depth := -1.0
var _reverb: AudioEffectReverb

func _ready() -> void:
	_reverb = ensure_bus()

## Adds the Tunnel bus and its reverb once per process (AudioServer outlives
## the scene) and returns the reverb.
static func ensure_bus() -> AudioEffectReverb:
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		# A bus may only send to one before it: next to Master, before the rest.
		AudioServer.add_bus(1)
		bus = 1
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.set_bus_send(bus, &"Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = ROOM
		rv.damping = DAMPING
		rv.predelay_msec = PREDELAY_MS
		rv.predelay_feedback = PREDELAY_FEEDBACK
		rv.spread = 0.8
		rv.hipass = 0.15
		rv.dry = 1.0
		rv.wet = 0.0
		AudioServer.add_bus_effect(bus, rv)
		AudioServer.set_bus_effect_enabled(bus, 0, false)
	for bus_name in SENDS:
		var b := AudioServer.get_bus_index(bus_name)
		if b >= 0:
			AudioServer.set_bus_send(b, BUS)
	return AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb

## The echo's share at `depth` metres inside a tunnel (RoadMap.tunnel_depth).
static func amount_at(depth: float) -> float:
	return smoothstep(0.0, WET_RAMP, depth)

## Metres inside a tunnel the listener is (0 or less outside).
func listener_depth() -> float:
	if forced_depth >= 0.0:
		return forced_depth
	if not is_instance_valid(listener) or RoadMap.tunnels().is_empty():
		return -INF
	return RoadMap.tunnel_depth(RoadFrame.s_at(RoadFrame.unroll(listener.global_position).z))

func _process(delta: float) -> void:
	var want := amount_at(listener_depth())
	amount = lerpf(amount, want, 1.0 - exp(-RATE * delta))
	if absf(amount - want) < 0.002:
		amount = want
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0 or _reverb == null:
		return
	var on := amount > 0.0
	if AudioServer.is_bus_effect_enabled(bus, 0) != on:
		AudioServer.set_bus_effect_enabled(bus, 0, on)
	_reverb.wet = WET * amount
