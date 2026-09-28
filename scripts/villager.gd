extends Sprite2D
# One villager.
#
# Villagers no longer wander at random: whoever looks after the town (town.gd)
# hands them a small plan - "walk to that tree, chop for four seconds, carry
# the logs back to the warehouse" - and this script walks that plan through.
#
# A plan is an Array of Dictionaries, one per step:
#   {"op":"goto",  "cell": Vector2}          walk to a free tile
#   {"op":"goto_near", "cell": Vector2}      walk to a neighbour of a taken tile
#   {"op":"work",  "secs": float}            swing the tool / dig / hammer
#   {"op":"wait",  "secs": float}
#   {"op":"say",   "text": String}           white speech bubble
#   {"op":"think", "text": String}           light blue thought bubble
#   {"op":"carry", "kind": String}           "" / "wood" / "stone" / "food"
#   {"op":"anim",  "mode": String}           stand / walk / work / idle / cast
#   {"op":"face",  "cell": Vector2}
#   {"op":"swim",  "on": bool}               in the water, ripples, body sunk
#   {"op":"fish",  "on": bool}               holding a rod (fx draws the line)
#   {"op":"sit",   "on": bool}               sitting by the fire
#   {"op":"hide"}  {"op":"show"}             step into / out of a building
#   {"op":"call",  "fn": Callable}
#   {"op":"speed", "mult": float}
#   {"op":"loop",  "to": int}                jump back to a step index

const HW := 32.0
const HH := 16.0
# paved roads make walking quicker
const ROAD_SPEED := 1.45
const CHILD_SCALE := 0.72
const ANIM_STEP := 0.16

# ---------------------------------------------------------------- animation
# Skins ship as <skin>_<action>_<dir>.<frame>.png.  Walking and carrying exist
# for all five facings, working only for the two "facing the job" ones.
static var SKIN_CACHE := {}

static func _seq(skin_name: String, action: String, d: int, max_frames: int = 6) -> Array:
	var out: Array = []
	for i in max_frames:
		var p := "res://assets/tt/chars/%s_%s_%d.%d.png" % [skin_name, action, d, i]
		if not ResourceLoader.exists(p):
			break
		out.append(load(p))
	return out

static func _idle_seq(skin_name: String, d: int) -> Array:
	var out: Array = []
	var first := "res://assets/tt/chars/%s_idle.%d.png" % [skin_name, d]
	if ResourceLoader.exists(first):
		out.append(load(first))
	for f in range(1, 5):
		var p := "res://assets/tt/chars/%s_idle.%d%d.png" % [skin_name, d, f]
		if not ResourceLoader.exists(p):
			break
		out.append(load(p))
	return out

static func load_skin(skin_name: String) -> Dictionary:
	if SKIN_CACHE.has(skin_name):
		return SKIN_CACHE[skin_name]
	var loaded := {"stand": {}, "walk": {}, "carry": {}, "work": {}, "idle": {}, "cast": {}}
	for d in 5:
		var sp := "res://assets/tt/chars/%s_stand_%d.0.png" % [skin_name, d]
		if ResourceLoader.exists(sp):
			loaded["stand"][d] = load(sp)
		var walk := _seq(skin_name, "walk", d)
		if not walk.is_empty():
			loaded["walk"][d] = walk
		var carry := _seq(skin_name, "carry", d)
		if not carry.is_empty():
			loaded["carry"][d] = carry
		var work := _seq(skin_name, "work", d)
		if not work.is_empty():
			loaded["work"][d] = work
		var cast := _seq(skin_name, "shoot", d)
		if not cast.is_empty():
			loaded["cast"][d] = cast
		var idle := _idle_seq(skin_name, d)
		if not idle.is_empty():
			loaded["idle"][d] = idle
	SKIN_CACHE[skin_name] = loaded
	return loaded

# ---------------------------------------------------------------- identity
var bank := {}
var skin := "craftsman"

# 手上的货：原版把"手里拿的木料/石头/麦子"单独切成了 wood_carried_<方向>.<帧>.png，
# 身体那帧只是空手姿势，所以要在身上再挂一个精灵，货物才看得见。
static var ITEM_CACHE := {}

