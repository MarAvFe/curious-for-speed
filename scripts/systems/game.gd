extends Node
## Scene flow, the one animation clock, shared materials, command-line test modes.

const TITLE := "res://scenes/title.tscn"
const RACE := "res://scenes/race.tscn"
const PARENT := "res://scenes/parent_menu.tscn"
const MODELS := ["stinger", "brute", "hatch", "pickup", "van", "bubble", "jeep", "monster"]  ## tools/cars.py PLAYABLE
const LIVERIES := 6
const PLAYER_COLOURS := [Color("#4ff3ff"), Color("#ff4fb5"), Color("#ffd23d"), Color("#b6ff4f")]  ## P1-P4 cursors

var t := 0.0  ## one clock for every looping animation
var level_id := 1  ## track number
var args: Dictionary = {}
var vc_mat: StandardMaterial3D
var glow_mat: StandardMaterial3D
var actor_mat: StandardMaterial3D  ## vertex colour + outline pass (ships, critters, props)
var _parent_menu: Node = null
var _fade: ColorRect
var palette: Dictionary
var picks: Array[int] = []  ## car index (shape * LIVERIES + livery) per player, set in the garage; empty = solo from save
var _recoloured := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	vc_mat = StandardMaterial3D.new()
	vc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vc_mat.vertex_color_use_as_albedo = true
	glow_mat = vc_mat.duplicate()
	glow_mat.disable_fog = true
	actor_mat = vc_mat  # outlines are baked into the meshes (tools/meshkit.outline_shell)
	palette = JSON.parse_string(FileAccess.get_file_as_string("res://assets/palette.json"))
	Bindings.parent_menu_requested.connect(open_parent_menu)
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(1, 0.97, 0.93, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_fade)
	get_tree().root.focus_exited.connect(func() -> void: get_tree().call_group("pausable", "request_pause"))
	if args.has("test"):
		_self_test.call_deferred()
		return
	if args.has("check"):
		_check_scripts.call_deferred()
		return
	if args.has("snap"):  # --snap=<name> [--scene=book]: screenshot after 2 s, quit
		_snap.call_deferred()
	if args.has("car"):
		Save.data["car"] = int(args["car"])
	if args.has("players"):  # --players=N: split-screen run straight into a race (with --level)
		for k in clampi(int(args["players"]), 1, 4):
			picks.append(((k * 3) % MODELS.size()) * LIVERIES + k)
		Bindings.set_players(picks.size())
	if args.has("level"):
		level_id = int(args["level"])
		go.call_deferred(RACE)


## One shared pulse for every glowing thing (integer cycles per 2 s).
func pulse(cycles := 1) -> float:
	return 0.5 + 0.5 * sin(TAU * t * cycles / 2.0)


func _process(delta: float) -> void:
	t += delta
	glow_mat.albedo_color = Color.WHITE.lerp(Color(0.82, 0.9, 0.9), pulse())


func go(scene: String) -> void:
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))
	tw.tween_property(_fade, "color:a", 0.0, 0.5)


