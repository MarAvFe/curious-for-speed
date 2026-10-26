extends Node3D
## Title = garage. First: how many players (1-4). Then each player has a turntable car on top (with their 4 keys
## drawn above it) and a cursor on the shape grid below (4 x 2; locked shapes are black silhouettes, every finished
## race unlocks the next, revealed here). Everyone moves their own cursor; ENTER takes everyone's pick to the colour
## step (◀ ▶ each), ENTER again to track select. Back (Esc) steps back. Hold accept on ⚙ for the grown-up menu.

const COLS := 4
const THUMB := Vector2(100, 52)
const SPACING := [0.0, 6.0, 4.2, 3.2]  ## turntable spacing and scale by player count
const SCALE := [1.0, 0.8, 0.6, 0.45]
const ARROWS := {KEY_LEFT: 0, KEY_RIGHT: 1, KEY_UP: 2, KEY_DOWN: 3}

var _cam: Camera3D
var _cl: CanvasLayer
var _grid: Control
var _overlay: Control
var _cells: Array[TextureButton] = []  ## index = row * COLS + col = shape
var _slots: Array[Panel] = []  ## light backing so black (locked) silhouettes still read
var _p: Array[Dictionary] = []  ## per player: cell, colour, cool, stand, ring, car
var _arm := 0.3
var _menu: IconMenu  ## player count, or track select
var _stage := "count"  ## count | car | colour | track
var _gear_hold := 0.0
var _black: StandardMaterial3D
var _revealing := false
var _sparkle: CPUParticles3D
var _dot: Texture2D


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#1d1840")
	sm.sky_horizon_color = Color("#ff9a6b")
	sm.ground_horizon_color = Color("#ff9a6b")
	sm.ground_bottom_color = Color("#2b2357")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 3.0, 9.5)
	_cam.rotation.x = -0.31  # aimed below the cars, so the platforms sit in the upper half; the grid owns the lower half
	_cam.fov = 42
	add_child(_cam)
	_black = _flat(Color("#0a0812"))
	_sparkle = CPUParticles3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.12
	pm.height = 0.24
	_sparkle.mesh = pm
	_sparkle.material_override = _flat(Color("#fff6c8"))
	_sparkle.amount = 40
	_sparkle.one_shot = true
	_sparkle.emitting = false
	_sparkle.explosiveness = 0.9
	_sparkle.lifetime = 1.2
	_sparkle.spread = 180.0
	_sparkle.initial_velocity_min = 3.0
	_sparkle.initial_velocity_max = 7.0
	_sparkle.gravity = Vector3(0, -3, 0)
	add_child(_sparkle)
	_dot = load("res://assets/ui/icon_dot.png")
	_cl = CanvasLayer.new()
	add_child(_cl)
	_build_grid()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_cl.add_child(_overlay)
	if not Save.car_unlocked(int(Save.data["car"]) % Save.CARS):
		Save.data["car"] = 0
	if Game.picks.is_empty():  # first visit: player 1 from the save, then pick how many players
		_p.append(_new_player(int(Save.data["car"]) % Save.CARS, int(Save.data["colour"]) % Game.LIVERIES))
		_build_stands()
		_go_count()
	else:  # back from a race: same players, straight to the grid
		for c in Game.picks:
			_p.append(_new_player(c / Game.LIVERIES, c % Game.LIVERIES))
		_tint_all()
		_build_stands()
		_go_stage("car")
	AudioBus.music("music_title")
	Bindings.honked.connect(_on_honk)
	var rv := int(Save.data["reveal"])
	if rv >= 0:
		_reveal.call_deferred(rv)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _new_player(shape: int, colour: int) -> Dictionary:
	return {"cell": shape, "colour": colour, "cool": 0.0}


func _build_grid() -> void:
	_grid = Control.new()
	_cl.add_child(_grid)
	for shape in Save.CARS:
		var pn := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.75, 0.72, 0.9, 0.22)
		sb.set_corner_radius_all(8)
		pn.add_theme_stylebox_override("panel", sb)
		pn.size = THUMB
		pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(pn)
		_slots.append(pn)
		var b := TextureButton.new()
		b.texture_normal = load("res://assets/ui/icon_car_%d.png" % shape)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = THUMB
		b.size = THUMB
		b.pivot_offset = b.size / 2.0
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_entered.connect(_hover.bind(shape))
		_grid.add_child(b)
		_cells.append(b)
	_tint_all()


## 3-4 players: every vehicle is open for the session (the save's progress is untouched), so nobody waits for a turn.
func _open(shape: int) -> bool:
	return _p.size() >= 3 or Save.car_unlocked(shape)


