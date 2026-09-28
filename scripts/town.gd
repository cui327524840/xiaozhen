extends Node2D
# The town director.
#
# world.gd owns the map, the buildings and the clock; this script owns the
# people.  Every villager that has nothing to do is handed a plan here, so the
# town always looks like it is being lived in: somebody chops wood, somebody
# hauls the logs to the warehouse, somebody carries the harvest in, somebody
# fishes at the lake, somebody sits in the market square - and at night they
# walk into their own house and are really gone until morning.

const WORK_START := 7.0
const WORK_END := 19.0
const MEAL_START := 12.0
const MEAL_END := 13.0
const SLEEP_HOUR := 22.0
const WAKE_HOUR := 6.0
const FIRE_HOUR := 19.6
const FIRE_EVERY := 3
const MEAL_LENGTH := 4.0

const SEASON_NAMES := ["春天", "夏天", "秋天", "冬天"]
const SEASON_LENGTH := 8          # game days per season

# 渡劫不能随时来：只有夜里那两个时辰引得到天雷，失败之后还要等几天
const TRIBULATION_START := 21.0
const TRIBULATION_END := 23.0
const TRIBULATION_COOLDOWN_DAYS := 3

# 《仙逆》 style ladder: 练气 → 筑基 → 结丹 → 元婴 → 化神 → 婴变 → 问鼎 …
const REALMS := [
	{"name": "练气期", "layers": 9, "need": 34.0},
	{"name": "筑基期", "layers": 9, "need": 68.0},
	{"name": "结丹期", "layers": 3, "need": 120.0},
	{"name": "元婴期", "layers": 3, "need": 190.0},
	{"name": "化神期", "layers": 1, "need": 300.0},
	{"name": "婴变期", "layers": 1, "need": 430.0},
	{"name": "问鼎期", "layers": 1, "need": 600.0},
	{"name": "阴虚境", "layers": 1, "need": 820.0},
	{"name": "阳实境", "layers": 1, "need": 1100.0},
]

const TRAIT_POOL := [
	"勤劳", "懒散", "开朗", "内向", "贪吃", "急性子", "慢性子",
	"爱干净", "爱热闹", "爱读书", "爱喝酒", "爱钓鱼",
]

var world: Node2D
var fx: Node2D

var tick := 0.0
var job_tick := 0.0
var season := 0
var season_day := 0
var fire_night := false
var fire_cell := Vector2i(-1, -1)
var fire_day := -99
var chatter := {}        # villager -> seconds of "no chatting" left
var thought_cd := {}     # villager -> seconds until the next thought
var meal_done := {}      # villager -> day number of the last lunch
var last_day := 1
var events := []         # recent town events, shown in the panel

# 统计用（-- --debug-life）：跑一段之后看看村民到底干了多少种事
var debug_stats := false
var stats := {}

func _note(kind: String) -> void:
	if debug_stats:
		stats[kind] = int(stats.get(kind, 0)) + 1

func stats_report() -> String:
	var parts: Array = []
	for k in stats.keys():
		parts.append("%s×%d" % [String(k), int(stats[k])])
	return "，".join(parts) if not parts.is_empty() else "（还没有人休息过）"

func setup(w: Node2D) -> void:
	world = w
	fx = w.fx

func _process(delta: float) -> void:
	if world == null or not world.world_started:
		return
	var ts: float = world.time_scale()
	tick += delta * ts
	job_tick += delta * ts
	_count_down(chatter, delta * ts)
	_count_down(thought_cd, delta * ts)
	_calendar()
	if tick >= 0.7:
		tick = 0.0
		for v in world._live_villagers():
			_step_villager(v)
		_meetings()
		_thoughts()
		_campfire_tick()
		_cultivation_glow()
	if job_tick >= 8.0:
		job_tick = 0.0
		_assign_jobs()
		_assign_homes()

func _count_down(d: Dictionary, delta: float) -> void:
	for k in d.keys():
		d[k] = float(d[k]) - delta
		if float(d[k]) <= 0.0:
			d.erase(k)

func log_event(text: String) -> void:
	events.push_front(text)
	while events.size() > 6:
		events.pop_back()

# ---------------------------------------------------------------- calendar

func _calendar() -> void:
	if world.day_number == last_day:
		return
	last_day = world.day_number
	season_day += 1
	if fire_night and world.hour >= WAKE_HOUR:
		fire_night = false
	if season_day >= SEASON_LENGTH:
		season_day = 0
		season = (season + 1) % 4
		world.on_season_changed(season)
		log_event("%s到了" % SEASON_NAMES[season])

func season_name() -> String:
	return SEASON_NAMES[season]

func is_work_time() -> bool:
	var h: float = world.hour
	return h >= WORK_START and h < WORK_END

func is_meal_time() -> bool:
	var h: float = world.hour
	return h >= MEAL_START and h < MEAL_END

func _hungry(v) -> bool:
	return world.food < 30.0 or v.mood < 45.0 or int(meal_done.get(v.pname, -1)) != world.day_number

# ---------------------------------------------------------------- the day

func _step_villager(v) -> void:
	v.mood_target = world.happiness
	# safety net: a villager can get walled in by a new building or a felled
	# tree that grew back around him - walk him back to the village centre
	if _enclosed(v):
		v.grid_pos = world._free_cell_near(Vector2(world.cross_cell), 6.0)
		v.cancel_plan()
		return
	if v.child:
		if v.is_idle():
			v.run_plan(_child_plan(v))
		return
	if v.inside_home:
		if v.is_idle():
			# only come back out in the morning - otherwise they would pop out
			# again the moment they stepped inside
			if world.hour >= WAKE_HOUR and world.hour < SLEEP_HOUR:
				v.sleeping = false
				v.run_plan(_wake_plan(v))
		return
	if world.hour >= SLEEP_HOUR or world.hour < WAKE_HOUR:
		if v.is_idle():
			v.run_plan(_sleep_plan(v))
		return
	if fire_night and v.is_idle() and not v.sitting:
		v.run_plan(_fire_plan(v))
		return
	if v.sitting and v.is_idle():
		if world.hour >= SLEEP_HOUR or not fire_night:
			v.run_plan([{"op": "sit", "on": false}, {"op": "say", "text": v.pick(["火快灭了，回屋睡吧", "今晚聊得真痛快"])}])
		else:
			# keep chatting around the fire
			v.run_plan(_fire_chat_plan(v))
		return
	if not v.is_idle():
		return
	# --- something to do ---
	if is_meal_time() and _hungry(v) and v.home_cell.x >= 0:
		meal_done[v.pname] = world.day_number
		v.run_plan(_meal_plan(v))
		return
	if v.pending_tribulation:
		# 渡劫要等时辰：夜里 21:00-23:00 才引得到天雷
		if tribulation_ready(v):
			v.pending_tribulation = false
			v.run_plan(_tribulation_plan(v))
		else:
			v.pending_tribulation = false
			v.run_plan([
				{"op": "activity", "text": "修为已满，等时辰渡劫"},
				{"op": "think", "text": v.pick([
					"修为满了，得等到夜里子时前后才能渡劫",
					"天雷不是随时都有的，再等等",
					"这几日先稳住气机，莫要急躁"])},
			])
		return
	if v.cultivate and cultivation_place().x >= 0:
		v.run_plan(_cultivate_plan(v))
		return
	if is_work_time():
		var work := _work_plan(v)
		if not work.is_empty():
			_note("干活")
			v.run_plan(work)
			return
	v.run_plan(_leisure_plan(v))

