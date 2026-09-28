extends CanvasLayer

var world: Node2D
var res_label: Label
var clock_label: Label
var info_label: Label
var toast: Label
var toast_t := 0.0
var built := false
var buttons := {}
var build_grid: GridContainer
var speed_button: Button
var grow_button: Button
var save_button: Button
var start_menu: Control
var menu: PanelContainer
var menu_box: VBoxContainer
var menu_target := {}

# left stats panel / bottom build bar can be folded away to see the town
var stats_panel: PanelContainer
var stats_box: VBoxContainer
var fold_stats: Button
var bar_panel: PanelContainer
var fold_bar: Button
# right hand 修仙系统 panel
var xx_panel: PanelContainer
var xx_body: VBoxContainer
var xx_list: VBoxContainer
var xx_toggle: Button
var xx_open := false
var xx_timer := 0.0
# the little panel you get when you click a villager
var v_panel: PanelContainer
var v_box: VBoxContainer
var v_target: Node = null
var chat_input: LineEdit
var v_reply := ""
var v_timer := 0.0

func setup(w: Node2D) -> void:
	world = w
	_build()

func _sb(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

func _build() -> void:
	if built:
		return
	built = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(14, 12)
	panel.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.11, 0.09, 0.78), 12, 12))
	root.add_child(panel)
	stats_panel = panel
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	stats_box = VBoxContainer.new()
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_box.add_theme_constant_override("separation", 4)
	vb.add_child(stats_box)
	res_label = Label.new()
	res_label.add_theme_font_size_override("font_size", 18)
	res_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	stats_box.add_child(res_label)
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 15)
	clock_label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	stats_box.add_child(clock_label)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(0.80, 0.95, 0.82))
	stats_box.add_child(info_label)

	fold_stats = Button.new()
	fold_stats.text = "收起面板"
	fold_stats.custom_minimum_size = Vector2(96, 22)
	fold_stats.add_theme_font_size_override("font_size", 11)
	fold_stats.add_theme_stylebox_override("normal", _sb(Color(0.28, 0.24, 0.20, 0.9), 7, 3))
	fold_stats.add_theme_stylebox_override("hover", _sb(Color(0.38, 0.32, 0.26, 0.9), 7, 3))
	fold_stats.pressed.connect(_toggle_stats)
	vb.add_child(fold_stats)

	var bar := PanelContainer.new()
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.11, 0.09, 0.86), 14, 10))
	root.add_child(bar)
	bar_panel = bar
	# the fold button lives *outside* the grid, otherwise hiding the grid hides
	# the button as well and the bar can never be opened again
	var bar_vb := VBoxContainer.new()
	bar_vb.add_theme_constant_override("separation", 4)
	bar_vb.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(bar_vb)
	var hb := GridContainer.new()
	hb.columns = 12
	hb.add_theme_constant_override("h_separation", 5)
	hb.add_theme_constant_override("v_separation", 5)
	bar_vb.add_child(hb)
	build_grid = hb

	for kind in world.build_order:
		var def: Dictionary = world.build_defs[kind]
		var b := Button.new()
		b.text = world.build_button_text(kind)
		b.custom_minimum_size = Vector2(99, 44)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", _sb(Color(0.36, 0.28, 0.20, 0.95), 10, 6))
		b.add_theme_stylebox_override("hover", _sb(Color(0.47, 0.36, 0.25, 0.95), 10, 6))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.58, 0.44, 0.28, 0.95), 10, 6))
		var k: String = kind
		b.pressed.connect(func() -> void: world.select_build(k))
		hb.add_child(b)
		buttons[kind] = b

	var cancel := Button.new()
	cancel.text = "取消\nEsc"
	cancel.custom_minimum_size = Vector2(99, 44)
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.add_theme_stylebox_override("normal", _sb(Color(0.30, 0.24, 0.20, 0.95), 10, 6))
	cancel.add_theme_stylebox_override("hover", _sb(Color(0.40, 0.32, 0.26, 0.95), 10, 6))
	cancel.pressed.connect(func() -> void: world.select_build(""))
	hb.add_child(cancel)

	var sp := Button.new()
	sp.text = "时间\n1x"
	sp.custom_minimum_size = Vector2(99, 44)
	sp.add_theme_font_size_override("font_size", 12)
	sp.add_theme_stylebox_override("normal", _sb(Color(0.22, 0.28, 0.36, 0.95), 10, 6))
	sp.add_theme_stylebox_override("hover", _sb(Color(0.30, 0.38, 0.48, 0.95), 10, 6))
	sp.pressed.connect(func() -> void: world.cycle_speed_wrap())
	hb.add_child(sp)
	speed_button = sp

	grow_button = Button.new()
	grow_button.custom_minimum_size = Vector2(99, 44)
	grow_button.add_theme_font_size_override("font_size", 12)
	grow_button.add_theme_stylebox_override("normal", _sb(Color(0.20, 0.32, 0.22, 0.95), 10, 6))
	grow_button.add_theme_stylebox_override("hover", _sb(Color(0.28, 0.44, 0.30, 0.95), 10, 6))
	grow_button.add_theme_stylebox_override("pressed", _sb(Color(0.36, 0.54, 0.36, 0.95), 10, 6))
	grow_button.pressed.connect(func() -> void: world.grow_map())
	hb.add_child(grow_button)

	save_button = Button.new()
	save_button.text = "保存\nCtrl+S"
	save_button.custom_minimum_size = Vector2(99, 44)
	save_button.add_theme_font_size_override("font_size", 12)
	save_button.add_theme_stylebox_override("normal", _sb(Color(0.30, 0.26, 0.34, 0.95), 10, 6))
	save_button.add_theme_stylebox_override("hover", _sb(Color(0.40, 0.34, 0.46, 0.95), 10, 6))
	save_button.pressed.connect(func() -> void: world.save_game())
	hb.add_child(save_button)

	fold_bar = Button.new()
	fold_bar.text = "收起建造栏 ▲"
	fold_bar.custom_minimum_size = Vector2(99, 44)
	fold_bar.add_theme_font_size_override("font_size", 12)
	fold_bar.add_theme_stylebox_override("normal", _sb(Color(0.26, 0.24, 0.28, 0.95), 10, 6))
	fold_bar.add_theme_stylebox_override("hover", _sb(Color(0.36, 0.33, 0.40, 0.95), 10, 6))
	fold_bar.pressed.connect(_toggle_bar)
	bar_vb.add_child(fold_bar)

	toast = Label.new()
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("font_size", 22)
	toast.add_theme_color_override("font_outline_color", Color(0.12, 0.09, 0.06, 0.9))
	toast.add_theme_constant_override("outline_size", 6)
	toast.visible = false
	root.add_child(toast)

	# anchor after the children exist, otherwise the size is still zero and the
	# bar ends up hanging off the bottom edge
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 96)
	_build_xiuxian(root)
	_ensure_villager_panel()

