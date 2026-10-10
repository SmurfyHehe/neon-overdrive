extends RefCounted

# Roadside building kit (buildings step 1, 2026-10-07): one shared facade
# material for every building, varied per building instead of per material.
#
# Before: every building was the same dark box wearing one of two materials
# with the same world-space window grid, so the street read as one long
# apartment block. Now each building picks:
# - a facade tile from an 8-tile atlas (apartment bays, shop glass, office
#   ribbon, warehouse door, open parking slab, brick, concrete panel,
#   corrugated metal), with a separate ground-floor row so shops get glass
#   and warehouses get roller doors at street level,
# - a base tint from the Amber vs Dusk palette (dark brick, concrete, navy,
#   sand, soot, rust),
# - a floor count (the tile repeats once per floor, so the roof line always
#   lands on a whole floor),
# - a lit-window density.
#
# All of that goes in per-instance shader parameters (instance uniforms) on
# ONE ShaderMaterial, so variety costs no extra materials, meshes or nodes.
# The facade is mapped in the building's own space, not world space, so a
# floating-origin recentre cannot shift the pattern.
#
# The atlas is drawn here in code (no image asset to import), 32x32 px per
# tile with nearest filtering for the PS2 look. Each tile is one bay wide and
# one floor tall: RGB is albedo detail (multiplied by the tint), alpha marks
# glass that may light up.
#
# World step 3 (W6, 2026-10-10) grows the atlas from 8 to 12 tiles for the
# new district kinds: loft (factory windows in brick), clapboard (timber
# house siding), hangar (pale metal panels, a sliding door) and container
# (a stack of shipping containers, each one its own colour). It also adds
# district palettes: a Districts spec may weight the TINTS it draws from.
#
# Step 2 adds building types on top (see TYPES) and shop / garage signs
# (scripts/world/building_signs.gd). Which windows are lit is decided per window in the
# shader from a hash, so it never repeats from one building to the next.
#
# World step 3 (2026-10-10): shop fronts with life inside. The ground-floor
# glass of a shop shows a lit room behind it, drawn by the same shader with
# interior mapping: the view ray is traced from the glass into a box one bay
# wide, one floor tall and ROOM_DEPTH deep, and whichever wall it hits is
# painted from a hash (shelves, washing machines, a back bar with figures, a
# bare room with one security light). No geometry, no texture, no extra draw
# call: the room costs fragments only where shop glass is on screen. Shops
# roll a shutter down as the night clock passes their closing time (ROOMS
# below, jittered per building); bars stay lit to closing. What a district's
# shops are is data (Districts "fronts").

const BuildingSigns := preload("res://scripts/world/building_signs.gd")
const Districts := preload("res://scripts/world/districts.gd")

const TILE_PX := 32
const TILES := 12

# Tile ids (atlas columns).
const T_APARTMENT := 0
const T_SHOP := 1
const T_OFFICE := 2
const T_WAREHOUSE := 3
const T_PARKING := 4
const T_BRICK := 5
const T_CONCRETE := 6
const T_CORRUGATED := 7
const T_LOFT := 8
const T_CLAPBOARD := 9
const T_HANGAR := 10
const T_CONTAINER := 11

# Floor-to-floor height per tile, m (approximate real values: offices are
# taller than flats; warehouses are one tall storey; a mill floor is 4 m, a
# hangar bay 6 m, a shipping container 2.6 m).
const FLOOR_H := [3.0, 3.4, 3.6, 4.5, 3.0, 3.1, 3.2, 4.2, 4.0, 2.8, 6.0, 2.6]
# Nominal bay width per tile, m. The shader rounds each face to a whole
# number of bays so windows are never cut at a corner. A container bay is
# one 20 ft box, long side out.
const BAY_W := [3.0, 4.5, 3.0, 5.0, 6.0, 2.6, 3.4, 4.0, 4.0, 3.4, 8.0, 6.1]
# Share of lit windows that are cold fluorescent rather than warm
# incandescent: homes are warm, offices and car parks are cold.
const COOL_BIAS := [0.2, 0.7, 0.85, 0.6, 1.0, 0.25, 0.35, 0.6, 0.12, 0.08, 0.9, 0.8]
# Emission scale per tile: a lit office ribbon or open car-park deck is a
# whole bay of glass, so it is dimmed to sit beside a single lit flat
# window instead of glowing as a white panel.
const GLOW := [1.0, 0.75, 0.3, 0.8, 0.22, 1.0, 1.0, 1.0, 0.6, 1.0, 0.8, 1.0]
# How much each bay-and-floor cell takes its own colour (0 none, 1 full): a
# container stack is boxes from different lines, not one painted wall.
const CELL_VARY := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]

# Base tints, linear-ish albedo. Dark on purpose: this is a city at 2 a.m.,
# the facades are read by their windows and the sodium haze, not by colour.
# Amber vs Dusk only (no magenta, no cyan).
const TINTS := [
	Color(0.30, 0.29, 0.27),  # concrete
	Color(0.33, 0.29, 0.24),  # warm grey
	Color(0.32, 0.18, 0.13),  # brick
	Color(0.15, 0.19, 0.30),  # dusk navy (#1B2A4A family)
	Color(0.38, 0.33, 0.25),  # sand
	Color(0.17, 0.16, 0.16),  # soot
	Color(0.30, 0.18, 0.11),  # rust
	Color(0.23, 0.24, 0.28),  # slate
	# World step 3: district palette colours. Only a district's "tints"
	# table reaches these; the even draw stops at DEFAULT_TINTS.
	Color(0.42, 0.17, 0.10),  # old red brick
	Color(0.47, 0.43, 0.35),  # cream clapboard
	Color(0.43, 0.44, 0.45),  # pale hangar metal
	Color(0.46, 0.21, 0.08),  # container orange (#FF8A1F family, dulled)
	Color(0.40, 0.30, 0.13),  # ochre
]
const DEFAULT_TINTS := 8