func _tint_all() -> void:
	for shape in _cells.size():
		_cells[shape].modulate = Color.WHITE if _open(shape) else Color(0.02, 0.01, 0.05)  # blacked out = locked


## One turntable per player, side by side, smaller the more players there are.
func _build_stands() -> void:
	var n := _p.size()
	for k in n:
		var p := _p[k]
		if p.has("stand"):
			(p["stand"] as Node3D).queue_free()
			p.erase("car")
		var st := Node3D.new()
		st.position = Vector3((k - (n - 1) / 2.0) * SPACING[n - 1], 0.9, 0.0)
		st.scale = Vector3.ONE * SCALE[n - 1]
		var disc := MeshInstance3D.new()  # dark disc + neon rim in the car's colour
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.4
		cyl.bottom_radius = 3.4
		cyl.height = 0.2
		cyl.radial_segments = 32
		disc.mesh = cyl
		disc.material_override = _flat(Color("#231d3d"))
		disc.position.y = -0.1
		st.add_child(disc)
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 3.35
		tor.outer_radius = 3.6
		tor.rings = 48
		tor.ring_segments = 4
		ring.mesh = tor
		ring.material_override = _flat(Color("#4ff3ff"))
		st.add_child(ring)
		add_child(st)
		p["stand"] = st
		p["ring"] = ring
		_show(k)