func update_state() -> void:
	if not built:
		return
	res_label.text = "木材 %d      石料 %d      食物 %d      金币 %d" % [
		int(world.wood), int(world.stone), int(world.food), int(world.gold)
	]
	clock_label.text = "第 %d 天   %02d:%02d      人口 %d/%d      幸福 %d%%" % [
		int(world.day_number), int(world.hour), int(fmod(world.hour, 1.0) * 60.0),
		int(world.population), int(world.housing), int(world.happiness)
	]
	clock_label.text = "%s   %s" % [world.season_name(), clock_label.text]
	speed_button.text = "时间\n%s%s" % [world.speed_text(), "（夜）" if world.is_night() else ""]
	info_label.text = "地图 %d×%d   村民 %d 人   建筑 %d 座   工地 %d 处   动物 %d 只" % [
		int(world.mw), int(world.mh), world.villagers.size(),
		world.buildings.size(), world.sites.size(), world.animals.size()
	]
	var gc: Dictionary = world.grow_cost()
	grow_button.text = "扩张地图\n金%d 木%d 石%d" % [int(gc["gold"]), int(gc["wood"]), int(gc["stone"])]
	grow_button.modulate = Color(1, 1, 1, 1) if world.can_grow() else Color(0.72, 0.68, 0.66, 1.0)
	for kind in buttons:
		var b: Button = buttons[kind]
		var def: Dictionary = world.build_defs[kind]
		var afford: bool = world.wood >= float(def["wood"]) and world.stone >= float(def["stone"])
		b.modulate = Color(1, 1, 1, 1.0) if afford else Color(0.70, 0.62, 0.60, 1.0)
		if world.build_kind == kind:
			b.modulate = Color(0.88, 1.0, 0.72, 1.0)

