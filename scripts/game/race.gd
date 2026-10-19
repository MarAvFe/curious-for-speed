extends Node3D
## Generic race: loads tracks/track_N.json + its kit, runs player, rivals, traffic, gates, nitro, the finish
## and the flat podium. Everything track-specific comes from JSON. No fail state: bumps slow you, never stop the race.

const UP := Vector3.UP
const CRUISE := 30.0  ## m/s at speed 1.0
const NITRO_ADD := 13.0
const BRAKE_TO := 12.0
const STEER_V := 11.0
const DRIFT := 0.15  ## outward push on curves = K * v^2 * DRIFT (m/s): lean into the turn
const LANES := [-6.75, -2.25, 2.25, 6.75]
const TRAFFIC_MODELS := ["hatch", "van", "pickup"]
const GRID := [Vector2(-6.0, -3.0), Vector2(-6.0, 3.0), Vector2(-16.0, -3.0), Vector2(-16.0, 3.0)]  # (d, x); player last

var T: Dictionary
var L := 0.0
var DS := 2.0
var W := 9.0
var lim := 8.8  ## |x| limit for a car's centre (road + curb - half width)
var laps := 2
var pos := PackedVector3Array()
var tan := PackedVector3Array()
var rig := PackedVector3Array()
var curv := PackedFloat32Array()
var gs := 1.0  ## game speed
var player: Racer
var rivals: Array[Racer] = []
var racers: Array[Racer] = []
var traffic: Array[Racer] = []
var gates: Array[Dictionary] = []  ## {s, kind, ...nodes}
var birds: Array[Dictionary] = []
var cam: Camera3D
var hud: Node
var engine: AudioStreamPlayer
var state := "countdown"  ## countdown | race | finish | podium
var clock := 0.0
var inp := 0.0
var bot: Node = null
var bumps := 0
var near_misses := 0
var lead_t := 0.0  ## seconds the player spent ahead of every rival (tests: overtakes are possible)
var honks := 0
var pause_layer: CanvasLayer
var _resume_t := -10.0
var _cam_look := Vector3.ZERO
var _fov := 70.0
var _celebrate_t := 0.0
var _assist := 0.0
var _bump_times: Array[float] = []
var _rng := RandomNumberGenerator.new()
var _sparks: CPUParticles3D
var _fireworks: Array[CPUParticles3D] = []
var _confetti: CPUParticles3D
var _scrape_cd := 0.0
var _last_lap := 0
var frame_ms: PackedFloat32Array = []
var _last_us := 0


func _ready() -> void:
	add_to_group("pausable")
	_rng.seed = int(Game.args.get("seed", "1"))
	var path := "res://tracks/track_%d.json" % Game.level_id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("track missing: " + path)
		Game.go(Game.TITLE)
		return
	T = parsed
	gs = float(Game.args.get("speed", Save.setting("speed")))
	laps = int(Game.args.get("laps", T["laps"]))
	DS = float(T["ds"])
	W = float(T["width"])
	lim = W + float(T["curb"]) - Racer.HALF_W - 0.1
	for p: Array in T["samples"]:
		pos.append(Vector3(p[0], p[1], p[2]))
		curv.append(float(p[3]))
	var n := pos.size()
	L = n * DS
	for i in n:
		var t := (pos[(i + 1) % n] - pos[(i - 1 + n) % n]).normalized()
		tan.append(t)
		rig.append(Vector3(t.x, 0.0, t.z).normalized().cross(UP))
	_build_env()
	_build_world()
	_build_cars()
	_build_fx()
	cam = Camera3D.new()
	cam.fov = _fov
	cam.near = 0.3
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	_cam_follow(1.0, true)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	engine = AudioStreamPlayer.new()
	engine.stream = AudioBus.stream("loop_engine", true)
	engine.bus = "SFX"
	engine.volume_db = -10.0
	add_child(engine)
	engine.play()
	AudioBus.music(str(T["music"]))
	Bindings.honked.connect(_on_honk)
	_last_us = Time.get_ticks_usec()
	if Game.args.has("bot"):
		bot = load("res://tests/bot.gd").new()
		bot.set("runner", self)
		bot.set("bad", Game.args["bot"] == "bad")
		add_child(bot)
	if Game.args.has("shots"):
		_shot_tour.call_deferred()
	elif Game.args.has("podium"):
		_podium_shots.call_deferred()
	else:
		_countdown()


# ---------------- track math ----------------
func _i(s: float) -> int:
	return int(fposmod(s, L) / DS) % pos.size()


func point(s: float) -> Vector3:
	var f := fposmod(s, L) / DS
	var i := int(f) % pos.size()
	return pos[i].lerp(pos[(i + 1) % pos.size()], f - floorf(f))


