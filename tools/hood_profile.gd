extends SceneTree

# Prints each player car's bonnet profile for choosing hood_cam by hand
# (2026-10-11): the highest top surface in the camera's 0.6 m box at every
# 5 cm along the centre line from the nose back to the windscreen base, the
# CabinSpec default point and the fitted point. Headless is fine.
#
#   <godot> --headless --audio-driver Dummy --path . -s res://tools/hood_profile.gd

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const HoodFit := preload("res://scripts/view/hood_fit.gd")

var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		OS.set_environment("NEON_CAR", kind)
		AudioSettings.path = Harness.SETTINGS_PATH
		game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
		await _frames(30)
		var p: PlayerCar = game.get("player")
		var cab := CabinSpec.for_kind(PlayerCar.chassis_kind())
		var fit = HoodFit.new()
		fit.build(p.chassis_visual, p.global_transform.affine_inverse())
		var dflt := CabinSpec.hood_cam(cab)
		print("CAR %s nose_z %.3f cowl %s default %s fitted %s roof_default %s" % [kind, fit.nose_z, cab.cowl, dflt, fit.fit_hood(dflt), CabinSpec.roof_back_cam(cab)])
		var z: float = fit.nose_z
		var line := ""
		while z < float(cab.cowl.y) + 0.4:
			line += "%.2f:%.3f " % [z, fit.box_top(z)]
			z += 0.05
		print("PROFILE %s %s" % [kind, line])
		game.queue_free()
		await process_frame
		await process_frame
	OS.set_environment("NEON_CAR", "")
	quit(0)
