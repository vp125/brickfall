extends Node2D
## Brickfall: Breakout with a neon 3D look. Game logic runs on a flat 800x600 field;
## the 3D scene (bricks, ball, paddle, floor) is built in code and mirrors that field.
## The 2D layer on top draws the HUD and overlays. No external assets.

# ---- Levels: one string per row. "." = empty, "1"-"3" = bricks needing that many hits.
const LEVELS := [
	{"name": "Wall", "info": "Warm-up: clear every brick. Hit with the paddle edge to steer the ball.", "rows": [
		"1111111111",
		"1111111111",
		"1111111111",
		"1111111111",
		"1111111111",
		"1111111111",
	]},
	{"name": "Pyramid", "info": "New: ! bricks explode and break every brick touching them. Your paddle is a little narrower.", "rows": [
		"....11....",
		"...1221...",
		"..12XX21..",
		".12222221.",
		"1122222211",
		"1111111111",
	]},
	{"name": "Checker", "info": "More ! bricks, spread out. Line up chain reactions for big scores.", "rows": [
		"1.1.1.1.1.",
		".2.X.2.X.2",
		"1.1.1.1.1.",
		".2.2.X.2.2",
		"1.1.1.1.1.",
		".2.2.2.2.2",
	]},
	{"name": "Invader", "info": "New: steel bricks never break. Clear every other brick to finish the level.", "rows": [
		"..1....1..",
		"...1..1...",
		"..111111..",
		".11X11X11.",
		"1111111111",
		"A.111111.A",
		"A.1....1.A",
		"...11.11..",
	]},
	{"name": "Fortress", "info": "Steel walls guard the core. Get in from the top or bottom, then set off the ! pair.", "rows": [
		"2222222222",
		"A........A",
		"A.111111.A",
		"A.1....1.A",
		"A.1.XX.1.A",
		"A.1....1.A",
		"A.111111.A",
	]},
	{"name": "Overload", "info": "Everything at once: 3-hit bricks, steel blocks and four ! bricks. Good luck.", "rows": [
		"3333333333",
		"2X22XX22X2",
		"1111111111",
		"3.A.3.A.3.",
		"1111111111",
		"2222222222",
	]},
	{"name": "The Prism", "info": "BOSS: break the crystal core. Its bolts cost a life, so dodge them or knock them out with the ball.", "boss": true, "rows": [
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"A........A",
		"A........A",
	]},
]
# A level with "boss": true spawns the boss on top of its rows (use only "." and "A" in rows).
# Each level has a short "info" line shown before launch.
# Brick key: "." empty, "1"-"3" hits to break, "A" armored (never breaks), "X" explosive
# (breaks in one hit and destroys every breakable brick touching it, chaining into other X).

# ---- Constants
var W := 800.0 # field width in game px: follows the window, so wide phones get a wide field
const H := 600.0
const S := 0.02 # game px -> 3D units
const COLS := 10
var BW := 68.0 # brick width: recomputed per level so the brick grid spans the field
const BH := 22.0
const GAP := 6.0
const TOP := 76.0
const ROW_COLORS: Array[Color] = [
	Color("ff2e63"), Color("ff7a3d"), Color("ffd23f"),
	Color("39ff88"), Color("22d3ee"), Color("a78bfa"),
]
const ROW_POINTS: Array[int] = [60, 50, 40, 30, 20, 10]
const BALL_R := 8.0
const SPEED_START := 380.0
const SPEED_MAX := 640.0
const MAX_STEP := 4.0 # px per physics substep, under half a brick height
const PADDLE_H := 14.0
const PADDLE_W := 110.0
const PADDLE_WIDE_RATIO := 1.6 # width multiplier while the wide power-up is active
const PADDLE_SHRINK := 0.08 # paddle loses this fraction of its width every level...
const PADDLE_MIN_RATIO := 0.62 # ...down to this fraction of the starting width
const K_NORMAL := 0
const K_ARMOR := 1
const K_BOMB := 2
const K_BOSS := 3
const BOSS_HP := 24 # phase 2 starts at 16 hp left, phase 3 at 8
const BOSS_COLORS: Array[Color] = [Color("ff2e9a"), Color("ff7a2a"), Color("ff2e3a")]
const WIDE_TIME := 12.0
const PADDLE_KEY_SPEED := 620.0
const MAX_BOUNCE_DEG := 62.0
const LIVES_START := 3
const DROP_CHANCE := 0.18
const TRAIL_LEN := 8
const GLOW := 0.22 # master glow level: 1.0 = full neon, lower = subtler

const INK := Color("e8f4ff")
const MUTED := Color("7f8fb8")
const ACCENT := Color("ffc145")
const CYAN := Color("22d3ee")
const MAGENTA := Color("ff2e9a")
const HUD_BG := Color(0.03, 0.04, 0.09, 0.88)
const Synth := preload("res://audio_synth.gd")

# Rounded, bevelled "pillow" shape drawn on a flat quad. The bevel normal is derived from
# the rounded-rect distance field, then lit from the top-left, which gives each piece
# a gradient body, a bright rim on the lit edge and a soft neon edge glow.
# With shadow=1 the same quad becomes a soft drop shadow.
const SHAPE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_col : source_color = vec4(1.0);
uniform vec2 size = vec2(1.3, 0.4);
uniform float radius = 0.08;
uniform float bevel = 0.1;
uniform float energy = 1.0;
uniform float dim = 1.0;
uniform float shadow = 0.0;
float sd(vec2 p) {
	vec2 d = abs(p) - (size * 0.5 - vec2(radius));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float s = sd(p);
	if (shadow > 0.5) {
		ALBEDO = vec3(0.0);
		ALPHA = (1.0 - smoothstep(-0.16, 0.03, s)) * 0.55;
	} else {
		float a = 1.0 - smoothstep(-0.012, 0.0, s);
		float b = clamp(-s / bevel, 0.0, 1.0);
		float e = 0.004;
		vec2 g = vec2(sd(p + vec2(e, 0.0)) - sd(p - vec2(e, 0.0)), sd(p + vec2(0.0, e)) - sd(p - vec2(0.0, e)));
		g = normalize(g + vec2(1e-6));
		float tilt = pow(1.0 - b, 1.4) * 1.5;
		vec3 n = normalize(vec3(g * tilt, 1.0));
		vec3 L = normalize(vec3(-0.45, -0.6, 0.8));
		float diff = clamp(dot(n, L), 0.0, 1.0);
		vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
		float spec = pow(clamp(dot(n, H), 0.0, 1.0), 30.0) * (1.0 - b);
		float grad = mix(1.2, 0.5, UV.y);
		vec3 col = base_col.rgb * grad * (0.5 + 0.8 * diff);
		col += vec3(1.0) * spec * 0.85;
		col += base_col.rgb * pow(1.0 - b, 3.0) * 0.45;
		col += vec3(1.0) * 0.10 * smoothstep(0.45, 0.0, UV.y) * b;
		ALBEDO = col * energy * dim;
		ALPHA = a;
	}
}
"""

# Emerald-cut crystal brick: sharp rectangle with clipped corners, a chamfered rim whose
# four faces are lit differently (light from top-left), a faceted table with diagonal
# seams, bright facet edges, a twinkling star and cracks that grow as the brick is damaged.
const CRYSTAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_col : source_color = vec4(1.0);
uniform vec2 size = vec2(1.3, 0.4);
uniform float bevel = 0.1;
uniform float energy = 1.0;
uniform float damage = 0.0;
uniform float phase = 0.0;
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
void fragment() {
	vec2 hs = size * 0.5;
	vec2 p = (UV - 0.5) * size;
	float dl = p.x + hs.x;
	float dr = hs.x - p.x;
	float dt = p.y + hs.y;
	float db = hs.y - p.y;
	float band = min(min(dl, dr), min(dt, db));
	float corner = min(min(dl + dt, dr + dt), min(dl + db, dr + db));
	float a = smoothstep(0.05, 0.062, corner);
	vec3 base = base_col.rgb;
	vec3 col;
	if (band < bevel) {
		float lit = 0.3;
		if (band == dt) { lit = 1.35; }
		else if (band == dl) { lit = 1.1; }
		else if (band == dr) { lit = 0.5; }
		float e = 1.0 - band / bevel;
		col = base * lit + vec3(1.0) * e * e * (lit > 0.9 ? 0.6 : 0.08);
		float m = min(min(abs(dl - dt), abs(dr - dt)), min(abs(dl - db), abs(dr - db)));
		col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.022, m)) * 0.5;
	} else {
		// two crossing diagonal grids cut the table into triangular facets of very different brightness
		float u = p.x * 2.6 - p.y * 5.0;
		float v = p.x * 2.6 + p.y * 5.0 + 3.0;
		vec2 cell = vec2(floor(u), floor(v));
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float tri = fract(u) + fract(v) > 1.0 ? 1.0 : 0.0;
		col = base * (0.28 + 0.95 * h + 0.25 * tri) * mix(1.3, 0.7, UV.y);
		float sm = min(min(fract(u), 1.0 - fract(u)), min(fract(v), 1.0 - fract(v)));
		col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.06, sm)) * 0.4;
		col += base * 0.35 * smoothstep(0.35, 0.0, abs(p.x - p.y * 1.6 + 0.1));
	}
	col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.02, abs(band - bevel))) * 0.5;
	col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.016, band)) * 0.5;
	vec2 sp = vec2(-hs.x * 0.68, -hs.y * 0.4);
	float tw = pow(max(0.0, sin(TIME * 2.2 + phase)), 12.0);
	vec2 q = abs(p - sp);
	float star = max(max(0.0, 1.0 - q.x / 0.17) * max(0.0, 1.0 - q.y / 0.014), max(0.0, 1.0 - q.y / 0.11) * max(0.0, 1.0 - q.x / 0.012));
	col += vec3(1.0) * star * tw * 1.6;
	if (damage > 0.3) {
		float c = 1.0 - smoothstep(0.0, 0.009, seg(p, vec2(-0.08, 0.0), vec2(hs.x * 0.75, hs.y)));
		col = mix(col, base * 0.12, c * 0.9);
	}
	if (damage > 0.6) {
		float c = 1.0 - smoothstep(0.0, 0.009, seg(p, vec2(-0.08, 0.0), vec2(-hs.x * 0.55, -hs.y)));
		col = mix(col, base * 0.12, c * 0.9);
	}
	ALBEDO = col * energy * (1.0 - 0.25 * damage);
	ALPHA = a * (band < bevel ? 1.0 : 0.9);
}
"""