func _enclosed(v) -> bool:
	var c := Vector2i(int(round(v.grid_pos.x)), int(round(v.grid_pos.y)))
	if not world._inside(c.x, c.y):
		return true
	for s in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if world.walkable(c.x + s.x, c.y + s.y):
			return false
	return true

# ---------- sleeping, waking, eating ----------

func _home_spot(v) -> Vector2:
	if v.home_cell.x < 0:
		return world._free_cell_near(Vector2(world.cross_cell), 6.0)
	return Vector2(v.home_cell)

func _sleep_plan(v) -> Array:
	return [
		{"op": "say", "text": v.pick(_night_lines(v)), "secs": 2.4},
		{"op": "goto", "cell": _home_spot(v)},
		{"op": "face", "cell": Vector2(v.home_cell)},
		{"op": "hide"},
		{"op": "call", "fn": func() -> void: v.sleeping = true},
	]

func _wake_plan(v) -> Array:
	return [
		{"op": "show"},
		{"op": "activity", "text": "刚起床"},
		{"op": "say", "text": v.pick(_morning_lines(v)), "secs": 2.6},
		{"op": "goto", "cell": world._free_cell_near(_home_spot(v), 3.0)},
	]

func _meal_plan(v) -> Array:
	return [
		{"op": "activity", "text": "回家吃午饭"},
		{"op": "goto", "cell": _home_spot(v)},
		{"op": "anim", "mode": "sit"},
		{"op": "say", "text": v.pick(["先吃口饭，下午接着干", "今天的饭真香", "歇口气再干活"]), "secs": 2.4},
		{"op": "wait", "secs": MEAL_LENGTH},
		{"op": "anim", "mode": "stand"},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 4.0)
			world.food = maxf(0.0, world.food - 1.0)
			world._refresh_hud()},
	]

# ---------- construction ----------

func _build_plan_for(v, site) -> Array:
	if not _site_alive(site):
		return []
	# 记住自己在给哪个工地干活：工地一完工，_finish_site 会把大家当场叫停
	v.build_site = site
	var ops: Array = [{"op": "carry", "kind": ""}]
	var wh: Vector2i = world.warehouse_cell()
	if wh.x >= 0 and site.progress < 0.9 and rng_roll(0.65):
		ops.append({"op": "activity", "text": "去仓库取木料"})
		ops.append({"op": "goto", "cell": world.random_spot_near(Vector2(wh), 2.0)})
		ops.append({"op": "work", "secs": 1.6, "what": "在仓库取木料"})
		ops.append({"op": "carry", "kind": "wood"})
		# 他去仓库的这段时间里，房子可能已经被别人盖好了：那就别再把料扛过去
		ops.append({"op": "call", "fn": func() -> void: _drop_build_load(v, site)})
	ops.append({"op": "goto_near", "cell": Vector2(site.cell)})
	ops.append({"op": "call", "fn": func() -> void: _drop_build_load(v, site)})
	ops.append({"op": "face", "cell": Vector2(site.cell)})
	ops.append({"op": "activity", "text": "在盖房子"})
	var phase: String = site.phase_text()
	if phase == "挖地基":
		ops.append({"op": "work", "secs": 4.0, "what": "正在挖地基"})
	else:
		ops.append({"op": "work", "secs": 4.0, "what": "正在%s" % phase})
	ops.append({"op": "call", "fn": func() -> void:
		# another builder may have finished the job while this one was walking
		if not is_instance_valid(site) or site.progress >= 1.0:
			return
		site.poke()
		var done: bool = site.add_progress(0.11 if v.work_rate < 1.2 else 0.15)
		world._refresh_hud()
		if done:
			world._finish_site(site)})
	ops.append({"op": "carry", "kind": ""})
	return ops

func _site_alive(site) -> bool:
	return is_instance_valid(site) and site.progress < 1.0

# 工地已经完工：手里的木料放下，人停在原地（别再走到一栋盖好的房子前面去）
func _drop_build_load(v, site) -> void:
	if _site_alive(site):
		return
	v.cancel_plan()

# 房子盖好时由 world._finish_site 调：所有还在给这个工地干活的人当场收工。
# 返回被叫停的人数（诊断用）。
func abort_build_plans(site) -> int:
	var stopped := 0
	for v in world._live_villagers():
		if is_instance_valid(v) and v.build_site == site:
			v.cancel_plan()
			stopped += 1
	return stopped

func rng_roll(p: float) -> bool:
	return world.rng.randf() < p

func next_site() -> Node:
	var best: Node = null
	for s in world.sites:
		if not is_instance_valid(s) or s.progress >= 1.0:
			continue
		if best == null:
			best = s
		elif s.progress < best.progress:
			best = s
	return best

# ---------- jobs ----------

func _work_plan(v) -> Array:
	var site: Node = next_site()
	if site != null and rng_roll(0.85):
		v.job = v.job if v.job != "none" else "build"
		return _build_plan_for(v, site)
	# 村里快见底的时候先别管本职，先去把缺口补上，不然就卡住不发展了
	var urgent := worst_need()
	if float(urgent[1]) > 0.7 and String(urgent[0]) != job_resource(v.job):
		var urgent_plan := _work_for_need(v, String(urgent[0]))
		if not urgent_plan.is_empty():
			return urgent_plan
	match v.job:
		"lumber":
			var p := _harvest_plan(v, "wood")
			if not p.is_empty():
				return p
		"quarry":
			var p2 := _harvest_plan(v, "stone")
			if not p2.is_empty():
				return p2
		"farm":
			var p3 := _farm_plan(v)
			if not p3.is_empty():
				return p3
		"fish":
			var p4 := _fish_plan(v)
			if not p4.is_empty():
				return p4
		"trade":
			var p5 := _stall_plan(v)
			if not p5.is_empty():
				return p5
		"herb":
			var p6 := _herb_plan(v)
			if not p6.is_empty():
				return p6
		"build":
			if site != null:
				return _build_plan_for(v, site)
	# nothing matched: help somewhere useful
	return _odd_job(v)

func _odd_job(v) -> Array:
	# 没活干的人去看村里最缺什么：木料、石料还是吃的
	var needs := need_scores()
	var order: Array = ["wood", "stone", "food"]
	order.sort_custom(func(a, b): return float(needs[a]) > float(needs[b]))
	for res in order:
		var p := _work_for_need(v, String(res))
		if not p.is_empty():
			return p
	return []

# 村里现在最缺什么：分数越高越急（0 = 够用，1 = 见底）
func need_scores() -> Dictionary:
	var want_wood := 90.0 + float(world.buildings.size()) * 6.0
	var want_stone := 70.0 + float(world.buildings.size()) * 5.0
	var want_food := 45.0 + float(world.population) * 9.0
	return {
		"wood": clampf(1.0 - float(world.wood) / want_wood, 0.0, 1.5),
		"stone": clampf(1.0 - float(world.stone) / want_stone, 0.0, 1.5),
		"food": clampf(1.0 - float(world.food) / want_food, 0.0, 1.5),
	}

func worst_need() -> Array:
	var needs := need_scores()
	var best := ""
	var best_v := 0.0
	for k in ["wood", "stone", "food"]:
		if float(needs[k]) > best_v:
			best_v = float(needs[k])
			best = String(k)
	return [best, best_v]

# 某个工种平时在产出什么，用于判断"要不要放下本职去救急"
func job_resource(job: String) -> String:
	match job:
		"lumber":
			return "wood"
		"quarry":
			return "stone"
		"farm", "fish", "herb":
			return "food"
	return ""

