extends Node
## Hosts the game inside a SubViewport so the picture can be turned 90 degrees when the
## screen is taller than wide (a phone held upright, or an in-app browser that cannot rotate).
## In landscape the image is shown unrotated. Mouse, touch and key events arrive at the
## window, are mapped into the sub-viewport (undoing the rotation), and pushed to the game.

const GAME_SCENE := "res://main.tscn"
const BASE_W := 800.0 # the game never gets narrower than this, or shorter than BASE_H
const BASE_H := 600.0

var sv: SubViewport
var holder: Control
var disp: TextureRect
var game: Node
var rotated := false
var holder_pos := Vector2.ZERO # screen position of the holder's top-left corner
var disp_off := Vector2.ZERO # where the image sits inside the holder (letterboxing)
var px_per_unit := 1.0 # sub-viewport pixels per logical unit of the displayed image
var check_t := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0d1220")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	holder = Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	disp = TextureRect.new()
	disp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disp.stretch_mode = TextureRect.STRETCH_SCALE
	disp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(disp)

	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size_2d_override_stretch = true
	add_child(sv)
	layout()
	disp.texture = sv.get_texture()

	game = (load(GAME_SCENE) as PackedScene).instantiate()
	sv.add_child(game)
	if "rotated_hint" in game:
		game.rotated_hint = rotated
	get_tree().root.size_changed.connect(layout)


func layout() -> void:
	var vis := get_tree().root.get_visible_rect().size
	if vis.x <= 0.0 or vis.y <= 0.0:
		return
	var win_px := Vector2(DisplayServer.window_get_size())
	var k := maxf(win_px.x / vis.x, 0.01)
	rotated = vis.y > vis.x
	# the landscape area the game gets, in logical units of the window
	var area := Vector2(vis.y, vis.x) if rotated else vis
	# game space: 600 high, at least 800 wide, wider on wide screens
	var gw := maxf(BASE_W, BASE_H * area.x / area.y)
	# fit the picture inside the area (bars only when the screen is narrower than 4:3)
	var d := Vector2(area.x, area.x * BASE_H / gw)
	if d.y > area.y:
		d = Vector2(area.y * gw / BASE_H, area.y)
	disp_off = (area - d) / 2.0
	holder.size = area
	if rotated:
		# turned so the game's top edge runs down the left side of the screen;
		# the player turns the phone clockwise to see it upright
		holder.rotation = -PI / 2.0
		holder_pos = Vector2(0.0, vis.y)
	else:
		holder.rotation = 0.0
		holder_pos = Vector2.ZERO
	holder.position = holder_pos
	disp.position = disp_off
	disp.size = d
	sv.size = Vector2i((d * k).round())
	sv.size_2d_override = Vector2i(Vector2(gw, BASE_H).round())
	px_per_unit = float(sv.size.x) / d.x
	if game != null:
		if "rotated_hint" in game:
			game.rotated_hint = rotated
		if game.has_method("on_resized"):
			game.on_resized()


# ---- input mapping
func map_pos(p: Vector2) -> Vector2:
	var local := p - holder_pos
	if rotated:
		local = Vector2(-local.y, local.x)
	return (local - disp_off) * px_per_unit


func map_delta(v: Vector2) -> Vector2:
	if rotated:
		v = Vector2(-v.y, v.x)
	return v * px_per_unit


func _input(event: InputEvent) -> void:
	if sv == null:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var e := event.duplicate() as InputEventMouse
		e.position = map_pos(event.position)
		e.global_position = e.position
		if e is InputEventMouseMotion:
			e.relative = map_delta(event.relative)
			e.velocity = map_delta(event.velocity)
		sv.push_input(e, false)
	elif event is InputEventScreenTouch:
		var t := event.duplicate() as InputEventScreenTouch
		t.position = map_pos(event.position)
		sv.push_input(t, false)
	elif event is InputEventScreenDrag:
		var dr := event.duplicate() as InputEventScreenDrag
		dr.position = map_pos(event.position)
		dr.relative = map_delta(event.relative)
		dr.velocity = map_delta(event.velocity)
		sv.push_input(dr, false)
	elif event is InputEventKey:
		sv.push_input(event, false)


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	check_t += delta
	if check_t < 0.4:
		return
	check_t = 0.0
	# iOS Safari (and in-app browsers) can report the new size late after a rotation;
	# if the page and the engine disagree about portrait vs landscape, re-send the resize event
	var js_portrait: Variant = JavaScriptBridge.eval("window.innerHeight > window.innerWidth")
	if js_portrait is bool and js_portrait != rotated:
		JavaScriptBridge.eval("window.dispatchEvent(new Event('resize'))")