func tangent(s: float) -> Vector3:
	return tan[_i(s)]


func right(s: float) -> Vector3:
	return rig[_i(s)]


func curvature(s: float) -> float:
	return curv[_i(s)]


func world(s: float, x: float, dy := 0.0) -> Vector3:
	return point(s) + right(s) * x + UP * dy


## Signed shortest distance along the loop from b to a (a ahead of b -> positive).
func ahead(a: float, b: float) -> float:
	return fposmod(a - b + L * 0.5, L) - L * 0.5


# ---------------- build ----------------
func _build_env() -> void:
	var pal: Dictionary = T["palette"]
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(pal["sky"][0])
	sm.sky_horizon_color = Color(pal["sky"][1])
	sm.ground_horizon_color = Color(pal["sky"][1])
	sm.ground_bottom_color = Color(pal["fog"])
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(pal["fog"])
	env.fog_density = 1.0
	env.fog_depth_begin = float(T["fog"][0])
	env.fog_depth_end = float(T["fog"][1])
	env.fog_depth_curve = 1.3
	env.fog_sky_affect = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_world() -> void:
	var kit: PackedScene = load("res://assets/tracks/track_%d.glb" % Game.level_id)
	var world := kit.instantiate()
	add_child(world)
	Game.paint(world, false, false)
	var n := Game.level_id
	for g: Dictionary in T["gates"]:  # railway crossing: two arms take turns, one half of the road always open
		var gd := {"s": float(g["s"]), "kind": "cross", "period": float(g["period"]), "arms": [], "angle": [0.0, 0.0], "rung": -1}
		var s := float(g["s"])
		for side: int in [-1, 1]:
			var post: Node3D = (load("res://assets/tracks/gate_post_%d.glb" % n) as PackedScene).instantiate()
			Game.paint(post)
			add_child(post)
			var px := side * (W + float(T["curb"]) + 0.8)
			post.global_transform = Transform3D(Basis.looking_at(-right(s) * side, UP), world(s, px))
			var pivot := Node3D.new()
			add_child(pivot)
			# pivot frame: +X points across the road toward the centre, rotation about the track tangent lifts it
			var xa := -right(s) * side
			pivot.global_transform = Transform3D(Basis(xa, UP, xa.cross(UP)), world(s, px, 2.6))
			var arm: Node3D = (load("res://assets/tracks/gate_arm_%d.glb" % n) as PackedScene).instantiate()
			Game.paint(arm, true)
			pivot.add_child(arm)
			gd["arms"].append(pivot)
		gates.append(gd)
	for g: Dictionary in T["slides"]:  # construction barrier sweeping across the lanes
		var b: Node3D = (load("res://assets/tracks/slide_barrier_%d.glb" % n) as PackedScene).instantiate()
		Game.paint(b, true)
		add_child(b)
		gates.append({"s": float(g["s"]), "kind": "slide", "width": float(g["width"]), "amp": float(g["amp"]),
			"period": float(g["period"]), "node": b, "cx": 0.0})
	var bird_scene: PackedScene = load("res://assets/fx/bird.glb")
	for b: Dictionary in T.get("birds", []):
		var c := world(float(b["s"]), float(b["x"]), float(b["y"]))
		for k in 5:
			var nd: Node3D = bird_scene.instantiate()
			Game.paint(nd, true)
			nd.scale = Vector3.ONE * 1.8
			add_child(nd)
			birds.append({"node": nd, "centre": c + Vector3(0, k * 1.8, 0), "r": 10.0 + k * 3.0, "phase": k * 1.3 + float(b["s"])})


func _build_cars() -> void:
	var mine := int(Save.data["car"]) % (Game.LIVERIES * 2)
	# rivals: three other liveries, models alternate so the field looks mixed
	var picks: Array[int] = []
	var li := (mine + 1) % Game.LIVERIES
	var model := 1 - mine / Game.LIVERIES
	while picks.size() < 3:
		if li != mine % Game.LIVERIES:
			picks.append(model * Game.LIVERIES + li)
			model = 1 - model
		li = (li + 2) % Game.LIVERIES if picks.size() < 2 else (li + 1) % Game.LIVERIES
	for k in 4:
		var r := Racer.new()
		var ci := mine if k == 3 else picks[k]
		r.idx = ci
		r.colour = Game.car_colour(ci)
		add_child(r)
		r.setup(load(Game.car_path(ci)), "player" if k == 3 else "rival")
		r.d = GRID[k].x
		r.x = GRID[k].y
		r.target_x = r.x
		r.cruise = CRUISE * gs
		r.skill = [1.0, 0.97, 1.02, 1.0][k]
		racers.append(r)
		if k == 3:
			player = r
		else:
			rivals.append(r)
	var nt := int(T["traffic"])
	for k in nt:
		var t := Racer.new()
		add_child(t)
		t.setup(load("res://assets/cars/traffic_%s_%d.glb" % [TRAFFIC_MODELS[k % 3], (k / 3) % 4]), "traffic")
		t.d = 80.0 + (L - 160.0) * float(k) / nt + _rng.randf_range(-20, 20)
		t.x = LANES[_rng.randi() % 4]
		t.target_x = t.x
		t.cruise = _rng.randf_range(13.0, 19.0) * gs
		t.speed = t.cruise
		traffic.append(t)
	for r in racers + traffic:
		_place(r, 0.0)