static func load_item_bank(item: String) -> Dictionary:
	if ITEM_CACHE.has(item):
		return ITEM_CACHE[item]
	var out := {}
	for d in 5:
		var arr := _seq(item, "carried", d, 4)
		if not arr.is_empty():
			out[d] = arr
	ITEM_CACHE[item] = out
	return out

var item_sprite: Sprite2D = null
var item_bank := {}
var item_name := ""

var grid_pos := Vector2.ZERO
var base_speed := 2.0
var speed := 2.0
var time_scale := 1.0
var rng := RandomNumberGenerator.new()

var map_w := 48
var map_h := 48
var blocked_cells: Array = []
var road_cells: Array = []

var dir := 4
var anim_t := 0.0
var frame_i := 0
var anim_mode := "stand"

var pname := "村民"
var female := false
var child := false
var mood := 60.0
var mood_target := 60.0
var partner := ""
var friends := {}
var spouse_day := -1
var born_day := 1
var home_cell := Vector2i(-1, -1)
var last_thought := ""
var traits: Array = []
var work_rate := 1.0
var chat_bias := 1.0
var recent_lines: Array = []

# --- age, ability and cultivation ----------------------------------------
var raw_speed := 2.0
var trait_speed := 1.0
var skill_speed := 1.0
var life_hours := 0.0     # game hours this villager has been alive
var skill := 1.0          # 1.0 = a fresh pair of hands
var cultivate := false    # sent to the 修仙场 by the player
var realm := 0            # index into town.REALMS
var layer := 1
var xp := 0.0
var xp_need := 22.0
var cultivating_vis := false
var breakthrough_flash := 0.0
var pending_tribulation := false
var last_tribulation_day := 0

# what this villager does for a living
var job := "none"
var job_place := Vector2(-1, -1)
var work_target := Vector2(-1, -1)

# --- state ---------------------------------------------------------------
var busy := false       # holding still for a scripted social beat
var state := "idle"     # idle / walk / work / talk / play / argue / marry
var sleeping := false
var inside_home := false
var swimming := false
var fishing := false
var sitting := false
var talking_to: Node = null
var jitter := 0.0
var hop := 0.0
var art_h := 48.0

# --- speech bubble -------------------------------------------------------
var bubble: PanelContainer
var bubble_label: Label
var bubble_t := 0.0
var bubble_kind := ""

# --- the plan currently being executed ------------------------------------
var plan: Array = []
var plan_i := 0
var plan_done: Callable = Callable()
var build_site = null    # 正在施工的工地（完工时 town 会把大家叫停）
var wait_t := 0.0
var activity := "在原地发呆"
var carry_kind := ""
var speed_mult := 1.0

var path: Array = []
var idle_wait := 0.0
var _guard := 0

func setup(start: Vector2, r: RandomNumberGenerator, mw: int, mh: int, cells: Array = [], roads: Array = []) -> void:
	centered = true
	grid_pos = start
	map_w = mw
	map_h = mh
	blocked_cells = cells
	road_cells = roads
	rng = r
	apply_skin("craftsman")
	_set_dir(4, false)
	_apply_position()

func apply_skin(skin_name: String) -> void:
	skin = skin_name
	bank = load_skin(skin_name)
	if bank["stand"].is_empty():
		bank = load_skin("craftsman")
	texture = _first_texture()
	_measure_art()
	_ensure_item_sprite()

# 手里那件货画在身体之后（子节点后画），锚点和身体共用同一张图集的画布
func _ensure_item_sprite() -> void:
	if item_sprite == null:
		item_sprite = Sprite2D.new()
		item_sprite.centered = true
		item_sprite.visible = false
		add_child(item_sprite)
	item_sprite.position = offset

func _carry_item() -> String:
	match carry_kind:
		"wood":
			return "wood"
		"stone":
			return "stone"
		"crop":
			return "corn"
		"fish":
			return "fish"
		"ore":
			return "ore"
		"nuggets":
			return "nuggets"
		"food":
			return "flour"
	return ""

