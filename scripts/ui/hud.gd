extends CanvasLayer
## Wordless HUD. Top: one flat bar from start flag to finish flag with every racer on it (no places, no numbers);
## a tick marks the lap. Bottom right: nitro tank. Centre: start lights. One per split-screen view.

var race: Node
var me: Racer  ## whose nitro tank this shows; drawn biggest on the bar
var _bar: Control
var _lights := 0
var _celebrate := 0.0
var _podium := false
var _tex := {}


func _ready() -> void:
	for k: String in ["dot", "web", "flag", "flame", "light"]:
		_tex[k] = load("res://assets/ui/icon_%s.png" % k)
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_hud)
	add_child(_bar)


func _process(_dt: float) -> void:
	_bar.queue_redraw()


func _draw_hud() -> void:
	var r := race
	var vs := _bar.get_viewport_rect().size
	var u := vs.y / 360.0  # works in retro (640x360) and full (1280x720)
	# ---- progress bar ----
	var y := 18.0 * u + _celebrate * vs.y * 0.35
	var x0 := vs.x * 0.2
	var x1 := vs.x * 0.8
	_bar.draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.08, 0.06, 0.16, 0.6), 7.0 * u, true)
	_bar.draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.85), 3.0 * u, true)
	var laps := int(r.get("laps"))
	for k in range(1, laps):
		var lx := lerpf(x0, x1, float(k) / laps)
		_bar.draw_line(Vector2(lx, y - 6 * u), Vector2(lx, y + 6 * u), Color(1, 1, 1, 0.85), 2.0 * u)
	var fs := 22.0 * u
	_bar.draw_texture_rect(_tex["flag"], Rect2(Vector2(x1 + 4 * u, y - fs * 0.8), Vector2(fs, fs)), false)
	var racers: Array = r.get("racers")
	var player: Racer = me
	var slot := 0
	for rc: Racer in racers:  # rivals first, player drawn last (on top)
		if rc == player:
			continue
		var px := lerpf(x0, x1, float(r.call("progress", rc)))
		var off := (slot - 1) * 10.0 * u if _podium else 0.0  # flat podium: side by side at the flag
		_dot(rc.colour, Vector2(px + off, y), 9.0 * u)
		slot += 1
	if player:
		var px := lerpf(x0, x1, float(r.call("progress", player)))
		var s := 13.0 * u * (1.0 + 0.15 * Game.pulse(2))
		_dot(player.colour, Vector2(px, y), s)
		_bar.draw_texture_rect(_tex["web"], Rect2(Vector2(px, y) - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.9))
	# ---- nitro tank ----
	if player and not _podium:
		var w := 14.0 * u
		var h := 80.0 * u
		var bx := vs.x - 30.0 * u
		var by := vs.y - 24.0 * u
		_bar.draw_rect(Rect2(bx - 2 * u, by - h - 2 * u, w + 4 * u, h + 4 * u), Color(0.08, 0.06, 0.16, 0.6))
		var full := float(player.get("nitro"))
		var c := Color("#4ff3ff").lerp(Color.WHITE, 0.5 * Game.pulse(4)) if bool(player.get("boosting")) else Color("#4ff3ff")
		_bar.draw_rect(Rect2(bx, by - h * full, w, h * full), c)
		var fsz := 22.0 * u
		_bar.draw_texture_rect(_tex["flame"], Rect2(Vector2(bx + w * 0.5 - fsz * 0.5, by - h - fsz - 4 * u), Vector2(fsz, fsz)), false, c)
	# ---- start lights ----
	if _lights > 0:
		var ls := 34.0 * u
		var cx := vs.x * 0.5
		for k in 3:
			var on := _lights >= 4 or _lights > k
			var col := Color("#3dff7a") if _lights >= 4 else (Color("#ff3d5a") if on else Color(0.2, 0.18, 0.28, 0.8))
			_bar.draw_texture_rect(_tex["light"], Rect2(Vector2(cx + (k - 1.5) * ls * 1.2 + ls * 0.1, vs.y * 0.28), Vector2(ls, ls)), false, col)


func _dot(c: Color, p: Vector2, s: float) -> void:
	_bar.draw_texture_rect(_tex["dot"], Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)


func lights(n: int) -> void:
	_lights = n


func celebrate() -> void:
	create_tween().tween_property(self, "_celebrate", 1.0, 1.0).set_trans(Tween.TRANS_SINE)


func podium() -> void:
	_podium = true
	_celebrate = 0.0
