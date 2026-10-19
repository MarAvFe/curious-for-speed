extends Node
## Bot drivers use ONLY input actions, exercising the real code paths.
## good: steers toward the AI's chosen line, nitro on clear road, honks at traffic. bad: random holds and mashing.

var runner: Node
var bad := false
var _t := 0.0
var _dir := 0.0
var _nitro := false
var _rng := RandomNumberGenerator.new()
var _timeout := 0.0


func _ready() -> void:
	_rng.seed = int(Game.args.get("seed", "7"))


func _press(a: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(a, strength)
	else:
		Input.action_release(a)


func _process(dt: float) -> void:
	_timeout += dt
	if _timeout > 600.0:
		Game.quit_bot({"ok": false, "why": "timeout", "d": runner.get("player").d})
		return
	var p: Racer = runner.get("player")
	if bad:
		_t -= dt
		if _t <= 0.0:
			_t = _rng.randf_range(0.2, 1.5)
			_dir = float(_rng.randi_range(-1, 1))
			_nitro = _rng.randf() < 0.5
			if _rng.randf() < 0.3:
				Input.parse_input_event(_key_event())
		_press("steer_left", _dir < 0.0)
		_press("steer_right", _dir > 0.0)
		_press("nitro", _nitro)
		_press("steer_down", _rng.randf() < 0.02)
		return
	var want: float = runner.call("ai_target_x", p)
	var err := want - p.x
	var k := clampf(absf(err) / 2.0, 0.0, 1.0)
	_press("steer_left", err < -0.3, k)
	_press("steer_right", err > 0.3, k)
	_press("nitro", p.nitro > 0.5 and absf(err) < 1.0)
	_t -= dt
	if _t <= 0.0:
		_t = 4.0
		Input.parse_input_event(_honk_event())


func _key_event() -> InputEventKey:  # unbound key -> honk path
	var e := InputEventKey.new()
	e.physical_keycode = KEY_Q
	e.pressed = true
	return e


func _honk_event() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "honk"
	e.pressed = true
	return e