# Shop rooms (world step 3). id is the shader's room kind; close is game
# minutes since 8 p.m. when the shutter comes down ([min, max], jittered per
# building), -1 never, -2 down all night; close_chance is the share of that
# kind that closes at all (a corner store is 24-hour more often than not).
# What a kind looks like inside is in the shader (room_back / room_floor /
# room_ceiling).
const ROOMS := {
	"store": {"id": 0, "close": [180.0, 300.0], "close_chance": 0.3},
	"laundromat": {"id": 1, "close": [90.0, 210.0], "close_chance": 1.0},
	"bar": {"id": 2, "close": [330.0, 400.0], "close_chance": 1.0},
	"vacant": {"id": 3, "close": -1, "close_chance": 0.0},
	"shuttered": {"id": 3, "close": -2, "close_chance": 1.0},
}
const ROOM_NAMES := ["store", "laundromat", "bar", "vacant"]
# Sign words that fit each room (all from BuildingSigns' word atlas), so a
# laundromat is not signed BAR. A vacant or shuttered unit keeps an old sign.
const SIGN_WORDS := {
	"store": ["LIQUOR", "PAWN", "VIDEO", "OPEN", "24 HR", "KEYS", "NOODLES"],
	"laundromat": ["LAUNDRY", "OPEN"],
	"bar": ["BAR", "CAFE", "NOODLES", "OPEN"],
	"vacant": ["LIQUOR", "PAWN", "VIDEO", "KEYS", "NOODLES", "LAUNDRY"],
	"shuttered": ["LIQUOR", "PAWN", "VIDEO", "KEYS", "NOODLES", "LAUNDRY"],
}
# Shader values for "never" and "all night" closing times.
const NEVER := 1.0e9
const ALWAYS := -1.0e9
## Game minutes a shutter takes to roll down (12 real seconds at the
## 20-minute night).
const SHUTTER_MINUTES := 6.0
const ROOM_DEPTH := 4.0

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float emission_energy = 1.25;
uniform int tiles = 12;
uniform float bay_w[12];
uniform float cool_bias[12];
uniform float glow[12];
uniform float cell_vary[12];
// Night clock (living world step 1): scales every building's lit density, so
// the same windows go dark in the same order through the night (WindowLights).
uniform float lit_scale = 1.0;
// Shop fronts (world step 3): the night clock in game minutes since 8 p.m.,
// how deep the fake room is, how bright, and how long a shutter takes.
uniform float minutes = 240.0;
uniform float room_depth = 4.0;
uniform float room_energy = 0.7;
uniform float shutter_minutes = 6.0;
uniform float wash_energy = 2.0;

instance uniform int tile = 0;
instance uniform vec3 tint : source_color = vec3(0.3);
instance uniform vec3 size = vec3(1.0);
instance uniform float floor_h = 3.2;
instance uniform float lit_density = 0.3;
instance uniform float seed = 0.0;
// How far the block reaches below the road (a hill's foundation): floors are
// counted from the road, not from the block's bottom.
instance uniform float base = 0.0;
// Building wear (world step 1), 0 clean .. 1 derelict: ground grime, rain
// streaks down some bays, dark stains, a soot line under the roof edge, and
// a patchy roof. All of it is hashed per bay and floor, no texture.
instance uniform float wear = 0.5;
// Shop front (world step 3): the room kind behind the ground-floor glass
// (0 store, 1 laundromat, 2 bar, 3 vacant; -1 none) and when its shutter
// comes down, game minutes since 8 p.m. (1e9 never, -1e9 all night).
instance uniform int room = -1;
instance uniform float close_at = 1e9;
// Street light on the walls (world step 3b): the district's lamp colour
// times its strength, and how high up the front it reaches, m. A whole
// street takes the colour of its lamps, and a dark district stays dark.
instance uniform vec3 street = vec3(0.0);
instance uniform float street_reach = 10.0;

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 lcam;

