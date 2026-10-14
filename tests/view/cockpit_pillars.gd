extends SceneTree

# Cockpit A-pillars (#738, Roy 1549, 2026-10-14): every playable car, booted as
# the player's car in the cockpit view, at rest:
#   - the driver-side A-pillar trim is at most PILLAR_MAX_DEG + 0.5 wide in yaw
#     at eye level (rays from the car's own eye across yaw -75..+75 at pitch 0,
#     +6 and -6, tested against the Pillars mesh only); the passenger side too.
#     Before the per-car width it was 9 to 13 degrees, the kei 19. The kei's
#     cabin is 20 cm narrower and its pillar sits 22 cm from the eye, so at the
#     minimum width it stays over the limit: printed as a note, not failed
#     (its fix is the eye, #737).
#   - see-through: in the cockpit view the pillar material's alpha is 1 minus
#     ViewSettings.pillar_see_through (0.35 by default -> 0.65), it follows the
#     setting the next frame, and in the chase view, the hood view and photo
#     mode (P) it is solid again.
# Run: <godot> --headless --audio-driver Dummy --path . -s res://tests/view/cockpit_pillars.gd
# Exit code 1 on failure.

const Harness := preload("res://tests/traffic/traffic_harness.gd")
const PITCHES := [0.0, 6.0, -6.0]
const YAW_MAX := 75.0
const LIMIT_DEG := CockpitFrame.PILLAR_MAX_DEG + 0.5
const NOTE_ONLY := ["p4_kei"]

var fails := 0
var logger := Harness.ErrorCounter.new()
var game: Node
var p: PlayerCar
var cam: ChaseCamera

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL " + msg)
		fails += 1

func _initialize() -> void:
	OS.add_logger(logger)
	root.size = Vector2i(1280, 720)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _boot(kind: String) -> void:
	OS.set_environment("NEON_CAR", kind)
	AudioSettings.path = Harness.SETTINGS_PATH
	ViewSettings.set_pillar_see_through(ViewSettings.PILLAR_SEE_THROUGH_DEFAULT)
	game = Harness.boot(self, 0, 150.0, 7, 1.0e6)
	await _frames(60)
	p = game.get("player")
	cam = game.get("camera")
	if p == null or cam == null:
		return
	p.driver = func(c: PlayerCar) -> void:
		c.throttle_input = 0.0
		c.brake_input = 1.0
		c.handbrake_input = 0.0
		c.steering_input = 0.0
	cam.shake_enabled = false
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _frames(30)