func _particles(c: Color, n: int, v: float, life: float, size := 0.25) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.disable_fog = true
	p.material_override = mat
	p.amount = n
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = v * 0.5
	p.initial_velocity_max = v
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0))
	p.scale_amount_curve = sc
	add_child(p)
	return p


func _build_fx() -> void:
	_sparks = _particles(Color("#ffc46b"), 14, 6.0, 0.4, 0.12)
	for c: String in ["#ff4fb5", "#4ff3ff", "#ffd23d", "#b6ff4f"]:
		var f := _particles(Color(c), 60, 22.0, 1.6, 0.5)
		f.gravity = Vector3(0, -4, 0)
		f.damping_min = 4.0
		f.damping_max = 6.0
		_fireworks.append(f)
	_confetti = _particles(Color.WHITE, 120, 4.0, 4.0, 0.18)
	_confetti.one_shot = false
	_confetti.explosiveness = 0.0
	_confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_confetti.emission_box_extents = Vector3(14, 0.5, 4)
	_confetti.gravity = Vector3(0, -2.5, 0)
	_confetti.color_ramp = null
	var g := Gradient.new()  # each flake gets a random party colour
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([Color("#ff4fb5"), Color("#4ff3ff"), Color("#ffd23d"), Color("#b6ff4f")])
	_confetti.color_initial_ramp = g
	(_confetti.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	(_confetti.material_override as StandardMaterial3D).albedo_color = Color.WHITE


# ---------------- frame ----------------
func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now
	clock += dt
	_update_gates(dt)
	_update_birds()
	match state:
		"countdown":
			_player_input(dt)
			for r in racers + traffic:
				_place(r, dt)
			# rev the engine with nitro during the countdown: harmless fun
			if engine:
				engine.pitch_scale = lerpf(engine.pitch_scale, 1.25 if Input.is_action_pressed("nitro") else 0.7, 1.0 - exp(-6.0 * dt))
			_cam_follow(dt)
		"race", "finish":
			_assist_update(dt)
			_player_input(dt)
			_drive_player(dt)
			for r in rivals:
				_drive_ai(r, dt)
			_drive_traffic(dt)
			_collide()
			for r in racers + traffic:
				r.bump_cd -= dt
				_place(r, dt)
			_laps()
			if state == "race" and rivals.all(func(r: Racer) -> bool: return player.d > r.d):
				lead_t += dt
			_engine_sound(dt)
			if state == "race":
				_cam_follow(dt)
			else:
				_celebrate_cam(dt)
		"podium":
			_podium_cam(dt)
	if state in ["countdown", "race"] and Input.is_action_just_pressed("pause"):
		request_pause()
	_restart_input(dt)


func _player_input(dt: float) -> void:
	var raw := Input.get_axis("steer_left", "steer_right")
	var r := 1.0 / 0.12 if absf(raw) > absf(inp) else 1.0 / 0.08  # keyboard -> stick-like ramp
	inp = move_toward(inp, raw, r * dt)


func _drive_player(dt: float) -> void:
	var p := player
	if p.done:  # after the line: autopilot cruises on
		_drive_ai(p, dt)
		p.speed = minf(p.speed, CRUISE * gs * 0.8)
		return
	var target := p.cruise
	p.boosting = Input.is_action_pressed("nitro") and p.nitro > 0.02
	if p.boosting:
		target += NITRO_ADD * gs
		p.nitro = maxf(p.nitro - 0.28 * dt, 0.0)
		if Input.is_action_just_pressed("nitro"):
			AudioBus.play("sfx_nitro")
	elif Input.is_action_just_pressed("nitro"):
		AudioBus.play("sfx_boop", 1.3)  # empty tank: a tiny "nope", never a punishment
	if Input.is_action_pressed("steer_down"):
		target = BRAKE_TO * gs
	p.nitro = minf(p.nitro + 0.03 * dt, 1.0)
	var k := 0.9 if target > p.speed else 2.2
	p.speed = lerpf(p.speed, target, 1.0 - exp(-k * dt))
	var steer_v := STEER_V * clampf(p.speed / 18.0, 0.4, 1.0)
	p.vx = lerpf(p.vx, inp * steer_v, 1.0 - exp(-7.0 * dt))
	_integrate(p, dt, DRIFT * (1.0 - 0.6 * _assist))


## Shared motion: forward along the track, lateral with the outward curve push, walls.
func _integrate(r: Racer, dt: float, drift: float) -> void:
	var s := r.s(L)
	var push := curvature(s) * r.speed * r.speed * drift
	r.x += (r.vx - push) * dt
	var gate_block := _gate_block(r, dt)
	if gate_block:
		r.speed = 0.0
	else:
		r.d += r.speed * dt
	if absf(r.x) > lim:
		r.x = clampf(r.x, -lim, lim)
		r.vx = -signf(r.x) * 1.5
		r.speed *= 1.0 - 0.5 * dt  # scrape: a little slower, never stopped
		if r == player:
			_scrape_cd -= dt
			if _scrape_cd <= 0.0:
				_scrape_cd = 0.25
				AudioBus.play("sfx_scrape", randf_range(0.9, 1.1))
				_sparks.global_position = r.global_position + right(s) * signf(r.x) * 1.0 + UP * 0.4
				_sparks.restart()


## Gates and barriers: a car may not drive into a closed arm or the barrier block. Returns true if held.
func _gate_block(r: Racer, dt: float) -> bool:
	var s := r.s(L)
	for g in gates:
		var front := ahead(float(g["s"]), s) - Racer.HALF_L
		var step := r.speed * dt
		if front < -0.2 or front > step + 0.5:
			continue
		if _blocked(g, r.x):
			if r.speed > 6.0 and r.bump(1.0):
				if r == player:
					AudioBus.play("sfx_bump")
					_on_bump()
			return true
	return false


func _blocked(g: Dictionary, x: float) -> bool:
	var hw := Racer.HALF_W + 0.2
	if g["kind"] == "cross":
		# arm 0 covers the left half (x < 0), arm 1 the right half; "down" when angle < 0.6 rad
		if g["angle"][0] < 0.6 and x - hw < 0.3:
			return true
		if g["angle"][1] < 0.6 and x + hw > -0.3:
			return true
		return false
	var cx := float(g["cx"])
	return absf(x - cx) < float(g["width"]) * 0.5 + hw


func _update_gates(dt: float) -> void:
	for g in gates:
		if g["kind"] == "cross":
			var ph := fmod(clock, float(g["period"])) / float(g["period"])
			var down := 0 if ph < 0.5 else 1  # which arm is down; the other is up
			if down != int(g["rung"]):
				g["rung"] = down
				if player and absf(ahead(float(g["s"]), player.s(L))) < 140.0:
					AudioBus.play("sfx_bell")
			for a in 2:
				var want := 0.0 if a == down else 1.35
				g["angle"][a] = move_toward(float(g["angle"][a]), want, 1.8 * dt)
				var pv: Node3D = g["arms"][a]
				# rotate the arm up about the pivot's local Z (the track tangent)
				pv.get_child(0).rotation = Vector3(0, 0, float(g["angle"][a]))
		else:
			g["cx"] = float(g["amp"]) * sin(TAU * clock / float(g["period"]))
			var s := float(g["s"])
			(g["node"] as Node3D).global_transform = Transform3D(Basis.looking_at(tangent(s), UP), world(s, float(g["cx"])))


# ---------------- AI ----------------
## Where a car would like to be: inside line on curves, dodging whatever is in front. Also used by the bot.
func ai_target_x(r: Racer, look := 40.0) -> float:
	var s := r.s(L)
	var line := clampf(curvature(s + 30.0) * 320.0, -5.5, 5.5)
	if r.kind == "rival":
		line += [-1.5, 1.0, 2.0][rivals.find(r) % 3]
	var cands: Array[float] = [line, r.x, -6.75, -2.25, 2.25, 6.75, r.x - 3.5, r.x + 3.5]
	var best := r.x
	var best_c := INF
	for c in cands:
		c = clampf(c, -lim, lim)
		var cost := absf(c - line) * 0.15 + absf(c - r.x) * 0.1
		for o in racers + traffic:
			if o == r:
				continue
			var a := ahead(o.s(L), s)
			if a > 0.0 and a < look and o.speed < r.speed + 2.0 and absf(o.x - c) < 2.6:
				cost += 50.0 * (1.0 - a / look) + 5.0
		for g in gates:
			var a := ahead(float(g["s"]), s)
			if a > 0.0 and a < look + 20.0:
				if g["kind"] == "slide":
					# predict where the block will be when we arrive
					var at := clock + a / maxf(r.speed, 5.0)
					var cx := float(g["amp"]) * sin(TAU * at / float(g["period"]))
					if absf(c - cx) < float(g["width"]) * 0.5 + 1.6:
						cost += 80.0
				elif _blocked(g, c):
					cost += 60.0
		if cost < best_c:
			best_c = cost
			best = c
	return best


func _drive_ai(r: Racer, dt: float) -> void:
	r.target_x = ai_target_x(r)
	r.vx = lerpf(r.vx, clampf((r.target_x - r.x) * 1.6, -8.0, 8.0), 1.0 - exp(-5.0 * dt))
	var gap := r.d - player.d
	# asymmetric: leaders ease off a lot, chasers barely speed up, so an overtake can be held (with nitro)
	var band := clampf(1.0 - gap / 450.0, 0.88, 1.04) if not player.done else 1.0
	if r.kind == "rival" and _assist > 0.0 and gap > 0.0:
		band -= 0.06 * _assist  # player struggling: rivals ease off a touch
	var target := r.cruise * r.skill * band
	r.boosting = r.kind == "rival" and gap < -40.0 and r.nitro > 0.3 and not player.done
	if r.boosting:
		target += NITRO_ADD * gs * 0.8
		r.nitro -= 0.25 * dt
	r.nitro = minf(r.nitro + 0.04 * dt, 1.0)
	# don't plough into someone directly ahead when there is no gap
	for o in racers + traffic:
		if o == r:
			continue
		var a := ahead(o.s(L), r.s(L))
		if a > 0.0 and a < 12.0 and absf(o.x - r.x) < 2.2:
			target = minf(target, o.speed + 1.0)
	r.speed = lerpf(r.speed, target, 1.0 - exp(-1.0 * dt))
	_integrate(r, dt, DRIFT * 0.5)


func _drive_traffic(dt: float) -> void:
	var ps := player.s(L)
	for t in traffic:
		var s := t.s(L)
		var target := t.cruise
		for o in traffic + racers:
			if o == t:
				continue
			var a := ahead(o.s(L), s)
			if a > 0.0 and a < 18.0 and absf(o.x - t.x) < 2.4:
				target = minf(target, o.speed - 1.0)
		for g in gates:  # queue politely at closed arms
			var a := ahead(float(g["s"]), s)
			if a > 0.0 and a < 14.0 and _blocked(g, t.x):
				target = 0.0
		t.speed = lerpf(t.speed, maxf(target, 0.0), 1.0 - exp(-2.0 * dt))
		t.vx = clampf((t.target_x - t.x) * 1.5, -3.0, 3.0)
		if absf(t.target_x - t.x) > 0.3:
			t.blink_t = maxf(t.blink_t, 0.3)
		t.x += t.vx * dt
		if not _gate_block(t, dt):
			t.d += t.speed * dt
		# recycle: traffic far behind the player reappears ahead, in a lane with room
		var rel := ahead(t.s(L), ps)
		if rel < -120.0 and state == "race":
			_respawn_traffic(t, ps)


func _respawn_traffic(t: Racer, ps: float) -> void:
	for tries in 8:
		var nd := ps + _rng.randf_range(260.0, 480.0)
		var lane: float = LANES[_rng.randi() % 4]
		var ok := true
		for o in traffic:
			if o != t and absf(ahead(o.s(L), fposmod(nd, L))) < 30.0 and absf(o.x - lane) < 3.0:
				ok = false
				break
		for g in gates:
			if absf(ahead(float(g["s"]), fposmod(nd, L))) < 40.0:
				ok = false
		if ok:
			t.d = nd
			t.x = lane
			t.target_x = lane
			t.speed = t.cruise
			t.was_ahead = true
			return


# ---------------- collisions, near misses, drafting ----------------
func _collide() -> void:
	var all := racers + traffic
	for i in all.size():
		var a := all[i]
		for j in range(i + 1, all.size()):
			var b := all[j]
			if a.kind == "traffic" and b.kind == "traffic":
				continue
			var ds := ahead(a.s(L), b.s(L))
			var dx := a.x - b.x
			if absf(ds) < Racer.HALF_L * 2.0 and absf(dx) < Racer.HALF_W * 2.0:
				# push apart sideways; the car behind takes the speed loss
				var push := (Racer.HALF_W * 2.0 - absf(dx)) * 0.5 + 0.05
				var sgn := signf(dx) if dx != 0.0 else 1.0
				var wa := 0.25 if a.kind == "traffic" else 1.0  # traffic is heavier, racers bounce off it
				var wb := 0.25 if b.kind == "traffic" else 1.0
				a.x += sgn * push * wa
				b.x -= sgn * push * wb
				a.vx = sgn * 3.0 * wa
				b.vx = -sgn * 3.0 * wb
				var back := b if ds > 0.0 else a
				var front := a if ds > 0.0 else b
				back.speed = minf(back.speed, front.speed * 0.9)
				var hit_a := a.bump()
				var hit_b := b.bump()
				if (a == player and hit_a) or (b == player and hit_b):
					AudioBus.play("sfx_bump")
					_on_bump()
	if state != "race":
		return
	var ps := player.s(L)
	for t in traffic:  # near miss: overtake traffic close by without touching -> nitro + swish
		var rel := ahead(t.s(L), ps)
		var now_ahead := rel > 0.0
		if t.was_ahead and not now_ahead and rel > -6.0:
			var gap := absf(t.x - player.x) - Racer.HALF_W * 2.0
			if gap > 0.0 and gap < 1.6 and player.speed > t.speed + 4.0:
				player.nitro = minf(player.nitro + 0.2, 1.0)
				near_misses += 1
				AudioBus.play("sfx_whoosh", randf_range(0.95, 1.1))
		t.was_ahead = now_ahead
	for r in rivals:  # drafting: tuck in behind a rival to fill the tank
		var a := ahead(r.s(L), ps)
		if a > 4.0 and a < 18.0 and absf(r.x - player.x) < 1.8:
			player.nitro = minf(player.nitro + 0.12 * get_process_delta_time(), 1.0)


func _place(r: Racer, dt: float) -> void:
	var s := r.s(L)
	r.pose(world(s, r.x), tangent(s), right(s), dt)


# ---------------- race flow ----------------
func _countdown() -> void:
	state = "countdown"
	for k in 3:
		await get_tree().create_timer(1.0).timeout
		hud.call("lights", k + 1)
		AudioBus.play("sfx_beep_low")
	await get_tree().create_timer(1.0).timeout
	hud.call("lights", 4)
	AudioBus.play("sfx_beep_high")
	state = "race"
	var boost := Input.is_action_pressed("nitro")  # holding nitro through GO = a rocket start
	player.speed = 12.0 * gs if boost else 4.0 * gs
	for r in rivals:
		r.speed = 6.0 * gs
	await get_tree().create_timer(1.2).timeout
	hud.call("lights", 0)


func _laps() -> void:
	if player.done:
		return
	var lap := int(floorf(player.d / L))
	if lap > _last_lap and lap < laps:
		AudioBus.play("sfx_lap")
	_last_lap = lap
	if player.d >= laps * L:
		_finish()


func progress(r: Racer) -> float:
	if state == "podium":
		return 1.0  # flat podium: everyone arrives together
	return clampf(r.d / (laps * L), 0.0, 1.0)


func _finish() -> void:
	player.done = true
	player.boosting = false
	state = "finish"
	_celebrate_t = 0.0
	AudioBus.play("sfx_fanfare")
	hud.call("celebrate")
	if bot:  # tests never touch the family's progress
		Game.quit_bot(result())
		return
	Save.record_level(Game.level_id)
	for k in 6:
		await get_tree().create_timer(0.7).timeout
		var f := _fireworks[k % _fireworks.size()]
		f.global_position = player.global_position + tangent(player.s(L)) * -40.0 + right(player.s(L)) * _rng.randf_range(-20, 20) + UP * _rng.randf_range(18, 28)
		f.restart()
		AudioBus.play("sfx_pop", randf_range(0.85, 1.15))
	await get_tree().create_timer(1.2).timeout
	_podium()


## Flat podium: all four cars side by side on the start straight, same height, same light. No places.
func _podium() -> void:
	Game.fade(func() -> void:
		state = "podium"
		_celebrate_t = 0.0
		var s0 := 34.0
		var order := [0, 1, 3, 2]  # player in a middle slot
		for k in 4:
			var r := racers[order[k]]
			r.done = true
			r.boosting = false
			r.speed = 0.0
			r.vx = 0.0
			r.d = s0
			r.x = LANES[k]
			_place(r, 0.0)
		for t in traffic:
			t.visible = false
		_confetti.global_position = world(s0, 0.0, 12.0)
		_confetti.emitting = true
		_podium_cam(1.0, true)
		hud.call("podium")
		engine.stop())
	await get_tree().create_timer(2.0).timeout
	for k in 4:
		var f := _fireworks[k]
		f.global_position = world(34.0 - 30.0, (k - 1.5) * 12.0, 25.0)
		f.restart()
		AudioBus.play("sfx_pop", 0.9 + 0.1 * k)
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(6.0).timeout
	Game.go(Game.TITLE)


# ---------------- camera ----------------
func _cam_follow(dt: float, snap := false) -> void:
	var s := player.s(L)
	var t := tangent(s)
	var p := player.global_position
	var want := p - t * 7.5 + UP * 2.9 - right(s) * player.x * 0.15
	var look := world(s + 14.0, player.x * 0.6, 1.2)
	var kp := 1.0 if snap else 1.0 - exp(-dt / 0.1)
	var kr := 1.0 if snap else 1.0 - exp(-dt / 0.18)
	cam.global_position = cam.global_position.lerp(want, kp)
	_cam_look = _cam_look.lerp(look, kr)
	cam.look_at(_cam_look, UP)
	var fast := clampf((player.speed - CRUISE * gs) / (NITRO_ADD * gs), 0.0, 1.0)
	_fov = lerpf(_fov, 70.0 + 9.0 * fast, 1.0 - exp(-3.0 * dt)) if not snap else 70.0
	cam.fov = _fov


## After the line: the camera swings round to a front three-quarter view. Eased, no roll.
func _celebrate_cam(dt: float) -> void:
	_celebrate_t += dt
	var k := clampf(_celebrate_t / 4.0, 0.0, 1.0)
	var angle := deg_to_rad(140.0) * (k * k * (3.0 - 2.0 * k))
	var s := player.s(L)
	var base := -tangent(s) * 9.0 + UP * (3.0 - 1.0 * k)
	var want := player.global_position + base.rotated(UP, angle)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt / 0.08))
	_cam_look = _cam_look.lerp(player.global_position + UP * 0.8, 1.0 - exp(-dt / 0.15))
	cam.look_at(_cam_look, UP)


