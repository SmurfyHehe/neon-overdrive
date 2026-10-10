class_name NativeTyres
extends RefCounted

# Switch for the C++ tyre maths experiment (2026-10-10). Off by default: every
# car runs the vendored GDScript wheel. On (environment variable
# NEON_NATIVE_TYRES=1, or NativeTyres.enabled = true before cars are built),
# new wheels are scripts/car/gevp_wheel_native.gd, if the library is loaded.

const WHEEL_SCRIPT := "res://scripts/car/gevp_wheel_native.gd"

static var enabled := OS.get_environment("NEON_NATIVE_TYRES") == "1"

static func available() -> bool:
	return ClassDB.class_exists(&"GevpTyreNative")

static func active() -> bool:
	return enabled and available()

static func new_wheel() -> Wheel:
	if active():
		return (load(WHEEL_SCRIPT) as GDScript).new()
	return Wheel.new()
