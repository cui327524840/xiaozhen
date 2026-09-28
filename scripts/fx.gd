extends Node2D
# Everything the town needs that is not a sprite: fireworks for a finished
# building, the campfire the villagers sit around, water ripples, fishing
# lines, splashes and the little "+1 木头" floating labels.
#
# It is drawn procedurally so no extra art has to ship with the game.

var parts: Array = []       # {pos, vel, t, life, color, size, grav, drag}
var ripples: Array = []     # {pos, t, life, r}
var texts: Array = []       # {pos, text, t, life, color}
var lines: Array = []       # {id, from, to, stamp, color}
var stamps: Array = []      # firework flashes {pos, t, life, color, r}
var bolts: Array = []       # lightning {pos, t, life, color}
var auras: Array = []       # cultivation rings {id, pos, realm, stamp}
var marks: Array = []       # "找到他" markers {id, pos, t, life}

var weather := ""           # kept for the old API；天气粒子已经停用了
var cam: Camera2D
var fire_on := false
var fire_pos := Vector2.INF
var fire_t := 0.0
var spawn_acc := 0.0

func _ready() -> void:
	z_index = 120
	z_as_relative = false

func _process(delta: float) -> void:
	fire_t += delta
	_update_particles(delta)
	_update_fire(delta)
	_update_weather(delta)
	_update_lines()
	_update_auras()
	_update_marks(delta)
	queue_redraw()

func _update_particles(delta: float) -> void:
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p["t"] += delta
		if p["t"] >= p["life"]:
			parts.remove_at(i)
		else:
			p["vel"] = (p["vel"] as Vector2) * (1.0 - float(p["drag"]) * delta)
			p["vel"] = (p["vel"] as Vector2) + Vector2(0.0, float(p["grav"]) * delta)
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		i -= 1
	var j := ripples.size() - 1
	while j >= 0:
		var r: Dictionary = ripples[j]
		r["t"] += delta
		if r["t"] >= r["life"]:
			ripples.remove_at(j)
		j -= 1
	var k := texts.size() - 1
	while k >= 0:
		var t: Dictionary = texts[k]
		t["t"] += delta
		if t["t"] >= t["life"]:
			texts.remove_at(k)
		k -= 1
	var m := stamps.size() - 1
	while m >= 0:
		var s: Dictionary = stamps[m]
		s["t"] += delta
		if s["t"] >= s["life"]:
			stamps.remove_at(m)
		m -= 1
	var b := bolts.size() - 1
	while b >= 0:
		var bol: Dictionary = bolts[b]
		bol["t"] += delta
		if bol["t"] >= bol["life"]:
			bolts.remove_at(b)
		b -= 1

# ---------------------------------------------------------------- particles

func burst(pos: Vector2, color_a: Color, color_b: Color, count: int = 46, power: float = 120.0) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + randf() * 0.2
		var sp := power * (0.45 + randf() * 0.75)
		parts.append({
			"pos": pos + Vector2(0, randf_range(-10.0, 10.0)),
			"vel": Vector2(cos(a), sin(a) * 0.85) * sp,
			"t": 0.0, "life": randf_range(0.7, 1.5),
			"color": color_a if randf() < 0.6 else color_b,
			"size": randf_range(1.6, 3.4), "grav": 130.0, "drag": 1.6,
		})
	stamps.append({
		"pos": pos, "t": 0.0, "life": 0.55,
		"color": color_a, "r": power * 0.75,
	})

func firework(pos: Vector2) -> void:
	var palettes := [
		[Color(1.0, 0.86, 0.45), Color(1.0, 0.55, 0.35)],
		[Color(0.75, 0.92, 1.0), Color(0.55, 0.75, 1.0)],
		[Color(1.0, 0.7, 0.85), Color(0.95, 0.85, 1.0)],
		[Color(0.7, 1.0, 0.7), Color(1.0, 0.95, 0.6)],
	]
	var pal: Array = palettes[randi() % palettes.size()]
	burst(pos, pal[0], pal[1], 54, 135.0)

func splash(pos: Vector2) -> void:
	for i in 9:
		var a := randf_range(-PI * 0.85, -PI * 0.15)
		parts.append({
			"pos": pos, "vel": Vector2(cos(a), sin(a)) * randf_range(28.0, 62.0),
			"t": 0.0, "life": randf_range(0.35, 0.6),
			"color": Color(0.82, 0.92, 1.0, 0.9), "size": randf_range(1.2, 2.4),
			"grav": 190.0, "drag": 0.6,
		})
	ripple(pos, 22.0)

func smoke(pos: Vector2, color := Color(0.35, 0.33, 0.32, 0.5)) -> void:
	parts.append({
		"pos": pos, "vel": Vector2(randf_range(-6.0, 6.0), randf_range(-26.0, -14.0)),
		"t": 0.0, "life": randf_range(0.9, 1.6), "color": color,
		"size": randf_range(2.5, 4.5), "grav": -4.0, "drag": 0.4,
	})