func flash(text: String, color: Color) -> void:
	if not built:
		return
	toast.text = text
	toast.modulate = color
	toast.visible = true
	toast_t = 1.4

# ---------- right-click context menu ----------

func menu_open() -> bool:
	return menu != null and menu.visible

func close_menu() -> void:
	if menu != null:
		menu.visible = false
	menu_target = {}

func open_menu(kind: String, index: int, at: Vector2) -> void:
	if not built:
		return
	_ensure_menu()
	menu_target = {"kind": kind, "index": index}
	_build_menu()
	menu.visible = true
	var vp := menu.get_viewport_rect().size
	var want := menu.get_combined_minimum_size()
	menu.position = Vector2(
		clampf(at.x, 8.0, maxf(8.0, vp.x - want.x - 8.0)),
		clampf(at.y, 8.0, maxf(8.0, vp.y - want.y - 8.0))
	)

func open_site(index: int, at: Vector2) -> void:
	open_menu("site", index, at)

func _ensure_menu() -> void:
	if menu != null:
		return
	menu = PanelContainer.new()
	menu.visible = false
	menu.add_theme_stylebox_override("panel", _sb(Color(0.11, 0.09, 0.07, 0.97), 10, 10))
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 5)
	menu.add_child(menu_box)
	add_child(menu)

func _menu_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 34)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", _sb(Color(0.30, 0.25, 0.20, 0.95), 8, 5))
	b.add_theme_stylebox_override("hover", _sb(Color(0.42, 0.34, 0.26, 0.95), 8, 5))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.52, 0.42, 0.30, 0.95), 8, 5))
	b.pressed.connect(cb)
	return b

# ---------- start menu: continue a save or begin a new town ----------

func open_start_menu() -> void:
	if start_menu != null:
		return
	start_menu = Control.new()
	start_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_menu.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_menu.add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	centre.add_child(box)

	var title := Label.new()
	title.text = "小 镇 家 园"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "选一个存档继续，或者开始新的小镇"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var saves: Array = world.list_saves()
	for s in saves:
		var slot := int(s["slot"])
		box.add_child(_menu_button(String(s["label"]), func() -> void:
			close_start_menu()
			world.load_game(slot)))
	box.add_child(_menu_button("新的游戏", func() -> void:
		close_start_menu()
		world.new_game()))
	box.add_child(_menu_button("退出", func() -> void: get_tree().quit()))

	var hint := Label.new()
	hint.text = "左键建造/采集　右键菜单（信息·升级·移动·拆除）　= 加速　- 减速　Ctrl+S 保存"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(start_menu)

func close_start_menu() -> void:
	if start_menu != null:
		start_menu.queue_free()
		start_menu = null