func _sync_item() -> void:
	if item_sprite == null:
		return
	var want := _carry_item()
	if want == "":
		if item_sprite.visible:
			item_sprite.visible = false
		return
	if want != item_name:
		item_name = want
		item_bank = load_item_bank(want)
	var arr: Array = item_bank.get(dir, [])
	if arr.is_empty():
		item_sprite.visible = false
		return
	item_sprite.visible = true
	item_sprite.texture = arr[frame_i % arr.size()]
	item_sprite.flip_h = flip_h
	item_sprite.position = offset

func _first_texture() -> Texture2D:
	var stand: Dictionary = bank["stand"]
	var first: Texture2D = null
	for k in stand:
		first = stand[k]
		break
	return first

func _measure_art() -> void:
	if texture == null:
		return
	var img := texture.get_image()
	var used := img.get_used_rect()
	var size := Vector2(img.get_width(), img.get_height())
	var ax := float(used.position.x) + float(used.size.x) * 0.5
	var ay := float(used.position.y + used.size.y)
	offset = Vector2(size.x * 0.5 - ax, size.y * 0.5 - ay)
	art_h = float(used.size.y)

func set_identity(new_name: String, is_female: bool, is_child: bool, town_day: int) -> void:
	pname = new_name
	female = is_female
	child = is_child
	born_day = town_day
	if is_child:
		scale = Vector2.ONE * CHILD_SCALE
		mood = 80.0

func set_traits(list: Array) -> void:
	traits = list
	work_rate = 1.0
	chat_bias = 1.0
	trait_speed = 1.0
	for t in list:
		match String(t):
			"勤劳":
				work_rate *= 1.35
			"懒散":
				work_rate *= 0.72
			"急性子":
				trait_speed *= 1.15
			"慢性子":
				trait_speed *= 0.86
			"开朗":
				chat_bias *= 1.5
			"内向":
				chat_bias *= 0.55
			"爱热闹":
				chat_bias *= 1.25
	_recompute_speed()

# 活得越久、修为越高，手脚就越麻利
func refresh_skill() -> void:
	var base := 1.0 + minf(2.0, life_hours / 300.0)
	var realm_bonus := float(realm) * 0.22 + float(layer - 1) * 0.02
	skill = base + realm_bonus
	skill_speed = 1.0 + 0.15 * (skill - 1.0)
	work_rate = minf(4.0, maxf(0.6, work_rate) * (1.0 + 0.12 * (skill - 1.0)))
	_recompute_speed()

func _recompute_speed() -> void:
	base_speed = raw_speed * trait_speed * skill_speed
	speed = base_speed * time_scale

func has_trait(t: String) -> bool:
	return traits.has(t)

func set_time_scale(s: float) -> void:
	time_scale = s
	_recompute_speed()

func become_adult() -> void:
	if not child:
		return
	child = false
	scale = Vector2.ONE

func display_name() -> String:
	return "%s（小孩）" % pname if child else pname

func is_free() -> bool:
	return plan.is_empty() and not sleeping and not inside_home

func is_idle() -> bool:
	return plan.is_empty()

func mood_word() -> String:
	if mood >= 80.0:
		return "很开心"
	if mood >= 60.0:
		return "还不错"
	if mood >= 40.0:
		return "一般"
	if mood >= 20.0:
		return "有点烦"
	return "快气炸了"

func job_text() -> String:
	match job:
		"lumber":
			return "伐木工"
		"quarry":
			return "采石工"
		"farm":
			return "农夫"
		"fish":
			return "渔夫"
		"build":
			return "工匠（盖房子）"
		"trade":
			return "商人"
		"herb":
			return "采药人"
		_:
			return "小孩" if child else "暂时没活干"

func activity_text() -> String:
	return activity

func home_text() -> String:
	if home_cell.x < 0:
		return "还没有房子，先挤一挤"
	return "住在 %d,%d 的木屋" % [home_cell.x, home_cell.y]

func partner_text() -> String:
	if partner == "":
		return "还没成家"
	return "和 %s 结婚了" % partner

func traits_text() -> String:
	if traits.is_empty():
		return "平平常常"
	return "、".join(traits)

# ---------- speech bubbles ----------

func _ensure_bubble() -> void:
	if bubble != null:
		return
	bubble = PanelContainer.new()
	bubble.z_index = 80
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", _bubble_style(true))
	bubble_label = Label.new()
	bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_label.add_theme_font_size_override("font_size", 13)
	bubble.add_child(bubble_label)
	bubble.visible = false
	add_child(bubble)

