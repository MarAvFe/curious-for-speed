extends Node3D
## Title = garage. The chosen car turns on a glowing platform. Row: ◀ ▶ ▶(go) ⚙. Go -> pick a track (icons of
## the real track shapes). Icons only.

var _car: Node3D
var _menu: IconMenu
var _cl: CanvasLayer
var _ring: MeshInstance3D
var _stage := "car"
var _gear_hold := 0.0


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
	cam.position = Vector3(0, 2.4, 8.5)
	cam.rotation.x = -0.16
	cam.fov = 45
	add_child(cam)
	var floor_mi := MeshInstance3D.new()  # turntable: dark disc + neon rim
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.2
	cyl.radial_segments = 32
	floor_mi.mesh = cyl
	floor_mi.material_override = _flat(Color("#231d3d"))
	floor_mi.position.y = -0.1
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
	_cl = CanvasLayer.new()
	add_child(_cl)
	_show_car()
	_build_menu()
	AudioBus.music("music_title")
	Bindings.honked.connect(_on_honk)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _show_car() -> void:
	var rot := 0.6
	if _car:
		rot = _car.rotation.y
		_car.queue_free()
	var i := int(Save.data["car"])
	_car = (load(Game.car_path(i)) as PackedScene).instantiate()
	Game.paint(_car)
	_car.rotation.y = rot
	add_child(_car)
	(_ring.material_override as StandardMaterial3D).albedo_color = Game.car_colour(i)


func _build_menu() -> void:
	if _menu:
		_menu.queue_free()
	_menu = IconMenu.new()
	_menu.icon_size = 84.0
	if _stage == "car":
		_menu.add_item("prev", "prev", Color(0.85, 0.85, 0.95))
		_menu.add_item("go", "play", Color("#4ff3ff"))
		_menu.add_item("next", "next", Color(0.85, 0.85, 0.95))
		_menu.add_item("gear", "gear", Color(0.6, 0.6, 0.72))
		_menu.sel = 1
	else:
		_menu.add_item("home", "home", Color("#ff4fb5"))
		for n in range(1, 3):
			var ok := FileAccess.file_exists("res://tracks/track_%d.json" % n)
			_menu.add_item("track_%d" % n, "track_%d" % n, [Color("#ffd23d"), Color("#ff7a3d")][n - 1], ok)
		_menu.back_id = "home"
		_menu.sel = 1
	_cl.add_child(_menu)
	_menu.chosen.connect(_on_choice)


func _on_honk() -> void:
	AudioBus.play("sfx_honk")
	if _car:  # the car hops on its suspension
		var tw := create_tween()
		tw.tween_property(_car, "position:y", 0.35, 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_car, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE)


func _on_choice(id: String) -> void:
	match id:
		"prev", "next":
			var n := Game.LIVERIES * 2
			Save.data["car"] = posmod(int(Save.data["car"]) + (1 if id == "next" else -1), n)
			Save.write()
			_show_car()
		"go":
			_stage = "track"
			_build_menu()
		"home":
			_stage = "car"
			_build_menu()
		"gear":
			pass  # parent settings need a 1.5 s hold (see _process), so a tap does nothing
		_:
			if id.begins_with("track_"):
				Game.start_level(int(id.trim_prefix("track_")))


func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	_menu.position = Vector2((vs.x - _menu.size.x) / 2.0, vs.y * 0.74)
	if _car:
		_car.rotation.y += dt * 0.5
	if _stage == "car":
		var gear: Control = _menu.items[3]["node"]
		var held := _menu.sel == 3 and (Input.is_action_pressed("menu_accept") or Input.is_action_pressed("nitro") or (gear as BaseButton).button_pressed)
		_gear_hold = _gear_hold + dt if held else 0.0
		gear.rotation = _gear_hold * 3.0
		if _gear_hold >= 1.5:
			_gear_hold = -INF
			Game.open_parent_menu()