func _build_menu() -> void:
	for c in menu_box.get_children():
		c.queue_free()
	var kind: String = String(menu_target.get("kind", ""))
	var index: int = int(menu_target.get("index", -1))
	if kind == "site":
		var sinfo: Dictionary = world.site_info(index)
		menu_box.add_child(_menu_label(String(sinfo["title"]), 17, Color(1.0, 0.94, 0.78)))
		for line in sinfo["lines"]:
			menu_box.add_child(_menu_label(String(line), 13, Color(0.85, 0.90, 0.96)))
		menu_box.add_child(_menu_label("—— 操作 ——", 12, Color(0.7, 0.72, 0.76)))
		menu_box.add_child(_menu_button("催一催（叫最近的村民来干活）", func() -> void:
			world.nudge_site(index)
			close_menu()))
		menu_box.add_child(_menu_button("取消建造（退回一半材料）", func() -> void:
			world.cancel_site_at(index)
			close_menu()))
	elif kind == "building":
		var info: Dictionary = world.building_info(index)
		menu_box.add_child(_menu_label(String(info["title"]), 17, Color(1.0, 0.94, 0.78)))
		for line in info["lines"]:
			menu_box.add_child(_menu_label(String(line), 13, Color(0.85, 0.90, 0.96)))
		menu_box.add_child(_menu_label("—— 操作 ——", 12, Color(0.7, 0.72, 0.76)))
		var level := int(info["level"])
		if level < int(info["max_level"]):
			var cost: Dictionary = info["upgrade"]
			menu_box.add_child(_menu_button(
				"升级 → Lv%d（木%d 石%d）" % [level + 1, int(cost["wood"]), int(cost["stone"])],
				func() -> void:
					world.upgrade_building(index)
					open_menu("building", index, menu.position)
			))
		else:
			menu_box.add_child(_menu_label("已经是最高等级", 13, Color(0.72, 0.95, 0.7)))
		menu_box.add_child(_menu_button("移动", func() -> void:
			world.begin_move(index)
			close_menu()))
		menu_box.add_child(_menu_button("拆除（返还一半材料）", func() -> void:
			var cell: Vector2 = world.buildings[index]["cell"]
			world._try_demolish(Vector2i(int(cell.x), int(cell.y)))
			close_menu()))
	else:
		var info: Dictionary = world.resource_info(index)
		menu_box.add_child(_menu_label(String(info["title"]), 17, Color(1.0, 0.94, 0.78)))
		for line in info["lines"]:
			menu_box.add_child(_menu_label(String(line), 13, Color(0.85, 0.90, 0.96)))
		menu_box.add_child(_menu_label("—— 操作 ——", 12, Color(0.7, 0.72, 0.76)))
		if int(world.resources[index].get("hits", 0)) > 0:
			menu_box.add_child(_menu_button("派村民采集", func() -> void:
				var cell: Vector2 = world.resources[index]["cell"]
				world._try_harvest(Vector2i(int(cell.x), int(cell.y)))
				close_menu()))
		else:
			menu_box.add_child(_menu_label("现在没什么可采的，等它长起来", 13, Color(0.8, 0.86, 0.78)))
	menu_box.add_child(_menu_button("关闭", close_menu))

# ---------- folding panels ----------

func _toggle_stats() -> void:
	stats_box.visible = not stats_box.visible
	fold_stats.text = "收起面板" if stats_box.visible else "展开面板"

func _toggle_bar() -> void:
	if build_grid == null:
		return
	build_grid.visible = not build_grid.visible
	fold_bar.text = "收起建造栏 ▲" if build_grid.visible else "展开建造栏 ▼"
	# 折叠以后面板要重新贴到底边，不然它会停在原来的高度上挡住地图
	if bar_panel != null:
		bar_panel.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)

# ---------- 修仙系统：右侧折叠菜单 ----------