func spark(pos: Vector2, color := Color(1.0, 0.78, 0.35)) -> void:
	parts.append({
		"pos": pos, "vel": Vector2(randf_range(-18.0, 18.0), randf_range(-42.0, -16.0)),
		"t": 0.0, "life": randf_range(0.5, 1.1), "color": color,
		"size": randf_range(1.2, 2.2), "grav": 55.0, "drag": 0.8,
	})

func ripple(pos: Vector2, r: float = 16.0) -> void:
	ripples.append({"pos": pos, "t": 0.0, "life": 1.1, "r": r})

# A tribulation lightning bolt, drawn from above down to the villager.
func bolt(pos: Vector2, color := Color(0.9, 0.94, 1.0)) -> void:
	bolts.append({"pos": pos, "t": 0.0, "life": 0.7, "color": color})
	burst(pos, color, Color(1.0, 1.0, 1.0), 30, 90.0)
	for i in 14:
		spark(pos + Vector2(randf_range(-10.0, 10.0), 0), color)

# Cultivation aura: refreshed every frame by whoever is meditating.
func aura(id: int, pos: Vector2, realm: int) -> void:
	var st := Engine.get_process_frames()
	for e in auras:
		if int(e["id"]) == id:
			e["pos"] = pos
			e["realm"] = realm
			e["stamp"] = st
			return
	auras.append({"id": id, "pos": pos, "realm": realm, "stamp": st})

func _update_auras() -> void:
	var st := Engine.get_process_frames()
	var i := auras.size() - 1
	while i >= 0:
		if st - int(auras[i]["stamp"]) > 3:
			auras.remove_at(i)
		i -= 1

# 「找到他」的定位圈：贴在地面上会呼吸的黄圈，跟着被跟拍的村民走
func highlight(id: int, pos: Vector2, secs: float) -> void:
	for e in marks:
		if int(e["id"]) == id:
			e["pos"] = pos
			e["t"] = 0.0
			e["life"] = secs
			return
	marks.append({"id": id, "pos": pos, "t": 0.0, "life": secs})

# whoever is being followed calls this every frame so the ring keeps up
func keep_highlight(id: int, pos: Vector2) -> void:
	for e in marks:
		if int(e["id"]) == id:
			e["pos"] = pos
			return

func _update_marks(delta: float) -> void:
	var i := marks.size() - 1
	while i >= 0:
		marks[i]["t"] = float(marks[i]["t"]) + delta
		if float(marks[i]["t"]) >= float(marks[i]["life"]):
			marks.remove_at(i)
		i -= 1

static func realm_color(realm: int) -> Color:
	match realm:
		0:
			return Color(0.78, 0.96, 1.0)
		1:
			return Color(0.62, 0.86, 1.0)
		2:
			return Color(1.0, 0.92, 0.55)
		3:
			return Color(0.85, 0.70, 1.0)
		4:
			return Color(1.0, 1.0, 1.0)
		_:
			return Color(1.0, 0.78, 0.45)

func float_text(pos: Vector2, text: String, color := Color(1.0, 0.98, 0.86)) -> void:
	texts.append({"pos": pos, "text": text, "t": 0.0, "life": 1.4, "color": color})

# A villager holding a rod calls this every frame while fishing; entries older
# than a couple of frames are dropped, so a line disappears the moment the
# villager stops.
func fish_line(id: int, from: Vector2, to: Vector2) -> void:
	var st := Engine.get_process_frames()
	for e in lines:
		if int(e["id"]) == id:
			e["from"] = from
			e["to"] = to
			e["stamp"] = st
			return
	lines.append({"id": id, "from": from, "to": to, "stamp": st})

func _update_lines() -> void:
	var st := Engine.get_process_frames()
	var i := lines.size() - 1
	while i >= 0:
		if st - int(lines[i]["stamp"]) > 3:
			lines.remove_at(i)
		i -= 1

# ----------------------------------------------------------------- weather

func set_weather(mode: String) -> void:
	if weather == mode:
		return
	weather = mode
	parts.clear()

func _update_weather(delta: float) -> void:
	# 停止生成花瓣/落叶/雪花：这些粒子每帧都要新建、移动、绘制，对一台老机器
	# 来说纯属浪费。留个空函数，免得别处调用报错。
	pass

# ------------------------------------------------------------- camp fire

func light_fire(pos: Vector2) -> void:
	fire_pos = pos
	fire_on = true
	fire_t = 0.0

func put_out_fire() -> void:
	fire_on = false
	fire_pos = Vector2.INF

func _update_fire(delta: float) -> void:
	if not fire_on:
		return
	if randf() < delta * 26.0:
		spark(fire_pos + Vector2(randf_range(-5.0, 5.0), -6.0))
	if randf() < delta * 7.0:
		smoke(fire_pos + Vector2(randf_range(-4.0, 4.0), -18.0))

# ------------------------------------------------------------------- draw