# A flat triangular crystal shard with a gradient and bright edges. Tumbles in 3D when it breaks off.
const SHARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_col : source_color = vec4(1.0);
uniform float energy = 1.3;
void fragment() {
	float e = min(min(UV.x, UV.y), 1.0 - UV.x - UV.y);
	float g = mix(1.3, 0.45, clamp(UV.y + UV.x * 0.4, 0.0, 1.0));
	float tone = UV.x > UV.y ? 1.0 : 0.65;
	vec3 col = base_col.rgb * g * tone + vec3(1.0) * (1.0 - smoothstep(0.0, 0.1, e)) * 0.7;
	ALBEDO = col * energy;
	ALPHA = 0.95;
}
"""

# Expanding shock ring around a brick, used when a layer breaks off a multi-hit brick.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 base_col : source_color = vec4(1.0);
uniform vec2 size = vec2(1.3, 0.4);
uniform float radius = 0.03;
uniform float pad = 0.8;
uniform float t = 0.0;
float sd(vec2 p) {
	vec2 d = abs(p) - (size * 0.5 - vec2(radius));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}
void fragment() {
	vec2 p = (UV - 0.5) * (size + vec2(2.0 * pad));
	float s = sd(p);
	float r = t * pad * 0.95;
	float w = 0.03 + 0.04 * t;
	float ring = exp(-pow((s - r) / w, 2.0));
	ALBEDO = base_col.rgb * ring * (1.0 - t) * 2.2;
}
"""

# Additive neon aura around a rounded-rect. Sits on a quad that is `pad` larger on every side.
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 base_col : source_color = vec4(1.0);
uniform vec2 size = vec2(1.3, 0.4);
uniform float radius = 0.08;
uniform float pad = 0.4;
uniform float strength = 1.0;
float sd(vec2 p) {
	vec2 d = abs(p) - (size * 0.5 - vec2(radius));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}
void fragment() {
	vec2 p = (UV - 0.5) * (size + vec2(2.0 * pad));
	float s = max(sd(p), 0.0);
	float h = exp(-s / (pad * 0.32)) * (1.0 - smoothstep(pad * 0.55, pad, s));
	ALBEDO = base_col.rgb * h * strength;
}
"""

# Glossy sphere, lit from the top-left, seen from above.
const BALL_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 base_col : source_color = vec4(1.0);
uniform float energy = 1.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 L = normalize(vec3(-0.45, 0.55, 0.75));
	float d = clamp(dot(n, L), 0.0, 1.0);
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float spec = pow(clamp(dot(n, H), 0.0, 1.0), 60.0);
	float fres = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.5);
	ALBEDO = (base_col.rgb * (0.3 + 0.9 * d) + base_col.rgb * fres * 1.1) * energy + vec3(1.0) * spec * 1.6;
}
"""

enum State { READY, PLAY, PAUSED, OVER, WIN, CLEARED, NAME }

class Brick:
	var pop := 0.0 # brief scale pulse after a layer breaks
	var col := 0 # grid column, so the brick can be re-laid out when the window changes
	var halo: ShaderMaterial
	var kind := 0 # K_NORMAL, K_ARMOR (never breaks) or K_BOMB (explodes neighbours)
	var rect: Rect2
	var row: int
	var hits: int
	var max_hits: int
	var node: MeshInstance3D
	var mat: ShaderMaterial

class Ball:
	var pos: Vector2
	var vel: Vector2
	var trail: Array[Vector2] = []
	var node: Node3D
	var trail_nodes: Array[MeshInstance3D] = []

class Drop:
	var pos: Vector2
	var kind: String # "W" or "M"
	var node: Node3D

class Shot:
	var pos: Vector2
	var vel: Vector2
	var node: MeshInstance3D

class Part:
	var pos: Vector2
	var vel: Vector2
	var h: float
	var hv: float
	var life: float
	var max_life: float
	var size := 1.0
	var spin := Vector3.ZERO
	var ring := false # true = expanding shock ring (a flash with its own shader)
	var flash := false # true = expanding light burst, false = tumbling crystal shard
	var node: MeshInstance3D
	var mat: ShaderMaterial # per-instance material, only used by flashes
	var pool_key := "" # which flash pool the node returns to

var state: State
var level := 0
var score := 0
var lives := LIVES_START
var speed := SPEED_START
var bricks: Array[Brick] = []
var balls: Array[Ball] = []
var drops: Array[Drop] = []
var parts: Array[Part] = []
var shard_pool: Array[MeshInstance3D] = []
var flash_pool := {} # kind -> Array of hidden flash nodes (each keeps its own mesh and material)
var paddle_x := W / 2.0
var paddle_w := PADDLE_W
var paddle_synced_w := -1.0 # width the paddle meshes were last built for
var paddle_synced_wide := false
var wide_left := 0.0
var mouse_active := false
var shake := 0.0
var stall_grace := 0.0 # seconds the ball stays frozen after a long frame
var perf_frame := 60
var dbg_on := false # ?debug in the web link: show frame timing under the HUD
var dbg_t := 0.0
var dbg_nosound := false # ?debug&nosound: skip all sound effects
var dbg_nofx := false # ?debug&nofx: skip shatter shards and flashes
var dbg_delta := 0.0 # worst frame time / worst script time in the current 2 s window
var dbg_script := 0.0
var dbg_shown := ""
var perf_test := false # --perf: trigger a chain explosion and print slow frames
var rotated_hint := false # set by shell.gd when the picture is turned for a portrait screen
var PADDLE_Y := H - 44.0 # raised on touch layouts so a thumb and the home bar stay clear

var _font: Font
var _box := StyleBoxFlat.new()

# 3D scene
var world := Node3D.new()
var camera := Camera3D.new()
var paddle_node: MeshInstance3D
var paddle_mesh: PlaneMesh
var paddle_mat: ShaderMaterial
var paddle_shadow_mesh: PlaneMesh
var armor_mat: ShaderMaterial
var bomb_mat: ShaderMaterial
var armor_halo_mat: ShaderMaterial
var bomb_halo_mat: ShaderMaterial
var rail_nodes: Array[MeshInstance3D] = []
var shape_shader: Shader
var crystal_shader: Shader
var shard_shader: Shader
var ring_shader: Shader
var shard_meshes: Array[ArrayMesh] = []
var shard_mats: Array[ShaderMaterial] = []
var halo_shader: Shader
var halo_row_mats: Array[ShaderMaterial] = []
var paddle_halo_mat: ShaderMaterial
var paddle_halo_mesh: PlaneMesh
var ball_halo_mat: ShaderMaterial
var row_mats: Array[ShaderMaterial] = []
var ball_mat: ShaderMaterial
var trail_mat: StandardMaterial3D
var paddle_shadow_mat: ShaderMaterial
var brick_mesh: PlaneMesh
var brick_shadow_mesh: PlaneMesh
var ball_mesh: SphereMesh
var ball_shadow_mesh: PlaneMesh
var trail_mesh: SphereMesh

# dev screenshot mode: godot --path . -- --shot=out.png
var shot_path := ""
var shot_frame := 300
var start_level := 0

