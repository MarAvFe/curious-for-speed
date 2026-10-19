extends Node3D
## Title = garage. The highlighted car turns on a glowing platform. Below: all 8 cars in one grid (4 x 2);
## locked cars are black silhouettes and can't be picked. Every finished race unlocks the next one, revealed here.
## Right column: ▶ (go to track select) and ⚙ (hold for the grown-up menu). Icons only.

const COLS := 5  ## 4 cars + the action column
const THUMB := Vector2(100, 52)

var _car: Node3D
var _ring: MeshInstance3D
var _cl: CanvasLayer
var _grid: Control
var _cells: Array[TextureButton] = []  ## index = row * COLS + col
var _slots: Array[Panel] = []  ## light backing so black (locked) silhouettes still read
var _sel := 0
var _cool := 0.0
var _arm := 0.3
var _menu: IconMenu  ## track select
var _stage := "car"
var _gear_hold := 0.0
var _black: StandardMaterial3D
var _revealing := false
var _sparkle: CPUParticles3D


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
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.0, 9.5)
	cam.rotation.x = -0.31  # aimed below the car, so the platform sits in the upper half; the grid owns the lower half
	cam.fov = 42
	add_child(cam)
	var floor_mi := MeshInstance3D.new()  # turntable: dark disc + neon rim in the car's colour
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.2
	cyl.radial_segments = 32
	floor_mi.mesh = cyl
	floor_mi.material_override = _flat(Color("#231d3d"))
	floor_mi.position = Vector3(0, -0.1, 0)
	add_child(floor_mi)
	_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 3.35
	tor.outer_radius = 3.6
	tor.rings = 48
	tor.ring_segments = 4
	_ring.mesh = tor
	_ring.material_override = _flat(Color("#4ff3ff"))
	add_child(_ring)
	for n: Node3D in [floor_mi, _ring]:
		n.position.y += 0.9  # platform sits in the upper half, the grid takes the lower half
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
	_sparkle.position = Vector3(0, 1.8, 0)
	add_child(_sparkle)
	_cl = CanvasLayer.new()
	add_child(_cl)
	_build_grid()
	if not Save.car_unlocked(int(Save.data["car"])):
		Save.data["car"] = 0
	_sel = _cell_of(int(Save.data["car"]))
	_show_car(int(Save.data["car"]))
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


func _cell_of(car: int) -> int:
	return (car / 4) * COLS + car % 4


func _car_of(cell: int) -> int:  ## -1 for the action column
	var col := cell % COLS
	return -1 if col == 4 else (cell / COLS) * 4 + col


func _build_grid() -> void:
	_grid = Control.new()
	_cl.add_child(_grid)
	for cell in COLS * 2:
		var car := _car_of(cell)
		if car >= 0:
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
		var icon := "car_%d" % car if car >= 0 else ("play" if cell / COLS == 0 else "gear")
		b.texture_normal = load("res://assets/ui/icon_%s.png" % icon)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = THUMB if car >= 0 else Vector2(THUMB.y, THUMB.y)
		b.size = b.custom_minimum_size
		b.pivot_offset = b.size / 2.0
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _sel = cell; _pick())
		b.mouse_entered.connect(func() -> void: _hover(cell))
		_grid.add_child(b)
		_cells.append(b)
	_tint_all()


func _tint_all() -> void:
	for cell in _cells.size():
		var car := _car_of(cell)
		var b := _cells[cell]
		if car >= 0:
			b.modulate = Color.WHITE if Save.car_unlocked(car) else Color(0.02, 0.01, 0.05)  # blacked out = locked
		else:
			b.modulate = Color("#4ff3ff") if cell / COLS == 0 else Color(0.6, 0.6, 0.72)


func _hover(cell: int) -> void:
	if _revealing:
		return
	_sel = cell
	var car := _car_of(cell)
	if car >= 0:
		_show_car(car)


func _show_car(i: int) -> void:
	var rot := 0.6
	if _car:
		rot = _car.rotation.y
		_car.queue_free()
	_car = (load(Game.car_path(Game.sel_car(i))) as PackedScene).instantiate()
	Game.paint(_car)
	_car.rotation.y = rot
	_car.position.y = 0.9
	add_child(_car)
	var open := Save.car_unlocked(i) and not (_revealing and i == int(Save.data["reveal"]))
	if not open:  # silhouette: a hint of what's to come, nothing more
		for n in _car.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = _black
	(_ring.material_override as StandardMaterial3D).albedo_color = Game.car_colour(Game.sel_car(i)) if open else Color(0.25, 0.22, 0.35)