func _work_for_need(v, res: String) -> Array:
	match res:
		"wood":
			return _harvest_plan(v, "wood")
		"stone":
			return _harvest_plan(v, "stone")
		"food":
			var p: Array = _farm_plan(v)
			if p.is_empty():
				p = _fish_plan(v)
			if p.is_empty():
				p = _stall_plan(v)
			return p
	return []

func _nearest_resource(kind: String, from: Vector2) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for r in world.resources:
		if int(r["hits"]) <= 0 or bool(r.get("busy", false)):
			continue
		if String(r["resource"]) != kind:
			continue
		var d: float = Vector2(r["cell"]).distance_to(from)
		if d < best_d:
			best_d = d
			best = r
	return best

func _harvest_plan(v, kind: String) -> Array:
	var r: Dictionary = _nearest_resource(kind, v.grid_pos)
	if r.is_empty():
		return []
	r["busy"] = true
	var hits := int(r["hits"])
	var acc := [0.0]
	var ops: Array = [{"op": "carry", "kind": ""}]
	ops.append({"op": "goto_near", "cell": Vector2(r["cell"])})
	ops.append({"op": "face", "cell": Vector2(r["cell"])})
	var what := "正在砍树" if kind == "wood" else "正在采石"
	ops.append({"op": "activity", "text": what})
	for i in maxi(1, hits):
		ops.append({"op": "work", "secs": 3.0, "what": what})
	ops.append({"op": "call", "fn": func() -> void:
		for i in maxi(1, hits):
			var got: Dictionary = world.take_harvest(r)
			acc[0] += float(got.get("gain", 0.0))})
	var wh: Vector2i = world.warehouse_cell()
	if wh.x >= 0:
		ops.append({"op": "carry", "kind": kind})
		ops.append({"op": "activity", "text": "把货搬去仓库"})
		ops.append({"op": "goto", "cell": wh})
		ops.append({"op": "work", "secs": 1.8, "what": "正在卸货"})
		ops.append({"op": "call", "fn": func() -> void:
			world.grant(kind, acc[0] * 0.45, v.grid_pos)
			r["busy"] = false})
		ops.append({"op": "carry", "kind": ""})
	else:
		ops.append({"op": "call", "fn": func() -> void:
			world.grant(kind, acc[0] * 0.45, v.grid_pos)
			r["busy"] = false})
	return ops

func _farm_plan(v) -> Array:
	var field: Dictionary = world.next_ripe_field()
	if not field.is_empty():
		var cell: Vector2 = field["cell"]
		# 先"认领"这块田（别人不会再抢），等真的割完那一刻田里才矮下去。
		# 认领用的是 busy，不是把 ripe 抹掉——抹掉的话下一步 _grow_fields 会
		# 马上把它标成"熟了"，第二个人又会跑来割同一格。
		world.claim_field(field)
		var acc := [0.0]
		var ops: Array = [{"op": "carry", "kind": ""}]
		ops.append({"op": "goto_near", "cell": cell})
		ops.append({"op": "face", "cell": cell})
		ops.append({"op": "activity", "text": "在收庄稼"})
		for i in 3:
			ops.append({"op": "work", "secs": 2.4, "what": "正在收庄稼"})
		ops.append({"op": "call", "fn": func() -> void:
			# 整块田一次割完，所以按格数给粮食（和以前一格一格割的总量一样）
			acc[0] = (5.0 + world.rng.randf() * 3.5) * float(world.plot_cells(field))
			world.harvest_field(field)
			world.fx.burst(world.iso(cell) + Vector2(0, 4),
				Color(0.95, 0.86, 0.42), Color(0.86, 0.70, 0.28), 22, 70.0)
			world.fx.float_text(world.iso(cell) + Vector2(0, 4), "收了 %d 粮食" % int(acc[0]),
				Color(0.98, 0.94, 0.62))})
		var wh: Vector2i = world.warehouse_cell()
		if wh.x >= 0:
			ops.append({"op": "carry", "kind": "crop"})
			ops.append({"op": "activity", "text": "把粮食搬进仓库"})
			ops.append({"op": "goto", "cell": world.random_spot_near(Vector2(wh), 2.0)})
			ops.append({"op": "work", "secs": 2.0, "what": "正在装仓"})
			ops.append({"op": "carry", "kind": ""})
		ops.append({"op": "call", "fn": func() -> void:
			world.grant("food", acc[0], v.grid_pos)})
		return ops
	# no ripe field: weed / water the plots so they grow faster
	var plot: Dictionary = world.next_field()
	if not plot.is_empty():
		var cell2: Vector2 = plot["cell"]
		return [
			{"op": "goto_near", "cell": cell2},
			{"op": "face", "cell": cell2},
			{"op": "activity", "text": "在田里锄草"},
			{"op": "work", "secs": 3.2, "what": "正在锄草"},
			# 锄草也是整块地一起长，不然同一块田会高一块矮一块
			{"op": "call", "fn": func() -> void: world.tend_field(plot)},
			{"op": "think", "text": v.pick(["庄稼快点长吧", "今年收成应该不错", "这块地该上肥了"])},
		]
	return []

func _fish_plan(v) -> Array:
	var spot: Vector2i = world.fishing_spot_near(v.grid_pos)
	if spot.x < 0:
		return []
	var water: Vector2i = world.water_next_to(spot)
	var acc := [0.0]
	var ops: Array = [
		{"op": "carry", "kind": ""},
		{"op": "goto", "cell": Vector2(spot)},
		{"op": "activity", "text": "在湖边钓鱼"},
		{"op": "face", "cell": Vector2(water)},
		{"op": "fish", "on": true},
		# 钓鱼是要等的：抛竿、等鱼咬钩、再收线
		{"op": "wait", "secs": 22.0, "what": "在湖边等鱼咬钩"},
		{"op": "think", "text": v.pick(["水面这么静，鱼还没来", "再等等，快了", "钓鱼最要紧的是耐心"])},
		{"op": "wait", "secs": 14.0, "what": "在湖边等鱼咬钩"},
		{"op": "call", "fn": func() -> void:
			acc[0] = 2.5 + world.rng.randf() * 2.5
			world.fx.splash(world.iso(Vector2(water)) + Vector2(0, 8))
			world.fx.float_text(world.iso(Vector2(water)) + Vector2(0, 6), "+1 鱼",
				Color(0.86, 0.94, 1.0))
			v.mood = minf(100.0, v.mood + 3.0)},
		{"op": "fish", "on": false},
		{"op": "think", "text": v.pick(_fish_lines(v))},
	]
	# 钓上来的鱼要提回仓库才算数
	var wh: Vector2i = world.warehouse_cell()
	if wh.x >= 0:
		ops.append({"op": "carry", "kind": "fish"})
		ops.append({"op": "activity", "text": "把鱼提回仓库"})
		ops.append({"op": "goto", "cell": world.random_spot_near(Vector2(wh), 2.0)})
		ops.append({"op": "work", "secs": 2.2, "what": "正在卸鱼"})
		ops.append({"op": "carry", "kind": ""})
	ops.append({"op": "call", "fn": func() -> void:
		world.grant("food", acc[0], Vector2(spot))})
	return ops

func _stall_plan(v) -> Array:
	var m: Vector2i = world.building_spot("market")
	if m.x < 0:
		m = world.building_spot("tradeguild")
	if m.x < 0:
		return []
	return [
		{"op": "goto", "cell": world.random_spot_near(Vector2(m), 2.0)},
		{"op": "activity", "text": "在市集做生意"},
		{"op": "work", "secs": 5.0, "what": "正在摆摊"},
		{"op": "call", "fn": func() -> void:
			world.gold += 1.5 + v.skill * 0.4
			world.fx.float_text(world.iso(Vector2(m)) + Vector2(0, 2), "+金币",
				Color(1.0, 0.92, 0.55))
			world._refresh_hud()},
		{"op": "say", "text": v.pick(_market_lines(v)), "secs": 2.4},
	]

