class_name ViewSettings
extends RefCounted

# View settings (2026-10-06): the cockpit field of view, in the same
# user://settings.cfg AudioSettings uses (its own [view] section). The pause
# menu shows one slider; ChaseCamera reads cockpit_fov every frame, so a change
# applies at once. The speed widening (up to +6 degrees) is added on top.
# The View page (camera proposal section 4, Roy 1494, 2026-10-13) adds the chase
# distance (Near / Normal / Far), a chase FOV, a hood FOV of its own (the hood
# used the cockpit's) and the "remember last view" switch; ChaseCamera reads
# them every frame too. The shake and FOV-widening rows on that page are
# AccessSettings ([access]); head motion is FxSettings ([fx]).

const COCKPIT_FOV_DEFAULT := 62.0
const COCKPIT_FOV_MIN := 55.0
const COCKPIT_FOV_MAX := 78.0

## Chase distance: Near / Normal / Far. Far is the police view: 1.4x the
## distance and 0.6 m higher, so a cop on the bumper and the road ahead both
## show. A choice of three, not a slider (a 2.73x looks wrong and gets reported).
const CHASE_DISTANCES := ["Near", "Normal", "Far"]
const CHASE_DIST_SCALE := [0.85, 1.0, 1.4]
const CHASE_DIST_LIFT := [0.0, 0.0, 0.6]   # metres added to the chase height
const CHASE_DISTANCE_DEFAULT := 1
## The chase view's resting FOV (vertical degrees); the speed widening rides on top.
const CHASE_FOV_DEFAULT := 58.0
const CHASE_FOV_MIN := 50.0
const CHASE_FOV_MAX := 70.0
## The hood view's own FOV (1500: 65, a touch wider than the cockpit's 62: there
## is no dash to crop).
const HOOD_FOV_DEFAULT := 65.0
const HOOD_FOV_MIN := 55.0
const HOOD_FOV_MAX := 85.0
## Chase follow, the smoothing modes A / B / C by their View page names.
const FOLLOW_NAMES := ["Tight", "Smooth", "Loose"]
## Pillars see-through (#738, Roy 1549): in the cockpit view the A-pillar trim
## is drawn this much see-through, 0 = solid. Capped so a pillar never vanishes.
const PILLAR_SEE_THROUGH_DEFAULT := 0.35
const PILLAR_SEE_THROUGH_MAX := 0.7

const CAMERA_SMOOTHING_DEFAULT := 1   # chase-cam smoothing (#31): 0 A hard snap, 1 B light (default, #119), 2 C smoothing + swing
const CAMERA_SMOOTHING_MAX := 2

## The view F left the game in (2026-10-11): "chase", "cockpit" or "hood". Chase
## is where the game has always started; flip the default here to start elsewhere.
const CAMERA_VIEWS := ["chase", "cockpit", "hood"]
const CAMERA_VIEW_DEFAULT := "chase"

static var cockpit_fov := COCKPIT_FOV_DEFAULT
static var camera_view := CAMERA_VIEW_DEFAULT
static var chase_distance := CHASE_DISTANCE_DEFAULT
static var chase_fov := CHASE_FOV_DEFAULT
static var hood_fov := HOOD_FOV_DEFAULT
static var pillar_see_through := PILLAR_SEE_THROUGH_DEFAULT
## Off: every start is in the chase view, whatever F left.
static var remember_view := true

## Whether the view F left is remembered across starts. Play only: on the test
## folder's shared settings file one test's last F press would start the next
## one in another view. A test that sets its own AudioSettings.path opts in.
static func remembers_view() -> bool:
	var TestMode := preload("res://scripts/core/test_mode.gd")
	return remember_view and (not TestMode.active() or AudioSettings.path != AudioSettings.default_path())

static func set_camera_view(v: String) -> void:
	camera_view = v if CAMERA_VIEWS.has(v) else CAMERA_VIEW_DEFAULT
static var camera_smoothing := CAMERA_SMOOTHING_DEFAULT

static func set_camera_smoothing(v: int) -> void:
	camera_smoothing = clampi(v, 0, CAMERA_SMOOTHING_MAX)