func _bubble_style(speech: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# thoughts are light blue, speech is warm white
	sb.bg_color = Color(1.0, 1.0, 0.97, 0.95) if speech else Color(0.78, 0.89, 1.0, 0.96)
	sb.set_corner_radius_all(9)
	sb.set_content_margin_all(6)
	sb.border_color = Color(0.32, 0.24, 0.16, 0.55) if speech else Color(0.30, 0.45, 0.68, 0.65)
	sb.set_border_width_all(2)
	return sb

func say(text: String, secs: float = 2.6) -> void:
	_show_bubble(text, secs, true, display_name())

func say_thought(text: String, secs: float = 3.4) -> void:
	last_thought = text
	_show_bubble(text, secs, false, display_name())

# pick a line and remember it so the same villager does not repeat itself
func pick(pool: Array, memory: int = 10) -> String:
	if pool.is_empty():
		return ""
	var fresh: Array = []
	for line in pool:
		if not recent_lines.has(line):
			fresh.append(line)
	var src: Array = fresh if not fresh.is_empty() else pool
	var line := String(src[rng.randi_range(0, src.size() - 1)])
	recent_lines.append(line)
	while recent_lines.size() > memory:
		recent_lines.remove_at(0)
	return line

func _wrap_bubble(text: String, per_line: int = 13, max_lines: int = 3) -> String:
	var out := ""
	var line := ""
	var width := 0
	var lines := 0
	for i in text.length():
		var ch := text[i]
		var w := 1 if ch.unicode_at(0) < 128 else 2
		if width + w > per_line * 2 and lines < max_lines - 1:
			out += line + "\n"
			line = ""
			width = 0
			lines += 1
		line += ch
		width += w
	return out + line

func _show_bubble(text: String, secs: float, speech: bool, who: String = "") -> void:
	_ensure_bubble()
	var want_kind := "speech" if speech else "thought"
	if bubble_kind != want_kind:
		bubble_kind = want_kind
		bubble.add_theme_stylebox_override("panel", _bubble_style(speech))
	var prefix := "%s：" % who if speech else "%s 在想：" % who
	bubble_label.text = _wrap_bubble(prefix + text)
	bubble_label.add_theme_color_override(
		"font_color",
		Color(0.14, 0.11, 0.08) if speech else Color(0.13, 0.24, 0.44)
	)
	bubble.visible = true
	bubble_t = secs
	await get_tree().process_frame
	if bubble == null or not is_instance_valid(bubble):
		return
	bubble.size = Vector2.ZERO
	await get_tree().process_frame
	if bubble == null or not is_instance_valid(bubble):
		return
	# a little slack, otherwise the last character gets clipped
	var want := bubble.get_combined_minimum_size() + Vector2(10.0, 3.0)
	bubble.size = want
	bubble.position = Vector2(-want.x * 0.5, -art_h - want.y - 14.0)

func _update_bubble(delta: float) -> void:
	if bubble_t > 0.0:
		bubble_t -= delta
		if bubble_t <= 0.0 and bubble != null:
			bubble.visible = false
	if bubble != null and bubble.visible:
		bubble.modulate.a = clampf(bubble_t * 2.5, 0.0, 1.0)

# ---------- plans ----------

func run_plan(ops: Array, done: Callable = Callable()) -> void:
	plan = ops.duplicate()
	plan_i = 0
	plan_done = done
	wait_t = 0.0
	busy = false
	talking_to = null
	_start_op()

func cancel_plan() -> void:
	plan = []
	plan_i = 0
	plan_done = Callable()
	build_site = null
	path = []
	busy = false
	swimming = false
	fishing = false
	sitting = false
	carry_kind = ""
	speed_mult = 1.0
	anim_mode = "stand"
	activity = "在原地发呆"
	state = "idle"
	_apply_position()

func plan_active() -> bool:
	return plan_i < plan.size()

func _cur_op():
	if plan_i < 0 or plan_i >= plan.size():
		return null
	return plan[plan_i]

func _next() -> void:
	plan_i += 1
	_guard += 1
	if _guard > 64:
		_guard = 0
		_finish_plan()
		return
	if plan_i >= plan.size():
		_finish_plan()
		return
	_start_op()

func _finish_plan() -> void:
	plan = []
	plan_i = 0
	build_site = null
	activity = "在原地发呆"
	anim_mode = "stand"
	state = "idle"
	carry_kind = ""
	var cb := plan_done
	plan_done = Callable()
	if cb.is_valid():
		cb.call()

func _start_op() -> void:
	var op = _cur_op()
	if op == null:
		_finish_plan()
		return
	match String(op.get("op", "")):
		"goto", "goto_near":
			var cell: Vector2 = op["cell"]
			work_target = cell
			var near := String(op.get("op", "")) == "goto_near"
			path = _path_to(cell, near)
			state = "walk"
			anim_mode = "walk"
			activity = "赶路（去 %d,%d）" % [int(cell.x), int(cell.y)]
			if path.is_empty():
				# already standing there, or the spot became unreachable
				_next()
		"work":
			# _process already multiplies dt by the time scale, so the seconds in
			# the plan stay real seconds and only get divided by the work rate
			wait_t = float(op.get("secs", 2.0)) / maxf(0.2, work_rate)
			anim_mode = "work"
			state = "work"
			activity = String(op.get("what", "正在干活"))
			if has_work_target():
				face_cell(work_target)
			play_work()
		"wait":
			wait_t = float(op.get("secs", 1.0))
			anim_mode = String(op.get("anim", "stand"))
			state = "wait"
			activity = String(op.get("what", activity))
		"talk":
			wait_t = float(op.get("secs", 2.0)) / maxf(0.2, time_scale)
			anim_mode = "stand"
			state = "talk"
			activity = String(op.get("what", "正在聊天"))
			if op.has("cell"):
				face_cell(op["cell"])
		"say":
			say(String(op.get("text", "")), float(op.get("secs", 2.6)))
			_next()
		"think":
			say_thought(String(op.get("text", "")), float(op.get("secs", 3.4)))
			_next()
		"carry":
			carry_kind = String(op.get("kind", ""))
			anim_mode = "walk" if carry_kind == "" else "carry"
			_next()
		"anim":
			anim_mode = String(op.get("mode", "stand"))
			_next()
		"face":
			face_cell(op["cell"])
			_next()
		"swim":
			swimming = bool(op.get("on", true))
			_apply_position()
			_next()
		"fish":
			fishing = bool(op.get("on", true))
			_next()
		"sit":
			sitting = bool(op.get("on", true))
			_apply_position()
			anim_mode = "idle" if sitting else "stand"
			_next()
		"hide":
			inside_home = true
			visible = false
			activity = "在屋里"
			_next()
		"show":
			inside_home = false
			visible = true
			_next()
		"call":
			var fn: Callable = op["fn"]
			if fn.is_valid():
				fn.call()
			_next()
		"speed":
			speed_mult = float(op.get("mult", 1.0))
			_next()
		"activity":
			activity = String(op.get("text", activity))
			_next()
		"loop":
			plan_i = int(op.get("to", 0))
			_guard += 1
			if _guard > 64:
				_guard = 0
				_finish_plan()
				return
			_start_op()
		_:
			_next()

func play_work() -> void:
	frame_i = 0
	anim_t = 0.0

func _anim_frames(mode: String) -> Array:
	var bank_key := mode
	if mode == "walk" and carry_kind != "":
		bank_key = "carry"
	var table: Dictionary = bank.get(bank_key, {})
	return table.get(dir, [])

func has_work_target() -> bool:
	return work_target.x >= 0.0 or work_target.y >= 0.0

# compatibility helpers used by the town director
func go_to(cell: Vector2, cb: Callable = Callable()) -> void:
	run_plan([{"op": "goto", "cell": cell}, {"op": "call", "fn": cb}])

func release() -> void:
	cancel_plan()

func assign(cell: Vector2, duration: float, cb: Callable) -> void:
	run_plan([
		{"op": "goto_near", "cell": cell},
		{"op": "face", "cell": cell},
		{"op": "work", "secs": duration, "what": "正在采集"},
		{"op": "call", "fn": cb},
	])

func face_cell(cell: Vector2) -> void:
	var d := cell - grid_pos
	if d.length() < 0.01:
		return
	_face_travel((d.x - d.y) * HW, (d.x + d.y) * HH)

func add_friend(other: String, amount: float) -> float:
	var cur := float(friends.get(other, 0.0))
	cur = clampf(cur + amount, 0.0, 100.0)
	friends[other] = cur
	return cur

func friendship(other: String) -> float:
	return float(friends.get(other, 0.0))

# ---------- per-frame ----------

func _process(delta: float) -> void:
	_update_bubble(delta)
	mood += (mood_target - mood) * minf(1.0, delta * 0.08)
	if jitter > 0.0:
		jitter = maxf(0.0, jitter - delta)
		_apply_position()
	if hop > 0.0:
		hop += delta
		_apply_position()
	if breakthrough_flash > 0.0:
		breakthrough_flash = maxf(0.0, breakthrough_flash - delta)
		self_modulate = Color(1.0, 1.0, 0.85).lerp(Color.WHITE, 1.0 - breakthrough_flash)
	if (sleeping or inside_home) and plan.is_empty():
		texture = _idle_frame()
		_sync_item()
		return
	var dt := delta * time_scale
	if cultivating_vis:
		var fxc = _fx()
		if fxc != null:
			fxc.aura(get_instance_id(), position, realm)
	if fishing:
		_tick_fishing(delta)
	if swimming:
		_tick_swim(delta)
	if plan.is_empty():
		_tick_idle_anim(delta)
		_sync_item()
		return
	_run_op(dt, delta)
	_sync_item()

func _run_op(dt: float, delta: float) -> void:
	var op = _cur_op()
	if op == null:
		_finish_plan()
		return
	match String(op.get("op", "")):
		"goto", "goto_near":
			if path.is_empty():
				_next()
				return
			var wp: Vector2 = path[0]
			if (wp - grid_pos).length() < 0.08:
				path.remove_at(0)
				if path.is_empty():
					_next()
				return
			var i := int(wp.y) * map_w + int(wp.x)
			if i >= 0 and i < blocked_cells.size() and blocked_cells[i]:
				# somebody built on our route; look for another way round
				var target: Vector2 = op["cell"]
				path = _path_to(target, String(op["op"]) == "goto_near")
				if path.is_empty():
					_next()
				return
			_step(dt, wp)
			_tick_anim(delta, "walk")
		"work":
			wait_t -= dt
			if wait_t <= 0.0:
				_next()
			else:
				_tick_anim(delta, "work")
		"talk":
			wait_t -= dt
			if wait_t <= 0.0:
				_next()
		"wait":
			wait_t -= dt
			if wait_t <= 0.0:
				_next()
			elif anim_mode == "work":
				_tick_anim(delta, "work")

func _tick_idle_anim(delta: float) -> void:
	var frames: Array = bank.get("idle", {}).get(dir, [])
	if frames.is_empty():
		var still = bank.get("stand", {}).get(dir, texture)
		frames = [still]
	if frames.is_empty():
		return
	anim_t += delta
	if anim_t >= ANIM_STEP * 4.0:
		anim_t = 0.0
		frame_i = (frame_i + 1) % frames.size()
	texture = frames[clampi(frame_i, 0, frames.size() - 1)]

func _tick_anim(delta: float, mode: String) -> void:
	var frames := _anim_frames(mode)
	if frames.is_empty():
		var still = bank.get("stand", {}).get(dir, texture)
		frames = [still] if still != null else []
	if frames.is_empty():
		return
	anim_t += delta
	var step := ANIM_STEP
	if mode == "work":
		step = ANIM_STEP * 0.85
	if anim_t >= step:
		anim_t = 0.0
		if mode == "stand":
			frame_i = 0
		else:
			frame_i = (frame_i + 1) % frames.size()
	texture = frames[clampi(frame_i, 0, frames.size() - 1)]

func _idle_frame() -> Texture2D:
	var frames: Array = bank.get("idle", {}).get(dir, [])
	if frames.is_empty():
		return bank.get("stand", {}).get(dir, texture)
	return frames[0]

func _tick_fishing(delta: float) -> void:
	var fxc = _fx()
	if fxc != null:
		var water: Vector2 = work_target
		if not has_work_target():
			water = grid_pos + Vector2(0, 1)
		var from := position + Vector2(0, -6)
		var to := Vector2((water.x - water.y) * HW, (water.x + water.y) * HH + HH)
		fxc.fish_line(get_instance_id(), from, to)
	_tick_anim(delta * 5.0, "cast")

func _tick_swim(delta: float) -> void:
	if rng.randf() < delta * 2.2:
		var fxc = _fx()
		if fxc != null:
			fxc.ripple(position + Vector2(randf_range(-8.0, 8.0), 2.0), 14.0)

func _fx():
	var w := get_parent()
	while w != null and not ("fx" in w):
		w = w.get_parent()
	return w.fx if w != null else null

# ---------- movement ----------

func _set_dir(d: int, flip: bool) -> void:
	dir = d
	flip_h = flip

func _face_travel(vx: float, vy: float) -> void:
	var ax := absf(vx)
	var ay := absf(vy)
	if ax <= ay * 0.45:
		_set_dir(0 if vy < 0.0 else 4, false)
	elif ay <= ax * 0.45:
		_set_dir(2, vx > 0.0)
	elif vy < 0.0:
		_set_dir(1, vx > 0.0)
	else:
		_set_dir(3, vx > 0.0)

func _apply_position() -> void:
	var p := Vector2((grid_pos.x - grid_pos.y) * HW, (grid_pos.x + grid_pos.y) * HH + HH)
	if swimming:
		p.y += 9.0
	if sitting:
		p.y += 2.0
	if jitter > 0.0:
		p += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.5, 1.5))
	if hop > 0.0:
		p.y -= absf(sin(hop * 9.0)) * 7.0
	position = p