func _build_xiuxian(root: Control) -> void:
	xx_panel = PanelContainer.new()
	xx_panel.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.14, 0.21, 0.92), 12, 10))
	root.add_child(xx_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	xx_panel.add_child(vb)
	xx_toggle = Button.new()
	xx_toggle.text = "修仙系统 ◀"
	xx_toggle.custom_minimum_size = Vector2(190, 30)
	xx_toggle.add_theme_font_size_override("font_size", 14)
	xx_toggle.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	xx_toggle.add_theme_stylebox_override("normal", _sb(Color(0.22, 0.26, 0.40, 0.95), 8, 5))
	xx_toggle.add_theme_stylebox_override("hover", _sb(Color(0.30, 0.36, 0.54, 0.95), 8, 5))
	xx_toggle.pressed.connect(_toggle_xiuxian)
	vb.add_child(xx_toggle)
	xx_body = VBoxContainer.new()
	xx_body.add_theme_constant_override("separation", 6)
	xx_body.visible = false
	vb.add_child(xx_body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	xx_body.add_child(scroll)
	xx_list = VBoxContainer.new()
	xx_list.add_theme_constant_override("separation", 5)
	scroll.add_child(xx_list)
	xx_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

func _toggle_xiuxian() -> void:
	xx_open = not xx_open
	xx_body.visible = xx_open
	xx_toggle.text = "修仙系统 ▶" if xx_open else "修仙系统 ◀"
	_reanchor_xx()
	if xx_open:
		_update_xiuxian()

# the panel grows when the list is expanded, so re-hug the right edge
func _reanchor_xx() -> void:
	if xx_panel != null:
		xx_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

func _update_xiuxian() -> void:
	if xx_list == null or not xx_open:
		return
	# the panel also runs while the title screen is up, when there is no town yet
	if world == null or not world.world_started or world.town == null:
		return
	for c in xx_list.get_children():
		c.queue_free()
	var t = world.town
	var place: Vector2i = t.cultivation_place()
	xx_list.add_child(_menu_label(
		"修仙场：%s" % ("已建成" if place.x >= 0 else "还没建（建造栏最后一项）"),
		13, Color(0.82, 0.92, 1.0)))
	xx_list.add_child(_menu_label(
		"记名弟子 %d 人   ·   修炼时间就是经验，满了自动渡劫" % t.cultivator_count(),
		12, Color(0.72, 0.80, 0.92)))
	for row in t.cultivation_rows():
		var v = row["v"]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.17, 0.20, 0.28, 0.9), 8, 8))
		xx_list.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		box.add_child(_menu_label(
			"%s   ·   活了 %d 小时   ·   能力 %.2f" % [
				String(row["name"]), int(row["hour"]), float(row["skill"])],
			13, Color(1.0, 0.95, 0.82)))
		box.add_child(_menu_label(
			"工作：%s   心情：%s" % [String(row["job"]), String(row["mood"])],
			11, Color(0.80, 0.86, 0.92)))
		box.add_child(_menu_label(
			"境界：%s   修为 %d/%d" % [String(row["realm"]), int(row["xp"]), int(row["need"])],
			11, Color(0.78, 0.90, 1.0)))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(290, 10)
		bar.max_value = maxf(1.0, float(row["need"]))
		bar.value = float(row["xp"])
		bar.show_percentage = false
		box.add_child(bar)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		box.add_child(hb)
		var b1 := Button.new()
		b1.text = "停止修仙" if bool(row["cultivate"]) else "指派修仙"
		b1.custom_minimum_size = Vector2(96, 26)
		b1.add_theme_font_size_override("font_size", 11)
		b1.pressed.connect(func() -> void:
			t.assign_cultivation(v, not bool(v.cultivate))
			_update_xiuxian())
		hb.add_child(b1)
		var b2 := Button.new()
		b2.text = "找到他"
		b2.custom_minimum_size = Vector2(70, 26)
		b2.add_theme_font_size_override("font_size", 11)
		b2.pressed.connect(func() -> void:
			# 镜头跟住他，并且把信息面板放到他旁边的屏幕上
			world.focus_villager(v, 12.0)
			open_villager_at_world(v))
		hb.add_child(b2)
	_reanchor_xx()

# 把一个村民的信息面板放到他身边的屏幕上：镜头刚被拉过去时他就在画面正中，
# 面板贴着右下角一点，这样人和面板都在视野里
func open_villager_at_world(v) -> void:
	var vp := get_viewport().get_visible_rect().size
	var at := vp * 0.5
	if world != null and world.camera != null and is_instance_valid(v):
		var cam = world.camera
		at = (v.position - cam.position) * cam.zoom + vp * 0.5
	# 面板本身是从 at 往右下偏 20,-60 摆的，这里让它的左边缘再往右让开一点，
	# 免得正好糊在村民脸上
	open_villager(v, Vector2(at.x + 92.0, at.y + 8.0))

