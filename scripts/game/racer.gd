class_name Racer
extends Node3D
## One car on the track: a racer (player/rival) or traffic. Motion lives in track space:
## d = distance driven along the centreline (laps add up), x = lateral offset. Race places it in the world.

const HALF_W := 1.0
const HALF_L := 2.3

var kind := "rival"  ## player | rival | traffic
var who := -1  ## player slot (0-3) for humans, -1 otherwise
var inp := 0.0  ## humans: smoothed steering input
var lap := 0
var idx := 0  ## car index (racers) -> colour
var d := 0.0
var x := 0.0
var vx := 0.0
var speed := 0.0
var target_x := 0.0
var cruise := 30.0
var nitro := 1.0
var boosting := false
var colour := Color.WHITE
var skill := 1.0
var done := false
var ahead_of := 0  ## traffic: bit k set = was ahead of player k last frame (near-miss check)
var bump_cd := 0.0
var blink_t := 0.0  ## traffic: >0 while indicators flash
var model: Node3D
var blink: Node3D
var flames: Array[Node3D] = []
var _wobble := 0.0
var _roll := 0.0


func setup(car: Node3D, k: String) -> void:
	kind = k
	model = car
	add_child(model)
	Game.paint(model)
	blink = model.find_child("blink", true, false) as Node3D
	if blink:
		for n in blink.find_children("*", "MeshInstance3D", true, false) + ([blink] if blink is MeshInstance3D else []):
			(n as MeshInstance3D).material_override = Game.glow_mat
		blink.visible = false
	# soft contact shadow so the car sits on the road
	var sh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.3, 4.9)
	q.orientation = PlaneMesh.FACE_Y
	sh.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.05, 0.03, 0.1, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.material_override = m
	sh.position.y = 0.04
	add_child(sh)
	if kind != "traffic":  # nitro flames: two glowing cones out of the back, scaled while boosting
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.18
		cm.height = 1.0
		cm.radial_segments = 6
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(0.55, 0.85, 1.0, 0.85)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.disable_fog = true
		for sx: float in [-0.45, 0.45]:
			var f := MeshInstance3D.new()
			f.mesh = cm
			f.material_override = fm
			f.rotation.x = PI / 2  # cone tip points +Z (backwards)
			f.position = Vector3(sx, 0.42, 2.45)
			f.scale = Vector3.ONE * 0.01
			model.add_child(f)
			flames.append(f)


func s(L: float) -> float:
	return fposmod(d, L)


## Visual pose: yaw toward the direction of travel, small roll into lateral motion, wobble after bumps.
func pose(pos: Vector3, fwd: Vector3, right: Vector3, dt: float) -> void:
	var heading := (fwd + right * clampf(vx / maxf(speed, 4.0), -0.5, 0.5)).normalized()
	global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), pos)
	_wobble = maxf(_wobble - dt, 0.0)
	_roll = lerpf(_roll, clampf(-vx * 0.012, -0.08, 0.08), 1.0 - exp(-6.0 * dt))
	model.rotation = Vector3(0.0, sin(_wobble * 28.0) * _wobble * 0.25, _roll + sin(_wobble * 22.0) * _wobble * 0.12)
	for f in flames:
		var k := (1.0 + 0.3 * sin(Game.t * 40.0 + f.position.x * 9.0)) if boosting else 0.01
		f.scale = f.scale.lerp(Vector3(1.0, 1.4 * k, 1.0) * (1.0 if boosting else 0.01), 1.0 - exp(-14.0 * dt))
	if blink:
		blink_t = maxf(blink_t - dt, 0.0)
		blink.visible = blink_t > 0.0 and fmod(Game.t, 0.5) < 0.28


func bump(strength := 1.0) -> bool:
	_wobble = 0.35 * strength
	if bump_cd > 0.0:
		return false
	bump_cd = 0.5
	return true