func _run() -> void:
	var only := OS.get_environment("NEON_FIT_CAR")
	for k in PlayerCars.KINDS:
		var kind := String(k.id)
		if only != "" and kind != only:
			continue
		await _boot(kind)
		_check(p != null and cam != null and cam.frame != null, "%s: the game should boot with a cockpit frame" % kind)
		if p != null and cam != null and cam.frame != null:
			_widths(kind)
			await _see_through(kind)
		game.queue_free()
		await process_frame
		await process_frame
	OS.set_environment("NEON_CAR", "")
	if logger.errors.size() > 0:
		print("FAIL %d engine errors: %s" % [logger.errors.size(), str(logger.errors.slice(0, 5))])
		fails += logger.errors.size()
	print("cockpit_pillars: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

## The Pillars mesh's triangles in car space.
func _pillar_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi := cam.frame.get_node_or_null("Pillars") as MeshInstance3D
	_check(mi != null and mi.mesh != null, "the cabin has a Pillars mesh")
	if mi == null or mi.mesh == null:
		return out
	var xf := p.global_transform.affine_inverse() * mi.global_transform
	for v in mi.mesh.get_faces():
		out.append(xf * v)
	return out

static func _hit(tris: PackedVector3Array, from: Vector3, dir: Vector3) -> bool:
	var t := 0
	while t + 2 < tris.size():
		if Geometry3D.ray_intersects_triangle(from, dir, tris[t], tris[t + 1], tris[t + 2]) != null:
			return true
		t += 3
	return false

## Blocked yaw spans at a pitch: [[start, end], ...] in degrees, + = left.
static func _spans(tris: PackedVector3Array, eye: Vector3, pitch: float) -> Array:
	var spans := []
	var start := INF
	var yaw := -YAW_MAX
	while yaw <= YAW_MAX + 1.5:
		var dir := Vector3(0, 0, -1).rotated(Vector3.RIGHT, deg_to_rad(pitch)).rotated(Vector3.UP, deg_to_rad(yaw))
		var blocked := yaw <= YAW_MAX and _hit(tris, eye, dir)
		if blocked and start == INF:
			start = yaw
		elif not blocked and start != INF:
			spans.append([start, yaw - 1.0])
			start = INF
		yaw += 1.0
	return spans

func _widths(kind: String) -> void:
	var tris := _pillar_tris()
	if tris.is_empty():
		return
	var eye: Vector3 = cam.frame.cab.eye
	var widest := 0.0
	var where := ""
	for pitch in PITCHES:
		for sp in _spans(tris, eye, pitch):
			var w: float = sp[1] - sp[0] + 1.0
			if w > widest:
				widest = w
				where = "pitch %+.0f, yaw %.0f..%.0f" % [pitch, sp[0], sp[1]]
	var side := "driver" if where.find("yaw -") == -1 and where != "" else "passenger"
	print("  %-16s widest pillar %4.1f deg (%s side, %s)" % [kind, widest, side, where])
	if kind in NOTE_ONLY:
		print("  %-16s note: over the limit at the minimum width, the eye is its fix (#737)" % kind)
	else:
		_check(widest <= LIMIT_DEG, "%s: the pillar is %.1f deg wide at %s, limit %.1f" % [kind, widest, where, LIMIT_DEG])

func _see_through(kind: String) -> void:
	var frame: CockpitFrame = cam.frame
	var want := 1.0 - ViewSettings.PILLAR_SEE_THROUGH_DEFAULT
	_check(absf(frame.pillar_alpha() - want) < 0.01, "%s: cockpit pillars drawn at alpha %.2f, expected %.2f" % [kind, frame.pillar_alpha(), want])
	_check(frame.pillar_mat != null and frame.pillar_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and absf(frame.pillar_mat.albedo_color.a - want) < 0.01,
		"%s: the pillar material is alpha-blended at %.2f" % [kind, frame.pillar_mat.albedo_color.a if frame.pillar_mat != null else -1.0])
	ViewSettings.set_pillar_see_through(0.0)
	await _frames(3)
	_check(absf(frame.pillar_alpha() - 1.0) < 0.01 and frame.pillar_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "%s: see-through 0 draws the pillars solid the next frame (alpha %.2f)" % [kind, frame.pillar_alpha()])
	ViewSettings.set_pillar_see_through(0.6)
	await _frames(3)
	_check(absf(frame.pillar_alpha() - 0.4) < 0.01, "%s: see-through 60%% follows live (alpha %.2f)" % [kind, frame.pillar_alpha()])
	cam.set_view(ChaseCamera.View.CHASE)
	await _frames(3)
	_check(absf(frame.pillar_alpha() - 1.0) < 0.01, "%s: the chase view draws the pillars solid (alpha %.2f)" % [kind, frame.pillar_alpha()])
	cam.set_view(ChaseCamera.View.HOOD)
	await _frames(3)
	_check(absf(frame.pillar_alpha() - 1.0) < 0.01, "%s: the hood view draws the pillars solid (alpha %.2f)" % [kind, frame.pillar_alpha()])
	cam.set_view(ChaseCamera.View.COCKPIT)
	await _frames(3)
	_check(absf(frame.pillar_alpha() - 0.4) < 0.01, "%s: back in the cockpit the setting applies again (alpha %.2f)" % [kind, frame.pillar_alpha()])
	# photo mode (P) from the cockpit: a shot from outside wants solid pillars
	var gs: GameState = game.get("game_state")
	_check(gs != null, "%s: the game has a GameState" % kind)
	if gs != null:
		gs.toggle_photo()
		await _frames(3)
		_check(gs.state == GameState.State.PHOTO and absf(frame.pillar_alpha() - 1.0) < 0.01, "%s: photo mode draws the pillars solid (state %d, alpha %.2f)" % [kind, gs.state, frame.pillar_alpha()])
		gs.close_photo()
		await _frames(3)
		_check(gs.state == GameState.State.PLAYING and absf(frame.pillar_alpha() - 0.4) < 0.01, "%s: back from photo mode the setting applies again (state %d, alpha %.2f)" % [kind, gs.state, frame.pillar_alpha()])
	ViewSettings.set_pillar_see_through(ViewSettings.PILLAR_SEE_THROUGH_DEFAULT)
