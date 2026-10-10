extends SceneTree

# The bolt-on AFR/PSI gauge pod and the head unit clock (2026-10-09), headless:
# - a car with no boost setup has no pod; the moment it has one (stock or the
#   Tuner) the pod is fitted on the cockpit frame, styled for the car, its PSI
#   face scaled to the setup, under the sightline (CockpitFrame.DASH_TOP_MIN_DEG)
# - idle: the PSI needle reads a vacuum, the AFR sits near stoich
# - full throttle on boost: PSI above zero, AFR rich
# - lift off in gear at speed: the overrun fuel cut pegs the AFR lean
# - every player car has a style and a mount, and its pod builds
# - the head unit's clock is on its own layer, big, and lit with the radio off
# Exit code 1 on failure. Run:
#   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --path . -s res://tests/view/gauge_pod.gd

const TIMEOUT_TICKS := 60 * 60
const STOCK_BOOST := 0.7

enum Step { BOOT, NO_POD, IDLE, PULL, LIFT, DONE }

var step := Step.BOOT
var step_start := 0
var tick := 0
var failures: Array[String] = []
var throttle := 0.0
var brake := 1.0
var peak_psi := -99.0
var min_afr := 99.0

func _initialize() -> void:
	OS.set_environment("NEON_TRAFFIC", "0")
	OS.set_environment("NEON_CAR", "p1_coupe")   # naturally aspirated stock: no pod until boost is added
	change_scene_to_file("res://Game.tscn")

func _drive(c: PlayerCar) -> void:
	c.throttle_input = throttle
	c.brake_input = brake
	c.steering_input = 0.0

func _physics_process(delta: float) -> bool:
	tick += 1
	var game := current_scene
	if game == null or game.get("player") == null or game.get("camera") == null:
		return tick > TIMEOUT_TICKS and _end("Game never became ready")
	var p: PlayerCar = game.player
	var cam: ChaseCamera = game.camera
	p.driver = _drive
	var frame: CockpitFrame = cam.frame
	if frame == null:
		return _end("no cockpit frame (NEON_COCKPIT=0?)")
	var waited := tick - step_start
	match step:
		Step.BOOT:
			if waited == 10:
				cam.set_view(ChaseCamera.View.COCKPIT)
				_go(Step.NO_POD)
		Step.NO_POD:
			if waited == 20:
				_check(p.turbo_boost_max == 0.0, "the stock coupe is naturally aspirated (%.2f bar)" % p.turbo_boost_max)
				_check(not GaugeReadouts.has_pod(p) and frame.pod == null, "no boost setup, no pod")
				_check_styles()
				_check_clock(frame)
				p.turbo_boost_max = STOCK_BOOST   # the Tuner fits a turbo
			if waited == 22:
				var pod := frame.pod
				_check(pod != null and pod.get_parent() == frame, "the pod is fitted the tick after the first boost setup")
				if pod != null:
					_check(pod.kind == "p1_coupe" and pod.style == GaugePod.STYLES["p1_coupe"], "the pod wears the coupe's style")
					_check(pod.boost_max == STOCK_BOOST and pod.psi_max == 15.0, "the PSI face is scaled for %.1f bar: max %.0f (want 15)" % [pod.boost_max, pod.psi_max])
					_check(pod.afr_needle != null and pod.psi_needle != null, "two needles")
					var tris := pod.triangle_count()
					_check(tris > 100 and tris < 1600, "the pod is about 1300 triangles (%d)" % tris)
					_check_sightline(pod)
				_go(Step.IDLE)
		Step.IDLE:
			if waited == 90:
				var r: GaugeReadouts = frame.pod.readouts
				_check(r.psi < -5.0 and r.psi > -14.0, "idle manifold reads a vacuum (%.1f psi)" % r.psi)
				_check(absf(r.afr - GaugeReadouts.STOICH) < 0.8, "idle AFR near stoich (%.1f)" % r.afr)
				_check(not r.fuel_cut and not r.boosting, "idle: no fuel cut, no boost")
				var needle: float = rad_to_deg(frame.pod.psi_needle.rotation.z)
				_check(needle > 120.0 - GaugePod.SWEEP * 0.5, "the PSI needle sits left of the zero mark (%.0f deg)" % needle)
				throttle = 1.0
				brake = 0.0
				_go(Step.PULL)
		Step.PULL:
			var r: GaugeReadouts = frame.pod.readouts
			if waited % 30 == 0:
				print("pull t=%d gear %d rpm %.0f boost %.2f bar psi %.1f afr %.1f thr %.2f" % [waited, p.gear, p.motor_rpm, p.boost, r.psi, r.afr, p.throttle_amount])
			peak_psi = maxf(peak_psi, r.psi)
			min_afr = minf(min_afr, r.afr)
			if waited == 540:
				_check(peak_psi > 3.0, "full throttle spools boost: peak %.1f psi (want > 3)" % peak_psi)
				_check(min_afr < 13.0 and min_afr > 10.5, "on boost the AFR goes rich (min %.1f)" % min_afr)
				_check(r.boosting, "the gauge says boosting at the end of the pull (%.1f psi)" % r.psi)
				_check(p.current_speed() > 10.0, "the car is moving (%.1f m/s)" % p.current_speed())
				throttle = 0.0
				_go(Step.LIFT)
		Step.LIFT:
			if waited == 45:
				var r: GaugeReadouts = frame.pod.readouts
				_check(r.fuel_cut, "lift off in gear at speed: the overrun fuel cut (gear %d, rpm %.0f, clutch %.2f)" % [p.gear, p.motor_rpm, p.clutch_amount])
				_check(r.afr > 17.0, "the AFR pegs lean on the cut (%.1f)" % r.afr)
				_check(r.psi < 0.0, "off the throttle the manifold is back in vacuum (%.1f psi)" % r.psi)
				return _end("")
	return false

