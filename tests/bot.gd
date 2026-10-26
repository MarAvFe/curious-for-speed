extends Node
## Bot drivers use ONLY input actions, exercising the real code paths.
## good: steers toward the AI's chosen line, nitro on clear road, honks at traffic. bad: random holds and mashing.
## Split screen (--players=N): the good bot drives every player through their own actions.

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
	if bad:
		_t -= dt
		if _t <= 0.0:
			_t = _rng.randf_range(0.2, 1.5)
			_dir = float(_rng.randi_range(-1, 1))
			_nitro = _rng.randf() < 0.5
			if _rng.randf() < 0.3:
				Input.parse_input_event(_key_event())
		_press(Bindings.act(0, "steer_left"), _dir < 0.0)
		_press(Bindings.act(0, "steer_right"), _dir > 0.0)
		_press(Bindings.act(0, "nitro"), _nitro)
		return
	for p: Racer in runner.get("players"):
		var want: float = runner.call("ai_target_x", p)
		var err := want - p.x
		var k := clampf(absf(err) / 2.0, 0.0, 1.0)
		_press(Bindings.act(p.who, "steer_left"), err < -0.3, k)
		_press(Bindings.act(p.who, "steer_right"), err > 0.3, k)
		_press(Bindings.act(p.who, "nitro"), p.nitro > 0.5 and absf(err) < 1.0)
	_t -= dt
	if _t <= 0.0:
		_t = 4.0
		for p: Racer in runner.get("players"):
			Input.parse_input_event(_honk_event(p.who))


func _key_event() -> InputEventKey:  # unbound key -> honk path
	var e := InputEventKey.new()
	e.physical_keycode = KEY_Q
	e.pressed = true
	return e


func _honk_event(who: int) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = Bindings.act(who, "honk")
	e.pressed = true
	return e