func _podium_cam(dt: float, snap := false) -> void:
	_celebrate_t += dt
	var s0 := 34.0
	var sway := sin(_celebrate_t * 0.35) * 6.0
	var want := world(s0 + 17.0, sway, 3.2)
	cam.global_position = want if snap else cam.global_position.lerp(want, 1.0 - exp(-dt / 0.3))
	cam.look_at(world(s0, 0.0, 0.9), UP)
	cam.fov = 60.0


func _update_birds() -> void:
	for b in birds:
		var a := Game.t * 0.4 + float(b["phase"])
		var c: Vector3 = b["centre"]
		var r: float = b["r"]
		var n: Node3D = b["node"]
		var p := c + Vector3(cos(a) * r, sin(a * 2.0) * 1.5, sin(a) * r)
		n.look_at_from_position(p, c + Vector3(cos(a + 0.2) * r, 0.0, sin(a + 0.2) * r), UP)
		n.rotate_object_local(Vector3.FORWARD, sin(Game.t * TAU * 1.5 + float(b["phase"])) * 0.45)


func _engine_sound(dt: float) -> void:
	if not engine or not engine.playing:
		return
	# fake gearbox: pitch climbs within a gear, drops at each shift
	var v := player.speed / gs
	var gears := [0.0, 9.0, 17.0, 25.0, 33.0, 60.0]
	var g := 0
	while g < gears.size() - 2 and v > gears[g + 1]:
		g += 1
	var f := clampf((v - gears[g]) / (gears[g + 1] - gears[g]), 0.0, 1.0)
	var want := 0.75 + 0.08 * g + 0.6 * f
	engine.pitch_scale = lerpf(engine.pitch_scale, want, 1.0 - exp(-10.0 * dt))
	engine.volume_db = lerpf(engine.volume_db, -9.0 if player.boosting else -12.0, 1.0 - exp(-4.0 * dt))