func _check_styles() -> void:
	for k in PlayerCars.KINDS:
		var id: String = k.id
		_check(GaugePod.STYLES.has(id), "a pod style for %s" % id)
		_check(GaugePod.MOUNTS.has(id), "a pod mount for %s" % id)
		var pod := GaugePod.new(id, 1.5)
		root.add_child(pod)
		_check(pod.psi_max == 30.0, "%s: a 1.5 bar setup gets a 30 psi face (%.0f)" % [id, pod.psi_max])
		_check(pod.triangle_count() > 100, "%s: the pod built (%d tris)" % [id, pod.triangle_count()])
		pod.queue_free()
	_check(GaugePod.psi_face_max(0.5) == 15.0 and GaugePod.psi_face_max(1.0) == 30.0, "PSI face steps: 0.5 bar -> 15, 1.0 bar -> 30")

## The pod sits in the A-pillar zone the sightline spec leaves to the pillars
## (|x| > 0.55 in tests/view/cockpit_interior.gd), inside the cabin, under the
## roof, and ahead of the eye.
func _check_sightline(pod: GaugePod) -> void:
	var pos := pod.position
	_check(absf(pos.x) > 0.55 and pos.x > -0.80, "the pod is on the driver's pillar, inside the cabin (x %.2f)" % pos.x)
	_check(pos.y + GaugePod.GAUGE_R + GaugePod.PITCH * 0.5 < 1.30, "the pod stays under the roof (y %.2f)" % pos.y)
	_check(pos.z < ChaseCamera.COCKPIT_EYE.z - 0.5, "the pod is well ahead of the eye (z %.2f)" % pos.z)
	var to_eye: Vector3 = (ChaseCamera.COCKPIT_EYE - pos).normalized()
	var facing: float = (pod.basis * Vector3.BACK).dot(to_eye)
	_check(facing > 0.97, "the faces point at the eye (cos %.3f)" % facing)

func _check_clock(frame: CockpitFrame) -> void:
	var hu: HeadUnit = frame.head_unit
	_check(hu != null and hu.clock_canvas != null, "the head unit has a clock layer")
	if hu == null or hu.clock_canvas == null:
		return
	_check(hu.clock_text != "" and hu.clock_text.contains(":"), "the clock shows the night clock (%s)" % hu.clock_text)
	_check(hu.is_dimmed(), "the radio starts off, so the screen is dimmed")
	_check(hu.clock_canvas.modulate == Color.WHITE and hu.canvas.modulate.v < 0.5, "the clock layer stays lit while the screen dims")
	_check(hu.clock_canvas.get_index() > hu.canvas.get_index(), "the clock draws over the screen")

func _go(next: Step) -> void:
	step = next
	step_start = tick

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _end(msg: String) -> bool:
	if msg != "":
		failures.append(msg)
	for f in failures:
		printerr("FAIL: ", f)
	print("gauge_pod: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
	return true
