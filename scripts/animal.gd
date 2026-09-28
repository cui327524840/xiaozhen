extends Sprite2D
# One animal: a sheep, a duck, the dog, the cat, a deer or a boar.
#
# Animals are living decoration.  Each one keeps to a patch around its home,
# walks to a spot on the original game's own walk frames, grazes for a while and
# then picks the next spot.  The farm animals walk back into the pen at night.
# Villagers that get free time can walk up and pet one (see town.gd), which
# makes it hop and gives the villager a little mood.

const HW := 32.0
const HH := 16.0
const ANIM_STEP := 0.15

# art   = folder under res://assets/tt/
# anim  = animation sets keyed by what they are for.  Every set is a file-name
#         prefix; frames are "<prefix>.<number>.png" and get collected by
#         scanning the folder, so the odd 1-digit / 2-digit padding the original
#         game uses does not matter.
# where = what counts as a nice spot: grass, shore, village or wild
# 原版的动物只画了两个"侧后方"朝向，名字里的 1 / 3 对应游戏里的方向编号
# （1 = 背对镜头的侧向，3 = 面朝镜头的侧向），两边都是朝左画的，朝右靠镜像。
# 所以走路时要按"往画面下方走（靠近镜头）用 3、往画面上方走用 1"来挑帧，
# 只按左右挑的话就会出现倒着走、横着走的怪样子。
# faces = 图上画的是朝哪边（羊/狗/猫/鹿/野猪朝左，鸭子朝右）
const SPECIES := {
	"sheep": {
		"name": "羊", "cry": "咩~", "art": "buildings02", "faces": "left",
		"anim": {"toward": "ani_sheepwalk_02", "away": "ani_sheepwalk_00",
			"graze": "ani_sheepwalk_03"},
		"speed": 0.42, "roam": 3, "where": "grass", "shelter": true,
	},
	"duck": {
		"name": "鸭", "cry": "嘎嘎", "art": "chars", "faces": "right",
		"anim": {"toward": "ani_duck_02", "away": "ani_duck_02"},
		"speed": 0.30, "roam": 2, "where": "water", "shelter": false, "dy": 7.0,
	},
	"dog": {
		"name": "狗", "cry": "汪汪", "art": "chars", "faces": "left",
		"anim": {"toward": "dog_walk_3", "away": "dog_walk_1", "graze": "dog_idle"},
		"speed": 0.95, "roam": 5, "where": "village", "shelter": true,
	},
	"cat": {
		"name": "猫", "cry": "喵~", "art": "chars", "faces": "left",
		"anim": {"toward": "cat_walk_3", "away": "cat_walk_1", "graze": "cat_idle"},
		"speed": 0.70, "roam": 4, "where": "village", "shelter": true,
	},
	"deer": {
		"name": "鹿", "cry": "呦呦", "art": "chars", "faces": "left",
		"anim": {"toward": "deer_walk_3", "away": "deer_walk_1", "graze": "deer_idle"},
		"speed": 1.05, "roam": 5, "where": "wild", "shelter": false,
	},
	"boar": {
		"name": "野猪", "cry": "哼哼", "art": "chars", "faces": "left",
		"anim": {"toward": "boar_walk_3", "away": "boar_walk_1", "graze": "boar_idle"},
		"speed": 0.62, "roam": 4, "where": "wild", "shelter": false,
	},
}

# frames are looked up per prefix, once for the whole run: scanning a folder of
# a few thousand files for every animal would be silly
static var _frame_cache := {}
static var _art_cache := {}

var world: Node2D
var species := "sheep"
var kind_name := "羊"
var cry := ""
var bank := {}
var home := Vector2.ZERO
var roam := 5
var where := "grass"
var shelter := false
var walk_speed := 20.0
var dy := 0.0
var rng := RandomNumberGenerator.new()

