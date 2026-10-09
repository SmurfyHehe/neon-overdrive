extends SceneTree

# Renders the AFR/PSI gauge pod and the head unit clock for judging them by
# eye, for one car (NEON_CAR=<kind>, the coupe by default): a turbo is fitted
# if the car has none (the pod comes with the first boost setup), then
#   <kind>_cockpit.png   the driver's rest view (the pod on the pillar, the radio)
#   <kind>_pod_idle.png  the eye turned to the pod at idle (vacuum, stoich)
#   <kind>_pod_pull.png  the same mid-pull on boost (rich, psi up)
#   <kind>_radio.png     the eye turned to the head unit, radio off, the clock lit
# Needs the real renderer (no --headless). Writes to user://gauge_pod_shots/.
#
#   <godot> --path . -s res://tools/gauge_pod_shots.gd
#   set NEON_CAR=p3_tuner & <godot> --path . -s res://tools/gauge_pod_shots.gd

var game: Node
var throttle := 0.0
var brake := 1.0

func _initialize() -> void:
	AudioSettings.path = "user://gauge_pod_shots_settings.cfg"
	OS.set_environment("NEON_TRAFFIC", "0")
	if OS.get_environment("NEON_CAR") == "":
		OS.set_environment("NEON_CAR", "p1_coupe")
	game = (load("res://Game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game   # the frame finds the night clock through the current scene
	_run.call_deferred()

func _run() -> void:
	for i in 30:
		await process_frame
	var p: PlayerCar = game.get("player")
	var cam: ChaseCamera = game.get("camera")
	var kind := PlayerCar.chassis_kind()
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = throttle
		c.brake_input = brake
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	var frame: CockpitFrame = cam.frame
	if p.turbo_boost_max <= 0.0:
		p.turbo_boost_max = 0.7   # the Tuner's turbo, so the pod is fitted
	for i in 60:
		await physics_frame
	var dir := ProjectSettings.globalize_path("user://gauge_pod_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var pod: GaugePod = frame.pod
	print("%s: pod %s, psi face max %.0f, %d tris, clock '%s'" % [kind, "fitted" if pod != null else "MISSING", pod.psi_max if pod != null else 0.0, pod.triangle_count() if pod != null else 0, frame.head_unit.clock_text])
	# the game's own cockpit camera: what the player sees at rest
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_cockpit.png" % [dir, kind])
	var shot := Camera3D.new()
	shot.fov = 50.0
	shot.near = 0.03
	root.add_child(shot)
	var pod_at: Vector3 = frame.to_global(pod.position) if pod != null else frame.to_global(Vector3(-0.7, 1.0, -0.45))
	var eye_at: Vector3 = p.global_transform * cam.eye
	shot.global_position = eye_at
	shot.look_at(pod_at)
	shot.make_current()
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_pod_idle.png" % [dir, kind])
	if pod != null:
		print("idle: psi %.1f afr %.1f" % [pod.readouts.psi, pod.readouts.afr])
	# a pull: wait for boost, then shoot
	throttle = 1.0
	brake = 0.0
	var waited := 0
	while waited < 60 * 12 and (pod == null or pod.readouts.psi < 4.0):
		await physics_frame
		waited += 1
	shot.global_position = p.global_transform * cam.eye
	shot.look_at(frame.to_global(pod.position) if pod != null else pod_at)
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_pod_pull.png" % [dir, kind])
	if pod != null:
		print("pull: psi %.1f afr %.1f boost %.2f bar rpm %.0f gear %d" % [pod.readouts.psi, pod.readouts.afr, p.boost, p.motor_rpm, p.gear])
	throttle = 0.0
	brake = 1.0
	for i in 90:
		await physics_frame
	# the head unit, radio off: the clock is lit
	shot.global_position = p.global_transform * cam.eye
	shot.look_at(frame.to_global(CockpitFrame.HEAD_UNIT_POS))
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_radio.png" % [dir, kind])
	print("radio: station %d dimmed %s clock '%s'" % [frame.head_unit.station, str(frame.head_unit.is_dimmed()), frame.head_unit.clock_text])
	print("wrote ", dir)
	quit(0)