# ---------- click a villager: who he is and what he is up to ----------

func _ensure_villager_panel() -> void:
	if v_panel != null:
		return
	v_panel = PanelContainer.new()
	v_panel.visible = false
	v_panel.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.12, 0.17, 0.96), 12, 12))
	v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 5)
	v_panel.add_child(v_box)
	add_child(v_panel)

func close_villager() -> void:
	if v_panel != null:
		v_panel.visible = false
	v_target = null
	v_reply = ""

func open_villager(v, at: Vector2) -> void:
	_ensure_villager_panel()
	v_target = v
	v_reply = ""
	_refresh_villager_panel()
	v_panel.visible = true
	v_panel.reset_size()
	var vp := v_panel.get_viewport_rect().size
	var want := v_panel.get_combined_minimum_size()
	v_panel.position = Vector2(
		clampf(at.x + 20.0, 8.0, maxf(8.0, vp.x - want.x - 8.0)),
		clampf(at.y - 60.0, 8.0, maxf(8.0, vp.y - want.y - 8.0))
	)

func _refresh_villager_panel() -> void:
	if v_panel == null or v_target == null or not is_instance_valid(v_target):
		return
	for c in v_box.get_children():
		c.queue_free()
	var v = v_target
	var info: Dictionary = world.villager_info(v)
	var title := Label.new()
	title.text = String(info["title"])
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	v_box.add_child(title)
	for line in info["lines"]:
		v_box.add_child(_menu_label(String(line), 12, Color(0.86, 0.90, 0.96)))
	if v_reply != "":
		v_box.add_child(_menu_label("他回你：%s" % v_reply, 12, Color(0.84, 1.0, 0.84)))
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "跟他说点什么，比如：去砍树 / 回家休息 / 去修仙"
	chat_input.custom_minimum_size = Vector2(320, 30)
	chat_input.add_theme_font_size_override("font_size", 12)
	chat_input.text_submitted.connect(func(t: String) -> void: _send_command(t))
	v_box.add_child(chat_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v_box.add_child(row)
	var quicks := [["去砍树", "去砍树"], ["去钓鱼", "去湖边钓鱼"], ["回家休息", "回家休息"],
		["去修仙", "去修仙"], ["去工地", "去工地盖房子"], ["去旅游", "出门旅游"]]
	for q in quicks:
		var b := Button.new()
		b.text = String(q[0])
		b.custom_minimum_size = Vector2(66, 26)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_stylebox_override("normal", _sb(Color(0.26, 0.29, 0.38, 0.95), 6, 3))
		b.add_theme_stylebox_override("hover", _sb(Color(0.34, 0.39, 0.50, 0.95), 6, 3))
		b.pressed.connect(func() -> void: _send_command(String(q[1])))
		row.add_child(b)
	v_box.add_child(_menu_button("关闭", close_villager))

func _send_command(text: String) -> void:
	if v_target == null or not is_instance_valid(v_target):
		return
	var reply: String = world.command_villager(v_target, text)
	v_reply = reply
	if reply != "":
		v_target.say(reply, 3.0)
	_refresh_villager_panel()

func _process(delta: float) -> void:
	if not built:
		return
	update_state()
	xx_timer += delta
	if xx_timer >= 0.6:
		xx_timer = 0.0
		_update_xiuxian()
	v_timer += delta
	if v_timer >= 0.6:
		v_timer = 0.0
		if v_panel != null and v_panel.visible:
			v_timer_refresh()
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast.visible = false

# keep the numbers in the villager panel live without stealing the keyboard
func v_timer_refresh() -> void:
	if chat_input != null and chat_input.has_focus():
		return
	var keep := v_reply
	_refresh_villager_panel()
	v_reply = keep