func _herb_plan(v) -> Array:
	var r: Dictionary = _nearest_resource("wood", v.grid_pos)
	var cell: Vector2 = Vector2(r["cell"]) if not r.is_empty() else world._free_cell_near(v.grid_pos, 6.0)
	return [
		{"op": "goto_near", "cell": cell},
		{"op": "activity", "text": "在采草药"},
		{"op": "work", "secs": 3.4, "what": "正在采药"},
		{"op": "call", "fn": func() -> void:
			world.grant("food", 2.0 + world.rng.randf() * 2.0, v.grid_pos)},
		{"op": "think", "text": v.pick(["这些草药能换点钱", "林子里好东西不少", "晒干了留着过冬"])},
	]

func _child_plan(v) -> Array:
	var spot: Vector2 = world.wander_spot(v.grid_pos)
	var pool := [
		[{"op": "goto", "cell": spot}, {"op": "say", "text": v.pick(_child_lines(v)), "secs": 2.2}],
		[{"op": "goto", "cell": spot}, {"op": "call", "fn": func() -> void: v.hop = 0.01},
			{"op": "wait", "secs": 3.0},
			{"op": "call", "fn": func() -> void: v.hop = 0.0},
			{"op": "think", "text": v.pick(["要是能抓到那只蝴蝶就好了", "爹娘什么时候回来呀", "我长大要当木匠"])}],
	]
	return pool[world.rng.randi_range(0, pool.size() - 1)]

# ---------- free time: market, lake, hiking, travelling ----------

func _leisure_plan(v) -> Array:
	var options: Array = ["stroll", "stroll"]
	if world.lake_any():
		options.append("lake")
		if season == 1:
			options.append("lake")
		if v.has_trait("爱钓鱼"):
			options.append("fish")
	if world.building_spot("market").x >= 0:
		options.append("market")
	if world.building_spot("well").x >= 0:
		options.append("well")
	if not world.animals.is_empty():
		options.append("animal")
		if v.child:
			options.append("animal")
	if world.hour >= 18.0 and world.building_spot("tavern").x >= 0:
		options.append("tavern")
		options.append("tavern")
		if v.has_trait("爱喝酒"):
			options.append("tavern")
	if world.building_spot("church").x >= 0 and world.day_number % 7 == 0:
		options.append("church")
	options.append("hike")
	if world.day_number % 5 == 2:
		options.append("travel")
	if v.has_trait("爱热闹"):
		options.append("market")
	if v.has_trait("爱干净"):
		options.append("well")
	var kind: String = options[world.rng.randi_range(0, options.size() - 1)]
	_note(kind)
	match kind:
		"lake":
			return _lake_plan(v)
		"fish":
			return _fish_plan(v)
		"market":
			return _market_plan(v)
		"well":
			return _well_plan(v)
		"tavern":
			return _tavern_plan(v)
		"church":
			return _church_plan(v)
		"animal":
			return _animal_plan(v)
		"hike":
			return _hike_plan(v)
		"travel":
			return _travel_plan(v)
		_:
			return _stroll_plan(v)

func _lake_plan(v) -> Array:
	var spot: Vector2i = world.fishing_spot_near(v.grid_pos)
	if spot.x < 0:
		return _stroll_plan(v)
	var water: Vector2i = world.water_next_to(spot, Vector2i(-1, -1))
	if water.x < 0:
		return _stroll_plan(v)
	var in_water: Vector2i = world.water_next_to(water, spot)
	if in_water.x < 0:
		in_water = water
	return [
		{"op": "activity", "text": "去湖边玩水"},
		{"op": "goto", "cell": Vector2(spot)},
		{"op": "face", "cell": Vector2(water)},
		{"op": "say", "text": v.pick(["水好凉快！", "夏天就该泡在水里", "你也下水啊"]), "secs": 2.4},
		{"op": "goto", "cell": Vector2(in_water)},
		{"op": "swim", "on": true},
		{"op": "call", "fn": func() -> void:
			world.fx.splash(world.iso(Vector2(water)) + Vector2(0, 8))},
		{"op": "wait", "secs": 8.0},
		{"op": "think", "text": v.pick(_lake_lines(v))},
		{"op": "swim", "on": false},
		{"op": "goto", "cell": Vector2(spot)},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 6.0)},
	]

func _market_plan(v) -> Array:
	var m: Vector2i = world.building_spot("market")
	if m.x < 0:
		return _stroll_plan(v)
	return [
		{"op": "activity", "text": "去市集逛逛"},
		{"op": "goto", "cell": world.random_spot_near(Vector2(m), 1.0)},
		{"op": "hide"},
		{"op": "activity", "text": "在市集里挑东西"},
		{"op": "wait", "secs": 7.0},
		{"op": "show"},
		{"op": "say", "text": v.pick(_market_lines(v)), "secs": 2.6},
		{"op": "call", "fn": func() -> void:
			if world.gold >= 1.0:
				world.gold -= 1.0
				world.food += 2.0
			v.mood = minf(100.0, v.mood + 5.0)
			world._refresh_hud()},
		{"op": "think", "text": v.pick(["今天市集人真多", "买点东西回家", "这价钱有点贵"])},
	]

func _well_plan(v) -> Array:
	var w: Vector2i = world.building_spot("well")
	if w.x < 0:
		return _stroll_plan(v)
	return [
		{"op": "activity", "text": "去井边打水"},
		{"op": "goto", "cell": world.random_spot_near(Vector2(w), 2.0)},
		{"op": "work", "secs": 2.4, "what": "正在打水"},
		{"op": "say", "text": v.pick(["这井水真甜", "打满一桶回家", "顺手给邻居家也打一桶"]), "secs": 2.4},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 4.0)},
	]

func _tavern_plan(v) -> Array:
	var t: Vector2i = world.building_spot("tavern")
	if t.x < 0:
		return _stroll_plan(v)
	return [
		{"op": "activity", "text": "在酒馆喝酒"},
		{"op": "goto", "cell": world.random_spot_near(Vector2(t), 1.0)},
		{"op": "say", "text": v.pick(_tavern_lines(v)), "secs": 2.6},
		{"op": "hide"},
		{"op": "activity", "text": "在酒馆里喝酒"},
		{"op": "wait", "secs": 9.0},
		{"op": "show"},
		{"op": "call", "fn": func() -> void:
			if world.gold >= 1.5:
				world.gold -= 1.5
				v.mood = minf(100.0, v.mood + 9.0)
			world._refresh_hud()},
	]

func _church_plan(v) -> Array:
	var c: Vector2i = world.building_spot("church")
	if c.x < 0:
		return _stroll_plan(v)
	return [
		{"op": "activity", "text": "在教堂做礼拜"},
		{"op": "goto", "cell": world.random_spot_near(Vector2(c), 1.0)},
		{"op": "say", "text": v.pick(["愿小镇平平安安", "求个风调雨顺", "心里踏实多了"]), "secs": 2.6},
		{"op": "hide"},
		{"op": "activity", "text": "在教堂里做礼拜"},
		{"op": "wait", "secs": 8.0},
		{"op": "show"},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 7.0)},
	]