static func set_cockpit_fov(v: float) -> void:
	cockpit_fov = clampf(v, COCKPIT_FOV_MIN, COCKPIT_FOV_MAX) if is_finite(v) else COCKPIT_FOV_DEFAULT  # clampf passes NaN through

static func set_chase_fov(v: float) -> void:
	chase_fov = clampf(v, CHASE_FOV_MIN, CHASE_FOV_MAX) if is_finite(v) else CHASE_FOV_DEFAULT

static func set_hood_fov(v: float) -> void:
	hood_fov = clampf(v, HOOD_FOV_MIN, HOOD_FOV_MAX) if is_finite(v) else HOOD_FOV_DEFAULT

static func set_pillar_see_through(v: float) -> void:
	pillar_see_through = clampf(v, 0.0, PILLAR_SEE_THROUGH_MAX) if is_finite(v) else PILLAR_SEE_THROUGH_DEFAULT

static func set_chase_distance(i: int) -> void:
	chase_distance = clampi(i, 0, CHASE_DISTANCES.size() - 1)

## The chase rig's distance multiplier and extra height for the setting.
static func chase_dist_scale() -> float:
	return CHASE_DIST_SCALE[chase_distance]

static func chase_dist_lift() -> float:
	return CHASE_DIST_LIFT[chase_distance]

## The View page's "Reset view" row: every row on that page back to its
## default (the view F is in now is left alone). Saves nothing by itself.
static func reset_view() -> void:
	cockpit_fov = COCKPIT_FOV_DEFAULT
	chase_fov = CHASE_FOV_DEFAULT
	hood_fov = HOOD_FOV_DEFAULT
	pillar_see_through = PILLAR_SEE_THROUGH_DEFAULT
	chase_distance = CHASE_DISTANCE_DEFAULT
	camera_smoothing = CAMERA_SMOOTHING_DEFAULT
	remember_view = true
	AccessSettings.reset()
	FxSettings.set_on("head_motion", true)

## Reads the file (missing or damaged means the default). Shares AudioSettings.path
## so tests that redirect one redirect all.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(AudioSettings.path) == OK
	set_cockpit_fov(float(cfg.get_value("view", "cockpit_fov", COCKPIT_FOV_DEFAULT)) if ok else COCKPIT_FOV_DEFAULT)
	set_camera_smoothing(int(cfg.get_value("view", "camera_smoothing", CAMERA_SMOOTHING_DEFAULT)) if ok else CAMERA_SMOOTHING_DEFAULT)
	set_camera_view(str(cfg.get_value("view", "camera_view", CAMERA_VIEW_DEFAULT)) if ok else CAMERA_VIEW_DEFAULT)
	set_chase_distance(int(cfg.get_value("view", "chase_distance", CHASE_DISTANCE_DEFAULT)) if ok else CHASE_DISTANCE_DEFAULT)
	set_chase_fov(float(cfg.get_value("view", "chase_fov", CHASE_FOV_DEFAULT)) if ok else CHASE_FOV_DEFAULT)
	set_hood_fov(float(cfg.get_value("view", "hood_fov", HOOD_FOV_DEFAULT)) if ok else HOOD_FOV_DEFAULT)
	set_pillar_see_through(float(cfg.get_value("view", "pillar_see_through", PILLAR_SEE_THROUGH_DEFAULT)) if ok else PILLAR_SEE_THROUGH_DEFAULT)
	remember_view = FxSettings._to_bool(cfg.get_value("view", "remember_view", true)) if ok else true

## Rewrites only the [view] section; the other sections stay.
static func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(AudioSettings.path)
	cfg.set_value("view", "cockpit_fov", cockpit_fov)
	cfg.set_value("view", "camera_smoothing", camera_smoothing)
	cfg.set_value("view", "camera_view", camera_view)
	cfg.set_value("view", "chase_distance", chase_distance)
	cfg.set_value("view", "chase_fov", chase_fov)
	cfg.set_value("view", "hood_fov", hood_fov)
	cfg.set_value("view", "pillar_see_through", pillar_see_through)
	cfg.set_value("view", "remember_view", remember_view)
	return cfg.save(AudioSettings.path) == OK
