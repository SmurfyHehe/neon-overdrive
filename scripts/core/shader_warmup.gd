extends Node

# Shader warm-up (graphics setup, 2026-10-10): runs behind the splash.
#
# Godot builds a shader pipeline the first time a material is drawn in a new
# way. Most are built on background threads, but one that is needed right now
# and is not ready stalls that frame ("draw" in the benchmark's pipeline
# lines), and the background ones still eat processor time while they run.
# Without this, that work lands in the first seconds of the drive and again
# whenever something shows up for the first time: the first exhaust flame, the
# first tyre smoke, the cockpit.
#
# Two steps, both while the splash covers the screen:
#  1. Every mesh, multimesh and particle node that is in the scene but hidden
#     (so it has never been drawn) gets a tiny stand-in drawn in front of the
#     camera for a few frames, a few per frame so the splash keeps moving.
#  2. Then it waits until Godot has stopped compiling (the pipeline counters
#     hold still), so the background work is finished before the drive.
# The splash holds its last pose until busy() is false; MAX_SECS bounds it and
# any key still skips the splash.
#
# Costs nothing afterwards: the node frees itself and its stand-ins.

const PER_FRAME := 16        # stand-ins added per frame
const LIVE_FRAMES := 4       # frames each stand-in is drawn
const QUIET_FRAMES := 30     # frames with no new pipeline = settled
const MAX_SECS := 6.0        # give up and let the game start
const PROXY_SIZE := 0.02     # metres: the stand-ins' size, 1.5 m ahead
const PIPELINE_MONITORS := [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
	Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]

static var _busy := false
## Last run, for the benchmark and tests: stand-ins drawn, pipelines compiled
## while it ran, seconds it took.
static var last := {"proxies": 0, "pipelines": 0, "secs": 0.0}

var _queue: Array[Node3D] = []
var _live: Array = []          # [node, frames left]
var _holder: Node3D
var _t := 0.0
var _quiet := 0
var _count_start := 0
var _count_last := 0
var _made := 0

static func busy() -> bool:
	return _busy

static func pipeline_count() -> int:
	var n := 0
	for m in PIPELINE_MONITORS:
		n += int(Performance.get_monitor(m))
	return n

func _ready() -> void:
	_busy = true
	process_mode = Node.PROCESS_MODE_ALWAYS   # the title holds the world paused
	_count_start = pipeline_count()
	_count_last = _count_start
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_holder = Node3D.new()
	_holder.name = "ShaderWarmupProxies"
	cam.add_child(_holder)
	_holder.position = Vector3(0.0, 0.0, -1.5)
	_collect(get_tree().root, {})

func _exit_tree() -> void:
	_busy = false
	if is_instance_valid(_holder):
		_holder.queue_free()
	for p in _queue:
		if is_instance_valid(p) and not p.is_inside_tree():
			p.free()

func _process(delta: float) -> void:
	_t += delta
	for i in range(_live.size() - 1, -1, -1):
		_live[i][1] -= 1
		if _live[i][1] <= 0:
			# a stand-in goes with its holder when the camera it hangs off is freed
			var proxy: Variant = _live[i][0]
			if is_instance_valid(proxy):
				(proxy as Node).queue_free()
			_live.remove_at(i)
	if is_instance_valid(_holder):
		for i in mini(PER_FRAME, _queue.size()):
			var p: Node3D = _queue.pop_back()
			_holder.add_child(p)
			_live.append([p, LIVE_FRAMES])
			_made += 1
	var count := pipeline_count()
	_quiet = _quiet + 1 if count == _count_last else 0
	_count_last = count
	var drained := _queue.is_empty() and _live.is_empty()
	if (drained and _quiet >= QUIET_FRAMES) or _t >= MAX_SECS:
		last = {"proxies": _made, "pipelines": count - _count_start, "secs": _t}
		print_verbose("ShaderWarmup: %d stand-ins, %d pipelines, %.2f s" % [_made, count - _count_start, _t])
		queue_free()

## Walks the tree for drawable nodes nothing has drawn yet (hidden ones), one
## stand-in per different mesh + material set.
func _collect(node: Node, seen: Dictionary) -> void:
	if node == _holder:
		return
	if node is GeometryInstance3D and not (node as Node3D).is_visible_in_tree():
		var key := _key(node)
		if key != "" and not seen.has(key):
			seen[key] = true
			var p := _proxy(node)
			if p != null:
				_queue.append(p)
	for c in node.get_children():
		_collect(c, seen)

static func _key(node: Node) -> String:
	var g := node as GeometryInstance3D
	var k := "%s|%d" % [node.get_class(), _id(g.material_override)]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return ""
		k += "|%d" % mi.mesh.get_instance_id()
		for s in mi.get_surface_override_material_count():
			k += ",%d" % _id(mi.get_surface_override_material(s))
	elif node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return ""
		k += "|%d|%s%s" % [mm.mesh.get_instance_id(), mm.use_colors, mm.use_custom_data]
	elif node is GPUParticles3D:
		var gp := node as GPUParticles3D
		if gp.draw_pass_1 == null:
			return ""
		k += "|%d|%d" % [gp.draw_pass_1.get_instance_id(), _id(gp.process_material)]
	elif node is CPUParticles3D:
		var cp := node as CPUParticles3D
		if cp.mesh == null:
			return ""
		k += "|%d" % cp.mesh.get_instance_id()
	else:
		return ""
	return k

static func _id(o: Object) -> int:
	return 0 if o == null else o.get_instance_id()

## A small copy that draws the same mesh with the same materials.
static func _proxy(node: Node) -> Node3D:
	var size := 1.0
	var out: GeometryInstance3D
	if node is MeshInstance3D:
		var src := node as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		for s in src.get_surface_override_material_count():
			mi.set_surface_override_material(s, src.get_surface_override_material(s))
		mi.skeleton = NodePath()
		size = src.mesh.get_aabb().get_longest_axis_size()
		out = mi
	elif node is MultiMeshInstance3D:
		var smm := (node as MultiMeshInstance3D).multimesh
		var mm := MultiMesh.new()
		mm.transform_format = smm.transform_format
		mm.use_colors = smm.use_colors
		mm.use_custom_data = smm.use_custom_data
		mm.mesh = smm.mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		size = smm.mesh.get_aabb().get_longest_axis_size()
		out = mmi
	elif node is GPUParticles3D:
		var sg := node as GPUParticles3D
		var gp := GPUParticles3D.new()
		gp.process_material = sg.process_material
		gp.draw_pass_1 = sg.draw_pass_1
		gp.amount = 1
		gp.lifetime = 0.5
		gp.local_coords = true
		gp.emitting = true
		size = maxf(sg.draw_pass_1.get_aabb().get_longest_axis_size(), 1.0) * 20.0   # particles fly off: keep them tiny
		out = gp
	elif node is CPUParticles3D:
		var sc := node as CPUParticles3D
		var cp := CPUParticles3D.new()
		cp.mesh = sc.mesh
		cp.amount = 1
		cp.lifetime = 0.5
		cp.local_coords = true
		cp.emitting = true
		size = maxf(sc.mesh.get_aabb().get_longest_axis_size(), 1.0) * 20.0
		out = cp
	if out == null:
		return null
	var g := node as GeometryInstance3D
	out.material_override = g.material_override
	out.material_overlay = g.material_overlay
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.layers = 1
	out.scale = Vector3.ONE * (PROXY_SIZE / maxf(size, 0.001))
	return out