## Fade out, run `mid` (rearrange the scene), fade back in.
func fade(mid: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(mid)
	tw.tween_property(_fade, "color:a", 0.0, 0.5)


func start_level(n: int) -> void:
	level_id = n
	go(RACE)


## Player 0's car from the save (solo), as a car index.
func saved_car() -> int:
	return (int(Save.data["car"]) % MODELS.size()) * LIVERIES + int(Save.data["colour"]) % LIVERIES


## Car index (shape * LIVERIES + livery) -> a new car node. Each shape's glb is baked in livery 0; other liveries
## swap its paint/web colours (exact palette entries, checked at build time by tools/cars.py).
func car(i: int) -> Node3D:
	var shape := (i / LIVERIES) % MODELS.size()
	var n: Node3D = (load("res://assets/cars/car_%s.glb" % MODELS[shape]) as PackedScene).instantiate()
	if i % LIVERIES != 0:
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var key := "%d/%s" % [i, mi.name]
			if not _recoloured.has(key):
				_recoloured[key] = recolour(mi.mesh, i % LIVERIES)
			mi.mesh = _recoloured[key]
	return n


func recolour(m: Mesh, livery: int) -> ArrayMesh:
	var src: Dictionary = palette["liveries"][0]
	var dst: Dictionary = palette["liveries"][livery]
	var swap := {}
	for k: String in ["paint", "web", "dark"]:
		for j in src[k].size():
			swap[Color(src[k][j]).to_rgba32()] = Color(dst[k][j])
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for v in c.size():
			c[v] = swap.get(c[v].to_rgba32(), c[v])
		a[Mesh.ARRAY_COLOR] = c
		out.add_surface_from_arrays(m.surface_get_primitive_type(s), a)
	return out


## Bright paint colour of a livery (HUD dots, sparks).
func car_colour(i: int) -> Color:
	return Color(palette["liveries"][i % LIVERIES]["paint"][3])


## Apply flat vertex-colour material to every mesh under `root`.
func paint(root: Node, glow := false, outline := true) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = glow_mat if glow else (actor_mat if outline else vc_mat)


func parent_open() -> bool:
	return _parent_menu != null and is_instance_valid(_parent_menu) and not _parent_menu.is_queued_for_deletion()


func open_parent_menu() -> void:
	if _parent_menu != null and is_instance_valid(_parent_menu):
		return
	if not ResourceLoader.exists(PARENT):
		return
	var ps: PackedScene = load(PARENT)
	_parent_menu = ps.instantiate()
	get_tree().paused = true
	add_child(_parent_menu)


func quit_bot(result: Dictionary) -> void:
	print("BOT_RESULT ", JSON.stringify(result))
	var f := FileAccess.open("user://bot_result.json", FileAccess.WRITE)  # GUI builds have no stdout
	if f:
		f.store_string(JSON.stringify(result))
		f.close()
	get_tree().quit(0 if result.get("ok", false) else 1)


## --check: compile every script in project context (autoloads present); exit 1 on any failure.
func _check_scripts() -> void:
	var bad := 0
	var n := 0
	var stack: Array[String] = ["res://scripts", "res://tests"]
	while not stack.is_empty():
		var dir := stack.pop_back() as String
		for sub in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				n += 1
				var sc: GDScript = load(dir + "/" + f)
				if sc == null or not sc.can_instantiate():
					bad += 1
					print("CHECK_FAIL ", dir + "/" + f)
	print("CHECK scripts=%d failed=%d" % [n, bad])
	get_tree().quit(1 if bad > 0 else 0)


func _snap() -> void:
	match str(args.get("scene", "")):
		"parent": open_parent_menu()
	await get_tree().create_timer(2.0).timeout
	if args.has("pause"):
		get_tree().call_group("pausable", "request_pause")
		await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/%s.png" % args["snap"])
	get_tree().quit()


## --test: input layer + save robustness. Prints TEST lines, exits 1 on failure.
func _self_test() -> void:
	var fails: PackedStringArray = []
	var backup := {}  # never clobber the family's real save/bindings
	for p: String in [Save.PATH, Bindings.PATH]:
		backup[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	var honks := [0]
	Bindings.honked.connect(func(_who: int) -> void: honks[0] += 1)
	# 1. unbound pad button and unbound key -> honk, nothing else
	for ev: InputEvent in [Bindings.joy_btn(JOY_BUTTON_LEFT_SHOULDER), Bindings.key(KEY_Q)]:
		ev.set("pressed", true)
		Input.parse_input_event(ev)
		await get_tree().process_frame
	if honks[0] != 2:
		fails.append("unbound->honk got %d" % honks[0])
	# 2. learn mode: a raw button becomes NITRO, keyboard default kept
	var learned := Bindings.joy_btn(JOY_BUTTON_MISC1)
	Bindings.learn("nitro", learned)
	if not InputMap.event_is_action(learned, "nitro") or not InputMap.event_is_action(Bindings.key(KEY_SPACE), "nitro"):
		fails.append("learn nitro")
	var ax := Bindings.joy_axis(JOY_AXIS_RIGHT_X, -1.0)
	Bindings.learn("steer_left", ax)
	if not InputMap.event_is_action(ax, "steer_left") or not InputMap.event_is_action(ax, "menu_left"):
		fails.append("learn axis")
	Bindings.reset_bindings()
	if InputMap.event_is_action(learned, "nitro"):
		fails.append("reset bindings")
	# split screen: 4 keys per player, nobody else's; solo player 1 also keeps pads (any pad, not just pad 0)
	var pad1 := Bindings.joy_btn(JOY_BUTTON_A)
	pad1.device = 1
	var has_key := func(c: Key, a: String) -> bool: return InputMap.event_is_action(Bindings.key(c), a)
	Bindings.set_players(4)
	if not has_key.call(KEY_S, "nitro@0") or has_key.call(KEY_S, "nitro@1") or not has_key.call(KEY_DOWN, "nitro@1") \
			or not has_key.call(KEY_V, "steer_left@3") or not has_key.call(KEY_I, "honk@2") or has_key.call(KEY_SPACE, "nitro@0") \
			or InputMap.event_is_action(pad1, "nitro@0") or not InputMap.event_is_action(pad1, "menu_accept"):
		fails.append("per-player keys")
	Bindings.set_players(1)
	if not InputMap.event_is_action(pad1, "nitro@0") or not has_key.call(KEY_SPACE, "nitro@0"):
		fails.append("solo extras")
	# colours: a recoloured car differs from the livery-0 bake (catches import colour conversion breaking the swap)
	var c0: MeshInstance3D = car(0).find_children("*", "MeshInstance3D", true, false)[0]
	var c4: MeshInstance3D = car(4).find_children("*", "MeshInstance3D", true, false)[0]
	var a0: PackedColorArray = c0.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var a4: PackedColorArray = c4.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var changed := 0
	for i in a0.size():
		changed += int(a0[i] != a4[i])
	if changed < a0.size() / 10:
		fails.append("recolour changed only %d/%d" % [changed, a0.size()])
	# 3. corrupt and missing save -> defaults, no crash
	var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
	f.store_string("{not json!!")
	f.close()
	Save.load_data()
	if Save.level(1)["cleared"] != false:
		fails.append("corrupt save")
	f = FileAccess.open(Save.PATH, FileAccess.WRITE)
	f.store_string('{"levels": {"1": {"cleared": "yes"}}, "settings": {"music": "loud"}}')
	f.close()
	Save.load_data()
	if typeof(Save.level(1)["cleared"]) != TYPE_BOOL or typeof(Save.setting("music")) != TYPE_FLOAT:
		fails.append("wrong-typed save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	Save.load_data()
	if Save.level(1)["cleared"] != false:
		fails.append("missing save")
	# unlocks: one car per finished race (repeats of the same track count), capped at 8; car index survives reload
	if int(Save.data["unlocked"]) != 1 or not Save.car_unlocked(0) or Save.car_unlocked(4):
		fails.append("fresh unlocks")
	Save.record_level(2)
	if int(Save.data["reveal"]) != Save.UNLOCK_ORDER[1] or not Save.car_unlocked(Save.UNLOCK_ORDER[1]):
		fails.append("first unlock")
	for k in 9:
		Save.record_level(2)
	if int(Save.data["unlocked"]) != Save.CARS or not Save.car_unlocked(7):
		fails.append("unlock cap %s" % Save.data["unlocked"])
	Save.data["car"] = 5
	Save.write()
	Save.load_data()
	if typeof(Save.data["car"]) != TYPE_INT or int(Save.data["car"]) != 5 or int(Save.data["unlocked"]) != Save.CARS:
		fails.append("car/unlocks reload")
	# 4. pause <-> parent menu flow (the stacked-pause bug): exactly one pause screen, never playable under it
	get_tree().change_scene_to_file(RACE)
	for i in 10:
		await get_tree().process_frame
	var lvl := get_tree().current_scene
	var layers := func() -> int: return lvl.get_children().filter(func(c: Node) -> bool: return c is CanvasLayer and c.process_mode == Node.PROCESS_MODE_ALWAYS).size()
	lvl.call("request_pause")
	open_parent_menu()
	await get_tree().process_frame
	_parent_menu.call("close")
	for i in 3:
		await get_tree().process_frame
	lvl.call("request_pause")
	await get_tree().process_frame
	if layers.call() != 1 or not get_tree().paused:
		fails.append("pause after parent menu: layers=%d paused=%s" % [layers.call(), get_tree().paused])
	lvl.call("_on_pause_choice", "resume")
	await get_tree().process_frame
	if layers.call() != 0 or get_tree().paused:
		fails.append("resume: layers=%d paused=%s" % [layers.call(), get_tree().paused])
	# 5. garage: 2 players, ENTER, player 2 flips colour with their own key, ENTER, a track -> a 2-player race
	get_tree().paused = false
	Save.data["unlocked"] = 1  # fresh progress: picking 2 players must open a second vehicle
	Save.data["reveal"] = -1
	get_tree().change_scene_to_file(TITLE)
	var tap := func(c: Key) -> void:
		for down: bool in [true, false]:
			var e := Bindings.key(c)
			e.pressed = down
			Input.parse_input_event(e)
			await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await tap.call(KEY_D)  # player count menu: 1 -> 2
	await get_tree().create_timer(0.35).timeout
	await tap.call(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	await tap.call(KEY_ENTER)  # everyone's shape
	await get_tree().create_timer(0.5).timeout
	await tap.call(KEY_RIGHT)  # player 2's right: next colour
	await tap.call(KEY_ENTER)  # everyone's colour -> tracks
	await get_tree().create_timer(0.5).timeout
	await tap.call(KEY_ENTER)  # track 1
	await get_tree().create_timer(1.5).timeout
	var race := get_tree().current_scene
	if picks.size() != 2 or picks[1] != 2 or race.get("players") == null or (race.get("players") as Array).size() != 2:
		fails.append("garage 2p flow: picks=%s scene=%s" % [picks, race.name])
	elif int(Save.data["unlocked"]) != 2:
		fails.append("2 players should open 2 vehicles, unlocked=%s" % Save.data["unlocked"])
	elif not ((race.get("views") as Array)[1]["box"] as Control).get_global_rect().position.y > 0.0:
		fails.append("2p views overlap: player 2's view is not the bottom half")
	for p: String in backup:
		if backup[p] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var w := FileAccess.open(p, FileAccess.WRITE)
			w.store_string(backup[p])
			w.close()
	print("TEST input+save+pause: ", "PASS" if fails.is_empty() else "FAIL " + ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