func _hike_plan(v) -> Array:
	var spot: Vector2 = world.scenic_spot(v.grid_pos)
	return [
		{"op": "activity", "text": "去爬山"},
		{"op": "speed", "mult": 1.25},
		{"op": "say", "text": v.pick(["今天天气好，去山上走走", "好久没上山了"]), "secs": 2.4},
		{"op": "goto", "cell": spot},
		{"op": "speed", "mult": 1.0},
		{"op": "anim", "mode": "idle"},
		{"op": "think", "text": v.pick(_hike_lines(v))},
		{"op": "wait", "secs": 6.0},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 8.0)
			world.happiness = minf(100.0, world.happiness + 0.2)},
	]

func _travel_plan(v) -> Array:
	var spot: Vector2 = world.scenic_spot(v.grid_pos)
	var gift := [0.0]
	return [
		{"op": "activity", "text": "出远门旅行"},
		{"op": "say", "text": v.pick(["我出去见见世面，几天就回", "听说山那边有个大城"]), "secs": 2.6},
		{"op": "goto", "cell": spot},
		{"op": "hide"},
		{"op": "wait", "secs": 10.0},
		{"op": "show"},
		{"op": "call", "fn": func() -> void:
			gift[0] = 6.0 + world.rng.randf() * 8.0
			world.gold += gift[0]
			v.mood = minf(100.0, v.mood + 10.0)},
		{"op": "say", "text": v.pick(["回来啦，给大家带了点东西", "外面可真热闹", "还是家里舒服"]), "secs": 2.8},
		{"op": "call", "fn": func() -> void:
			world.fx.float_text(v.position, "+%d 金币" % int(gift[0]), Color(1.0, 0.92, 0.55))
			world._flash("%s 旅行回来了" % v.pname, Color(0.94, 0.92, 1.0))
			world._refresh_hud()},
	]

func _stroll_plan(v) -> Array:
	var spot: Vector2 = world.wander_spot(v.grid_pos)
	return [
		{"op": "activity", "text": "在路上随便走走"},
		{"op": "goto", "cell": spot},
		{"op": "think", "text": v.pick(_think_pool(v))},
		{"op": "wait", "secs": 2.5},
	]

# ---------- 村里的动物 ----------

# 闲下来去看看村里的动物，摸摸它。被摸的动物会蹦一下冒个爱心，
# 村民自己也高兴一点（小孩子最喜欢这一口）。
func _animal_plan(v) -> Array:
	return _animal_plan_for(v, world.nearest_animal(v.grid_pos, 14.0))

func _animal_plan_for(v, pet) -> Array:
	if pet == null or not is_instance_valid(pet):
		return _stroll_plan(v)
	var near: Vector2i = world.open_spot_near(pet.grid_pos, 2.0)
	if near.x < 0:
		return _stroll_plan(v)
	return [
		{"op": "activity", "text": "去看看村里的%s" % String(pet.kind_name)},
		{"op": "goto", "cell": Vector2(near)},
		{"op": "face", "cell": pet.grid_pos},
		{"op": "say", "text": v.pick(_animal_lines(String(pet.species))), "secs": 2.4},
		{"op": "call", "fn": func() -> void:
			if is_instance_valid(pet):
				pet.pet()},
		{"op": "wait", "secs": 2.0},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 4.0)
			world.happiness = minf(100.0, world.happiness + 0.25)},
		{"op": "think", "text": v.pick(_animal_thoughts(String(pet.species)))},
	]

func _animal_lines(kind: String) -> Array:
	match kind:
		"sheep":
			return ["小羊乖，摸摸你", "羊毛软乎乎的", "别光顾着吃草呀"]
		"duck":
			return ["鸭子别乱跑", "嘎嘎，游得真快", "水里凉快吧"]
		"dog":
			return ["大黄，跟我转转", "好狗，看家辛苦了", "走，去田里看看"]
		"cat":
			return ["小咪，过来", "猫儿就爱晒太阳", "别老偷吃鱼干"]
		"deer":
			return ["鹿从林子里出来了", "轻点声，别惊着它"]
		"boar":
			return ["野猪下山了，小心点", "离它远些"]
	return ["来看看小动物"]

func _animal_thoughts(kind: String) -> Array:
	match kind:
		"sheep":
			return ["羊毛攒起来能做好衣裳", "过些日子该剪毛了"]
		"duck":
			return ["鸭子下的蛋能添个菜", "湖上比屋里自在"]
		"dog":
			return ["有狗看着，夜里安心"]
		"cat":
			return ["猫儿抓老鼠是把好手"]
		"deer":
			return ["林子里估计还有一群鹿"]
		"boar":
			return ["希望它别拱了庄稼"]
	return ["这些小东西让村子热闹多了"]

# ---------- the camp fire ----------

func _campfire_tick() -> void:
	if fire_night:
		if world.hour >= SLEEP_HOUR or world.hour < WAKE_HOUR:
			fire_night = false
			fx.put_out_fire()
		return
	if world.day_number == fire_day or world.day_number % FIRE_EVERY != 0:
		return
	if world.hour < FIRE_HOUR or world.hour >= SLEEP_HOUR:
		return
	var spot: Vector2i = world.open_spot_near(Vector2(world.cross_cell), 6.0)
	if spot.x < 0:
		return
	fire_cell = spot
	fire_day = world.day_number
	fire_night = true
	fx.light_fire(world.iso(Vector2(spot)) + Vector2(0, 6))
	world._flash("今晚大家围着火堆聚一聚！", Color(1.0, 0.86, 0.55))
	log_event("篝火之夜")

func _fire_seat(v, index: int) -> Vector2:
	var around := [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1),
		Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2),
	]
	var offset: Vector2 = around[index % around.size()]
	var want := Vector2(fire_cell) + offset
	if world.walkable(int(want.x), int(want.y)):
		return want
	return world._free_cell_near(Vector2(fire_cell), 3.0)

func _fire_plan(v) -> Array:
	var seat: Vector2 = _fire_seat(v, world.villagers.find(v))
	return [
		{"op": "activity", "text": "去篝火边聊天"},
		{"op": "goto", "cell": seat},
		{"op": "face", "cell": Vector2(fire_cell)},
		{"op": "sit", "on": true},
		{"op": "say", "text": v.pick(_fire_lines(v)), "secs": 2.8},
	]

func _fire_chat_plan(v) -> Array:
	var seat: Vector2 = _fire_seat(v, world.villagers.find(v))
	return [
		{"op": "sit", "on": true},
		{"op": "goto", "cell": seat},
		{"op": "face", "cell": Vector2(fire_cell)},
		{"op": "wait", "secs": 2.0},
		{"op": "say", "text": v.pick(_fire_lines(v)), "secs": 2.8},
		{"op": "wait", "secs": 3.0},
	]

# ---------- villagers meeting each other ----------

func _meetings() -> void:
	var list: Array = world._live_villagers()
	for i in list.size():
		var a = list[i]
		if not a.is_free() or a.sitting or chatter.has(a.pname):
			continue
		for j in range(i + 1, list.size()):
			var b = list[j]
			if not b.is_free() or b.sitting or chatter.has(b.pname):
				continue
			if a.grid_pos.distance_to(b.grid_pos) > 2.4:
				continue
			_start_chat(a, b)
			break

func _start_chat(a, b) -> void:
	var cold: float = 55.0 + world.rng.randf() * 45.0
	chatter[a.pname] = cold
	chatter[b.pname] = cold
	a.add_friend(b.pname, 3.0)
	b.add_friend(a.pname, 3.0)
	a.mood = minf(100.0, a.mood + 2.0)
	b.mood = minf(100.0, b.mood + 2.0)
	world.happiness = minf(100.0, world.happiness + 0.05)
	var hi: String = a.pick(_greet_lines(a))
	var reply: String = b.pick(_chat_lines(b, a))
	a.run_plan([
		{"op": "talk", "secs": 2.6, "what": "正在和%s聊天" % b.pname, "cell": b.grid_pos},
		{"op": "say", "text": hi, "secs": 2.6},
	])
	b.run_plan([
		{"op": "talk", "secs": 2.6, "what": "正在和%s聊天" % a.pname, "cell": a.grid_pos},
		{"op": "say", "text": reply, "secs": 2.6},
	])