# ---------------- input extras ----------------
func _on_honk() -> void:
	if get_tree().paused or state == "podium":
		return
	AudioBus.play("sfx_honk", randf_range(0.97, 1.04))
	honks += 1
	if state != "race":
		return
	# traffic ahead in your way moves over a lane, hazards flashing
	var ps := player.s(L)
	for t in traffic:
		var a := ahead(t.s(L), ps)
		if a > 0.0 and a < 80.0 and absf(t.x - player.x) < 3.5:
			var away := signf(t.x - player.x) if absf(t.x - player.x) > 0.5 else (1.0 if t.x < 0.0 else -1.0)
			var li := LANES.find(_nearest_lane(t.x))
			var ni := clampi(li + int(away), 0, 3)
			if ni == li:
				ni = clampi(li - int(away), 0, 3)
			t.target_x = LANES[ni]
			t.blink_t = 2.0


func _nearest_lane(x: float) -> float:
	var best: float = LANES[0]
	for l: float in LANES:
		if absf(l - x) < absf(best - x):
			best = l
	return best


func _on_bump() -> void:
	bumps += 1
	_bump_times.append(clock)


## Invisible assist: lots of recent bumps -> gentler curve push, rivals ease off. Never harder.
func _assist_update(dt: float) -> void:
	while not _bump_times.is_empty() and clock - _bump_times[0] > 20.0:
		_bump_times.pop_front()
	var want := clampf(_bump_times.size() / 6.0, 0.0, 1.0)
	_assist = move_toward(_assist, want, (0.5 if want > _assist else 0.03) * dt)