func _step(dt: float, tgt: Vector2) -> void:
	var d := (tgt - grid_pos)
	if d.length() < 0.001:
		return
	var v := d.normalized()
	_face_travel((v.x - v.y) * HW, (v.x + v.y) * HH)
	# never step *past* the waypoint: at 4x speed a single frame could otherwise
	# fly right over it and the villager would jitter back and forth for ever
	var step_len := _speed_here() * dt
	if step_len >= d.length():
		grid_pos = tgt
	else:
		grid_pos += v * step_len
	_apply_position()

func _speed_here() -> float:
	var sp := speed * speed_mult
	if road_cells.is_empty():
		return sp
	var i := int(round(grid_pos.y)) * map_w + int(round(grid_pos.x))
	if i >= 0 and i < road_cells.size() and road_cells[i]:
		return sp * ROAD_SPEED
	return sp

# Breadth-first search over the tile grid.  goal_blocked tells the search that
# the goal tile is taken by a resource or a building, so any free neighbour of
# it will do.
func _path_to(goal: Vector2, goal_blocked: bool) -> Array:
	var start := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.y)))
	var goal_cell := Vector2i(int(floor(goal.x)), int(floor(goal.y)))
	var manhattan := absi(start.x - goal_cell.x) + absi(start.y - goal_cell.y)
	if goal_blocked and manhattan <= 1:
		return []
	if not goal_blocked and start == goal_cell:
		return []
	var seen := {start: true}
	var came := {}
	var queue: Array = [start]
	var found := Vector2i(-1, -1)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if goal_blocked:
			if absi(cur.x - goal_cell.x) + absi(cur.y - goal_cell.y) <= 1:
				found = cur
				break
		elif cur == goal_cell:
			found = cur
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + step
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= map_w or nxt.y >= map_h:
				continue
			if seen.has(nxt):
				continue
			var i := nxt.y * map_w + nxt.x
			if i < 0 or i >= blocked_cells.size():
				continue
			if blocked_cells[i]:
				continue
			seen[nxt] = true
			came[nxt] = cur
			queue.append(nxt)
	if found.x < 0:
		return []
	var out: Array = []
	var node := found
	while node != start:
		out.push_front(Vector2(node))
		node = came[node]
	return out

# old name kept so the diagnostics in world.gd keep working
func pick_target() -> void:
	path = []
	idle_wait = 0.4