void vertex() {
	lpos = VERTEX * size;  // the mesh is a shared unit cube, scaled by the node
	lnrm = NORMAL;
	// the camera in the same space, for the shop-front ray (24 vertices per
	// building, so the inverse is cheap)
	lcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz * size;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// ---- shop rooms (world step 3) ----
// Room space: x along the face (0 .. bay width), y up from the floor
// (0 .. floor height), z into the building (0 .. room_depth).

// Product colours on a store shelf: white, red, amber, olive, brown, navy.
vec3 product(float h) {
	int k = int(h * 6.0);
	if (k == 0) { return vec3(0.9, 0.88, 0.8); }
	if (k == 1) { return vec3(0.8, 0.18, 0.12); }
	if (k == 2) { return vec3(1.0, 0.7, 0.2); }
	if (k == 3) { return vec3(0.45, 0.55, 0.2); }
	if (k == 4) { return vec3(0.5, 0.3, 0.15); }
	return vec3(0.15, 0.2, 0.4);
}

// The back wall, by room kind. p is the hit in room space, bw the bay width,
// s the building seed.
vec3 room_back(int kind, vec3 p, float bw, float s) {
	if (kind == 0) {
		// shelves to 2.2 m, a plank every 0.45 m, products in 0.25 m cells
		if (p.y > 2.2) { return vec3(0.55, 0.52, 0.48); }
		float row = floor(p.y / 0.45);
		float fy = fract(p.y / 0.45);
		if (fy > 0.88) { return vec3(0.7, 0.62, 0.5); }
		vec2 cell = vec2(floor(p.x / 0.25), row);
		float h = hash3(vec3(cell, s + 5.0));
		if (h > 0.82) { return vec3(0.3, 0.28, 0.26); }  // an empty slot
		float gap = step(0.08, fract(p.x / 0.25)) * step(fy, 0.75);
		return product(h / 0.82) * mix(0.35, 1.0, gap);
	}
	if (kind == 1) {
		// a row of front loaders 0.75 m wide, 0.95 m tall, a shelf above
		if (p.y < 0.95) {
			vec2 c = vec2(fract(p.x / 0.75) - 0.5, p.y / 0.95 - 0.5);
			float r = length(c * vec2(1.0, 1.27));
			if (r < 0.26) { return vec3(0.08, 0.09, 0.1); }
			if (r < 0.31) { return vec3(0.75, 0.78, 0.8); }
			float edge = step(abs(c.x), 0.46);
			return vec3(0.82, 0.84, 0.85) * mix(0.4, 1.0, edge);
		}
		if (p.y < 1.05) { return vec3(0.5, 0.5, 0.52); }
		// a poster on the wall now and then, else plain tile
		float h = hash3(vec3(floor(p.x / 1.5), 1.0, s + 9.0));
		float px = fract(p.x / 1.5);
		if (h < 0.3 && p.y > 1.4 && p.y < 2.1 && px > 0.2 && px < 0.7) { return vec3(0.9, 0.6, 0.25); }
		return vec3(0.62, 0.66, 0.66);
	}
	if (kind == 2) {
		// the back bar: a dark counter front, bottles on two lit shelves,
		// dark wall above
		if (p.y < 1.05) { return vec3(0.12, 0.08, 0.06); }
		if (p.y < 2.1) {
			float row = floor((p.y - 1.05) / 0.525);
			float fy = fract((p.y - 1.05) / 0.525);
			if (fy < 0.08) { return vec3(0.9, 0.75, 0.5); }  // the lit shelf edge
			float cx = fract(p.x / 0.12);
			float h = hash3(vec3(floor(p.x / 0.12), row, s + 13.0));
			float tall = 0.35 + 0.5 * fract(h * 7.0);
			if (fy < tall && abs(cx - 0.5) < 0.3) {
				vec3 g = h < 0.4 ? vec3(1.0, 0.6, 0.2) : (h < 0.7 ? vec3(0.4, 0.6, 0.25) : vec3(0.85, 0.85, 0.75));
				return g * 1.3;
			}
			return vec3(0.35, 0.22, 0.12);
		}
		return vec3(0.18, 0.12, 0.08);
	}
	// vacant: bare plaster with a paler patch where the shelves were
	float qx = fract(p.x / bw + 0.1);
	float patch = step(0.6, p.y) * step(p.y, 2.0) * step(0.3, qx) * step(qx, 0.8);
	return vec3(0.45, 0.42, 0.38) * mix(1.0, 1.25, patch);
}

vec3 room_floor(int kind, vec3 p) {
	if (kind == 1) {
		float ch = step(0.5, fract(floor(p.x / 0.5) * 0.5 + floor(p.z / 0.5) * 0.5));
		return mix(vec3(0.22, 0.24, 0.25), vec3(0.7, 0.72, 0.7), ch);
	}
	if (kind == 2) {
		float plank = step(0.92, fract(p.x / 0.3));
		return vec3(0.3, 0.18, 0.1) * (1.0 - 0.5 * plank);
	}
	if (kind == 3) { return vec3(0.3, 0.28, 0.26); }
	float line = max(step(0.94, fract(p.x / 0.6)), step(0.94, fract(p.z / 0.6)));
	return vec3(0.58, 0.56, 0.52) * (1.0 - 0.3 * line);
}

// Ceiling: tubes down the middle of the room for the store and laundromat,
// pendants for the bar, nothing in a vacant unit.
vec3 room_ceiling(int kind, vec3 p, float depth) {
	vec3 ceil_col = kind == 2 ? vec3(0.12, 0.09, 0.07) : vec3(0.6, 0.6, 0.58);
	if (kind == 3) { return ceil_col * 0.7; }
	if (kind == 2) {
		float pend = step(length(vec2(fract(p.x / 1.2) - 0.5, p.z / depth - 0.55) * vec2(1.0, 4.0)), 0.12);
		return ceil_col + vec3(1.0, 0.65, 0.3) * 2.5 * pend;
	}
	float tube = step(abs(p.z / depth - 0.5), 0.05) * step(0.1, fract(p.x / 1.4));
	return ceil_col + vec3(1.0, 1.0, 0.95) * 2.0 * tube;
}

// A shop front fragment: the shutter, or the room behind the glass.
// bay is the bay index along the face, u01 the position across it (0..1),
// pv metres above the floor,
// cy the atlas cell y (0 top .. 1 bottom), rd the view ray in local space,
// uax the along-face axis, n the outward face normal.
// Returns the colour; sets `shut` to 1 where the shutter covers the glass.
vec3 shop_front(float bay, float u01, float pv, float cy, vec3 rd, vec3 uax, vec3 n, float bw, float fh, out float shut) {
	float roll = clamp((minutes - close_at) / shutter_minutes, 0.0, 1.0);
	// the glass runs from atlas y 9/32 to 30/32; the shutter rolls down over it
	float edge = 0.28 + roll * 0.66;
	shut = step(cy, edge);
	if (shut > 0.5) {
		float slat = fract(pv * 3.0);
		float sl = 0.55 + 0.3 * smoothstep(0.0, 0.3, slat) * smoothstep(1.0, 0.7, slat);
		// the bottom rail while it is still moving
		sl += 0.4 * smoothstep(0.03, 0.0, abs(cy - edge)) * step(roll, 0.999);
		return vec3(sl);
	}
	float ru = dot(rd, uax);
	float rv = rd.y;
	float rin = max(-dot(rd, n), 1e-3);
	vec3 p = vec3(u01 * bw, pv, 0.0);
	float tb = room_depth / rin;
	float tu = ru > 1e-4 ? (bw - p.x) / ru : (ru < -1e-4 ? -p.x / ru : 1e9);
	float tv = rv > 1e-4 ? (fh - p.y) / rv : (rv < -1e-4 ? -p.y / rv : 1e9);
	float tm = min(tb, min(tu, tv));
	vec3 r = vec3(ru, rv, rin);
	vec3 h = p + r * tm;
	float s = seed + bay * 17.0;  // each bay its own stock and people
	vec3 col;
	if (tm == tb) {
		col = room_back(room, h, bw, s);
	} else if (tm == tv) {
		col = rv < 0.0 ? room_floor(room, h) : room_ceiling(room, h, room_depth);
	} else {
		// a side wall: the same fittings as the back wall, run along the depth
		col = room_back(room, vec3(h.z + (ru > 0.0 ? 0.0 : 1.7), h.y, h.x), room_depth, s + 31.0) * 0.85;
	}
	// figures: a bar has people at the counter, a store a customer now and
	// then; dark silhouettes on a plane two thirds of the way in
	if (room == 2 || room == 0) {
		float tf = room_depth * 0.66 / rin;
		if (tf < tm) {
			vec3 f = p + r * tf;
			float dark = 0.0;
			float thresh = room == 2 ? 0.75 : 0.25;
			for (int k = 0; k < 3; k++) {
				vec3 key = vec3(float(k), 2.0, s + 23.0);
				if (hash3(key) > thresh) { continue; }
				float cx = (0.15 + 0.7 * hash3(key + 1.0)) * bw;
				float ht = 1.55 + 0.25 * hash3(key + 2.0);
				float body = step(abs(f.x - cx), 0.2) * step(f.y, ht - 0.2);
				float head = step(length(vec2(f.x - cx, f.y - ht + 0.05)), 0.12);
				dark = max(dark, max(body, head));
			}
			col = mix(col, vec3(0.02, 0.015, 0.01), dark);
		}
	}
	// the room light: cold white in a store, cold fluorescent in a
	// laundromat, dim amber in a bar; a vacant unit has one security lamp on
	// the back wall and nothing else
	vec3 light;
	if (room == 0) { light = vec3(0.95, 1.0, 0.9) * 0.9; }
	else if (room == 1) { light = vec3(0.78, 0.9, 0.78) * 0.85; }
	else if (room == 2) { light = vec3(1.0, 0.6, 0.28) * 0.4; }
	else {
		vec3 lamp = vec3(bw * 0.5, fh * 0.85, room_depth - 0.1);
		float d = length(h - lamp);
		light = vec3(1.0, 0.75, 0.4) * (0.22 / (0.3 + d * d));
		if (tm == tb && d < 0.09) { light = vec3(2.5, 2.0, 1.4); }
	}
	float depthk = 1.0 - 0.3 * h.z / room_depth;
	return col * light * depthk * room_energy;
}

void fragment() {
	vec3 an = abs(lnrm);
	if (an.y > 0.5) {
		// flat roof: tar or pale gravel by building, gritty, with dark
		// patches where water sat once it is worn
		float gravel = step(0.5, fract(seed * 0.37));
		float grit = hash3(floor(lpos.xzy * 1.3) + seed);
		float patch = step(1.0 - 0.45 * wear, hash3(floor(lpos.xzy * 0.35) + seed + 3.0));
		ALBEDO = tint * mix(0.3, 0.5, gravel) * (0.8 + 0.4 * grit) * (1.0 - 0.4 * patch);
		ROUGHNESS = 1.0;
	} else {
		// horizontal coordinate along this face and the face's length
		bool on_x = an.x > an.z;
		float coord = on_x ? lpos.z * sign(lnrm.x) : -lpos.x * sign(lnrm.z);
		float len = on_x ? size.z : size.x;
		float bays = max(1.0, round(len / bay_w[tile]));
		float u = (coord + len * 0.5) / len * bays;
		float v = max(lpos.y + size.y * 0.5 - base, 0.0) / floor_h;
		float fl = floor(v);
		float row = fl < 0.5 ? 1.0 : 0.0;  // atlas row 1 = ground floor
		vec2 cell = vec2(fract(u), 1.0 - fract(v));
		vec2 auv = vec2((float(tile) + cell.x) / float(tiles), (row + cell.y) * 0.5);
		// gradients from the continuous coordinate, so the fract() seams do
		// not drop to the smallest mip and draw a line
		vec2 g = vec2(u / float(tiles), -v * 0.5);
		vec4 t = textureGrad(atlas, auv, dFdx(g), dFdy(g));
		ALBEDO = tint * t.rgb;
		ROUGHNESS = mix(0.9, 0.35, t.a);
		float face = on_x ? (lnrm.x > 0.0 ? 1.0 : 2.0) : (lnrm.z > 0.0 ? 3.0 : 4.0);
		vec3 key = vec3(floor(u), fl, seed * 7.13 + face * 31.7);
		float h = hash3(key);
		// world step 3: a container stack's cells each lean rust, navy or
		// stay the building's colour, lighter or darker
		float cv = cell_vary[tile];
		if (cv > 0.0) {
			float hc = hash3(key + 53.1);
			vec3 lean = hc < 0.34 ? vec3(1.25, 0.72, 0.5) : (hc < 0.62 ? vec3(0.5, 0.68, 1.15) : vec3(1.0));
			ALBEDO *= mix(vec3(1.0), lean * (0.6 + 0.7 * hash3(key + 91.7)), cv);
		}
		// threshold the glass mask: a blurred far mip must not let wall emit
		float lit = step(h, lit_density * lit_scale) * step(0.5, t.a);
		float h2 = hash3(key + 19.19);
		vec3 warm = vec3(1.0, 0.72, 0.38);
		vec3 cool = vec3(0.74, 0.86, 0.7);  // white-green fluorescent
		vec3 tv = vec3(0.42, 0.5, 0.8);
		vec3 c = h2 < cool_bias[tile] ? cool : warm;
		if (h2 > 0.96) { c = tv; }
		EMISSION = c * lit * mix(0.55, 1.0, hash3(key + 3.7)) * emission_energy * glow[tile];
		// shop front (world step 3): the ground-floor glass of a shop shows
		// its room, or its shutter
		if (room >= 0 && fl < 0.5 && t.a > 0.5) {
			vec3 uax = on_x ? vec3(0.0, 0.0, sign(lnrm.x)) : vec3(-sign(lnrm.z), 0.0, 0.0);
			vec3 rd = normalize(lpos - lcam);
			float shut = 0.0;
			vec3 rc = shop_front(floor(u), fract(u), v * floor_h, cell.y, rd, uax, lnrm, len / bays, floor_h, shut);
			if (shut > 0.5) {
				// nothing real lights the street, so the slats carry a
				// little of the sodium glow themselves or they read as black
				ALBEDO = tint * rc;
				ROUGHNESS = 0.7;
				EMISSION = vec3(1.0, 0.72, 0.45) * rc * 0.07;
			} else {
				ALBEDO = vec3(0.02);
				ROUGHNESS = 0.25;
				EMISSION = rc;
			}
		}
		// wear (world step 1): all on the wall, lit glass stays lit
		float wall = 1.0 - t.a;
		float hm = max(lpos.y + size.y * 0.5 - base, 0.0);  // metres above the road
		float grime = wear * 0.5 * smoothstep(2.2, 0.0, hm) * (1.0 - 0.7 * t.a);
		// a rain streak runs the height of some bays, broken on some floors
		float sb = hash3(vec3(floor(u), -1.0, seed + 41.0));
		float sx = 0.1 + 0.8 * fract(sb * 7.31);
		float streak = step(sb, wear * 0.45) * step(hash3(key + 7.7), 0.75) * smoothstep(0.05, 0.015, abs(fract(u) - sx)) * wall;
		float stain = step(hash3(vec3(floor(u * 0.5), floor(v * 0.5), seed + 11.0)), wear * 0.18) * wall;
		float soot = wear * 0.3 * smoothstep(size.y - base - 0.8, size.y - base, hm);
		ALBEDO *= 1.0 - clamp(grime + streak * 0.35 + stain * 0.22 + soot, 0.0, 0.6);
		// the lamps' light up the wall, strongest at the sidewalk
		float up = clamp(1.0 - hm / street_reach, 0.0, 1.0);
		EMISSION += ALBEDO * street * (up * up) * wash_energy * wall;
	}
}
"""

static var _material: ShaderMaterial
static var _lit_scale := 1.0
static var _minutes := 240.0
static var _atlas: ImageTexture
static var _unit_box: BoxMesh

## The one material every building shares.
static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("atlas", atlas())
		_material.set_shader_parameter("tiles", TILES)
		_material.set_shader_parameter("bay_w", PackedFloat32Array(BAY_W))
		_material.set_shader_parameter("cool_bias", PackedFloat32Array(COOL_BIAS))
		_material.set_shader_parameter("glow", PackedFloat32Array(GLOW))
		_material.set_shader_parameter("cell_vary", PackedFloat32Array(CELL_VARY))
		_material.set_shader_parameter("lit_scale", _lit_scale)
		_material.set_shader_parameter("minutes", _minutes)
		_material.set_shader_parameter("room_depth", ROOM_DEPTH)
		_material.set_shader_parameter("shutter_minutes", SHUTTER_MINUTES)
	return _material

## Night clock hook (WindowLights.set_minutes): the shop fronts read the time
## for their shutters. Only pushed to the GPU when it moved a tenth of a game
## minute, so a still clock costs nothing.
static func set_minutes(m: float) -> void:
	if absf(m - _minutes) < 0.1 and _material != null:
		return
	_minutes = m
	if _material != null:
		_material.set_shader_parameter("minutes", m)

static func minutes() -> float:
	return _minutes

## The shutter position for a closing time, 0 up .. 1 down, as the shader
## computes it (tests read it).
static func shutter_at(close_at: float, m: float) -> float:
	return clampf((m - close_at) / SHUTTER_MINUTES, 0.0, 1.0)

## Night clock hook (WindowLights.set_minutes): 1 is the midnight look the
## lit densities were tuned for, more early in the evening, less near dawn.
static func set_lit_scale(k: float) -> void:
	_lit_scale = k
	if _material != null:
		_material.set_shader_parameter("lit_scale", k)

## One unit cube shared by every building; the node's scale sets its size.
static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box

# Building types (buildings step 2). A type picks the facade tiles that suit
# it, its height range and whether it carries a sign. The old "garage" roll
# (the low sheds) is the garage type: an auto shop with roller doors and a
# TIRES / PARTS / AUTO / BODY sign, which milestone 8's stop-places can use.
const TYPES := {
	"apartment": {"tiles": [[T_APARTMENT, 60], [T_BRICK, 20], [T_CONCRETE, 20]], "h": [8.0, 24.0], "sign": 0.0},
	"shop": {"tiles": [[T_SHOP, 100]], "h": [3.4, 10.5], "sign": 0.85},
	"office": {"tiles": [[T_OFFICE, 70], [T_CONCRETE, 30]], "h": [12.0, 30.0], "sign": 0.0},
	"parking": {"tiles": [[T_PARKING, 100]], "h": [6.0, 15.0], "sign": 0.0},
	"garage": {"tiles": [[T_WAREHOUSE, 60], [T_CORRUGATED, 40]], "h": [0.0, 0.0], "sign": 0.7},
	"warehouse": {"tiles": [[T_WAREHOUSE, 60], [T_CORRUGATED, 40]], "h": [7.0, 12.0], "sign": 0.0},
	# Special buildings (step 5). A gas station is a kiosk at the back of its
	# lot under a lit canopy; a diner is a glass box behind a tall pole sign.
	"gas": {"tiles": [[T_SHOP, 100]], "h": [3.4, 3.4], "sign": 1.0, "word": "GAS"},
	"diner": {"tiles": [[T_SHOP, 100]], "h": [4.4, 4.4], "sign": 1.0, "word": "DINER"},
	# World step 3 (W6): the new district kinds' own buildings.
	"tenement": {"tiles": [[T_BRICK, 100]], "h": [9.0, 16.0], "sign": 0.0},
	"loft": {"tiles": [[T_LOFT, 80], [T_BRICK, 20]], "h": [14.0, 26.0], "sign": 0.5},
	"house": {"tiles": [[T_CLAPBOARD, 100]], "h": [5.6, 8.4], "sign": 0.0},
	"hangar": {"tiles": [[T_HANGAR, 100]], "h": [12.0, 18.0], "sign": 0.0},
	"containers": {"tiles": [[T_CONTAINER, 100]], "h": [5.2, 13.0], "sign": 0.0},
}
# Mix for an ordinary street until districts (step 4) set their own.
const STREET_MIX := [["apartment", 40], ["shop", 30], ["office", 18], ["parking", 12]]

# Roof shapes (world step 1, 2026-10-10). The flat box top was what every
# building still shared; RoofProps draws these from the same per-chunk
# MultiMesh as the tanks and AC units, so they cost no draw call. A district
# weights them (Districts SPECS "tops"); a type only takes the ones that suit
# it, and a type with nothing in the district's table stays flat.
#   flat     the box as it was
#   cornice  a projecting cap all round the roof edge
#   parapet  a raised false front along the street edge (shops)
#   gable    a pitched roof, ridge along the road
#   hip      a hipped (mansard) roof with a small flat top
#   setback  a penthouse floor set in from the edges
#   crown    stepped plant rooms and a short mast (offices)
const TOPS := ["flat", "cornice", "parapet", "gable", "hip", "setback", "crown"]
const TOPS_FOR := {
	"apartment": ["flat", "cornice", "gable", "hip", "setback"],
	"shop": ["flat", "cornice", "parapet", "gable", "hip"],
	"office": ["flat", "cornice", "setback", "crown"],
	"parking": ["flat"],
	"garage": ["flat", "gable"],
	"warehouse": ["flat", "gable"],
	"gas": ["flat"],
	"diner": ["flat"],
	"tenement": ["flat", "cornice", "gable", "hip"],
	"loft": ["flat", "cornice", "parapet", "setback"],
	"house": ["gable", "hip"],
	"hangar": ["flat", "gable"],
	"containers": ["flat"],
}
# The top a landmark's own building wears (RoofProps adds the landmark).
const LANDMARK_TOP := {
	"tower": "crown", "water_tower": "flat", "stacks": "flat", "screen": "flat",
	"steeple": "flat", "marquee": "flat", "control_tower": "flat", "crane": "flat",
	"high_sign": "flat", "mast": "gable",
}

## Picks a building's type and look from its own RNG and writes the look onto
## the mesh instance. is_low is the old "garage" roll (a low, wide shed);
## h_roll is the height draw in [0, 1]; district is a Districts spec (type
## mix, height overrides, lit-window and billboard multipliers). Returns
## {h, type, tile, floor_h, sign, sign_color, sign_style}; h is a whole
## number of floors, sign is "" when the building has none.
static func dress(mi: MeshInstance3D, rng: RandomNumberGenerator, is_low: bool, h_roll: float, w: float, d: float, district: Dictionary = {}) -> Dictionary:
	var type: String
	if is_low:
		type = district.get("low", "garage")
	else:
		type = _weighted_s(rng, district.get("mix", STREET_MIX))
	var spec: Dictionary = TYPES[type]
	var tile := _weighted(rng, spec.tiles)
	var fh: float = FLOOR_H[tile]
	var floors: int
	if type == "garage":
		floors = 1
	else:
		var hr: Array = district.get("h", {}).get(type, spec.h)
		floors = maxi(1, roundi(lerpf(hr[0], hr[1], h_roll) / fh))
		if type != "shop" and type != "gas" and type != "diner":
			floors = maxi(2, floors)
	var h := float(floors) * fh
	# One draw whether or not the district has a palette, so a building's
	# other rolls do not move when a district gains one.
	var tint_roll := rng.randi()
	var palette: Array = district.get("tints", [])
	var tint: Color = TINTS[tint_roll % DEFAULT_TINTS] if palette.is_empty() else TINTS[_weighted_at(tint_roll, palette)]
	tint = tint * rng.randf_range(0.65, 0.85)
	var density := rng.randf_range(0.12, 0.42)
	if tile == T_WAREHOUSE or tile == T_CORRUGATED or tile == T_HANGAR:
		density *= 0.4
	elif tile == T_OFFICE:
		density *= 0.6  # offices at 2 a.m. are mostly dark
	density = minf(density * float(district.get("lit", 1.0)), 0.6)
	# World step 1: wear and the roof shape, from the district's tables
	# (Districts.DEFAULTS when a district leaves them out).
	var wr: Array = district.get("wear", Districts.DEFAULTS.wear)
	var wear := rng.randf_range(float(wr[0]), float(wr[1]))
	var landmark: String = district.get("is_landmark", "")
	var top: String
	if landmark != "":
		top = LANDMARK_TOP[landmark]
		rng.randf()  # the top roll, so the rest of the look matches a plain building
	else:
		top = _pick_top(rng, type, district.get("tops", Districts.DEFAULTS.tops))
	mi.mesh = unit_box()
	mi.material_override = material()
	mi.scale = Vector3(w, h, d)
	mi.set_instance_shader_parameter("tile", tile)
	mi.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mi.set_instance_shader_parameter("size", Vector3(w, h, d))
	mi.set_instance_shader_parameter("floor_h", fh)
	mi.set_instance_shader_parameter("lit_density", density)
	mi.set_instance_shader_parameter("seed", float(rng.randi() % 4096))
	mi.set_instance_shader_parameter("wear", wear)
	# World step 3: what is behind the ground-floor glass, and when it shuts
	var front := pick_front(rng, type, district.get("fronts", Districts.DEFAULTS.fronts))
	mi.set_instance_shader_parameter("room", int(front.room))
	mi.set_instance_shader_parameter("close_at", float(front.close_at))
	if front.kind != "":
		mi.set_meta("shop_front", front.kind)
	elif mi.has_meta("shop_front"):
		mi.remove_meta("shop_front")
	var wash := Districts.wash_of(district)
	mi.set_instance_shader_parameter("street", wash[0])
	mi.set_instance_shader_parameter("street_reach", wash[1])
	mi.set_meta("facade_tile", tile)
	mi.set_meta("building_type", type)
	mi.set_meta("roof_top", top)
	if landmark != "":
		mi.set_meta("landmark", landmark)
	elif mi.has_meta("landmark"):
		mi.remove_meta("landmark")
	var word := ""
	if rng.randf() < float(spec.sign):
		var pool: Array = BuildingSigns.GARAGE_WORDS if type == "garage" else BuildingSigns.SHOP_WORDS
		if type == "shop" and SIGN_WORDS.has(front.kind):
			pool = SIGN_WORDS[front.kind]
		word = pool[rng.randi() % pool.size()]
		if spec.has("word"):
			word = spec.word
	# World step 3b: a district may weight its sign colours and how many are
	# lit panels. The same two draws either way, so no other roll moves.
	var sign_roll := rng.randi()
	var sign_table: Array = district.get("signs", [])
	var sign_color: int = sign_roll % BuildingSigns.COLORS.size() if sign_table.is_empty() else _weighted_at(sign_roll, sign_table)
	var sign_style := 1 if rng.randf() < float(district.get("panel", Districts.DEFAULTS.panel)) else 0
	# short words on shops can hang as a blade over the sidewalk instead
	var blade := type == "shop" and word.length() <= 5 and rng.randf() < 0.45
	if type == "gas":
		sign_color = 2  # forecourt fluorescent
		sign_style = 1
	elif type == "diner":
		sign_color = 0  # sodium amber
		sign_style = 0
	if word != "":
		mi.set_meta("sign_word", word)
	elif mi.has_meta("sign_word"):
		mi.remove_meta("sign_word")
	return {"h": h, "type": type, "tile": tile, "floor_h": fh, "sign": word, "sign_color": sign_color, "sign_style": sign_style, "blade": blade, "roof_seed": rng.randi(), "billboard": float(district.get("billboard", 1.0)), "top": top, "wear": wear, "landmark": landmark}

## The shop front for a building of `type`: {kind, room, close_at}. kind is
## a ROOMS key ("" and room -1 for a building with no shop glass), room the
## shader's kind id, close_at game minutes since 8 p.m. (NEVER / ALWAYS).
## Always three RNG draws, so the rest of the look stays stable per type.
static func pick_front(rng: RandomNumberGenerator, type: String, table: Array) -> Dictionary:
	var r1 := rng.randf()
	var r2 := rng.randf()
	var r3 := rng.randf()
	var kind := ""
	if type == "gas":
		kind = "store"
	elif type == "diner":
		kind = "bar"
	elif type == "shop":
		var total := 0
		for e in table:
			total += int(e[1])
		var r := int(r1 * float(total))
		kind = String(table[0][0])
		for e in table:
			r -= int(e[1])
			if r < 0:
				kind = String(e[0])
				break
	if kind == "":
		return {"kind": "", "room": -1, "close_at": NEVER}
	var spec: Dictionary = ROOMS[kind]
	var close_at := NEVER
	var c = spec.close
	if c is Array:
		if type == "gas" or type == "diner":
			close_at = NEVER  # 24-hour
		elif r2 < float(spec.close_chance):
			close_at = lerpf(float(c[0]), float(c[1]), r3)
	elif int(c) == -2:
		close_at = ALWAYS
	return {"kind": kind, "room": int(spec.id), "close_at": close_at}

## The roof shape for a building of `type` from a district's weight table,
## keeping only the shapes that suit the type; flat when none does.
static func _pick_top(rng: RandomNumberGenerator, type: String, table: Array) -> String:
	var allowed: Array = TOPS_FOR.get(type, ["flat"])
	var mine := []
	for e in table:
		if allowed.has(String(e[0])):
			mine.append(e)
	var roll := rng.randf()  # one draw whatever the table, so looks stay stable across tables
	if mine.is_empty():
		return "flat"
	var total := 0
	for e in mine:
		total += int(e[1])
	var r := int(roll * float(total))
	for e in mine:
		r -= int(e[1])
		if r < 0:
			return String(e[0])
	return String(mine[0][0])

static func _weighted_s(rng: RandomNumberGenerator, table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := rng.randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return String(e[0])
	return String(table[0][0])

static func _weighted(rng: RandomNumberGenerator, table: Array) -> int:
	return _weighted_at(rng.randi(), table)

## The table entry a draw already taken lands on.
static func _weighted_at(roll: int, table: Array) -> int:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := roll % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return int(e[0])
	return int(table[0][0])

# ---------- atlas ----------

## TILES tiles x 2 rows (upper floors on top, ground floor below), 32 px each.
static func atlas() -> ImageTexture:
	if _atlas == null:
		var img := Image.create(TILE_PX * TILES, TILE_PX * 2, false, Image.FORMAT_RGBA8)
		for t in TILES:
			for row in 2:
				_draw_tile(img, t, row == 1, t * TILE_PX, row * TILE_PX)
		img.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(img)
	return _atlas

# Pixel helpers. Tile coordinates: x right, y DOWN (y = 0 is the ceiling line
# of the floor, y = 31 the floor line).
static func _rect(img: Image, ox: int, oy: int, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			img.set_pixel(ox + x, oy + y, c)

static func _wall(v: float) -> Color:
	return Color(v, v, v, 0.0)

static func _glass(v: float) -> Color:
	return Color(v, v, v, 1.0)

static func _draw_tile(img: Image, t: int, ground: bool, ox: int, oy: int) -> void:
	var n := TILE_PX
	# a little per-pixel grit on every wall so flat colour never shows
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + t * 2 + (1 if ground else 0)
	for y in n:
		for x in n:
			img.set_pixel(ox + x, oy + y, _wall(0.62 + rng.randf_range(-0.06, 0.06)))
	match t:
		T_APARTMENT:
			if ground:
				# entrance bay look: smaller windows, a darker plinth
				_rect(img, ox, oy, 0, 24, n, n, _wall(0.4))
				_rect(img, ox, oy, 10, 8, 22, 20, _glass(0.18))
			else:
				_rect(img, ox, oy, 8, 6, 24, 20, _glass(0.15))
				# balcony slab and railing under the window
				_rect(img, ox, oy, 4, 21, 28, 23, _wall(0.82))
				for x in range(5, 28, 3):
					_rect(img, ox, oy, x, 23, x + 1, 27, _wall(0.3))
				_rect(img, ox, oy, 4, 27, 28, 28, _wall(0.3))
		T_SHOP:
			if ground:
				# full-height glass with mullions and a dark sign-band strip
				_rect(img, ox, oy, 0, 0, n, 7, _wall(0.28))
				_rect(img, ox, oy, 1, 9, n - 1, 30, _glass(0.2))
				_rect(img, ox, oy, 15, 9, 17, 30, _wall(0.35))
			else:
				_brick(img, ox, oy, 0.62)
				_rect(img, ox, oy, 9, 7, 23, 22, _glass(0.15))
				_rect(img, ox, oy, 8, 22, 24, 24, _wall(0.8))
		T_OFFICE:
			# continuous ribbon window, thin mullions, dark spandrel
			_rect(img, ox, oy, 0, 0, n, n, _wall(0.45))
			var top := 4 if ground else 7
			_rect(img, ox, oy, 0, top, n, 25, _glass(0.14))
			for x in [0, 8, 16, 24]:
				_rect(img, ox, oy, x, top, x + 1, 25, _wall(0.55))
		T_WAREHOUSE:
			_ribs(img, ox, oy, 0.55)
			if ground:
				# roller door, slats as darker lines, no glass
				_rect(img, ox, oy, 6, 6, 26, n, _wall(0.5))
				for y in range(7, n, 2):
					_rect(img, ox, oy, 6, y, 26, y + 1, _wall(0.36))
				_rect(img, ox, oy, 5, 5, 27, 6, _wall(0.8))
				# light spilling under a door left a hand's width open
				_rect(img, ox, oy, 6, 30, 26, n, _glass(0.3))
			else:
				# high clerestory strip
				_rect(img, ox, oy, 2, 3, 30, 7, _glass(0.18))
		T_PARKING:
			# concrete spandrel over an open, unglazed slab: the "glass" is
			# the open deck, lit by cold tubes
			_rect(img, ox, oy, 0, 0, n, 9, _wall(0.7))
			_rect(img, ox, oy, 0, 9, n, n, _glass(0.06))
			_rect(img, ox, oy, 0, 9, 2, n, _wall(0.6))
			if ground:
				_rect(img, ox, oy, 0, 28, n, n, _wall(0.5))
		T_BRICK:
			_brick(img, ox, oy, 0.6)
			# tall narrow window with a stone lintel and sill
			_rect(img, ox, oy, 11, 6, 21, 25, _glass(0.14))
			_rect(img, ox, oy, 10, 4, 22, 6, _wall(0.85))
			_rect(img, ox, oy, 10, 25, 22, 27, _wall(0.85))
			if ground:
				_rect(img, ox, oy, 0, 28, n, n, _wall(0.35))
		T_CONCRETE:
			# precast panel joints and one square window per panel
			_rect(img, ox, oy, 0, 0, n, 1, _wall(0.38))
			_rect(img, ox, oy, 0, 0, 1, n, _wall(0.38))
			_rect(img, ox, oy, 8, 8, 24, 22, _glass(0.15))
			# rust streak below the window
			_rect(img, ox, oy, 15, 22, 17, 30, _wall(0.48))
			if ground:
				_rect(img, ox, oy, 0, 26, n, n, _wall(0.4))
		T_CORRUGATED:
			_ribs(img, ox, oy, 0.58)
			if ground:
				_rect(img, ox, oy, 4, 8, 14, n, _wall(0.4))  # side door
				_rect(img, ox, oy, 20, 12, 27, 18, _glass(0.18))
			else:
				_rect(img, ox, oy, 20, 10, 27, 16, _glass(0.18))
		T_LOFT:
			_brick(img, ox, oy, 0.56)
			if ground:
				# a bar front: a painted base, a steel door, a low lit strip
				# of glass block and a pale lintel over both
				_rect(img, ox, oy, 0, 9, n, n, _wall(0.34))
				_rect(img, ox, oy, 0, 7, n, 9, _wall(0.85))
				_rect(img, ox, oy, 4, 12, 13, n, _wall(0.2))
				_rect(img, ox, oy, 11, 21, 12, 23, _wall(0.8))
				_rect(img, ox, oy, 17, 13, 29, 20, _glass(0.3))
				for x in [20, 23, 26]:
					_rect(img, ox, oy, x, 13, x + 1, 20, _wall(0.3))
			else:
				# the mill window: nearly the whole bay, small panes in a
				# steel grid, shallow arch (clipped corners), stone sill
				_rect(img, ox, oy, 4, 4, 28, 26, _glass(0.16))
				for x in [9, 15, 16, 22]:
					_rect(img, ox, oy, x, 4, x + 1, 26, _wall(0.3))
				for y in [10, 15, 21]:
					_rect(img, ox, oy, 4, y, 28, y + 1, _wall(0.3))
				for c in [[4, 4], [5, 4], [4, 5], [27, 4], [26, 4], [27, 5]]:
					img.set_pixel(ox + c[0], oy + c[1], _wall(0.5))
				_rect(img, ox, oy, 3, 26, 29, 28, _wall(0.85))
		T_CLAPBOARD:
			# horizontal boards, a shadow line under each
			for y in n:
				for x in n:
					img.set_pixel(ox + x, oy + y, _wall(0.52 if y % 4 == 3 else 0.72 - 0.03 * float((x / 9 + y / 4) % 2)))
			if ground:
				# front door with a porch light pane over it, one window,
				# a dark foundation
				_rect(img, ox, oy, 4, 11, 12, 29, _wall(0.9))
				_rect(img, ox, oy, 5, 12, 11, 29, _wall(0.3))
				_rect(img, ox, oy, 6, 13, 10, 16, _glass(0.3))
				_rect(img, ox, oy, 16, 9, 28, 23, _wall(0.9))
				_rect(img, ox, oy, 17, 10, 27, 22, _glass(0.16))
				_rect(img, ox, oy, 17, 15, 27, 16, _wall(0.9))
				_rect(img, ox, oy, 0, 29, n, n, _wall(0.38))
			else:
				# a sash window in a pale frame between dark shutters
				_rect(img, ox, oy, 10, 6, 22, 24, _wall(0.9))
				_rect(img, ox, oy, 11, 7, 21, 23, _glass(0.15))
				_rect(img, ox, oy, 11, 14, 21, 15, _wall(0.9))
				_rect(img, ox, oy, 15, 7, 17, 23, _wall(0.9))
				_rect(img, ox, oy, 6, 6, 9, 24, _wall(0.32))
				_rect(img, ox, oy, 23, 6, 26, 24, _wall(0.32))
		T_HANGAR:
			# big flat sheet panels, a joint every half bay
			for y in n:
				for x in n:
					img.set_pixel(ox + x, oy + y, _wall(0.58 if x % 16 == 0 else 0.76 + rng.randf_range(-0.03, 0.03)))
			if ground:
				# the sliding door: nearly the whole bay, leaves in darker
				# sheet, a row of small panes, a rail over the top
				_rect(img, ox, oy, 1, 3, 31, n, _wall(0.6))
				for x in [1, 8, 16, 23, 30]:
					_rect(img, ox, oy, x, 3, x + 1, n, _wall(0.42))
				for x in [3, 10, 18, 25]:
					_rect(img, ox, oy, x, 12, x + 4, 14, _glass(0.2))
				_rect(img, ox, oy, 0, 2, n, 3, _wall(0.34))
			else:
				# a painted band and a thin strip of roof-light glazing
				_rect(img, ox, oy, 0, 21, n, 25, _wall(0.4))
				_rect(img, ox, oy, 2, 3, 30, 5, _glass(0.2))
		T_CONTAINER:
			# one shipping container per cell, long side out: close ribs, a
			# dark frame top and bottom, the gap to the next box, a stencil
			# block where the line's name would be. No glass: nothing lit.
			for y in n:
				for x in n:
					img.set_pixel(ox + x, oy + y, _wall(0.7 if x % 2 == 0 else 0.56))
			_rect(img, ox, oy, 0, 0, n, 2, _wall(0.3))
			_rect(img, ox, oy, 0, 30, n, n, _wall(0.24))
			_rect(img, ox, oy, 0, 0, 1, n, _wall(0.18))
			_rect(img, ox, oy, 31, 0, n, n, _wall(0.3))
			_rect(img, ox, oy, 11, 9, 22, 14, _wall(0.92))
			_rect(img, ox, oy, 11, 16, 17, 18, _wall(0.92))

static func _brick(img: Image, ox: int, oy: int, v: float) -> void:
	for y in TILE_PX:
		var course := y / 3
		var shift := 3 if course % 2 == 1 else 0
		for x in TILE_PX:
			var mortar := y % 3 == 2 or (x + shift) % 6 == 5
			img.set_pixel(ox + x, oy + y, _wall(0.82 if mortar else v - 0.06 * float((x / 6 + course) % 3)))

static func _ribs(img: Image, ox: int, oy: int, v: float) -> void:
	for y in TILE_PX:
		for x in TILE_PX:
			var k := x % 4
			img.set_pixel(ox + x, oy + y, _wall(v + (0.12 if k == 0 else (-0.08 if k == 2 else 0.0))))