var _restart_hold := 0.0


func _restart_input(dt: float) -> void:
	if Input.is_action_pressed("restart"):
		_restart_hold += dt
		if _restart_hold >= 1.0:
			_restart_hold = -INF
			Game.start_level(Game.level_id)
	else:
		_restart_hold = 0.0


# ---------------- pause ----------------
const SPEEDS := [0.6, 0.8, 1.0]


func request_pause() -> void:
	if state in ["finish", "podium"] or bot != null:
		return
	if pause_layer != null and is_instance_valid(pause_layer):
		get_tree().paused = true
		return
	if get_tree().paused or Game.t - _resume_t < 0.25:
		return
	get_tree().paused = true
	pause_layer = CanvasLayer.new()
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.2, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var m := IconMenu.new()
	m.icon_size = 100.0
	m.set_anchors_preset(Control.PRESET_CENTER)
	m.add_item("resume", "play", Color("#4ff3ff"))
	m.add_item("restart", "restart", Color("#ffd23d"))
	m.add_item("home", "home", Color("#ff4fb5"))
	m.add_item("speed", "speed_%d" % (_speed_idx() + 1), Color("#b6ff4f"))
	pause_layer.add_child(m)
	m.position -= Vector2(m.get_combined_minimum_size().x / 2, 64)
	m.back_id = "resume"
	m.chosen.connect(_on_pause_choice)
	add_child(pause_layer)