var grid_pos := Vector2.ZERO
var target := Vector2.ZERO
var state := "graze"          # walk / graze / rest
var state_t := 2.0
var anim_t := 0.0
var frame_i := 0
var facing_left := false
var moving_toward := true     # 往画面下方走（靠近镜头）用"正面"那套帧
var art_faces := "left"       # 图上这条腿是朝哪边画的
var hop := 0.0
var petted := 0
var in_shelter := false

# ---------------------------------------------------------------- frame banks

static func _folder_files(folder: String) -> Array:
	if _art_cache.has(folder):
		return _art_cache[folder]
	var out: Array = []
	var dir := DirAccess.open(folder)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".png"):
				out.append(f)
	_art_cache[folder] = out
	return out

static func _frames(folder: String, prefix: String) -> Array:
	var key := folder + "|" + prefix
	if _frame_cache.has(key):
		return _frame_cache[key]
	var found: Array = []
	for f in _folder_files(folder):
		if not f.begins_with(prefix + "."):
			continue
		var num: String = f.substr(prefix.length() + 1)
		num = num.substr(0, num.length() - 4)
		if num.is_valid_int():
			found.append({"n": int(num), "f": String(f)})
	found.sort_custom(func(a, b): return int(a["n"]) < int(b["n"]))
	var out: Array = []
	for e in found:
		out.append(load(folder + String(e["f"])))
	_frame_cache[key] = out
	return out

# --------------------------------------------------------------------- set up

func setup(w: Node2D, sp: String, cell: Vector2) -> void:
	world = w
	species = sp
	var s: Dictionary = SPECIES.get(sp, SPECIES["sheep"])
	kind_name = String(s["name"])
	cry = String(s.get("cry", ""))
	roam = int(s["roam"])
	where = String(s["where"])
	shelter = bool(s.get("shelter", false))
	walk_speed = float(s["speed"])
	art_faces = String(s.get("faces", "left"))
	dy = float(s.get("dy", 0.0))
	var folder := "res://assets/tt/%s/" % String(s["art"])
	bank = {}
	for k in (s["anim"] as Dictionary).keys():
		bank[k] = _frames(folder, String(s["anim"][k]))
	grid_pos = cell
	home = cell
	target = cell
	rng.seed = hash(sp) + int(cell.x) * 7919 + int(cell.y) * 104729
	state = "graze"
	state_t = rng.randf_range(1.0, 5.0)
	_apply_position()
	_use("graze")

# ------------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	if world == null or not world.world_started:
		return
	tick(delta)

func tick(dt: float) -> void:
	if world == null:
		return
	_fix_if_wet()
	if hop > 0.0:
		hop = maxf(0.0, hop - dt)
	if shelter and world.is_night():
		_tick_night(dt)
		_apply_position()
		return
	if in_shelter:
		in_shelter = false
	visible = true
	state_t -= dt
	match state:
		"walk":
			_walk(dt)
		"graze":
			anim_t += dt * 0.6
			_use("graze")
			if state_t <= 0.0:
				_pick_spot()
	if hop > 0.0:
		_apply_position()

# 万一站进水里了（比如出生点旁边刚好是水），自己挪回岸上，别一直泡着
func _fix_if_wet() -> void:
	if world == null or where == "water":
		return
	var c := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.y)))
	if not world._inside(c.x, c.y):
		return
	if String(world.terrain[world._idx(c.x, c.y)]) != "water":
		return
	var spot: Vector2i = world.animal_spot(c, 5, "grass", self)
	if spot.x >= 0:
		grid_pos = Vector2(spot)
		home = Vector2(spot)
	else:
		grid_pos = world._free_cell_near(Vector2(c), 6.0)
		home = grid_pos
	_apply_position()

# farm animals head home when it gets dark and sleep there until morning
func _tick_night(dt: float) -> void:
	if in_shelter:
		visible = false
		return
	if grid_pos.distance_to(home) < 0.35:
		in_shelter = true
		visible = false
		state = "graze"
		return
	target = home
	state = "walk"
	_walk(dt)