func _draw() -> void:
	# cultivation auras glow on the ground under the meditating villager
	for e in auras:
		var col := realm_color(int(e["realm"]))
		var pulse := 13.0 + sin(fire_t * 2.0) * 1.5
		var centre: Vector2 = e["pos"] + Vector2(0, 4)
		draw_arc(centre, pulse, 0.0, TAU, 26, Color(col.r, col.g, col.b, 0.55), 2.0)
		draw_circle(centre, pulse * 0.8, Color(col.r, col.g, col.b, 0.10))
	# the "found him" ring, drawn on the ground under the followed villager
	for m in marks:
		var life: float = maxf(0.1, float(m["life"]))
		var f := clampf(1.0 - float(m["t"]) / life, 0.0, 1.0)
		var centre: Vector2 = m["pos"] + Vector2(0, 4)
		var pulse := 17.0 + sin(fire_t * 4.5) * 3.0
		var col := Color(1.0, 0.90, 0.42, 0.85 * minf(1.0, f * 4.0))
		draw_arc(centre, pulse, 0.0, TAU, 30, col, 2.6)
		draw_arc(centre, pulse * 0.6, 0.0, TAU, 26, Color(col.r, col.g, col.b, col.a * 0.45), 1.6)
	for bo in bolts:
		var f: float = 1.0 - float(bo["t"]) / float(bo["life"])
		var c: Color = bo["color"]
		c.a = f
		var top: Vector2 = bo["pos"] + Vector2(randf_range(-14.0, 14.0), -300.0)
		var mid: Vector2 = bo["pos"] + Vector2(randf_range(-18.0, 18.0), -150.0)
		draw_polyline(PackedVector2Array([top, mid, bo["pos"]]), c, 4.0)
		draw_circle(bo["pos"], 26.0 * f, Color(c.r, c.g, c.b, 0.22 * f))
	# water ripples sit behind everything else this node draws
	for r in ripples:
		var f := 1.0 - float(r["t"]) / float(r["life"])
		var rad := float(r["r"]) * (1.0 - f) + 6.0
		draw_arc(r["pos"], rad, 0.0, TAU, 22, Color(0.88, 0.95, 1.0, 0.55 * f), 1.6)
	if fire_on:
		_draw_fire()
	for s in stamps:
		var f: float = 1.0 - float(s["t"]) / float(s["life"])
		var c: Color = s["color"]
		c.a = 0.5 * f * f
		draw_circle(s["pos"], float(s["r"]) * (0.35 + 0.65 * (1.0 - f)), c)
	for p in parts:
		var f: float = 1.0 - float(p["t"]) / float(p["life"])
		var c: Color = p["color"]
		c.a *= maxf(0.0, f)
		draw_circle(p["pos"], float(p["size"]), c)
	for e in lines:
		var a: Vector2 = e["from"]
		var b: Vector2 = e["to"]
		draw_line(a, b, Color(0.95, 0.98, 1.0, 0.75), 1.4)
		var bob := sin(fire_t * 2.2) * 2.0
		draw_circle(b + Vector2(0, bob), 2.6, Color(0.95, 0.5, 0.35, 0.95))
	var font := ThemeDB.fallback_font
	for t in texts:
		var f: float = 1.0 - float(t["t"]) / float(t["life"])
		var pos: Vector2 = t["pos"] + Vector2(0, -26.0 * (1.0 - f))
		var c: Color = t["color"]
		c.a *= clampf(f * 1.6, 0.0, 1.0)
		var size := 15
		var w := font.get_string_size(t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := pos - Vector2(w * 0.5, 0.0)
		draw_string(font, at + Vector2(1.0, 1.0), t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.1, 0.08, 0.06, c.a))
		draw_string(font, at, t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

func _draw_fire() -> void:
	var flick := sin(fire_t * 9.0) * 2.0 + sin(fire_t * 21.0) * 1.2
	# warm glow
	for i in 6:
		var r := 96.0 - float(i) * 13.0
		draw_circle(fire_pos + Vector2(0, -6), r, Color(1.0, 0.72, 0.35, 0.035))
	# logs
	draw_line(fire_pos + Vector2(-24, 4), fire_pos + Vector2(20, -4), Color(0.28, 0.18, 0.10), 7.0)
	draw_line(fire_pos + Vector2(-18, -6), fire_pos + Vector2(22, 6), Color(0.36, 0.24, 0.14), 7.0)
	draw_line(fire_pos + Vector2(-20, 8), fire_pos + Vector2(18, 8), Color(0.24, 0.15, 0.09), 5.0)
	# flames: a few tapering triangles that flicker
	var flames := [
		[-13.0, 30.0, 0.9], [-6.0, 44.0, 1.0], [3.0, 40.0, 0.95], [11.0, 28.0, 0.85],
		[0.0, 52.0, 1.0],
	]
	for f in flames:
		var x: float = f[0]
		var h: float = f[1] + flick * 1.4
		var w: float = 9.0 * f[2]
		var base := fire_pos + Vector2(x, 1)
		var tip := fire_pos + Vector2(x + flick * 1.1, -h)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0), tip,
		]), Color(1.0, 0.55, 0.16, 0.85))
		var inner := h * 0.62
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w * 0.5, 0), base + Vector2(w * 0.5, 0),
			fire_pos + Vector2(x + flick * 0.9, -inner),
		]), Color(1.0, 0.88, 0.45, 0.9))