func _speed_idx() -> int:
	var cur := float(Save.setting("speed"))
	var best := 0
	for i in SPEEDS.size():
		if absf(SPEEDS[i] - cur) < absf(SPEEDS[best] - cur):
			best = i
	return best


func _on_pause_choice(id: String) -> void:
	if id == "speed":  # wordless speed: 1-3 chevrons; applies from the next race
		var i := (_speed_idx() + 1) % SPEEDS.size()
		Save.set_setting("speed", SPEEDS[i])
		(pause_layer.get_child(1) as IconMenu).set_icon("speed", "speed_%d" % (i + 1))
		AudioBus.play("sfx_honk", 0.9 + 0.1 * i)
		return
	pause_layer.queue_free()
	pause_layer = null
	get_tree().paused = false
	_resume_t = Game.t
	match id:
		"restart":
			Game.start_level(Game.level_id)
		"home":
			Game.go(Game.TITLE)


func parent_menu_closed() -> void:
	if pause_layer != null and is_instance_valid(pause_layer):
		get_tree().paused = true
	else:
		request_pause()


# ---------------- tests ----------------
func result() -> Dictionary:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var avg := 0.0
	for v in frame_ms:
		avg += v
	avg /= maxf(frame_ms.size(), 1)
	return {"ok": player.done, "track": Game.level_id, "time_s": snappedf(clock, 0.1), "bumps": bumps,
		"near_misses": near_misses, "honks": honks, "lead_s": snappedf(lead_t, 0.1),
		"rival_progress": rivals.map(func(r: Racer) -> float: return snappedf(progress(r), 0.01)),
		"frame_ms_avg": snappedf(avg, 0.01),
		"frame_ms_p99": snappedf(sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0, 0.01)}