## A newly won car: its slot and the turntable start black, then light up with a sparkle and the fanfare.
func _reveal(car: int) -> void:
	_revealing = true
	_sel = _cell_of(car)
	_show_car(car)
	var b := _cells[_sel]
	b.modulate = Color(0.02, 0.01, 0.05)
	await get_tree().create_timer(1.0).timeout
	AudioBus.play("sfx_fanfare")
	_sparkle.restart()
	create_tween().tween_property(b, "modulate", Color.WHITE, 0.8)
	_revealing = false
	Save.data["car"] = car
	Save.data["reveal"] = -1
	Save.write()
	_show_car(car)
	var tw := create_tween()  # the new car hops for joy
	tw.tween_property(_car, "position:y", 1.5, 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_car, "position:y", 0.9, 0.35).set_trans(Tween.TRANS_BOUNCE)


func _pick() -> void:
	if _arm > 0.0 or _revealing:
		return
	var car := _car_of(_sel)
	if car < 0:
		if _sel / COLS == 0:  # ▶
			AudioBus.play("sfx_blip", 1.3)
			_go_tracks()
		return  # ⚙ needs a hold (see _process)
	if not Save.car_unlocked(car):
		AudioBus.play("sfx_boop")  # locked: a soft "not yet", the slot gives a little shake
		var b := _cells[_sel]
		var tw := create_tween()
		for k in 3:
			tw.tween_property(b, "rotation", 0.08, 0.04)
			tw.tween_property(b, "rotation", -0.08, 0.04)
		tw.tween_property(b, "rotation", 0.0, 0.04)
		return
	AudioBus.play("sfx_blip", 1.3)
	Save.data["car"] = car
	Save.write()
	_go_tracks()


func _go_tracks() -> void:
	_stage = "track"
	_grid.visible = false
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
		_menu.queue_free()
		_menu = null
		_stage = "car"
		_grid.visible = true
		_arm = 0.3
		return
	Game.start_level(int(id.trim_prefix("track_")))


func _on_honk() -> void:
	AudioBus.play("sfx_honk")
	if _car:  # the car bounces on its suspension
		var tw := create_tween()
		tw.tween_property(_car, "position:y", 1.25, 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_car, "position:y", 0.9, 0.25).set_trans(Tween.TRANS_BOUNCE)


func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	if _car:
		_car.rotation.y += dt * 0.5
	if _stage == "track":
		_menu.position = Vector2((vs.x - _menu.size.x) / 2.0, vs.y * 0.74)
		return
	if Game.parent_open():
		_arm = 0.3
		return
	_arm -= dt
	# layout: two rows centred in the lower half
	var gap := 8.0
	var w := 4 * (THUMB.x + gap) + THUMB.y
	var x0 := (vs.x - w) / 2.0
	var y0 := vs.y * 0.6
	for cell in _cells.size():
		var b := _cells[cell]
		var col := cell % COLS
		var row := cell / COLS
		b.position = Vector2(x0 + col * (THUMB.x + gap), y0 + row * (THUMB.y + gap))
		var car := _car_of(cell)
		if car >= 0:
			_slots[car].position = b.position
			_slots[car].scale = b.scale
			_slots[car].pivot_offset = b.pivot_offset
		var k := 1.0 + (0.12 + 0.05 * sin(Game.t * TAU)) * float(cell == _sel)
		b.scale = b.scale.lerp(Vector2(k, k), 1.0 - exp(-12.0 * dt))
	# stick / arrows move around the grid
	var d := Vector2i.ZERO
	if Input.is_action_pressed("menu_right"):
		d.x = 1
	elif Input.is_action_pressed("menu_left"):
		d.x = -1
	elif Input.is_action_pressed("menu_down"):
		d.y = 1
	elif Input.is_action_pressed("menu_up"):
		d.y = -1
	_cool -= dt
	if d != Vector2i.ZERO and _cool <= 0.0 and not _revealing:
		_cool = 0.25
		var col := posmod(_sel % COLS + d.x, COLS)
		var row := posmod(_sel / COLS + d.y, 2)
		_hover(row * COLS + col)
		AudioBus.play("sfx_blip")
	elif d == Vector2i.ZERO:
		_cool = 0.0
	if Input.is_action_just_pressed("menu_accept") or Input.is_action_just_pressed("nitro"):
		_pick()
	# ⚙: hold accept 1.5 s (or the mouse) to open the grown-up menu; it turns while held
	var gear := _cells[COLS + 4]
	var held := _sel == COLS + 4 and (Input.is_action_pressed("menu_accept") or Input.is_action_pressed("nitro") or gear.button_pressed)
	_gear_hold = _gear_hold + dt if held else 0.0
	gear.rotation = _gear_hold * 3.0
	if _gear_hold >= 1.5:
		_gear_hold = -INF
		Game.open_parent_menu()
