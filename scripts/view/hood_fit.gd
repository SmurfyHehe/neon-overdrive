extends RefCounted

# Fits the hood view's two default camera points to the car's actual body
# (2026-10-11). CabinSpec gives each car a starting point from its cabin
# numbers; those are measured inside the cabin and a car with no CABIN of its
# own wears the coupe's, so on a tall bonnet, a raked windscreen or a bolted-on
# scoop the starting point can sit inside the body. This reads the body's
# triangles (any facing: the highest surface in a column is the top one, and
# Godot's winding makes "up" depend on the mesh) into a height map of the top
# surface (5 cm cells, the car centre strip only) and:
#   - hood camera: keeps the starting point if the highest surface within 0.3 m
#     of it (the 0.6 m box) is CLEAR below it; otherwise walks forward along the
#     bonnet (never nearer the nose than NOSE_MARGIN) to the lowest spot and
#     rises only as far as it has to;
#   - roof camera: rises to CLEAR above the highest surface within 0.3 m.
# A car whose CABIN has its own hood_cam / roof_back_cam is not fitted: those
# are the designed points. Runs when the hood view is entered (the body can
# change in the garage), about a few thousand triangles, a few milliseconds.

const CELL := 0.05
const BOX_HALF := 0.3       # the box round the camera that must stay under it
const CLEAR := 0.06         # m between the camera and the highest surface in the box
const NOSE_MARGIN := 0.45   # the hood camera stays this far behind the nose
const STEP := 0.05

var _z_lo := 0.0
var _nz := 0
var _nx := 0
var _grid := PackedFloat32Array()
var nose_z := 0.0
var empty := true

## Rasterises the body's top surface. `to_car` maps a mesh's global transform
## into the car's own space (target.global_transform.affine_inverse()).
func build(body: Node3D, to_car: Transform3D) -> void:
	if body == null:
		return
	var tris := PackedVector3Array()
	var lo_z := INF
	var hi_z := -INF
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _under_underside(mi):
			continue
		var xf := to_car * mi.global_transform
		for v in mi.mesh.get_faces():
			var w: Vector3 = xf * v
			tris.append(w)
			lo_z = minf(lo_z, w.z)
			hi_z = maxf(hi_z, w.z)
	if tris.is_empty():
		return
	nose_z = lo_z
	_z_lo = lo_z
	_nx = int(ceil(2.0 * BOX_HALF / CELL)) + 1
	_nz = int(ceil((hi_z - lo_z) / CELL)) + 1
	_grid.resize(_nx * _nz)
	_grid.fill(-INF)
	empty = false
	var i := 0
	while i + 2 < tris.size():
		_raster(tris[i], tris[i + 1], tris[i + 2])
		i += 3

static func _under_underside(n: Node) -> bool:
	var q := n
	while q != null:
		if q.name == Undercarriage.NODE_NAME or q.name == Undercarriage.PLATE_NAME:
			return true
		q = q.get_parent()
	return false

func _raster(a: Vector3, b: Vector3, c: Vector3) -> void:
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	if max_x < -BOX_HALF - CELL or min_x > BOX_HALF + CELL:
		return
	# vertices count on their own cell (a triangle smaller than a cell)
	for v in [a, b, c]:
		_put(v.x, v.z, v.y)
	var min_z := minf(a.z, minf(b.z, c.z))
	var max_z := maxf(a.z, maxf(b.z, c.z))
	var ix0 := maxi(0, int(ceil((min_x + BOX_HALF) / CELL)))
	var ix1 := mini(_nx - 1, int(floor((max_x + BOX_HALF) / CELL)))
	var iz0 := maxi(0, int(ceil((min_z - _z_lo) / CELL)))
	var iz1 := mini(_nz - 1, int(floor((max_z - _z_lo) / CELL)))
	# y = a.y - (nx * (x - a.x) + nz * (z - a.z)) / ny, the plane through the triangle
	var d := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if absf(d) < 1.0e-9:
		return
	for iz in range(iz0, iz1 + 1):
		var z := _z_lo + float(iz) * CELL
		for ix in range(ix0, ix1 + 1):
			var x := -BOX_HALF + float(ix) * CELL
			var u := ((x - a.x) * (c.z - a.z) - (c.x - a.x) * (z - a.z)) / d
			var v := ((b.x - a.x) * (z - a.z) - (x - a.x) * (b.z - a.z)) / d
			if u < 0.0 or v < 0.0 or u + v > 1.0:
				continue
			var y := a.y + u * (b.y - a.y) + v * (c.y - a.y)
			var k := iz * _nx + ix
			if y > _grid[k]:
				_grid[k] = y

func _put(x: float, z: float, y: float) -> void:
	var ix := int(round((x + BOX_HALF) / CELL))
	var iz := int(round((z - _z_lo) / CELL))
	if ix < 0 or ix >= _nx or iz < 0 or iz >= _nz:
		return
	var k := iz * _nx + ix
	if y > _grid[k]:
		_grid[k] = y

## The highest top surface within BOX_HALF of z (x within BOX_HALF of the
## centre line); -INF if the body has none there.
func box_top(z: float) -> float:
	if empty:
		return -INF
	var iz0 := maxi(0, int(ceil((z - BOX_HALF - _z_lo) / CELL)))
	var iz1 := mini(_nz - 1, int(floor((z + BOX_HALF - _z_lo) / CELL)))
	var top := -INF
	for iz in range(iz0, iz1 + 1):
		for ix in _nx:
			top = maxf(top, _grid[iz * _nx + ix])
	return top

## The hood camera for a starting point (car space): the same point when it
## clears the body, else the lowest nearby spot forward on the bonnet.
func fit_hood(start: Vector3) -> Vector3:
	if empty:
		return start
	var best := start
	var best_need := INF
	var z := start.z
	var z_min := nose_z + NOSE_MARGIN
	while true:
		var top := box_top(z)
		var need := start.y if top == -INF else maxf(start.y, top + CLEAR)
		if need < best_need - 0.005:
			best_need = need
			best = Vector3(start.x, need, z)
		z -= STEP
		if z < z_min:
			break
	return best

## The roof camera: the starting point, risen to clear the surface under it.
func fit_roof(start: Vector3) -> Vector3:
	if empty:
		return start
	var top := box_top(start.z)
	if top == -INF:
		return start
	return Vector3(start.x, maxf(start.y, top + CLEAR), start.z)