## Put player k's highlighted shape, in their colour, on their turntable.
func _show(k: int) -> void:
	var p := _p[k]
	var shape: int = p["cell"]
	var rot := 0.6 + k * 0.8
	if p.has("car"):
		rot = (p["car"] as Node3D).rotation.y
		(p["car"] as Node3D).queue_free()
	var ci := shape * Game.LIVERIES + int(p["colour"])
	var car := Game.car(ci)
	Game.paint(car)
	car.rotation.y = rot
	(p["stand"] as Node3D).add_child(car)
	p["car"] = car
	var open := _open(shape) and not (_revealing and shape == int(Save.data["reveal"]))
	if not open:  # silhouette: a hint of what's to come, nothing more
		for n in car.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = _black
	((p["ring"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Game.car_colour(ci) if open else Color(0.25, 0.22, 0.35)


## A newly won shape: its slot and player 1's turntable start black, then light up with a sparkle and the fanfare.
func _reveal(shape: int) -> void:
	_revealing = true
	var p := _p[0]
	p["cell"] = shape
	_show(0)
	var b := _cells[shape]
	b.modulate = Color(0.02, 0.01, 0.05)
	await get_tree().create_timer(1.0).timeout
	AudioBus.play("sfx_fanfare")
	_sparkle.position = (p["stand"] as Node3D).position + Vector3(0, 0.9, 0)
	_sparkle.restart()
	create_tween().tween_property(b, "modulate", Color.WHITE, 0.8)
	_revealing = false
	Save.data["car"] = shape
	Save.data["reveal"] = -1
	Save.write()
	_show(0)
	var tw := create_tween()  # the new car hops for joy
	tw.tween_property(p["car"], "position:y", 0.6, 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(p["car"], "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BOUNCE)


func _hover(shape: int) -> void:  ## mouse = player 1
	if _revealing or _stage != "car":
		return
	_p[0]["cell"] = shape
	_show(0)


# ---------------- stages ----------------
func _go_count() -> void:
	_go_stage("count")
	_menu = IconMenu.new()
	_menu.icon_size = 84.0
	for n in range(1, 5):
		_menu.add_item("players_%d" % n, "players_%d" % n, Game.PLAYER_COLOURS[n - 1])
	_menu.add_item("gear", "gear", Color(0.6, 0.6, 0.72))  # needs a hold, see _process
	_menu.sel = _p.size() - 1
	_cl.add_child(_menu)
	_menu.chosen.connect(_on_count)


func _on_count(id: String) -> void:
	if not id.begins_with("players_"):
		return
	var n := int(id.trim_prefix("players_"))
	while _p.size() > n:
		(_p.pop_back()["stand"] as Node3D).queue_free()
	while _p.size() < n:
		_p.append(_new_player(0, _p.size()))  # new players start on the first shape, in a colour of their own
	Bindings.set_players(n)
	if n == 2 and int(Save.data["unlocked"]) < 2:  # 2 players: at least 2 vehicles, then one more per win as usual
		Save.data["unlocked"] = 2
		Save.write()
	_tint_all()
	_build_stands()
	_go_stage("car")


func _go_stage(s: String) -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	_stage = s
	_grid.visible = s in ["car", "colour"]
	_arm = 0.3


## ENTER on the grid: everyone's shape at once. Locked picks shake and say "not yet".
func _confirm_shapes() -> void:
	var locked := _p.filter(func(p: Dictionary) -> bool: return not _open(p["cell"]))
	if locked.is_empty():
		AudioBus.play("sfx_blip", 1.3)
		_go_stage("colour")
		return
	AudioBus.play("sfx_boop")
	for p: Dictionary in locked:
		var b := _cells[p["cell"]]
		var tw := create_tween()
		for i in 3:
			tw.tween_property(b, "rotation", 0.08, 0.04)
			tw.tween_property(b, "rotation", -0.08, 0.04)
		tw.tween_property(b, "rotation", 0.0, 0.04)


func _go_tracks() -> void:
	AudioBus.play("sfx_blip", 1.6)
	Game.picks.clear()
	for p in _p:
		Game.picks.append(int(p["cell"]) * Game.LIVERIES + int(p["colour"]))
	Save.data["car"] = int(_p[0]["cell"])
	Save.data["colour"] = int(_p[0]["colour"])
	Save.write()
	_go_stage("track")
	_menu = IconMenu.new()
	_menu.icon_size = 84.0
	_menu.add_item("home", "home", Color("#ff4fb5"))
	var cols := [Color("#ffd23d"), Color("#ff7a3d"), Color("#a98bff"), Color("#9fe8ff")]
	for n in range(1, Save.LEVEL_COUNT + 1):
		var ok := FileAccess.file_exists("res://tracks/track_%d.json" % n)
		_menu.add_item("track_%d" % n, "track_%d" % n, cols[(n - 1) % cols.size()], ok)
	_menu.back_id = "home"
	_menu.sel = 1
	_cl.add_child(_menu)
	_menu.chosen.connect(_on_track)


func _on_track(id: String) -> void:
	if id == "home":
		_go_stage("colour")
		return
	Game.start_level(int(id.trim_prefix("track_")))


func _on_honk(who := 0) -> void:
	if _stage in ["car", "colour"]:
		return  # up is the horn, but on the grid it moves the cursor
	AudioBus.play("sfx_honk")
	if who < _p.size() and _p[who].has("car"):  # the car bounces on its suspension
		var car: Node3D = _p[who]["car"]
		var tw := create_tween()
		tw.tween_property(car, "position:y", 0.35, 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(car, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE)


## Player k's own keys move their cursor (car stage) or flip their colour (colour stage).
func _update_player(k: int, dt: float) -> void:
	var p := _p[k]
	var d := Vector2i.ZERO
	var held := func(a: String) -> bool: return Input.is_action_pressed(Bindings.act(k, a))
	if held.call("menu_right"):
		d.x = 1
	elif held.call("menu_left"):
		d.x = -1
	elif held.call("menu_down"):
		d.y = 1
	elif held.call("menu_up"):
		d.y = -1
	p["cool"] -= dt
	if d == Vector2i.ZERO:
		p["cool"] = 0.0
		return
	if p["cool"] > 0.0:
		return
	p["cool"] = 0.25
	if _stage == "car":
		var c: int = p["cell"]
		p["cell"] = posmod(c / COLS + d.y, 2) * COLS + posmod(c % COLS + d.x, COLS)
		AudioBus.play("sfx_blip")
	elif d.x != 0:
		p["colour"] = posmod(int(p["colour"]) + d.x, Game.LIVERIES)
		AudioBus.play("sfx_blip", 1.1)
	_show(k)


func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	for p in _p:
		if p.has("car"):
			(p["car"] as Node3D).rotation.y += dt * 0.5
	_overlay.queue_redraw()
	if _menu:
		_menu.position = Vector2((vs.x - _menu.size.x) / 2.0, vs.y * 0.74)
	if Game.parent_open():
		_arm = 0.3
		return
	_arm -= dt
	if _stage == "count":
		# ⚙: hold accept 1.5 s to open the grown-up menu; it turns while held
		var gear: Control = _menu.items[4]["node"]
		var held: bool = _menu.sel == 4 and (Input.is_action_pressed("menu_accept") or gear.get("button_pressed"))
		_gear_hold = _gear_hold + dt if held else 0.0
		gear.rotation = _gear_hold * 3.0
		if _gear_hold >= 1.5:
			_gear_hold = -INF
			Game.open_parent_menu()
		return
	if _stage == "track":
		return
	# layout: two rows centred in the lower half
	var gap := 8.0
	var x0 := (vs.x - COLS * (THUMB.x + gap) + gap) / 2.0
	var y0 := vs.y * 0.6
	for shape in _cells.size():
		var b := _cells[shape]
		b.position = Vector2(x0 + (shape % COLS) * (THUMB.x + gap), y0 + (shape / COLS) * (THUMB.y + gap))
		_slots[shape].position = b.position
		_slots[shape].scale = b.scale
		_slots[shape].pivot_offset = b.pivot_offset
		var on := _stage == "car" and _p.any(func(p: Dictionary) -> bool: return p["cell"] == shape)
		var k := 1.0 + (0.12 + 0.05 * sin(Game.t * TAU)) * float(on)
		b.scale = b.scale.lerp(Vector2(k, k), 1.0 - exp(-12.0 * dt))
	if _revealing:
		return
	for k in _p.size():
		_update_player(k, dt)
	if _arm > 0.0:
		return
	if Input.is_action_just_pressed("menu_accept"):
		if _stage == "car":
			_confirm_shapes()
		else:
			_go_tracks()
	elif Input.is_action_just_pressed("menu_back"):
		AudioBus.play("sfx_boop", 1.2)
		if _stage == "colour":
			_go_stage("car")
		else:
			_go_count()


# ---------------- overlay ----------------
## Above each turntable: that player's 4 keys (up = horn, down = nitro, sides steer) and, while picking colours,
## the colour row. On the grid: one cursor per player. At the bottom: the ENTER key that moves everyone on.
func _draw_overlay() -> void:
	if not _stage in ["car", "colour"]:
		return
	var vs := _overlay.get_viewport_rect().size
	var u := vs.y / 360.0
	var n := _p.size()
	var font := ThemeDB.fallback_font
	var cap := 13.0 * u
	for k in n:
		var p := _p[k]
		var pc: Color = Game.PLAYER_COLOURS[k]
		if n > 1 and _stage == "car":
			var b := _cells[p["cell"]]
			var half := b.size * b.scale / 2.0 + Vector2.ONE * (2.0 + 3.0 * k) * u
			_overlay.draw_rect(Rect2(b.position + b.size / 2.0 - half, half * 2.0), pc, false, 2.0 * u)
		var cx := _cam.unproject_position((p["stand"] as Node3D).global_position).x
		var keys: Array = Bindings.PLAYER_KEYS[k]
		var top := 4.0 * u
		var at := [Vector2(cx - cap * 1.6, top + cap * 1.1), Vector2(cx + cap * 0.6, top + cap * 1.1),  # left, right
			Vector2(cx - cap * 0.5, top), Vector2(cx - cap * 0.5, top + cap * 1.1)]  # up, down
		for i in 4:
			_keycap(Rect2(at[i], Vector2(cap, cap)), keys[i], pc, font, u)
		if _stage == "colour":
			var ds := minf(16.0 * u, vs.x / n / 9.0)
			var y := top + cap * 2.2 + ds
			for j in Game.LIVERIES:
				var s := ds * (1.5 if j == p["colour"] else 1.0)
				var c := Vector2(cx + (j - 2.5) * ds * 1.3, y)
				if j == p["colour"]:
					_overlay.draw_circle(c, s * 0.62, Color.WHITE)
				_overlay.draw_texture_rect(_dot, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Game.car_colour(j))
	var ew := 44.0 * u  # ENTER: everyone's pick, next step
	var er := Rect2(Vector2((vs.x - ew) / 2.0, vs.y - cap - 4.0 * u), Vector2(ew, cap))
	_keycap(er, KEY_ENTER, Color.WHITE.lerp(Color("#4ff3ff"), Game.pulse(2)), font, u)


func _keycap(r: Rect2, key: Key, edge: Color, font: Font, u: float) -> void:
	_overlay.draw_rect(r, Color(0.08, 0.06, 0.16, 0.85))
	_overlay.draw_rect(r, edge, false, 1.5 * u)
	if ARROWS.has(key):  # arrow keys get a drawn triangle, the default font may not have arrow glyphs
		var c := r.get_center()
		var h := r.size.y * 0.28
		var tri := PackedVector2Array([Vector2(h, 0), Vector2(-h, -h), Vector2(-h, h)])
		var rot: float = [PI, 0.0, -PI / 2.0, PI / 2.0][ARROWS[key]]
		var pts := PackedVector2Array()
		for v in tri:
			pts.append(c + v.rotated(rot))
		_overlay.draw_colored_polygon(pts, Color.WHITE)
		return
	var txt := OS.get_keycode_string(key).to_upper()
	var fs := int(r.size.y * 0.7)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_overlay.draw_string(font, Vector2(r.get_center().x - w / 2.0, r.position.y + r.size.y * 0.78), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