func _celebrate(v, cell: Vector2) -> void:
	if not v.is_free():
		return
	v.run_plan([
		{"op": "activity", "text": "去道喜"},
		{"op": "goto", "cell": world._free_cell_near(cell, 4.0)},
		{"op": "face", "cell": cell},
		{"op": "say", "text": v.pick(_congrats_lines()), "secs": 2.8},
		{"op": "call", "fn": func() -> void:
			v.mood = minf(100.0, v.mood + 6.0)},
	])

# a finished building: fireworks plus neighbours walking over to say well done
func celebrate(cell: Vector2, kind_name: String) -> void:
	var at: Vector2 = world.iso(cell) + Vector2(0, 8)
	fx.firework(at + Vector2(0, -30))
	fx.firework(at + Vector2(-40, -60))
	log_event("%s 建好了" % kind_name)
	var count := 0
	for v in world._live_villagers():
		if v.child or count >= 4:
			continue
		if v.grid_pos.distance_to(cell) <= 14.0:
			_celebrate(v, cell)
			count += 1

# ---------- loosely spaced thoughts ----------

func _thoughts() -> void:
	for v in world._live_villagers():
		if not v.is_free() or v.sitting or thought_cd.has(v.pname):
			continue
		if not rng_roll(0.35):
			continue
		thought_cd[v.pname] = 30.0 + world.rng.randf() * 40.0
		v.say_thought(v.pick(_think_pool(v)), 3.4)

# ---------- jobs and homes ----------

func _assign_jobs() -> void:
	var demand: Array = []   # [job, cell (workplace door)]
	for b in world.buildings:
		var kind: String = String(b["kind"])
		var job: String = world.job_for_building(kind)
		if job == "":
			continue
		var slots := 2 if kind in ["lumber", "quarry", "farm", "market", "carpenter", "bakery"] else 1
		var door: Vector2i = world.building_door_cell(b)
		for i in slots:
			demand.append([job, door])
	for v in world._live_villagers():
		if v.child or v.job == "none":
			continue
		var still := false
		for d in demand:
			if String(d[0]) == v.job:
				still = true
				break
		if not still:
			v.job = "none"
	var taken := {}
	for v in world._live_villagers():
		if v.child or v.job == "none":
			continue
		for d in demand:
			if String(d[0]) == v.job and not taken.has(str(d[1])):
				taken[str(d[1])] = true
				break
	for v in world._live_villagers():
		if v.child or v.job != "none":
			continue
		var best := -1
		var best_d := 1e9
		for i in demand.size():
			var slot: Array = demand[i]
			if taken.has(str(slot[1])):
				continue
			var d: float = Vector2(slot[1]).distance_to(v.grid_pos)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		var pick_slot: Array = demand[best]
		taken[str(pick_slot[1])] = true
		v.job = String(pick_slot[0])
		v.job_place = Vector2(pick_slot[1])
		v.apply_skin(world.skin_for_job(v.job, v.female))
		log_event("%s 当上了%s" % [v.pname, v.job_text()])
	# 还有空岗位、但没人闲着：从人最多的工种里抽一个过去。
	# 不这么做的话，新盖的采石场/面包房会一直没人干活，发展就停了。
	var quota := {}
	var counts := {}
	for d in demand:
		quota[String(d[0])] = int(quota.get(String(d[0]), 0)) + 1
	for v in world._live_villagers():
		if not v.child and v.job != "none":
			counts[v.job] = int(counts.get(v.job, 0)) + 1
	for i in demand.size():
		var slot: Array = demand[i]
		if taken.has(str(slot[1])):
			continue
		var want_job := String(slot[0])
		var pick = null
		var most := 1
		for v in world._live_villagers():
			if v.child or v.job == "none" or String(v.job) == want_job:
				continue
			var n := int(counts.get(v.job, 0))
			if n > most and n > int(quota.get(String(v.job), 0)):
				most = n
				pick = v
		if pick == null:
			break
		counts[pick.job] = int(counts.get(pick.job, 0)) - 1
		pick.job = want_job
		pick.job_place = Vector2(slot[1])
		pick.apply_skin(world.skin_for_job(pick.job, pick.female))
		counts[want_job] = int(counts.get(want_job, 0)) + 1
		taken[str(slot[1])] = true
		log_event("%s 改行当%s" % [pick.pname, pick.job_text()])

func _assign_homes() -> void:
	var houses: Array = []
	for b in world.buildings:
		if int(world.build_defs[String(b["kind"])].get("housing", 0)) > 0:
			houses.append(b)
	var used := {}
	for v in world._live_villagers():
		if v.home_cell.x >= 0:
			used[str(v.home_cell)] = int(used.get(str(v.home_cell), 0)) + 1
	for v in world._live_villagers():
		if v.home_cell.x >= 0 and _home_exists(houses, v.home_cell):
			continue
		var best_door := Vector2i(-1, -1)
		var best_d := 1e9
		for h in houses:
			var door: Vector2i = world.building_door_cell(h)
			var cap: int = 4 * int(round(world._level_mult(h)))
			if int(used.get(str(door), 0)) >= cap:
				continue
			var d: float = Vector2(door).distance_to(v.grid_pos)
			if d < best_d:
				best_d = d
				best_door = door
		v.home_cell = best_door
		if best_door.x >= 0:
			used[str(best_door)] = int(used.get(str(best_door), 0)) + 1

func _home_exists(houses: Array, door: Vector2i) -> bool:
	for h in houses:
		if world.building_door_cell(h) == door:
			return true
	return false

# ---------- 修仙 (《仙逆》 ladder) ----------

func realm_name(v) -> String:
	var r: Dictionary = REALMS[clampi(v.realm, 0, REALMS.size() - 1)]
	var layers := int(r["layers"])
	if layers <= 1:
		return String(r["name"])
	return "%s%d层" % [String(r["name"]), clampi(v.layer, 1, layers)]

func cultivation_place() -> Vector2i:
	if world == null:
		return Vector2i(-1, -1)
	return world.building_spot("xiuxian")

# 修为满了也要挑时辰，失败之后还要隔几天
func tribulation_ready(v) -> bool:
	if v.xp < v.xp_need:
		return false
	var last := int(v.last_tribulation_day)
	if last > 0 and world.day_number - last < TRIBULATION_COOLDOWN_DAYS:
		return false
	var h: float = world.hour
	return h >= TRIBULATION_START and h < TRIBULATION_END

func tribulation_window_text() -> String:
	return "每晚 %02d:00-%02d:00，失败后等 %d 天" % [
		int(TRIBULATION_START), int(TRIBULATION_END), TRIBULATION_COOLDOWN_DAYS]

# 境界越高、层数越高，升一层要的修为越多
func xp_need_for(v) -> float:
	var r: Dictionary = REALMS[clampi(v.realm, 0, REALMS.size() - 1)]
	return float(r["need"]) * (1.0 + 0.22 * float(maxi(0, v.layer - 1)))