# audio
var sfx := {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_next := 0
var music_player: AudioStreamPlayer
var audio_thread: Thread
var audio_unlocked := false
var audio_loading := false
var muted := false
# mobile / quality
const SETTINGS_PATH := "user://brickfall.cfg"
const TOUCH_GAIN := 1.35 # finger travel -> paddle travel
var mobile_ui := false # bigger buttons and a raised paddle
var touch_mode := false # relative drag control once a real touch is seen
var low_quality := false
var quality_chosen := false # true once the player picked a setting, which stops auto-detect
var env: Environment
var probe_time := 0.0
var probe_frames := 0
var clear_timer := 0.0
# boss
var boss: Brick = null
var boss_t := 0.0
var boss_fire_t := 0.0
var boss_phase := 0
var boss_cd := 0.0 # stops one ball touch counting as several hits
var invuln := 0.0 # after a bolt hits the paddle
var phase_banner := 0.0
var shots: Array[Shot] = []
var shot_mat: ShaderMaterial
var shot_halo_mat: ShaderMaterial
var boss_halo_mat: ShaderMaterial
# high scores (top 10, saved in user://brickfall.cfg)
const SCORES_MAX := 10
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
var scores: Array = [] # [{name, score, level}, ...] best first
var last_name := "AAA"
var name_idx := [0, 0, 0]
var name_slot := 0
var pending_state: State = State.OVER
var new_rank := -1
var combo := 0 # bricks broken since the ball last touched the paddle; raises the crash pitch
var frame_i := 0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	randomize()
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	mobile_ui = OS.has_feature("mobile")
	load_settings()
	for a in OS.get_cmdline_user_args():
		if a == "--mobile":
			mobile_ui = true
		elif a == "--low":
			low_quality = true
		elif a == "--perf":
			perf_test = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--frame="):
			shot_frame = int(a.substr(8))
		elif a.begins_with("--level="):
			start_level = clampi(int(a.substr(8)) - 1, 0, LEVELS.size() - 1)
	W = get_viewport().get_visible_rect().size.x
	get_viewport().size_changed.connect(on_resized)
	build_world()
	setup_audio()
	AudioServer.set_bus_mute(0, muted)
	set_quality(low_quality, false)
	prewarm_effects()
	fill_shard_pool(110)
	fill_flash_pool()
	new_game()
	if start_level > 0:
		level = start_level
		load_level()


## Shards are recycled instead of created and freed on every break, which is what made
## chain explosions hitch: a pool of hidden nodes is filled at startup.
func take_shard(mesh: Mesh) -> MeshInstance3D:
	var mi: MeshInstance3D
	if shard_pool.is_empty():
		mi = MeshInstance3D.new()
		world.add_child(mi)
	else:
		mi = shard_pool.pop_back()
	mi.mesh = mesh
	mi.rotation = Vector3.ZERO
	mi.scale = Vector3.ONE * 0.001
	mi.visible = true
	return mi


func make_flash(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bs := Vector2(BW * S, BH * S)
	match kind:
		"burst":
			mi.mesh = plane(bs + Vector2(1.2, 1.2))
			mi.material_override = halo_mat(Color.WHITE, bs, 0.03, 0.6, 3.0 / GLOW)
		"blast":
			mi.mesh = plane(Vector2(3.2, 2.7))
			mi.material_override = halo_mat(Color("ff7a2a"), Vector2(1.5, 0.9), 0.3, 1.4, 1.0)
		_:
			var rm := ShaderMaterial.new()
			rm.shader = ring_shader
			rm.set_shader_parameter("size", bs)
			mi.mesh = plane(bs + Vector2(1.6, 1.6))
			mi.material_override = rm
	mi.visible = false
	world.add_child(mi)
	return mi


func take_flash(kind: String) -> MeshInstance3D:
	var pool: Array = flash_pool[kind]
	var mi: MeshInstance3D = pool.pop_back() if not pool.is_empty() else make_flash(kind)
	mi.visible = true
	return mi


## Pooled flashes keep the old brick size, so after a resize they are rebuilt on demand.
func clear_flash_pool() -> void:
	for kind in flash_pool:
		for mi in flash_pool[kind]:
			mi.queue_free()
		flash_pool[kind] = []


func release_part(p: Part) -> void:
	if p.flash:
		p.node.visible = false
		flash_pool[p.pool_key].append(p.node)
	else:
		p.node.visible = false
		shard_pool.append(p.node)


func fill_flash_pool() -> void:
	for kind in ["burst", "blast", "ring"]:
		flash_pool[kind] = []
	for kind in ["burst", "burst", "burst", "burst", "burst", "burst", "blast", "blast", "ring", "ring", "ring"]:
		flash_pool[kind].append(make_flash(kind))


func fill_shard_pool(n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		mi.visible = false
		world.add_child(mi)
		shard_pool.append(mi)


## Draws every effect shader once, too small to see, so the web build compiles them while
## loading instead of hitching on the first brick that breaks.
func prewarm_effects() -> void:
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 0.001
	world.add_child(holder)
	var mats: Array = shard_mats.duplicate()
	var rm := ShaderMaterial.new()
	rm.shader = ring_shader
	rm.set_shader_parameter("size", Vector2(1, 1))
	mats.append(rm)
	mats.append(halo_mat(Color.WHITE, Vector2(1, 1), 0.03, 0.6, 1.0))
	for i in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = shard_meshes[i % shard_meshes.size()] if i < shard_mats.size() else plane(Vector2(1, 1))
		mi.material_override = mats[i]
		mi.position = Vector3(0, 0.3, 0)
		holder.add_child(mi)
	get_tree().create_timer(0.5).timeout.connect(holder.queue_free)


# Auto-pause when the app loses focus (incoming call, app switch, window deselected).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.PLAY and shot_path == "":
			state = State.PAUSED


# ---- 3D scene
func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3((p.x - W / 2.0) * S, y, (p.y - H / 2.0) * S)


func neon_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.65)
	m.metallic = 0.35
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


## Material for a bevelled shape of the given size (3D units).
func shape_mat(col: Color, size: Vector2, radius: float, bevel: float, energy: float, shadow := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shape_shader
	m.set_shader_parameter("base_col", col)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("bevel", bevel)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("shadow", 1.0 if shadow else 0.0)
	return m


func crystal_mat(col: Color, size: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = crystal_shader
	m.set_shader_parameter("base_col", col)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("bevel", 0.12)
	m.set_shader_parameter("energy", 0.85)
	return m


func make_shard(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func plane(size: Vector2) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = size
	return pm


## Adds a soft drop shadow under a node. Offset is in node-local units.
func add_shadow(parent: Node3D, mesh: PlaneMesh, radius: float) -> ShaderMaterial:
	var sm := shape_mat(Color.BLACK, mesh.size, radius, 0.1, 1.0, true)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = sm
	mi.position = Vector3(0.07, -0.17, 0.11)
	parent.add_child(mi)
	return sm


## Material for a neon aura (see HALO_SHADER) around a shape of the given size.
func halo_mat(col: Color, size: Vector2, radius: float, pad: float, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = halo_shader
	m.set_shader_parameter("base_col", col)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("pad", pad)
	m.set_shader_parameter("strength", strength * GLOW)
	return m


## Adds an additive glow quad under a node (below the shape, above the shadow).
func add_halo(parent: Node3D, size: Vector2, mat: ShaderMaterial, pad: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = plane(size + Vector2(2.0 * pad, 2.0 * pad))
	mi.material_override = mat
	mi.position = Vector3(0, -0.06, 0)
	mi.add_to_group("halo")
	mi.visible = not low_quality
	parent.add_child(mi)


func add_strip(size: Vector2, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = plane(size)
	var r := minf(size.x, size.y) * 0.5
	mi.material_override = shape_mat(col, size, r, r, 1.8)
	mi.position = pos
	world.add_child(mi)
	rail_nodes.append(mi)
	add_halo(mi, size, halo_mat(col, size, r, 0.5, 1.4), 0.5)


## Neon rails along the left, right and top edges, plus a red danger line along the bottom.
func build_rails() -> void:
	for n in rail_nodes:
		n.queue_free()
	rail_nodes.clear()
	var top_z := (40.0 - H / 2.0) * S
	var depth := (H - 40.0) * S
	var mid_z := top_z + depth / 2.0
	add_strip(Vector2(0.16, depth + 0.2), Vector3(-W / 2.0 * S + 0.08, 0.1, mid_z), MAGENTA)
	add_strip(Vector2(0.16, depth + 0.2), Vector3(W / 2.0 * S - 0.08, 0.1, mid_z), CYAN)
	add_strip(Vector2(W * S + 0.32, 0.16), Vector3(0, 0.1, top_z + 0.08), MAGENTA.lerp(CYAN, 0.5))
	# bottom line: only a visual (a danger line), the ball still falls through it and costs a life
	add_strip(Vector2(W * S + 0.32, 0.16), Vector3(0, 0.1, H / 2.0 * S - 0.08), Color("ff2e63"))


func build_world() -> void:
	add_child(world)

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.55)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 1.5 * GLOW
	env.glow_strength = 1.3
	env.glow_bloom = 0.25 * GLOW
	env.glow_hdr_threshold = 0.7
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in range(1, 6):
		env.set_glow_level(i, 1.0)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	shape_shader = Shader.new()
	shape_shader.code = SHAPE_SHADER
	halo_shader = Shader.new()
	halo_shader.code = HALO_SHADER
	crystal_shader = Shader.new()
	crystal_shader.code = CRYSTAL_SHADER
	shard_shader = Shader.new()
	shard_shader.code = SHARD_SHADER
	ring_shader = Shader.new()
	ring_shader.code = RING_SHADER
	for tri in [
		[Vector3(-0.2, 0, -0.16), Vector3(0.26, 0, -0.04), Vector3(-0.06, 0, 0.22)],
		[Vector3(-0.14, 0, -0.2), Vector3(0.2, 0, 0.1), Vector3(-0.22, 0, 0.12)],
		[Vector3(-0.1, 0, -0.22), Vector3(0.24, 0, 0.16), Vector3(-0.2, 0, 0.04)],
	]:
		shard_meshes.append(make_shard(tri[0], tri[1], tri[2]))

	# straight-down orthographic camera: the field maps 1:1 onto the 800x600 screen
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = H * S
	camera.position = Vector3(0, 20, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(camera)


	build_rails()

	# shared meshes and materials
	brick_mesh = plane(Vector2(BW * S - 0.04, BH * S - 0.04))
	brick_shadow_mesh = plane(brick_mesh.size + Vector2(0.06, 0.06))
	ball_mesh = SphereMesh.new()
	ball_mesh.radius = BALL_R * S
	ball_mesh.height = BALL_R * S * 2.0
	ball_shadow_mesh = plane(Vector2(0.4, 0.4))
	trail_mesh = SphereMesh.new()
	trail_mesh.radius = BALL_R * S * 0.7
	trail_mesh.height = BALL_R * S * 1.4
	for c in ROW_COLORS:
		row_mats.append(crystal_mat(c, brick_mesh.size))
		halo_row_mats.append(halo_mat(c, brick_mesh.size, 0.03, 0.4, 0.8))
		var sm := ShaderMaterial.new()
		sm.shader = shard_shader
		sm.set_shader_parameter("base_col", c)
		shard_mats.append(sm)
	# armored (steel, unbreakable) and explosive (hot orange, pulsing) bricks
	armor_mat = crystal_mat(Color("8d9bb5"), brick_mesh.size)
	armor_mat.set_shader_parameter("energy", 0.7)
	armor_halo_mat = halo_mat(Color("8d9bb5"), brick_mesh.size, 0.03, 0.4, 0.25)
	bomb_mat = crystal_mat(Color("ff5a1f"), brick_mesh.size)
	bomb_halo_mat = halo_mat(Color("ff5a1f"), brick_mesh.size, 0.03, 0.4, 1.2)
	var bsm := ShaderMaterial.new()
	bsm.shader = shard_shader
	bsm.set_shader_parameter("base_col", Color("ff7a2a"))
	shard_mats.append(bsm) # index 6: shards from explosive bricks
	var asm := ShaderMaterial.new()
	asm.shader = shard_shader
	asm.set_shader_parameter("base_col", Color("8d9bb5"))
	shard_mats.append(asm)
	var wsm := ShaderMaterial.new()
	wsm.shader = shard_shader
	wsm.set_shader_parameter("base_col", Color("cfeaff"))
	wsm.set_shader_parameter("energy", 1.0)
	shard_mats.append(wsm) # index 8: shield plates from multi-hit bricks

	ball_mat = ShaderMaterial.new()
	ball_mat.shader = Shader.new()
	ball_mat.shader.code = BALL_SHADER
	ball_mat.set_shader_parameter("base_col", ACCENT)
	ball_mat.set_shader_parameter("energy", 1.7)
	ball_halo_mat = halo_mat(ACCENT, Vector2(0.32, 0.32), 0.16, 0.6, 1.5)
	trail_mat = neon_mat(ACCENT, 1.4)

	paddle_mesh = plane(Vector2(PADDLE_W * S, PADDLE_H * S + 0.04))
	paddle_shadow_mesh = plane(paddle_mesh.size + Vector2(0.06, 0.06))
	paddle_mat = shape_mat(INK, paddle_mesh.size, paddle_mesh.size.y * 0.5, 0.13, 1.5)
	paddle_node = MeshInstance3D.new()
	paddle_node.mesh = paddle_mesh
	paddle_node.material_override = paddle_mat
	world.add_child(paddle_node)
	paddle_halo_mat = halo_mat(CYAN, paddle_mesh.size, paddle_mesh.size.y * 0.5, 0.5, 1.1)
	paddle_halo_mesh = plane(paddle_mesh.size + Vector2(1.0, 1.0))
	var ph := MeshInstance3D.new()
	ph.mesh = paddle_halo_mesh
	ph.material_override = paddle_halo_mat
	ph.position = Vector3(0, -0.06, 0)
	ph.add_to_group("halo")
	paddle_node.add_child(ph)
	paddle_shadow_mat = add_shadow(paddle_node, paddle_shadow_mesh, paddle_shadow_mesh.size.y * 0.5)


func clear_dynamic() -> void:
	clear_shots()
	boss = null
	for k in bricks:
		k.node.queue_free()
	bricks.clear()
	for b in balls:
		free_ball(b)
	balls.clear()
	for d in drops:
		d.node.queue_free()
	drops.clear()
	for p in parts:
		release_part(p)
	parts.clear()


func new_ball(pos: Vector2, vel: Vector2) -> Ball:
	var b := Ball.new()
	b.pos = pos
	b.vel = vel
	var n := MeshInstance3D.new()
	n.mesh = ball_mesh
	n.material_override = ball_mat
	add_shadow(n, ball_shadow_mesh, 0.2)
	add_halo(n, Vector2(0.32, 0.32), ball_halo_mat, 0.6)
	world.add_child(n)
	b.node = n
	for i in TRAIL_LEN:
		var t := MeshInstance3D.new()
		t.mesh = trail_mesh
		t.material_override = trail_mat
		t.visible = false
		world.add_child(t)
		b.trail_nodes.append(t)
	return b


func free_ball(b: Ball) -> void:
	b.node.queue_free()
	for t in b.trail_nodes:
		t.queue_free()


# ---- Game flow
func new_game() -> void:
	level = 0
	score = 0
	lives = LIVES_START
	load_level()


## Recomputes the brick width so ten columns span the field, and resizes every brick material.
func set_brick_size() -> void:
	BW = floorf((W - 68.0 - (COLS - 1) * GAP) / COLS)
	var sz := Vector2(BW * S - 0.04, BH * S - 0.04)
	brick_mesh.size = sz
	brick_shadow_mesh.size = sz + Vector2(0.06, 0.06)
	for m in row_mats:
		m.set_shader_parameter("size", sz)
	for m in halo_row_mats:
		m.set_shader_parameter("size", sz)
	for m in [armor_mat, bomb_mat, armor_halo_mat, bomb_halo_mat]:
		m.set_shader_parameter("size", sz)


func load_level() -> void:
	clear_dynamic()
	set_brick_size()
	var left := (W - (COLS * BW + (COLS - 1) * GAP)) / 2.0
	var rows: Array = LEVELS[level]["rows"]
	for r in rows.size():
		var line: String = rows[r]
		for c in line.length():
			if line[c] == ".":
				continue
			var b := Brick.new()
			b.rect = Rect2(left + c * (BW + GAP), TOP + r * (BH + GAP), BW, BH)
			b.row = r % ROW_COLORS.size()
			var ch: String = line[c]
			b.col = c
			b.halo = halo_row_mats[b.row]
			match ch:
				"A":
					b.kind = K_ARMOR
					b.hits = 1
					b.mat = armor_mat.duplicate()
					b.halo = armor_halo_mat
				"X":
					b.kind = K_BOMB
					b.hits = 1
					b.mat = bomb_mat.duplicate()
					b.halo = bomb_halo_mat
				_:
					b.hits = int(ch)
					b.mat = row_mats[b.row].duplicate()
			b.max_hits = b.hits
			b.mat.set_shader_parameter("phase", randf() * TAU)
			make_brick_node(b)
			bricks.append(b)
	if LEVELS[level].has("boss"):
		spawn_boss()
	reset_serve()


## Builds (or rebuilds) the 3D node for a brick from its current rect and material.
func make_brick_node(b: Brick) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = brick_mesh
	mi.material_override = b.mat
	mi.position = to3(b.rect.get_center(), 0.23)
	add_shadow(mi, brick_shadow_mesh, 0.04)
	add_halo(mi, brick_mesh.size, b.halo, 0.4)
	if b.kind == K_BOMB:
		var lbl := Label3D.new()
		lbl.text = "!"
		lbl.font_size = 56
		lbl.pixel_size = 0.009
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.outline_size = 12
		lbl.outline_modulate = Color("b0300c")
		lbl.position = Vector3(0, 0.3, 0)
		mi.add_child(lbl)
	world.add_child(mi)
	b.node = mi


## After the window changes size the bricks keep their columns but stretch to the new width.
func relayout_bricks() -> void:
	clear_flash_pool()
	set_brick_size()
	var left := (W - (COLS * BW + (COLS - 1) * GAP)) / 2.0
	for b in bricks:
		if b.kind == K_BOSS:
			continue
		b.rect = Rect2(left + b.col * (BW + GAP), b.rect.position.y, BW, BH)
		b.mat.set_shader_parameter("size", brick_mesh.size)
		b.node.queue_free()
		make_brick_node(b)


## The 3D scene is centred on the field, so these only need their game-space x kept in step.
## The paddle and balls follow the field centre.


## The paddle gets narrower on every level.
func base_paddle_w() -> float:
	return PADDLE_W * maxf(PADDLE_MIN_RATIO, 1.0 - PADDLE_SHRINK * level)


func breakable_left() -> int:
	var n := 0
	for k in bricks:
		if k.kind != K_ARMOR:
			n += 1
	return n


func reset_serve() -> void:
	PADDLE_Y = H - (84.0 if (mobile_ui or touch_mode) else 44.0)
	paddle_x = W / 2.0
	paddle_w = base_paddle_w()
	wide_left = 0.0
	speed = minf(SPEED_START + level * 30.0, SPEED_MAX - 40.0) # each level starts a little faster
	if LEVELS[level].has("boss"):
		speed = minf(speed, 470.0)
	for b in balls:
		free_ball(b)
	balls.clear()
	balls.append(new_ball(Vector2(paddle_x, PADDLE_Y - BALL_R - 1.0), Vector2.ZERO))
	state = State.READY


# ---- Input
func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		unlock_audio() # browsers and phones only allow sound after a first tap or key press
		if is_portrait():
			return
	if state == State.NAME:
		if event is InputEventKey and event.pressed and not event.echo:
			name_key(event)
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			name_click(get_global_mouse_position())
			return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_mode = true
		mobile_ui = true
	if event is InputEventScreenDrag:
		# relative drag: the paddle follows finger movement, so the thumb never covers it
		if state == State.PLAY or state == State.READY:
			paddle_x += event.relative.x * TOUCH_GAIN
	elif event is InputEventMouseMotion:
		mouse_active = true
		# a real mouse (not one emulated from touch) takes control back from touch mode
		if touch_mode and event.device != InputEvent.DEVICE_ID_EMULATION:
			touch_mode = false
			mobile_ui = OS.has_feature("mobile")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_active = true
		# Touch is emulated as mouse input, so taps and clicks share this path.
		var m := get_global_mouse_position()
		if pause_rect().has_point(m) and (state == State.PLAY or state == State.PAUSED):
			toggle_pause()
		elif sound_rect().has_point(m):
			toggle_mute()
		elif state == State.PAUSED and quality_rect().has_point(m):
			quality_chosen = true
			set_quality(not low_quality)
		else:
			act()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				act()
			KEY_P:
				toggle_pause()
			KEY_M:
				toggle_mute()
			KEY_G:
				quality_chosen = true
				set_quality(not low_quality)


# ---- High scores
func qualifies() -> bool:
	return score > 0 and (scores.size() < SCORES_MAX or score > int(scores[scores.size() - 1]["score"]))


## Called when a run ends. A top-10 score goes to initials entry first.
func finish_run(final: State) -> void:
	pending_state = final
	new_rank = -1
	if qualifies():
		for i in 3:
			name_idx[i] = maxi(0, LETTERS.find(last_name[i]))
		name_slot = 0
		state = State.NAME
		play("power_w")
	else:
		state = final
		if final == State.OVER:
			play("gameover")


func submit_name() -> void:
	var nm := ""
	for i in 3:
		nm += LETTERS[name_idx[i]]
	var pos := scores.size()
	for i in scores.size():
		if score > int(scores[i]["score"]):
			pos = i
			break
	scores.insert(pos, {"name": nm, "score": score, "level": level + 1})
	if scores.size() > SCORES_MAX:
		scores.resize(SCORES_MAX)
	new_rank = pos
	last_name = nm
	save_settings()
	play("clear")
	state = pending_state


func step_letter(slot: int, d: int) -> void:
	name_idx[slot] = (name_idx[slot] + d + LETTERS.length()) % LETTERS.length()
	name_slot = slot
	play("pause", 1.0 + 0.04 * name_idx[slot] / 5.0)


func name_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_UP: step_letter(name_slot, 1)
		KEY_DOWN: step_letter(name_slot, -1)
		KEY_LEFT: name_slot = maxi(0, name_slot - 1)
		KEY_RIGHT: name_slot = mini(2, name_slot + 1)
		KEY_BACKSPACE: name_slot = maxi(0, name_slot - 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: submit_name()
		_:
			if event.keycode >= KEY_A and event.keycode <= KEY_Z:
				name_idx[name_slot] = event.keycode - KEY_A
				name_slot = mini(2, name_slot + 1)
				play("pause", 1.2)


func name_slot_x(i: int) -> float:
	return W / 2.0 - 100.0 + 100.0 * i


func name_click(m: Vector2) -> void:
	for i in 3:
		var cx := name_slot_x(i)
		if Rect2(cx - 45, 205, 90, 62).has_point(m):
			step_letter(i, 1)
			return
		if Rect2(cx - 45, 345, 90, 62).has_point(m):
			step_letter(i, -1)
			return
		if Rect2(cx - 45, 267, 90, 78).has_point(m):
			name_slot = i
			return
	if name_ok_rect().has_point(m):
		submit_name()


# ---- Layout, settings and quality
## Touch layouts get larger tap targets that reach below the HUD bar.
func pause_rect() -> Rect2:
	return Rect2(W / 2.0 - 228.0, 0, 80, 72) if mobile_ui else Rect2(W / 2.0 - 172.0, 2, 44, 36)


func sound_rect() -> Rect2:
	return Rect2(W / 2.0 - 144.0, 0, 80, 72) if mobile_ui else Rect2(W / 2.0 - 122.0, 2, 44, 36)


func quality_rect() -> Rect2:
	return Rect2(W / 2.0 - 140.0, 370, 280, 52)


func name_ok_rect() -> Rect2:
	return Rect2(W / 2.0 - 80.0, 400, 160, 52)


## True when the window is taller than wide (a phone held upright).
func is_portrait() -> bool:
	var v := get_viewport().get_visible_rect().size
	return v.y > v.x


## The window changed size. Re-centre everything that already exists and rebuild the rails.
func on_resized() -> void:
	var new_w := get_viewport().get_visible_rect().size.x
	if is_equal_approx(new_w, W):
		return
	var dx := (new_w - W) / 2.0
	W = new_w
	relayout_bricks()
	for b in balls:
		b.pos.x += dx
		for i in b.trail.size():
			b.trail[i].x += dx
	for d in drops:
		d.pos.x += dx
	for sh in shots:
		sh.pos.x += dx
	paddle_x += dx
	if not rail_nodes.is_empty():
		build_rails()


func draw_rotate_prompt() -> void:
	var v := get_viewport().get_visible_rect().size
	draw_rect(Rect2(Vector2.ZERO, v), Color("070a14"))
	var c := v / 2.0
	# a phone outline with a curved arrow showing the turn
	draw_rect(Rect2(c.x - 34, c.y - 150, 68, 118), Color(CYAN, 0.9), false, 5.0)
	draw_rect(Rect2(c.x - 10, c.y - 142, 20, 4), Color(CYAN, 0.9))
	draw_arc(c + Vector2(0, -92), 92.0, deg_to_rad(-25.0), deg_to_rad(60.0), 24, Color(ACCENT, 0.95), 6.0)
	var tip := c + Vector2(0, -92) + Vector2.from_angle(deg_to_rad(60.0)) * 92.0
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-16, -14), tip + Vector2(14, -18), tip + Vector2(2, 18)]), ACCENT)
	glow_text("Turn your phone sideways", c.y + 70.0, 44, INK, HORIZONTAL_ALIGNMENT_CENTER, 0.0, v.x)
	text("Brickfall plays in landscape", c.y + 112.0, 26, MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.0, v.x)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		muted = cf.get_value("audio", "muted", false)
		low_quality = cf.get_value("video", "low_quality", false)
		quality_chosen = cf.get_value("video", "chosen", false)
		last_name = cf.get_value("scores", "last_name", "AAA")
		scores.clear()
		for e in cf.get_value("scores", "list", []):
			if e is Dictionary and e.has("score") and e.has("name"):
				scores.append(e)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "muted", muted)
	cf.set_value("video", "low_quality", low_quality)
	cf.set_value("video", "chosen", quality_chosen)
	cf.set_value("scores", "list", scores)
	cf.set_value("scores", "last_name", last_name)
	cf.save(SETTINGS_PATH)


## Low quality turns off the glow post-process and the additive aura quads, and breaks
## bricks into fewer shards. Everything else looks the same.
func set_quality(low: bool, save := true) -> void:
	low_quality = low
	if env != null:
		env.glow_enabled = not low
	for n in get_tree().get_nodes_in_group("halo"):
		n.visible = not low
	if save:
		save_settings()


## On a touch device, if the first seconds of play run slower than ~40 fps, drop to low
## quality automatically (unless the player has already chosen a setting).
func probe_performance(raw_dt: float) -> void:
	if quality_chosen or low_quality or not (mobile_ui or touch_mode) or state != State.PLAY:
		return
	probe_time += raw_dt
	probe_frames += 1
	if probe_frames >= 180:
		if probe_time / probe_frames > 1.0 / 40.0:
			set_quality(true)
		quality_chosen = true # only probe once
		save_settings()


func toggle_pause() -> void:
	if state == State.PLAY:
		state = State.PAUSED
		play("pause")
	elif state == State.PAUSED:
		state = State.PLAY
		play("pause")


func act() -> void:
	match state:
		State.READY: launch()
		State.PAUSED:
			state = State.PLAY
			play("pause")
		State.OVER, State.WIN: new_game()


func launch() -> void:
	var a := deg_to_rad(randf_range(-15.0, 15.0))
	balls[0].vel = Vector2(sin(a), -cos(a)) * speed
	state = State.PLAY
	play("launch")


# ---- Audio (all sounds are synthesised in audio_synth.gd, no files)
func setup_audio() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -3.0
		add_child(p)
		sfx_players.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -40.0
	add_child(music_player)
	audio_loading = true
	if OS.has_feature("web"):
		# the web export runs without threads, so build after the first frames are on screen
		get_tree().create_timer(0.3).timeout.connect(_build_audio_now)
	else:
		audio_thread = Thread.new()
		audio_thread.start(_build_audio)


func _build_audio_now() -> void:
	# main-thread build: yields every few ms so the game keeps running while sound loads
	Synth.budget_ms = 6.0
	var result: Dictionary = await Synth.build_all()
	_on_audio_ready(result)


func _build_audio() -> void:
	var result: Dictionary = await Synth.build_all()
	_on_audio_ready.call_deferred(result)


func _on_audio_ready(result: Dictionary) -> void:
	if audio_thread != null and audio_thread.is_started():
		audio_thread.wait_to_finish()
	audio_loading = false
	sfx = result["sfx"]
	music_player.stream = result["music"]
	try_start_music()


func unlock_audio() -> void:
	audio_unlocked = true
	try_start_music()


func try_start_music() -> void:
	if audio_unlocked and music_player.stream != null and not music_player.playing:
		music_player.play()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	save_settings()
	if not muted:
		play("pause")


func play(sound: String, pitch := 1.0, vol_db := 0.0) -> void:
	if dbg_nosound:
		return
	if not sfx.has(sound):
		return
	var p := sfx_players[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_players.size()
	p.stream = sfx[sound]
	p.pitch_scale = pitch
	p.volume_db = -3.0 + vol_db
	p.play()


# ---- Update
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	var dbg_t0 := Time.get_ticks_usec()
	if delta > 0.05 and state == State.PLAY and shot_path == "" and not perf_test:
		stall_grace = 0.18
	if frame_i == 30 and OS.has_feature("web"):
		# link flags (?debug, ?nosound, ?nofx), read a few frames in: a script call while the scene is
		# still being built breaks the 3D view on the web
		var q: Variant = JavaScriptBridge.eval("location.search")
		if q is String:
			dbg_on = q.contains("debug")
			dbg_nosound = dbg_on and q.contains("nosound")
			dbg_nofx = dbg_on and q.contains("nofx")
	if perf_test:
		if frame_i > 40 and delta > 0.022:
			print("frame ", frame_i, " delta_ms=", snappedf(delta * 1000.0, 0.1), " parts=", parts.size())
		if frame_i == 2700 and not OS.has_feature("web"):
			get_tree().quit()
	probe_performance(delta)
	if is_portrait() and state == State.PLAY:
		state = State.PAUSED
	if state != State.PAUSED:
		update(dt)
	sync_3d(dt)
	if dbg_on:
		dbg_script = maxf(dbg_script, (Time.get_ticks_usec() - dbg_t0) / 1000.0)
		dbg_delta = maxf(dbg_delta, delta * 1000.0)
		dbg_t += delta
		if dbg_t >= 2.0:
			dbg_shown = "worst frame %.0f ms   script %.1f ms   shards %d   input %s" % [dbg_delta, dbg_script, parts.size(), "TOUCH" if touch_mode else ("mouse" if mouse_active else "idle")]
			dbg_t = 0.0
			dbg_delta = 0.0
			dbg_script = 0.0
	# music sits lower when the game is not in active play
	var music_target := -16.0 if (state == State.PLAY or state == State.READY or state == State.CLEARED) else -25.0
	music_player.volume_db = lerpf(music_player.volume_db, music_target, minf(1.0, dt * 2.0))
	queue_redraw()
	frame_i += 1
	if shot_path != "" and frame_i == shot_frame:
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()


func update(dt: float) -> void:
	# Keys nudge the paddle; moving the mouse hands control back to it.
	var kd := int(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) \
		- int(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
	if kd != 0:
		paddle_x += kd * PADDLE_KEY_SPEED * dt
		mouse_active = false
	elif mouse_active and not touch_mode:
		paddle_x = get_global_mouse_position().x
	if shot_path != "" or perf_test:
		if state == State.READY and frame_i > 10:
			launch()
		elif state == State.PLAY and not balls.is_empty():
			paddle_x = balls[0].pos.x + sin(frame_i * 0.05) * 40.0
	paddle_x = clampf(paddle_x, paddle_w / 2.0, W - paddle_w / 2.0)

	wide_left = maxf(0.0, wide_left - dt)
	var target := base_paddle_w() * (PADDLE_WIDE_RATIO if wide_left > 0.0 else 1.0)
	paddle_w = lerpf(paddle_w, target, minf(1.0, dt * 12.0))
	shake = maxf(0.0, shake - dt * 1.5)
	phase_banner = maxf(0.0, phase_banner - dt)
	if boss != null or not shots.is_empty():
		update_boss(dt)

	if state == State.READY:
		balls[0].pos = Vector2(paddle_x, PADDLE_Y - BALL_R - 1.0)

	if state == State.PLAY:
		# after a long frame the ball waits a moment, so a stall never costs a life while the paddle catches up
		if stall_grace > 0.0:
			stall_grace -= dt
		else:
			for b in balls:
				move_ball(b, dt)
		var alive: Array[Ball] = []
		for b in balls:
			if b.pos.y - BALL_R < H:
				alive.append(b)
			else:
				free_ball(b)
		balls = alive
		if balls.is_empty():
			lives -= 1
			if lives <= 0:
				finish_run(State.OVER)
			else:
				reset_serve()
				play("lose")
		if state == State.PLAY and breakable_left() == 0:
			play("clear")
			# unbreakable bricks left over shatter with the level, so it reads as a clear
			for k in bricks.duplicate():
				k.node.queue_free()
				burst(k)
			bricks.clear()
			shake = 0.35
			clear_timer = 1.6
			state = State.CLEARED

	if state == State.CLEARED:
		clear_timer -= dt
		if clear_timer <= 0.0:
			if level + 1 < LEVELS.size():
				level += 1
				load_level()
			else:
				finish_run(State.WIN)

	var kept_drops: Array[Drop] = []
	for d in drops:
		d.pos.y += 150.0 * dt
		var caught := state == State.PLAY and d.pos.y + 10.0 >= PADDLE_Y and d.pos.y - 10.0 <= PADDLE_Y + PADDLE_H \
				and absf(d.pos.x - paddle_x) <= paddle_w / 2.0 + 12.0
		if caught:
			score += 25
			apply_power(d.kind)
		if caught or d.pos.y > H + 20.0:
			d.node.queue_free()
		else:
			kept_drops.append(d)
	drops = kept_drops

	var kept_parts: Array[Part] = []
	for p in parts:
		p.pos += p.vel * dt
		p.h += p.hv * dt
		if not p.flash:
			p.hv -= 14.0 * dt
		p.life -= dt
		if p.life <= 0.0:
			release_part(p)
		else:
			kept_parts.append(p)
	parts = kept_parts


func apply_power(kind: String) -> void:
	shake = maxf(shake, 0.25)
	play("power_w" if kind == "W" else "power_m")
	if kind == "W":
		wide_left = WIDE_TIME
	elif not balls.is_empty():
		var src := balls[0]
		var base := atan2(src.vel.x, -src.vel.y)
		for off in [-0.45, 0.45]:
			balls.append(new_ball(src.pos, Vector2(sin(base + off), -cos(base + off)) * speed))


## Substepped movement: no step travels more than MAX_STEP px, which is under
## half the thinnest brick, so a fast ball can never skip across one.
func move_ball(b: Ball, dt: float) -> void:
	var n := maxi(1, ceili(b.vel.length() * dt / MAX_STEP))
	var sdt := dt / n
	for i in n:
		b.pos += b.vel * sdt
		if b.pos.x < BALL_R:
			b.pos.x = BALL_R
			if b.vel.x < 0.0:
				play("wall", 0.95)
			b.vel.x = absf(b.vel.x)
		elif b.pos.x > W - BALL_R:
			b.pos.x = W - BALL_R
			if b.vel.x > 0.0:
				play("wall", 1.05)
			b.vel.x = -absf(b.vel.x)
		if b.pos.y < BALL_R + 40.0:
			b.pos.y = BALL_R + 40.0
			if b.vel.y < 0.0:
				play("wall", 1.2)
			b.vel.y = absf(b.vel.y)
		paddle_hit(b)
		brick_hit(b)
	b.trail.append(b.pos)
	if b.trail.size() > TRAIL_LEN:
		b.trail.pop_front()


func paddle_hit(b: Ball) -> void:
	if b.vel.y <= 0.0:
		return
	var half := paddle_w / 2.0
	var slack := BALL_R * 0.6
	if b.pos.y + BALL_R >= PADDLE_Y and b.pos.y - BALL_R <= PADDLE_Y + PADDLE_H \
			and b.pos.x >= paddle_x - half - slack and b.pos.x <= paddle_x + half + slack \
			and b.pos.y <= PADDLE_Y + PADDLE_H * 0.7:
		# Hit position sets the angle: centre goes straight up, edges up to MAX_BOUNCE_DEG off vertical.
		var off := clampf((b.pos.x - paddle_x) / half, -1.0, 1.0)
		var ang := deg_to_rad(off * MAX_BOUNCE_DEG)
		b.vel = Vector2(sin(ang), -cos(ang)) * speed
		b.pos.y = PADDLE_Y - BALL_R
		shake = maxf(shake, 0.12)
		combo = 0
		play("paddle", 1.0 + off * 0.1) # pitch follows where the ball landed


func brick_hit(b: Ball) -> void:
	var best: Brick = null
	var best_d2 := INF
	var best_delta := Vector2.ZERO
	for k in bricks:
		var closest := Vector2(
			clampf(b.pos.x, k.rect.position.x, k.rect.end.x),
			clampf(b.pos.y, k.rect.position.y, k.rect.end.y))
		var delta := b.pos - closest
		var d2 := delta.length_squared()
		if d2 < BALL_R * BALL_R and d2 < best_d2:
			best = k
			best_d2 = d2
			best_delta = delta
	if best == null:
		return

	# Outward contact normal. If the centre is inside the brick, use the shallowest axis.
	var n: Vector2
	if best_d2 > 0.0:
		var dist := sqrt(best_d2)
		n = best_delta / dist
		b.pos += n * (BALL_R - dist)
	else:
		var r := best.rect
		var l := b.pos.x - r.position.x
		var rt := r.end.x - b.pos.x
		var t := b.pos.y - r.position.y
		var bt := r.end.y - b.pos.y
		var m := minf(minf(l, rt), minf(t, bt))
		if m == l:
			n = Vector2.LEFT
		elif m == rt:
			n = Vector2.RIGHT
		elif m == t:
			n = Vector2.UP
		else:
			n = Vector2.DOWN

	# Reflect only when moving into the brick, so overlapping steps can't flip twice.
	var dot := b.vel.dot(n)
	if dot < 0.0:
		b.vel -= 2.0 * dot * n

	if best.kind == K_ARMOR:
		# armored bricks never break; the ball just bounces off with a clang
		play("clang", randf_range(0.9, 1.1))
		shake = maxf(shake, 0.06)
		b.vel = b.vel.normalized() * speed
		return

	if best.kind == K_BOSS:
		hit_boss(best)
		b.vel = b.vel.normalized() * speed
		return

	best.hits -= 1
	if best.hits <= 0:
		break_brick(best)
	else:
		score += 5
		layer_break(best)
		best.mat.set_shader_parameter("damage", 1.0 - float(best.hits) / float(best.max_hits))
	# Keep every ball on the current global speed.
	b.vel = b.vel.normalized() * speed


# ---- Boss
func spawn_boss() -> void:
	var size := Vector2(220.0, 64.0)
	var b := Brick.new()
	b.kind = K_BOSS
	b.rect = Rect2(W / 2.0 - size.x / 2.0, 98.0, size.x, size.y)
	b.row = 0
	b.hits = BOSS_HP
	b.max_hits = BOSS_HP
	var msz := size * S - Vector2(0.04, 0.04)
	b.mat = crystal_mat(BOSS_COLORS[0], msz)
	b.mat.set_shader_parameter("bevel", 0.2)
	b.mat.set_shader_parameter("phase", 1.0)
	boss_halo_mat = halo_mat(BOSS_COLORS[0], msz, 0.03, 0.7, 1.4)
	var mi := MeshInstance3D.new()
	mi.mesh = plane(msz)
	mi.material_override = b.mat
	mi.position = to3(b.rect.get_center(), 0.25)
	add_shadow(mi, plane(msz + Vector2(0.1, 0.1)), 0.05)
	add_halo(mi, msz, boss_halo_mat, 0.7)
	world.add_child(mi)
	b.node = mi
	bricks.append(b)
	boss = b
	boss_t = 0.0
	boss_phase = 0
	boss_fire_t = 2.5
	boss_cd = 0.0
	invuln = 0.0
	phase_banner = 0.0


func hit_boss(k: Brick) -> void:
	if boss_cd > 0.0:
		return
	boss_cd = 0.15
	k.hits -= 1
	score += 50
	if k.hits <= 0:
		break_brick(k)
		return
	k.mat.set_shader_parameter("damage", 1.0 - float(k.hits) / float(k.max_hits))
	layer_break(k)
	var phase := 0 if k.hits > 16 else (1 if k.hits > 8 else 2)
	if phase != boss_phase:
		boss_phase = phase
		phase_banner = 1.6
		clear_shots()
		blast(k.rect.get_center())
		k.mat.set_shader_parameter("base_col", BOSS_COLORS[phase])
		boss_halo_mat.set_shader_parameter("base_col", BOSS_COLORS[phase])
		boss_fire_t = 1.2


func update_boss(dt: float) -> void:
	boss_cd = maxf(0.0, boss_cd - dt)
	invuln = maxf(0.0, invuln - dt)
	if boss != null and state == State.PLAY:
		boss_t += dt * (0.7 + 0.35 * boss_phase)
		boss.rect.position.x = W / 2.0 + sin(boss_t) * (W / 2.0 - 140.0) - boss.rect.size.x / 2.0
		boss_fire_t -= dt
		if boss_fire_t <= 0.0:
			fire_boss()

	var kept: Array[Shot] = []
	for sh in shots:
		sh.pos += sh.vel * dt
		var gone := sh.pos.y > H + 30.0 or sh.pos.y < 0.0 or sh.pos.x < -30.0 or sh.pos.x > W + 30.0
		# the ball can knock a bolt out of the air
		for b in balls:
			if not gone and sh.pos.distance_to(b.pos) < BALL_R + 12.0:
				gone = true
				score += 25
				shake = maxf(shake, 0.1)
				play("ping", randf_range(1.0, 1.25))
				shot_pop(sh.pos)
		# a bolt that reaches the paddle costs a life
		if not gone and state == State.PLAY and sh.pos.y + 14.0 >= PADDLE_Y and sh.pos.y - 14.0 <= PADDLE_Y + PADDLE_H \
				and absf(sh.pos.x - paddle_x) <= paddle_w / 2.0 + 8.0:
			gone = true
			shot_pop(sh.pos)
			hurt_player()
		if gone:
			sh.node.queue_free()
		else:
			kept.append(sh)
	# hurt_player() may have cleared the list already
	if not shots.is_empty():
		shots = kept


func fire_boss() -> void:
	var c := boss.rect.get_center()
	var from := Vector2(c.x, boss.rect.end.y)
	var sp := 200.0 + 30.0 * boss_phase
	var aim := (Vector2(paddle_x, PADDLE_Y) - from).normalized()
	var spread: Array = [[0.0], [-0.3, 0.0, 0.3], [-0.45, -0.15, 0.15, 0.45]][boss_phase]
	for a in spread:
		shots.append(new_shot(from, aim.rotated(a) * sp))
	boss_fire_t = [2.6, 2.3, 1.9][boss_phase]
	play("zap")


func new_shot(pos: Vector2, vel: Vector2) -> Shot:
	if shot_mat == null:
		var sz := Vector2(0.22, 0.5)
		shot_mat = shape_mat(Color("ff3355"), sz, 0.11, 0.1, 1.6)
		shot_halo_mat = halo_mat(Color("ff3355"), sz, 0.11, 0.4, 1.2)
	var sh := Shot.new()
	sh.pos = pos
	sh.vel = vel
	var n := MeshInstance3D.new()
	n.mesh = plane(Vector2(0.22, 0.5))
	n.material_override = shot_mat
	n.rotation.y = atan2(vel.x, vel.y)
	add_halo(n, Vector2(0.22, 0.5), shot_halo_mat, 0.4)
	world.add_child(n)
	sh.node = n
	return sh


func clear_shots() -> void:
	for sh in shots:
		sh.node.queue_free()
	shots.clear()


func shot_pop(pos: Vector2) -> void:
	for i in 5:
		var p := Part.new()
		p.pos = pos
		p.vel = Vector2.from_angle(randf() * TAU) * (60.0 + randf() * 120.0)
		p.h = 0.3
		p.hv = 1.0 + randf() * 2.5
		p.life = 0.4 + randf() * 0.3
		p.max_life = p.life
		p.size = 0.6 + randf() * 0.5
		p.spin = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		var mi := take_shard(shard_meshes[i % shard_meshes.size()])
		mi.material_override = shard_mats[0]
		p.node = mi
		parts.append(p)


func hurt_player() -> void:
	if invuln > 0.0 or state != State.PLAY:
		return
	lives -= 1
	invuln = 1.8
	shake = 0.5
	clear_shots()
	if lives <= 0:
		finish_run(State.OVER)
	else:
		play("lose")


## A hit that strips one layer off a multi-hit brick: shock ring, flying plates, a pop and a glass crack.
func layer_break(k: Brick) -> void:
	var center := k.rect.get_center()
	var sz := k.rect.size * S
	play("layer", randf_range(0.95, 1.12))
	shake = maxf(shake, 0.14)
	k.pop = 0.22
	var f := Part.new()
	f.flash = true
	f.ring = true
	f.pos = center
	f.h = 0.34
	f.life = 0.45
	f.max_life = f.life
	var fm := take_flash("ring")
	f.mat = fm.material_override
	f.mat.set_shader_parameter("base_col", ROW_COLORS[k.row].lerp(Color.WHITE, 0.55))
	f.pool_key = "ring"
	f.node = fm
	parts.append(f)
	for i in (3 if low_quality else 7):
		var p := Part.new()
		var edge := randi() % 4
		var u := randf()
		match edge:
			0: p.pos = k.rect.position + Vector2(u * k.rect.size.x, 0)
			1: p.pos = k.rect.position + Vector2(u * k.rect.size.x, k.rect.size.y)
			2: p.pos = k.rect.position + Vector2(0, u * k.rect.size.y)
			_: p.pos = k.rect.position + Vector2(k.rect.size.x, u * k.rect.size.y)
		var dir := (p.pos - center).normalized()
		p.vel = dir * (70.0 + randf() * 110.0)
		p.h = 0.32
		p.hv = 1.0 + randf() * 2.2
		p.life = 0.55 + randf() * 0.35
		p.max_life = p.life
		p.size = 0.8 + randf() * 0.7
		p.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		var mi := take_shard(shard_meshes[i % shard_meshes.size()])
		mi.material_override = shard_mats[8]
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		p.node = mi
		parts.append(p)


## Breaks a brick. An explosive brick also takes out every breakable brick touching it
## (including diagonals), and those can chain into more explosive bricks.
func break_brick(first: Brick) -> void:
	bricks.erase(first)
	var queue: Array[Brick] = [first]
	var chain := 0
	while not queue.is_empty():
		var k: Brick = queue.pop_front()
		k.node.queue_free()
		score += ROW_POINTS[k.row] + (10 * chain if chain > 0 else 0)
		speed = minf(SPEED_MAX, speed + 4.0)
		burst(k, 3 if chain > 0 else -1, chain == 0)
		if k.kind == K_BOSS:
			score += 2000
			for j in 6:
				burst(k)
			for j in 3:
				blast(k.rect.position + Vector2(randf() * k.rect.size.x, randf() * k.rect.size.y))
			clear_shots()
			boss = null
		shake = minf(shake + 0.1, 0.4)
		combo += 1
		if chain == 0 or k.kind == K_BOMB:
			# each row crashes on its own note; a streak without touching the paddle climbs in pitch
			play("shatter%d" % k.row, 1.0 + 0.04 * minf(combo - 1, 10), 1.0)
		if randf() < DROP_CHANCE:
			drops.append(new_drop(k.rect.get_center(), "W" if randf() < 0.5 else "M"))
		if k.kind == K_BOMB:
			blast(k.rect.get_center())
			for o in bricks.duplicate():
				if o.kind != K_ARMOR and absf(o.rect.get_center().x - k.rect.get_center().x) < BW + GAP + 1.0 \
						and absf(o.rect.get_center().y - k.rect.get_center().y) < BH + GAP + 1.0:
					bricks.erase(o)
					queue.append(o)
		chain += 1


## Big orange shockwave for an explosive brick.
func blast(center: Vector2) -> void:
	play("boom", 1.0, 2.0)
	shake = 0.5
	if dbg_nofx:
		return
	var f := Part.new()
	f.flash = true
	f.pos = center
	f.h = 0.35
	f.life = 0.4
	f.max_life = f.life
	var fm := take_flash("blast")
	f.mat = fm.material_override
	f.pool_key = "blast"
	f.node = fm
	parts.append(f)


func new_drop(pos: Vector2, kind: String) -> Drop:
	var d := Drop.new()
	d.pos = pos
	d.kind = kind
	var n := MeshInstance3D.new()
	var dm := plane(Vector2(0.84, 0.44))
	n.mesh = dm
	var dcol := CYAN if kind == "W" else Color("ff2e63")
	n.material_override = shape_mat(dcol, dm.size, 0.22, 0.14, 1.7)
	add_shadow(n, plane(dm.size + Vector2(0.06, 0.06)), 0.25)
	add_halo(n, dm.size, halo_mat(dcol, dm.size, 0.22, 0.45, 1.3), 0.45)
	var lbl := Label3D.new()
	lbl.text = kind
	lbl.font_size = 40
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 10
	lbl.position = Vector3(0, 0.55, 0)
	var holder := Node3D.new()
	holder.add_child(n)
	holder.add_child(lbl)
	world.add_child(holder)
	d.node = holder
	return d


func burst(k: Brick, shards := -1, with_flash := true) -> void:
	if dbg_nofx:
		return
	var center := k.rect.get_center()
	# a quick light burst where the crystal broke
	if with_flash:
		var f := Part.new()
		f.flash = true
		f.pos = center
		f.h = 0.3
		f.life = 0.28
		f.max_life = f.life
		var fm := take_flash("burst")
		f.mat = fm.material_override
		f.mat.set_shader_parameter("base_col", ROW_COLORS[k.row].lerp(Color.WHITE, 0.35))
		f.pool_key = "burst"
		f.node = fm
		parts.append(f)
	# crystal shards fly outward and tumble
	var n_shards := shards if shards > 0 else (7 if low_quality else 16)
	if parts.size() > 90:
		n_shards = mini(n_shards, 2) # a long chain is already busy enough
	for i in n_shards:
		var p := Part.new()
		p.pos = k.rect.position + Vector2(randf() * k.rect.size.x, randf() * k.rect.size.y)
		var dir := (p.pos - center)
		dir = dir.normalized() if dir.length() > 1.0 else Vector2.from_angle(randf() * TAU)
		p.vel = dir * (90.0 + randf() * 230.0) + Vector2(0, 40)
		p.h = 0.3
		p.hv = 1.5 + randf() * 4.5
		p.life = 0.7 + randf() * 0.5
		p.max_life = p.life
		p.size = 0.7 + randf() * 1.1
		p.spin = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
		var mi := take_shard(shard_meshes[i % shard_meshes.size()])
		mi.material_override = shard_mats[6 if k.kind == K_BOMB else k.row]
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		p.node = mi
		parts.append(p)


func sync_3d(dt: float) -> void:
	paddle_node.position = to3(Vector2(paddle_x, PADDLE_Y + PADDLE_H / 2.0), 0.25)
	# resize the quad (not scale it) so the bevel stays the same width when widened
	# the meshes are rebuilt only when the width or the widened state actually changes
	var wide := wide_left > 0.0
	if paddle_w != paddle_synced_w or wide != paddle_synced_wide:
		paddle_synced_w = paddle_w
		paddle_synced_wide = wide
		paddle_mesh.size = Vector2(paddle_w * S, PADDLE_H * S + 0.04)
		paddle_mat.set_shader_parameter("size", paddle_mesh.size)
		paddle_halo_mesh.size = paddle_mesh.size + Vector2(1.0, 1.0)
		paddle_halo_mat.set_shader_parameter("size", paddle_mesh.size)
		paddle_halo_mat.set_shader_parameter("base_col", CYAN if wide else Color("7fdcff"))
		paddle_shadow_mesh.size = paddle_mesh.size + Vector2(0.06, 0.06)
		paddle_shadow_mat.set_shader_parameter("size", paddle_shadow_mesh.size)
		paddle_mat.set_shader_parameter("base_col", CYAN if wide else INK)

	for b in balls:
		b.node.position = to3(b.pos, BALL_R * S + 0.03)
		for i in TRAIL_LEN:
			var tn := b.trail_nodes[i]
			var idx := b.trail.size() - TRAIL_LEN + i
			if idx < 0 or idx >= b.trail.size() - 1:
				tn.visible = false
			else:
				tn.visible = true
				tn.position = to3(b.trail[idx], BALL_R * S + 0.03)
				tn.scale = Vector3.ONE * (0.25 + 0.75 * float(i) / float(TRAIL_LEN))
	for d in drops:
		d.node.position = to3(d.pos, 0.3)
	for p in parts:
		p.node.position = to3(p.pos, maxf(0.05, p.h))
		if p.ring:
			p.mat.set_shader_parameter("t", 1.0 - p.life / p.max_life)
		elif p.flash:
			var t := 1.0 - p.life / p.max_life
			p.node.scale = Vector3.ONE * (0.7 + t * 0.6)
			p.mat.set_shader_parameter("strength", 1.3 * (1.0 - t))
		else:
			p.node.scale = Vector3.ONE * p.size * clampf(p.life * 2.5, 0.0, 1.0)
			p.node.rotation += p.spin * dt

	for k in bricks:
		if k.pop > 0.0:
			k.pop = maxf(0.0, k.pop - dt * 5.0)
			k.node.scale = Vector3(1.0 + k.pop, 1.0, 1.0 + k.pop)

	if boss != null:
		boss.node.position = to3(boss.rect.get_center(), 0.25)
	for sh in shots:
		sh.node.position = to3(sh.pos, 0.3)
	paddle_node.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0

	# explosive bricks pulse
	var pulse := 1.0 + 0.8 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	bomb_halo_mat.set_shader_parameter("strength", 1.2 * GLOW * pulse)

	# the camera shakes on impacts
	camera.position = Vector3(randf_range(-1.0, 1.0) * shake * 0.1, 20.0, randf_range(-1.0, 1.0) * shake * 0.1)


# ---- 2D overlay (HUD, banners)
func text(s: String, y: float, size: int, color: Color, align: HorizontalAlignment, x := 0.0, width := W) -> void:
	draw_string(_font, Vector2(x, y), s, align, width, size, color)


func glow_text(s: String, y: float, size: int, color: Color, align: HorizontalAlignment, x := 0.0, width := W) -> void:
	var v := Vector2(x, y)
	draw_string_outline(_font, v, s, align, width, size, 12, Color(color, 0.10))
	draw_string_outline(_font, v, s, align, width, size, 6, Color(color, 0.22))
	draw_string(_font, v, s, align, width, size, color)


func _draw() -> void:
	# HUD bar with a neon underline
	draw_rect(Rect2(0, 0, W, 40), HUD_BG)
	draw_rect(Rect2(0, 38, W, 6), Color(CYAN, 0.12))
	draw_rect(Rect2(0, 39, W * 0.5, 2), Color(MAGENTA, 0.9))
	draw_rect(Rect2(W * 0.5, 39, W * 0.5, 2), Color(CYAN, 0.9))

	if dbg_on:
		text(dbg_shown, 62, 14, Color("ffd24a"), HORIZONTAL_ALIGNMENT_CENTER)
	text("SCORE", 27, 17, MUTED, HORIZONTAL_ALIGNMENT_LEFT, 16)
	glow_text("%05d" % score, 27, 20, INK, HORIZONTAL_ALIGNMENT_LEFT, 82)
	text("LEVEL %d  %s" % [level + 1, String(LEVELS[level]["name"]).to_upper()], 27, 17, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	text("LIVES", 27, 17, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, W - 16.0 - LIVES_START * 22.0 - 10.0)

	# pause and sound buttons (bigger, with a pill outline, on touch layouts)
	var k := 1.4 if mobile_ui else 1.0
	var bc := Vector2(pause_rect().get_center().x, 20.0)
	var sc := Vector2(sound_rect().get_center().x, 20.0)
	if mobile_ui:
		draw_rect(Rect2(bc - Vector2(26, 15), Vector2(52, 30)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(bc - Vector2(26, 15), Vector2(52, 30)), Color(MUTED, 0.5), false, 1.5)
		draw_rect(Rect2(sc - Vector2(26, 15), Vector2(52, 30)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(sc - Vector2(26, 15), Vector2(52, 30)), Color(MUTED, 0.5), false, 1.5)
	draw_set_transform(bc, 0.0, Vector2(k, k))
	if state == State.PAUSED:
		draw_colored_polygon(PackedVector2Array([Vector2(-5, -8), Vector2(-5, 8), Vector2(7, 0)]), ACCENT)
	else:
		draw_rect(Rect2(Vector2(-6, -8), Vector2(4, 16)), MUTED)
		draw_rect(Rect2(Vector2(2, -8), Vector2(4, 16)), MUTED)
	draw_set_transform(sc, 0.0, Vector2(k, k))
	var sk := MUTED if not muted else Color("ff5d73")
	draw_rect(Rect2(Vector2(-9, -3), Vector2(5, 6)), sk)
	draw_colored_polygon(PackedVector2Array([Vector2(-4, -3), Vector2(2, -8), Vector2(2, 8), Vector2(-4, 3)]), sk)
	if muted:
		draw_line(Vector2(-9, 9), Vector2(9, -9), sk, 2.0)
	else:
		draw_arc(Vector2(2, 0), 6.0, -0.9, 0.9, 10, sk, 1.6)
		draw_arc(Vector2(2, 0), 10.0, -0.9, 0.9, 12, sk, 1.6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if boss != null:
		var bw := 360.0
		var bx := (W - bw) / 2.0
		var frac := float(boss.hits) / float(boss.max_hits)
		var bcol := BOSS_COLORS[boss_phase]
		draw_rect(Rect2(bx - 2, 47, bw + 4, 14), Color(0.02, 0.03, 0.07, 0.85))
		draw_rect(Rect2(bx, 49, bw, 10), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(bx, 49, bw * frac, 10), bcol)
		draw_rect(Rect2(bx, 49, bw * frac, 3), Color(1, 1, 1, 0.3))
		draw_rect(Rect2(bx + bw / 3.0 - 1, 47, 2, 14), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bx + bw * 2.0 / 3.0 - 1, 47, 2, 14), Color(0, 0, 0, 0.7))
		text("THE PRISM", 59, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, bx - 10.0)
	if phase_banner > 0.0:
		glow_text("PHASE %d" % (boss_phase + 1), H / 2.0 + 20.0, 60, BOSS_COLORS[boss_phase], HORIZONTAL_ALIGNMENT_CENTER)

	for i in LIVES_START:
		var c := Vector2(W - 24.0 - (LIVES_START - 1 - i) * 22.0, 20)
		if i < lives:
			draw_circle(c, 11.0, Color(ACCENT, 0.12))
			draw_circle(c, 8.0, Color(ACCENT, 0.2))
			draw_circle(c, 6.0, ACCENT)
		else:
			draw_arc(c, 6.0, 0.0, TAU, 24, Color("3a4566"), 2.0)

	# paddle power-up timer
	if wide_left > 0.0:
		var frac := wide_left / WIDE_TIME
		draw_rect(Rect2(W / 2.0 - 60, H - 14, 120, 4), Color(CYAN, 0.18))
		draw_rect(Rect2(W / 2.0 - 60, H - 14, 120 * frac, 4), CYAN)

	match state:
		State.READY:
			glow_text("LEVEL %d  -  %s" % [level + 1, String(LEVELS[level]["name"]).to_upper()], H / 2.0 + 40.0, 36, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
			text(String(LEVELS[level]["info"]), H / 2.0 + 76.0, 16, INK, HORIZONTAL_ALIGNMENT_CENTER)
			text("Paddle %d%%   -   Ball speed %.1fx" % [roundi(100.0 * base_paddle_w() / PADDLE_W), speed / SPEED_START], H / 2.0 + 102.0, 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			if rotated_hint:
				text("Turn your phone clockwise so the game is upright", H / 2.0 + 130.0, 15, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
			if audio_loading:
				text("Loading sound... %d%%" % roundi(Synth.progress * 100.0), H - 86.0, 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			if not scores.is_empty():
				text("HIGH SCORE   %s   %06d" % [scores[0]["name"], int(scores[0]["score"])], H - 24.0, 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			banner("", "Tap, click or press Space to launch", 0.0, INK)
		State.CLEARED:
			glow_text("LEVEL CLEAR", H / 2.0 + 10.0, 56, Color("39ff88"), HORIZONTAL_ALIGNMENT_CENTER)
		State.PAUSED:
			banner("PAUSED", "Tap or press Space to resume", 0.55, CYAN)
			draw_rect(quality_rect(), Color(1, 1, 1, 0.07))
			draw_rect(quality_rect(), Color(CYAN, 0.7), false, 2.0)
			text("GRAPHICS: %s  (tap to change)" % ("LOW" if low_quality else "HIGH"), quality_rect().position.y + 32.0, 17, INK, HORIZONTAL_ALIGNMENT_CENTER, quality_rect().position.x, quality_rect().size.x)
		State.OVER: end_screen("GAME OVER", Color("ff2e63"))
		State.WIN: end_screen("YOU WIN", Color("39ff88"))
		State.NAME: name_screen()
	if is_portrait():
		draw_rotate_prompt()


func end_screen(title: String, color: Color) -> void:
	draw_rect(Rect2(0, 41, W, H - 41), Color(0.01, 0.015, 0.04, 0.82))
	glow_text(title, 130.0, 56, color, HORIZONTAL_ALIGNMENT_CENTER)
	text("Final score %d   -   Level %d" % [score, level + 1], 168.0, 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	glow_text("HIGH SCORES", 218.0, 20, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	if scores.is_empty():
		text("No scores yet", 258.0, 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for i in mini(8, scores.size()):
		var y := 252.0 + i * 27.0
		var ox := W / 2.0 - 400.0
		var e: Dictionary = scores[i]
		var hot := i == new_rank
		var c := ACCENT if hot else INK
		var fn := glow_text if hot else text
		fn.call("%d." % (i + 1), y, 19, MUTED, HORIZONTAL_ALIGNMENT_LEFT, 260.0 + ox, 60.0)
		fn.call(String(e["name"]), y, 19, c, HORIZONTAL_ALIGNMENT_LEFT, 320.0 + ox, 80.0)
		fn.call("L%d" % int(e["level"]), y, 16, MUTED, HORIZONTAL_ALIGNMENT_LEFT, 400.0 + ox, 60.0)
		fn.call("%06d" % int(e["score"]), y, 19, c, HORIZONTAL_ALIGNMENT_RIGHT, 440.0 + ox, 100.0)
	glow_text("Tap or press Space to play again", H - 56.0, 17, INK, HORIZONTAL_ALIGNMENT_CENTER)


func name_screen() -> void:
	draw_rect(Rect2(0, 41, W, H - 41), Color(0.01, 0.015, 0.04, 0.85))
	glow_text("NEW HIGH SCORE", 130.0, 50, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	text("Score %d   -   Level %d" % [score, level + 1], 168.0, 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	text("Enter your initials", 200.0, 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for i in 3:
		var cx := name_slot_x(i)
		var on := i == name_slot
		var col := ACCENT if on else INK
		var arrow := Color(CYAN, 0.9 if on else 0.45)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 16, 252), Vector2(cx + 16, 252), Vector2(cx, 226)]), arrow)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 16, 360), Vector2(cx + 16, 360), Vector2(cx, 386)]), arrow)
		draw_rect(Rect2(cx - 38, 262, 76, 90), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(cx - 38, 262, 76, 90), Color(col, 0.8 if on else 0.35), false, 2.0)
		glow_text(LETTERS[name_idx[i]], 334.0, 66, col, HORIZONTAL_ALIGNMENT_CENTER, cx - 38.0, 76.0)
	draw_rect(name_ok_rect(), Color(ACCENT, 0.12))
	draw_rect(name_ok_rect(), Color(ACCENT, 0.9), false, 2.0)
	glow_text("SAVE", name_ok_rect().position.y + 35.0, 24, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, name_ok_rect().position.x, name_ok_rect().size.x)
	text("Type letters or use the arrows  -  Enter to save", H - 56.0, 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)


func banner(title: String, sub: String, dim: float, color: Color) -> void:
	if dim > 0.0:
		draw_rect(Rect2(0, 41, W, H - 41), Color(0.01, 0.015, 0.04, dim))
	if title != "":
		glow_text(title, H / 2.0 - 2.0, 60, color, HORIZONTAL_ALIGNMENT_CENTER)
	glow_text(sub, (H / 2.0 + 36.0) if title != "" else (H - 112.0), 17, INK, HORIZONTAL_ALIGNMENT_CENTER)