func _walk(dt: float) -> void:
	var d := target - grid_pos
	if d.length() < 0.02:
		grid_pos = target
		state = "graze"
		state_t = rng.randf_range(5.0, 14.0)
		anim_t = 0.0
		_apply_position()
		return
	var v := d.normalized()
	_set_facing((v.x - v.y) * HW, (v.x + v.y) * HH)
	var scale: float = world.time_scale() if world != null else 1.0
	var step: float = walk_speed * dt * scale
	if step >= d.length():
		grid_pos = target
	else:
		grid_pos += v * step
	anim_t += dt * 1.6
	_use("walk")
	_apply_position()

func _pick_spot() -> void:
	var spot := Vector2i(-1, -1)
	if world != null:
		spot = world.animal_spot(Vector2i(round(home.x), round(home.y)), roam, where, self)
	if spot.x < 0:
		# nowhere free nearby: just keep grazing where we are
		state = "graze"
		state_t = rng.randf_range(1.5, 4.0)
		return
	target = Vector2(spot)
	state = "walk"
	anim_t = 0.0

# ------------------------------------------------------------------- animation

func _set_facing(dx: float, dy: float) -> void:
	if absf(dx) > 0.01:
		facing_left = dx < 0.0
	if absf(dy) > 0.01:
		# 画面 y 变大 = 朝镜头走；用对的那一套（正面/背面）
		moving_toward = dy > 0.0

func _use(kind: String) -> void:
	var arr: Array = []
	if kind == "walk":
		# 先按"走近/走远"挑一套，缺了就退回另一套
		var want := "toward" if moving_toward else "away"
		var other := "away" if moving_toward else "toward"
		arr = bank.get(want, [])
		if arr.is_empty():
			arr = bank.get(other, [])
	else:
		arr = bank.get("graze", [])
	if arr.is_empty():
		arr = _any_frames()
	if arr.is_empty():
		return
	# 图上是朝左画的，人要往右走就镜像；鸭子是朝右画的，反过来
	var art_left: bool = art_faces == "left"
	flip_h = facing_left != art_left
	frame_i = int(anim_t / ANIM_STEP) % arr.size()
	var tex: Texture2D = arr[clampi(frame_i, 0, arr.size() - 1)]
	if tex == null:
		return
	if tex == texture:
		return
	texture = tex
	_measure_art(tex)

# a species that only ships one animation (the duck) still has to be visible
func _any_frames() -> Array:
	for k in bank.keys():
		var arr: Array = bank[k]
		if not arr.is_empty():
			return arr
	return []

# anchor the drawn body's bottom centre on the node origin, exactly like the
# villagers do, so an animal stands *on* its tile instead of floating
func _measure_art(tex: Texture2D) -> void:
	var key := "off|" + tex.resource_path
	if _frame_cache.has(key):
		offset = _frame_cache[key]
		return
	var img := tex.get_image()
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var size := Vector2(img.get_width(), img.get_height())
	var ax := float(used.position.x) + float(used.size.x) * 0.5
	var ay := float(used.position.y + used.size.y)
	var off := Vector2(size.x * 0.5 - ax, size.y * 0.5 - ay)
	_frame_cache[key] = off
	offset = off

func _apply_position() -> void:
	var p := Vector2((grid_pos.x - grid_pos.y) * HW, (grid_pos.x + grid_pos.y) * HH + HH)
	p.y += dy
	if hop > 0.0:
		p.y -= absf(sin(hop * 9.0)) * 6.0
	position = p

# -------------------------------------------------------------------- petting

# called by the town director when a villager walks over to say hello
func pet() -> void:
	petted += 1
	hop = 0.8
	state = "graze"
	state_t = maxf(state_t, 3.0)
	if world == null or world.fx == null:
		return
	var fxc = world.fx
	fxc.float_text(position + Vector2(0, -22), "❤", Color(1.0, 0.60, 0.70))
	if cry != "":
		fxc.float_text(position + Vector2(0, -32), cry, Color(1.0, 0.98, 0.88))

# ----------------------------------------------------------------- save / load

func snapshot() -> Dictionary:
	return {"species": species, "x": grid_pos.x, "y": grid_pos.y}