func _cultivate_plan(v) -> Array:
	var place: Vector2i = cultivation_place()
	var inside: Vector2 = world.random_spot_near(Vector2(place), 1.0)
	return [
		{"op": "activity", "text": "去修仙场打坐"},
		{"op": "carry", "kind": ""},
		{"op": "goto", "cell": inside},
		{"op": "face", "cell": Vector2(place)},
		# 进到阵里去打坐，外面只看得到修仙场在发光
		{"op": "hide"},
		{"op": "activity", "text": "在修仙场里打坐"},
		{"op": "call", "fn": func() -> void: v.cultivating_vis = true},
		{"op": "wait", "secs": 18.0},
		{"op": "call", "fn": func() -> void: _cultivate_gain(v)},
		{"op": "show"},
		{"op": "activity", "text": "从修仙场出来"},
		{"op": "think", "text": v.pick(_cultivate_lines(v))},
	]

# 修仙场里有人打坐时，建筑自己发光（人已经进去了，看不见人）
func _cultivation_glow() -> void:
	if world == null or world.fx == null:
		return
	var place: Vector2i = cultivation_place()
	if place.x < 0:
		return
	var busy := false
	var best_realm := 0
	for v in world._live_villagers():
		if v.cultivating_vis:
			busy = true
			best_realm = maxi(best_realm, v.realm)
	if not busy:
		return
	world.fx.aura(place.x * 73856093 + place.y * 19349663, world.iso(Vector2(place)) + Vector2(0, 4), best_realm)

func _cultivate_gain(v) -> void:
	v.cultivating_vis = false
	v.xp += 18.0 * (0.4 + v.skill * 0.07)
	world.fx.aura(v.get_instance_id(), v.position, v.realm)
	world.fx.float_text(v.position + Vector2(0, -6), "+修为", Color(0.75, 0.92, 1.0))
	v.xp_need = xp_need_for(v)
	if v.xp >= v.xp_need:
		v.pending_tribulation = true

# 修为满了：先站出来说一句，再引动天雷渡劫
func _tribulation_plan(v) -> Array:
	return [
		{"op": "activity", "text": "准备渡劫"},
		{"op": "anim", "mode": "stand"},
		{"op": "say", "text": v.pick(["修为圆满了，我要引动天雷！", "今日便是渡劫之时！",
			"心里有点慌，但这一步必须走"]), "secs": 3.0},
		{"op": "wait", "secs": 2.6},
		{"op": "call", "fn": func() -> void: _tribulation(v)},
		{"op": "wait", "secs": 1.6},
	]

func _tribulation(v) -> void:
	var chance := clampf(0.72 + v.skill * 0.06 - float(v.realm) * 0.06, 0.35, 0.95)
	var ok: bool = world.rng.randf() < chance
	v.last_tribulation_day = world.day_number
	lightning(v)
	if ok:
		v.xp = 0.0
		var r: Dictionary = REALMS[clampi(v.realm, 0, REALMS.size() - 1)]
		v.layer += 1
		if v.layer > int(r["layers"]):
			v.layer = 1
			v.realm = mini(v.realm + 1, REALMS.size() - 1)
			world._flash("%s 突破到 %s！" % [v.pname, realm_name(v)], Color(0.85, 0.94, 1.0))
			log_event("%s 突破 %s" % [v.pname, realm_name(v)])
		else:
			world._flash("%s 渡劫成功：%s" % [v.pname, realm_name(v)], Color(0.85, 0.94, 1.0))
		v.mood = minf(100.0, v.mood + 12.0)
		v.breakthrough_flash = 2.0
		world.fx.firework(v.position + Vector2(0, -40))
	else:
		v.xp = v.xp_need * 0.55
		v.mood = maxf(0.0, v.mood - 10.0)
		world.fx.burst(v.position + Vector2(0, -20), Color(0.9, 0.5, 0.5), Color(0.7, 0.3, 0.4), 26, 70.0)
		world._flash("%s 渡劫失败，还得再练" % v.pname, Color(1.0, 0.72, 0.62))
		log_event("%s 渡劫失败" % v.pname)
	# 升了一层之后，下一层要的修为更多
	v.xp_need = xp_need_for(v)
	v.refresh_skill()

func lightning(v) -> void:
	world.fx.bolt(v.position + Vector2(0, -18), Color(0.85, 0.92, 1.0))
	world._flash("%s 正在渡劫！" % v.pname, Color(0.92, 0.88, 1.0))

# ---------- 修仙 panel ----------

func assign_cultivation(v, on: bool) -> void:
	v.cultivate = on
	if on:
		if v.realm <= 0 and v.layer < 1:
			v.realm = 0
			v.layer = 1
		if v.xp_need <= 0.0:
			v.refresh_skill()
		log_event("%s 开始修仙" % v.pname)
		world._flash("%s 开始修仙了" % v.pname, Color(0.86, 0.92, 1.0))
	else:
		log_event("%s 停止修仙" % v.pname)

func cultivation_rows() -> Array:
	var rows: Array = []
	if world == null:
		return rows
	for v in world._live_villagers():
		rows.append({
			"v": v,
			"name": v.display_name(),
			"hour": v.life_hours,
			"skill": v.skill,
			"realm": realm_name(v) if v.cultivate or v.realm > 0 else "凡人",
			"xp": v.xp,
			"need": v.xp_need,
			"cultivate": v.cultivate,
			"job": v.job_text(),
			"mood": v.mood_word(),
		})
	return rows

func cultivator_count() -> int:
	var n := 0
	if world == null:
		return n
	for v in world._live_villagers():
		if v.cultivate:
			n += 1
	return n

func next_realm_text(v) -> String:
	var r: Dictionary = REALMS[clampi(v.realm, 0, REALMS.size() - 1)]
	if v.layer >= int(r["layers"]):
		var nxt := mini(v.realm + 1, REALMS.size() - 1)
		return String(REALMS[nxt]["name"])
	return "%s%d层" % [String(r["name"]), v.layer + 1]

# ---------------------------------------------------------------- dialogue

func _season_word() -> String:
	match season:
		0:
			return "春天"
		1:
			return "夏天"
		2:
			return "秋天"
		_:
			return "冬天"

func _greet_lines(v) -> Array:
	var out: Array = [
		"哎，你也在忙啊？", "吃了没？", "今天天气不错啊", "这么巧，遇到你了",
		"我正要去找你呢", "你家的活干完了？", "看你满头汗，歇会儿吧",
		"早啊！", "哟，是你啊", "这阵子活多，累得慌",
		"你家孩子又长高了", "路上小心点，地滑",
	]
	if v.has_trait("开朗"):
		out.append("哈哈哈，见到你真高兴！")
		out.append("来来来，聊两句！")
	if v.has_trait("内向"):
		out.append("嗯……你好。")
	if v.mood < 40.0:
		out.append("唉，我有话想跟你说。")
	if season == 3:
		out.append("这么冷的天，你还出来啊")
	if season == 1:
		out.append("大热天的，去井边喝口水吧")
	return out