## --shots: screenshots around the lap (race camera), then quit.
func _shot_tour() -> void:
	state = "shots"
	var stops: Array[float] = [-12.0, 0.12 * L, 0.3 * L, 0.5 * L, 0.7 * L, 0.88 * L]
	for g in gates:
		stops.append(float(g["s"]) - 30.0)
	if T.has("tunnel"):
		stops.append(float(T["tunnel"][0]) + 40.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/shots"))
	for i in stops.size():
		player.d = stops[i]
		player.x = 2.0
		for k in 3:  # a few traffic cars just ahead so the shot shows the race
			traffic[k].d = stops[i] + 25.0 + k * 18.0
			traffic[k].x = LANES[(k + i) % 4]
		rivals[0].d = stops[i] + 12.0
		rivals[0].x = -3.0
		for r in racers + traffic:
			_place(r, 0.016)
		_cam_follow(1.0, true)
		for k in 30:
			_update_gates(0.016)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://docs/shots/track_%d_%02d.png" % [Game.level_id, i])
	print("SHOTS ", stops.size())
	get_tree().quit()


func _podium_shots() -> void:
	state = "shots"
	player.done = true
	_podium()
	await get_tree().create_timer(3.5).timeout
	get_viewport().get_texture().get_image().save_png("res://docs/shots/podium_%d.png" % Game.level_id)
	get_tree().quit()
