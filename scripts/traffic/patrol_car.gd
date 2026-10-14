class_name PatrolCar
extends TrafficCar

# The patrol car (police build plan F1): a C1 patrol body with the cop
# undercarriage. On patrol it is driven by the traffic controller; PolicePatrol
# hands it to TrafficManager.adopt(), so it is in the index like a rival and
# changes lanes like traffic. In a chase a CopBrain gives it a FreeDriver
# (police steps P4 / P5).

const KIND := "c1_patrol"

## Emergency lights (and siren) on. Nothing turns them on yet (pursuit is a
## later stage); this is the hook traffic already answers: with them on, cars
## ahead pull over to the right and slow (TrafficManager.add_siren).
var lights_on := false:
	set(on):
		lights_on = on
		if traffic != null:
			if on:
				traffic.add_siren(self)
			else:
				traffic.remove_siren(self)

func _exit_tree() -> void:
	if traffic != null:
		traffic.remove_siren(self)

## A patrol car ready to add to the tree (TrafficCar's setup runs in _ready).
## `body` is a cop kind: the C1 patrol sedan, or the C2 patrol SUV for the
## heat-4 heavy unit ("stock" is its push-bar build).
static func make(body := KIND) -> PatrolCar:
	var c := PatrolCar.new()
	c.kind = body
	c.build = "stock"
	c.role = Undercarriage.ROLE_COP
	c.spec = CarSpec.clone_spec(CarSpec.npc_spec(body))
	c.spec["parts"] = "full"   # real wheels and brakes, like the fleet's cops
	c.color = NpcCarBuilder.sheet_paint(body)
	c.add_to_group("patrol_cars")   # the near-miss log looks at it (near_miss_log.gd)
	return c

## Lane changes only once the manager has it in its index (TrafficManager.adopt);
## a car outside the index cannot be re-filed.
func _consider_lane_change(v: float) -> void:
	if _idx >= 0:
		super(v)

## P2 warning (police_heat.gd): the light bar goes once and the cop gives one
## whoop. Stand-in: the hazard/brake lamps flash for FLASH_SECS; the whoop is a
## short rising sweep on the Sirens bus.
const FLASH_SECS := 0.6
static var _whoop: AudioStreamWAV

func warn_flash() -> void:
	if chassis_visual != null:
		NpcCarBuilder.set_lamps(chassis_visual, 1.0, true)
		_lamp_key = -1
		get_tree().create_timer(FLASH_SECS).timeout.connect(_end_flash)
	var p := Sound3D.new()   # not AudioStreamPlayer3D: issue #567
	p.stream = _whoop_stream()
	if AudioServer.get_bus_index(&"Sirens") >= 0:
		p.bus = &"Sirens"
	p.max_distance = 220.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _end_flash() -> void:
	if chassis_visual != null and is_instance_valid(chassis_visual):
		NpcCarBuilder.set_lamps(chassis_visual, 0.0, false)
		_lamp_key = -1

## 0.4 s rising 600 -> 1500 Hz with a fade, 16-bit mono.
static func _whoop_stream() -> AudioStreamWAV:
	if _whoop != null:
		return _whoop
	var rate := 22050
	var n := int(0.4 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(600.0, 1500.0, t) / rate
		var v := sin(phase) * 0.4 * minf(1.0, (1.0 - t) * 4.0) * minf(1.0, t * 40.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	_whoop = AudioStreamWAV.new()
	_whoop.format = AudioStreamWAV.FORMAT_16_BITS
	_whoop.mix_rate = rate
	_whoop.stereo = false
	_whoop.data = data
	return _whoop