func _chat_lines(v, other) -> Array:
	var out: Array = [
		"%s，你家的庄稼长得真好" % other.pname,
		"听说仓库里木头又堆满了",
		"今年%s的雨真不少" % _season_word(),
		"我昨天在湖边看到一条大鱼",
		"我家那口子又嫌我干活慢了",
		"要是能多盖几间房子就好了",
		"干完这阵子我想歇一天",
		"村里人越来越多了",
		"你会做木工吗？我想加个门",
		"%s最近总一个人待着" % other.pname,
		"我小时候这地方还是一片林子",
		"今晚要不要一起去喝酒？",
		"山上能看到整个小镇，真好看",
		"我攒了几个金币，想买件新衣裳",
		"你家的鸡昨晚叫得真响",
		"这天凉了，得添件衣服",
	]
	if v.friendship(other.pname) >= 60.0:
		out.append("跟你说这些，我心里舒服多了")
		out.append("咱俩认识这么久，还是你最实在")
	if v.partner != "":
		out.append("我和%s成家以后，日子过得踏实" % v.partner)
	if other.partner != "":
		out.append("你家%s最近还好吧？" % other.partner)
	if v.child or other.child:
		out.append("小孩子就是闹腾")
	if v.job == "lumber":
		out.append("林子里的树我一天能砍好几棵")
	if v.job == "fish":
		out.append("湖里那鱼精得很，不好钓")
	if v.job == "trade":
		out.append("市集上今天的价钱还不错")
	if v.realm > 0:
		out.append("我最近在修仙场里打坐，心里特别静")
	if v.mood >= 80.0:
		out.append("今天我心情好得很！")
	if v.mood < 40.0:
		out.append("唉，日子有点难过啊")
	return out

func _night_lines(v) -> Array:
	var out: Array = [
		"天黑了，回屋睡觉", "今天累了，早点歇", "明儿还得早起干活",
		"灯油快没了，睡吧", "夜里风大，把门关好",
	]
	if v.has_trait("爱喝酒"):
		out.append("喝了点酒，回去就睡")
	if v.realm > 0:
		out.append("夜里正好打坐，清静")
	return out

func _morning_lines(v) -> Array:
	var out: Array = ["早上好！", "新的一天又开始了", "今天要好好干活",
		"睡得真香", "这天气适合干活"]
	if season == 3:
		out.append("外面下霜了，冷得很")
	if season == 0:
		out.append("春天的空气真新鲜")
	return out

func _fish_lines(v) -> Array:
	return [
		"鱼漂动了！", "今天鱼儿真给面子", "这湖里能钓上一整天",
		"钓条大的回家炖汤", "耐心点，总会咬钩的",
		"我小时候就在这儿钓鱼",
	]

func _lake_lines(v) -> Array:
	return [
		"水里比岸上凉快多了", "这湖看着就舒服", "游两圈就回家",
		"小时候常在这儿玩水", "水底的鱼真多",
	]

func _market_lines(v) -> Array:
	return [
		"来看看今天的行情", "这布料不错，我买一块",
		"老板，便宜点嘛", "市集真热闹，比家里有意思",
		"还是自家种的东西实在", "今天卖得不错",
	]

func _tavern_lines(v) -> Array:
	return [
		"再来一杯！", "今天辛苦了，喝点", "这酒有点烈",
		"讲讲你年轻时候的事", "一起干一杯！",
	]

func _hike_lines(v) -> Array:
	return [
		"从山上看小镇真小啊", "空气真好，心里也敞亮了",
		"这路爬起来还真费劲", "下次带孩子一起来",
		"山上的树比村里的密",
	]

func _child_lines(v) -> Array:
	return [
		"娘，我饿了！", "看我会翻跟头！", "我抓到蚂蚱啦",
		"哥哥带我玩", "我不想去田里干活",
		"这颗石头像个小馒头",
	]

func _fire_lines(v) -> Array:
	var out: Array = [
		"火真旺啊", "今晚的月亮真亮", "这么坐着真舒服",
		"讲个故事听听", "谁带了酒来？", "明天还得干活呢，少聊会儿",
		"我小时候村里也常生火", "这火光映着你脸都是红的",
		"唱一个山歌呗", "冬天生火最舒服了",
	]
	if v.realm > 0:
		out.append("我在火边打坐，气机更顺")
	if v.has_trait("爱热闹"):
		out.append("人多才热闹嘛！")
	if v.has_trait("内向"):
		out.append("……（安静地烤着火）")
	return out

func _congrats_lines() -> Array:
	return [
		"恭喜恭喜！这房子真漂亮", "盖得真快，你们手脚真快",
		"以后这儿热闹了", "这屋子我看了半天，真不错",
		"来道个喜，嘿嘿", "有了新房子，日子更好了",
	]

func _cultivate_lines(v) -> Array:
	return [
		"这灵气吸得真顺", "心静下来，杂念就少了",
		"昨天那道灵气我还没悟透", "筑基之后再想结丹的事",
		"打坐一夜，比睡一晚还精神", "我总觉得，天道就在头顶上",
		"灵气在经脉里走了一圈", "修仙路长，急不得",
	]

func _think_pool(v) -> Array:
	var out: Array = []
	# the town's condition first
	if world.food <= 8.0:
		out += ["粮仓要空了，得多种点", "有点饿，回去吃点东西"]
	if world.wood <= 6.0:
		out += ["木头不够用了，得去砍点树", "伐木场该有人干活了"]
	if world.gold < 5.0:
		out += ["口袋里没几个金币了", "得多赚点钱"]
	if world.population >= world.housing:
		out += ["房子不够住了，得再盖几间"]
	if world.happiness < 45.0:
		out += ["大家最近都不太高兴"]
	# the villager's own life
	if v.mood >= 80.0:
		out += ["今天心情特别好", "这日子越过越好了"]
	if v.mood < 40.0:
		out += ["心里有点烦", "是不是该歇一天了"]
	if v.partner != "":
		out += ["回家看看%s在做什么" % v.partner, "和%s过日子真踏实" % v.partner]
	else:
		out += ["什么时候也能成个家"]
	if v.has_trait("贪吃"):
		out += ["有点想吃面包了", "闻到谁家炖肉的香味了"]
	if v.has_trait("爱读书"):
		out += ["那本书还没看完", "字认得多，办事就是明白"]
	if v.has_trait("爱干净"):
		out += ["身上一身土，回去洗洗", "屋里该打扫了"]
	if v.has_trait("懒散"):
		out += ["真想找个地方躺一会儿", "活儿永远干不完"]
	if v.has_trait("勤劳"):
		out += ["今天还能再干一阵", "手里有活才安心"]
	if v.has_trait("急性子"):
		out += ["怎么还没走到", "这活儿太慢了，急人"]
	if v.has_trait("慢性子"):
		out += ["慢慢来，不着急", "走得急了反而累"]
	if v.child:
		out += ["想去湖边看鱼", "什么时候才能长大啊"]
	if v.job == "lumber":
		out += ["北边林子里的树真粗", "斧头该磨了"]
	if v.job == "fish":
		out += ["今天鱼情不错", "网该补一补了"]
	if v.job == "farm":
		out += ["庄稼长得挺好", "地里该上肥了"]
	if v.job == "trade":
		out += ["今天市集上人不少"]
	if v.job == "build":
		out += ["新房子快盖好了", "木料还差一点"]
	if v.job == "none":
		out += ["我该找点活干", "闲着心里不踏实"]
	# season / weather flavour
	match season:
		0:
			out += ["花都开了，真好看", "春天的风真舒服", "燕子回来了"]
		1:
			out += ["天太热了，想去湖边", "晒得人直冒汗", "蝉叫得真响"]
		2:
			out += ["树叶都黄了", "该收的庄稼得赶紧收", "风里都是谷子的味道"]
		_:
			out += ["手都冻僵了", "得给屋里多添点柴", "雪下得真大"]
	# realm flavour
	if v.realm >= 1:
		out += ["练气期九层是一道坎", "灵气在体内转了一圈"]
	if v.realm >= 3:
		out += ["结丹之后，寿元也长了", "凡人百年，修士千年"]
	# generic fallback flavour
	out += [
		"今天的风真舒服", "想去湖边转一圈", "希望多认识几个朋友",
		"要是村里有座教堂就好了", "听说北边林子很密",
		"该给家里添个水缸", "晚上想吃点热乎的",
	]
	return out
