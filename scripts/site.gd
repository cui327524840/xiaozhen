extends Node2D
# A building that is still being built.  The player pays for it up front, then
# villagers dig the foundation, haul the timber in from the warehouse and put
# the walls up while this node draws the progress bar above the plot.
#
# The finished building art is created immediately but only its lower part is
# shown; the visible slice grows with the progress, so the house really does
# rise out of the ground instead of popping into existence.

var world: Node2D
var kind := ""
var cell := Vector2i.ZERO
var foot := Vector2(2, 2)
var progress := 0.0
var reveal := 0.0
var art: Node2D
var parts_meta: Array = []      # {node, used}
var art_h := 40.0
var centre := Vector2.ZERO      # footprint centre, relative to the node
var hammering := 0.0
var dust_t := 0.0

# tile metrics (same numbers world.gd uses for the isometric grid)
const HW := 32.0
const HH := 16.0

const PHASES := [
	[0.22, "挖地基"], [0.38, "运木料"], [0.74, "砌墙"], [0.97, "封顶"], [1.01, "完工"],
]

func setup(w: Node2D, k: String, c: Vector2i) -> void:
	world = w
	kind = k
	cell = c
	foot = world.build_defs[k]["foot"]
	position = world._building_origin(k, c)
	# 占地的真正中心（按地砖算），坑、木料、进度条都以它为中心
	centre = world.iso(Vector2(c) + foot * 0.5) - position
	art = world._make_building_node(k)
	add_child(art)
	_collect(art)
	_apply_reveal(0.0)

func _collect(n: Node) -> void:
	for child in n.get_children():
		if child is Sprite2D:
			var sp := child as Sprite2D
			var used := sp.texture.get_image().get_used_rect()
			parts_meta.append({"node": sp, "used": used})
			art_h = maxf(art_h, float(used.size.y))
		_collect(child)

func phase_text() -> String:
	for p in PHASES:
		if progress < float(p[0]):
			return String(p[1])
	return "完工"

func add_progress(amount: float) -> bool:
	if progress >= 1.0:
		return false
	progress = clampf(progress + amount, 0.0, 1.0)
	_apply_reveal(progress)
	return progress >= 1.0

func _apply_reveal(p: float) -> void:
	# nothing but the freshly dug plot until the first fifth of the work
	reveal = clampf((p - 0.14) / 0.86, 0.0, 1.0)
	for m in parts_meta:
		var sp: Sprite2D = m["node"]
		var used: Rect2i = m["used"]
		var rh := maxf(2.0, float(used.size.y) * reveal)
		sp.region_enabled = true
		sp.region_rect = Rect2(
			float(used.position.x), float(used.position.y) + float(used.size.y) - rh,
			float(used.size.x), rh
		)
		sp.offset = Vector2(0.0, -rh * 0.5)

func _process(delta: float) -> void:
	hammering = maxf(0.0, hammering - delta)
	if progress < 1.0 and dust_t > 0.0:
		dust_t -= delta
		if dust_t <= 0.0 and world.fx != null:
			world.fx.smoke(global_position + centre + Vector2(randf_range(-20.0, 20.0), -6.0),
				Color(0.62, 0.55, 0.45, 0.42))
	queue_redraw()

func poke() -> void:
	hammering = 0.35
	dust_t = 0.12

func _diamond(scale_f: float) -> PackedVector2Array:
	# 直接用"这几格地砖并起来的外框"，保证坑和真正占的地方一致
	return world._foot_polygon(cell, foot, position, scale_f)

func _draw() -> void:
	# the dug plot / foundation
	var pit := Color(0.30, 0.22, 0.15, 0.85) if reveal < 0.6 else Color(0.34, 0.28, 0.21, 0.5)
	draw_colored_polygon(_diamond(0.98), pit)
	draw_polyline(_diamond(0.98), Color(0.22, 0.16, 0.11, 0.8), 2.0)
	# planks lying on the ground while the walls go up
	if reveal < 0.98:
		var hw := (foot.x + foot.y) * HW * 0.5
		var hh := (foot.x + foot.y) * HH * 0.5
		for i in 3:
			var off := (float(i) - 1.0) * hw * 0.35
			draw_line(centre + Vector2(off - hw * 0.28, -hh * 0.28 + 2.0),
				centre + Vector2(off + hw * 0.28, hh * 0.28 + 2.0),
				Color(0.48, 0.34, 0.20), 3.0)
	# scaffold posts while the frame is up
	if progress > 0.2 and progress < 0.99:
		var wob := sin(Time.get_ticks_msec() * 0.006) * 1.5
		var hw2 := (foot.x + foot.y) * HW * 0.45
		var top := centre + Vector2(0, -art_h * reveal - 6.0 + wob)
		draw_line(top + Vector2(-hw2, 0), top + Vector2(-hw2, 12), Color(0.44, 0.31, 0.18, 0.9), 2.0)
		draw_line(top + Vector2(hw2, 0), top + Vector2(hw2, 12), Color(0.44, 0.31, 0.18, 0.9), 2.0)
	# progress bar
	var bw := 58.0
	var by := centre.y - art_h - 26.0
	var bar := Rect2(-bw * 0.5, by, bw, 9.0)
	draw_rect(Rect2(bar.position - Vector2(2, 2), bar.size + Vector2(4, 4)), Color(0.10, 0.08, 0.06, 0.8), true)
	draw_rect(bar, Color(0.24, 0.20, 0.16, 0.95), true)
	var fill := bar
	fill.size.x = bw * progress
	var col := Color(0.98, 0.82, 0.35) if progress < 0.99 else Color(0.62, 0.95, 0.55)
	draw_rect(fill, col, true)
	var font := ThemeDB.fallback_font
	var label := "%s %d%%" % [phase_text(), int(round(progress * 100.0))]
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(-w * 0.5 + 1.0, by - 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.10, 0.08, 0.06, 0.85))
	draw_string(font, Vector2(-w * 0.5, by - 5.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.96, 0.86))
	if hammering > 0.0:
		var p := centre + Vector2(randf_range(-24.0, 24.0), -art_h * 0.6)
		draw_circle(p, 2.0, Color(1.0, 0.85, 0.5, hammering * 2.0))
