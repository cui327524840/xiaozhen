extends Node2D

const HW := 32.0
const HH := 16.0
# the map starts at this size and grows when the player pays for it
const START_W := 48
const START_H := 48
const MAX_W := 96
const MAX_H := 96
const GROW_STEP := 6
var mw := START_W
var mh := START_H

const TT := "res://assets/tt/"

# Real Townsmen 7 tiles sliced out of assets/images-2x/images/tilesets.
# Every tile is a 64x32 diamond centred at (32,16) inside a 64x64 canvas.
const TT_TILES := {
	"grass": [
		"tiles1/tile_1x1_g_0_0_00.png", "tiles1/tile_1x1_g_0_0_01.png",
		"tiles1/tile_1x1_g_2020_0_00.png", "tiles1/tile_1x1_g_2020_0_01.png",
		"tiles1/tile_1x1_g_2022_0_00.png",
	],
	"dirt": [
		"tiles1/tile_1x1_g_4_0_00.png", "tiles1/tile_1x1_g_4_0_03.png",
		"tiles1/tile_1x1_g_4040_0_00.png", "tiles1/tile_1x1_g_4404_0_00.png",
	],
	# the street_* atlas tiles only cover half a diamond (they rely on the game's
	# own road-joining logic), so roads use full-coverage dirt tiles instead
	"path": [
		"tiles1/tile_1x1_g_4_0_00.png", "tiles1/tile_1x1_g_4_0_03.png",
		"tiles1/tile_1x1_g_4404_0_00.png",
	],
	"field": [
		# 地本身是翻过的土，麦子另外画一层（见 _apply_crop_look）——这样割完
		# 能看到田里真的矮下去，而不是贴图原封不动
		"tiles1/tile_1x1_g_4404_0_00.png", "tiles1/tile_1x1_g_4040_0_00.png",
	],
	# seamless tiles drawn for this project (see work/make_water.ps1): one flat
	# sheet of water instead of the outlined single tile
	"water": [
		"water_flat/tile_water_deep_00.png",
	],
	"water_shore": [
		"water_flat/tile_water_shore_00.png", "water_flat/tile_water_shore_01.png",
	],
}

# decorative / harvestable props (sliced from objects_summer.xml)
const TT_PROPS := {
	"tree": ["objects/forest_1x1_00.0.png", "objects/forest_1x1_03.0.png", "objects/forest_1x1_10.0.png", "objects/forest_1x1_20.0.png"],
	"tree_small": ["objects/forest_1x1_30.0.png", "objects/forest_1x1_40.0.png"],
	"avenue_tree": ["objects/deco_1x1_avenue_tree_00.0.png", "objects/deco_1x1_avenue_tree_01.0.png"],
	# 能采的石头：原版图集里只有 19x13 的小石子和一层矿点闪光，村民挥镐看着
	# 像在挖空气，所以按同样的做法补了两张石头堆（rock/make_rocks.ps1 画的，
	# 矿脉那张叠的是原版 ore_vein_00 的闪光）
	"stone": ["rock/rock_00.png", "rock/rock_01.png"],
	"tuft": ["objects/ambient_1x1_grass_00.png", "objects/ambient_1x1_grass_01.png", "objects/ambient_1x1_grass_02.png", "objects/ambient_1x1_grass_04.png"],
	"flower": ["objects/flowers_1x1_01.png", "objects/flowers_1x1_03.png", "objects/flowers_1x1_05.png", "objects/flowers_1x1_07.png"],
	"mushroom": ["objects/ambient_1x1_mushroom_00.png", "objects/ambient_1x1_mushroom_01.png"],
}

# buildings: sprite path + footprint in tiles + base_lift
# base_lift raises the sprite so that its own drawn base diamond lands on the
# footprint outline: several Townsmen sprites carry a fence/path below the base
# diamond, and anchoring that decoration to the grid makes the building stick out
# over the tile in front of it.

# --- 树的一生 -------------------------------------------------------------
# 原版每个树种都给了三张图，文件名是 forest_1x1_<品种><阶段>：
#   阶段 0 = 长成的大树（可以砍）  1 = 砍完留下的树桩  3 = 小树（正在长）
# 所以砍掉的树会留个树桩，过一天冒小树，再过两天长回大树——林子砍得完，
# 但会长回来。
const TREE_KINDS := {
	0: {"big": "forest_1x1_00.0.png", "stump": "forest_1x1_01.0.png", "young": "forest_1x1_03.0.png"},
	1: {"big": "forest_1x1_10.0.png", "stump": "forest_1x1_11.0.png", "young": "forest_1x1_13.0.png"},
	2: {"big": "forest_1x1_20.0.png", "stump": "forest_1x1_21.0.png", "young": "forest_1x1_23.0.png"},
	3: {"big": "forest_1x1_30.0.png", "stump": "forest_1x1_31.0.png", "young": "forest_1x1_33.0.png"},
}
const TREE_STAGE_KEYS := ["stump", "young", "big"]
const TREE_STUMP_HOURS := 24.0    # 树桩 → 小树（1 个游戏日）
const TREE_YOUNG_HOURS := 48.0    # 小树 → 大树（2 个游戏日）
const TREE_HITS := 3
const TREE_AMOUNT := 18.0
const REFOREST_HOURS := 36.0      # 多久自己冒一棵新苗
const FIELD_GROW_HOURS := 20.0    # 一茬麦子从割完到再熟（游戏小时）
# 一块田被"认领"后最多占多久（游戏小时）。村民半路被别的事打断，田要能自己放开
const FIELD_CLAIM_HOURS := 1.0

const TT_BUILDINGS := {
	"house": {"path": "buildings02/building_residence_01.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"house_b": {"path": "buildings02/building_residence_02.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"house_c": {"path": "buildings02/building_residence_03.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"lumber": {"path": "buildings02/building_lumberjack_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"quarry": {"path": "buildings02/building_mine_l_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"well": {"path": "buildings02/building_well_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"warehouse": {"path": "buildings02/building_warehouse_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"market": {"path": "buildings02/building_market_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"windmill": {"path": "buildings02/building_windmill_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"church": {"path": "buildings01/building_church_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"bakery": {"path": "buildings01/building_bakery_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"fishing": {"path": "buildings01/building_fishing_lodge_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"goldsmith": {"path": "buildings01/building_goldsmith_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"hunters": {"path": "buildings02/building_hunters_cabin_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"medic": {"path": "buildings02/building_medicus_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"tailor": {"path": "buildings02/building_tailor_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"tavern": {"path": "buildings02/building_tavern_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"vineyard": {"path": "buildings02/building_vineyard_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"armory": {"path": "buildings03/building_armory_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"carpenter": {"path": "buildings03/building_carpenter_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"tradeguild": {"path": "buildings03/building_tradeguild_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"monastery": {"path": "buildings03/building_monestary_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	"firewatch": {"path": "buildings03/building_firewatch_00.0.png", "foot": Vector2(2, 2), "base_lift": 0},
	"xiuxian": {"path": "buildings_xiuxian/building_xiuxian_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
	# 牧场：原版的羊圈，围栏里就是草地
	"pasture": {"path": "buildings02/building_sheepwalk_00.0.png", "foot": Vector2(3, 3), "base_lift": 0},
}

const FARM_TILE := "buildings03/cornfield_1x1_00.4.png"

# --- lake: the real game paints water with 2x2 "blocks" whose nine-bit atlas
# mask covers the block plus its ring of neighbours.  Rather than decode that
# mask, each block is matched by which of its four cells are water, measured off
# the sliced sprites.  Key bits (measured, not guessed):
#   bit0 = south cell (1,1), bit1 = east (1,0), bit2 = west (0,1), bit3 = north (0,0)
# mirror = draw the sprite flipped horizontally, which swaps the east and west
# cells and is a symmetry of the isometric grid.
# The "c" tiles (water spilling over a cliff) are deliberately left out: a pond
# with no river feeding it should not have waterfalls on its banks.
const TT_WATER := "res://assets/tt/water/"
const LAKE_BLOCKS := {
	# entry = [file, mirror horizontally, mirror vertically].  The atlas is
	# missing the banks for the north shore, so those are the south-shore banks
	# flipped vertically - that is a symmetry of the isometric grid and it is
	# what makes a closed pond possible without leaving gaps.
	# 1 = south cell only, 8 = north cell only
	1: [["tile_2x2_ggggwwgww_0_1.0.png", false, false], ["tile_2x2_gwwgwwgww_0_1_02.0.png", false, false]],
	8: [["tile_2x2_ggggwwgww_0_1.0.png", false, true], ["tile_2x2_gwwgwwgww_0_1_02.0.png", false, true]],
	# 4 = west cell only, 2 = east cell only
	4: [["tile_2x2_gggwwgwwg_0_1.0.png", false, false], ["tile_2x2_gwwgwwgww_0_1_00.0.png", false, false]],
	2: [["tile_2x2_gggwwgwwg_0_1.0.png", true, false], ["tile_2x2_gwwgwwgww_0_1_00.0.png", true, false]],
	# 3 = east+south, 12 = north+west
	3: [["tile_2x2_gwwgwwgww_0_1_01.0.png", false, false]],
	12: [["tile_2x2_gwwgwwgww_0_1_01.0.png", false, true]],
	# 5 = west+south, 10 = north+east
	5: [
		["tile_2x2_gggwwwwww_0_1_00.0.png", false, false],
		["tile_2x2_gggwwwwww_0_1_01.0.png", false, false],
		["tile_2x2_gggwwwwww_0_1_02.0.png", false, false],
	],
	10: [
		["tile_2x2_gggwwwwww_0_1_00.0.png", false, true],
		["tile_2x2_gggwwwwww_0_1_01.0.png", false, true],
		["tile_2x2_gggwwwwww_0_1_02.0.png", false, true],
	],
	# 11 = north+east+south, 13 = north+west+south
	11: [["tile_2x2_wwwwwwgww_0_1.0.png", false, false]],
	13: [["tile_2x2_wwwwwwgww_0_1.0.png", false, true]],
	# 14 = north+east+west, 7 = south+east+west
	14: [["tile_2x2_wwwwwwwwg_0_1.0.png", false, false]],
	7: [["tile_2x2_wwwwwwwwg_0_1.0.png", false, true]],
	# open water: one texture, mirrored/flipped per block so the repeat is not
	# obvious - mixing the atlas' other water frames makes the lake look patched
	15: [["tile_2x2_w_1_1.0.png", false, false]],
}

# --- roads: full-diamond paved tiles (tile_1x1_pppp_*)
const TT_ROAD := "res://assets/tt/road/"
const ROAD_TILES := [
	"tile_1x1_pppp_1_0_00.png", "tile_1x1_pppp_1_0_02.png",
	"tile_1x1_pppp_1_0_03.png", "tile_1x1_pppp_1_0_05.png",
]
const ROAD_SPEED := 1.45

# --- time: one full 24h game day takes 2.5 real hours at 1x, and the eight
# night hours burn through ~2.5x faster than the sixteen day hours.
const DAY_SECONDS := 9000.0
const NIGHT_START := 22.0
const DAY_START := 6.0
const NIGHT_RATE := 4.0
const SPEEDS := [1.0, 2.0, 4.0]
const PRODUCE_EVERY := 4.0

const MAX_LEVEL := 3

# 地图扩张的价钱（金 / 木 / 石），每扩张一次乘 GROW_STEP_COST_SCALE
const GROW_COST_GOLD := 30
const GROW_COST_WOOD := 40
const GROW_COST_STONE := 20
const GROW_STEP_COST_SCALE := 1.7

# 湖的半径（横向格数）。湖按"屏幕空间的圆"生成，所以看起来是圆的而不是被拉长的。
const LAKE_RADIUS := 10.5

# cost to go from level N to N+1, and the multiplier applied to the building's
# housing / output at that level
const UPGRADE_COST := [
	{"wood": 45, "stone": 20},
	{"wood": 80, "stone": 45},
]
const LEVEL_MULT := [1.0, 1.8, 3.0]

const BUILD := {
	"house": {"name": "木屋", "wood": 30, "stone": 10, "foot": Vector2(3, 3), "art": "house", "housing": 4},
	"farm": {"name": "农田", "wood": 10, "stone": 0, "foot": Vector2(2, 2), "art": "farm", "food": 1.1},
	"lumber": {"name": "伐木场", "wood": 20, "stone": 5, "foot": Vector2(2, 2), "art": "lumber", "wood_rate": 2.0},
	"quarry": {"name": "采石场", "wood": 15, "stone": 20, "foot": Vector2(2, 2), "art": "quarry", "stone_rate": 1.6},
	"market": {"name": "市集", "wood": 25, "stone": 25, "foot": Vector2(3, 3), "art": "market", "gold": 0.13},
	"warehouse": {"name": "仓库", "wood": 40, "stone": 20, "foot": Vector2(3, 3), "art": "warehouse", "bonus": 0.12},
	"well": {"name": "水井", "wood": 8, "stone": 15, "foot": Vector2(2, 2), "art": "well", "happy": 6},
	# extra house looks: same stats, different sprite, placed by the map generator
	"house_b": {"name": "木屋", "wood": 30, "stone": 10, "foot": Vector2(3, 3), "art": "house_b", "housing": 4},
	"house_c": {"name": "木屋", "wood": 30, "stone": 10, "foot": Vector2(3, 3), "art": "house_c", "housing": 4},
	# --- 更多建筑：吃的、喝的、赚钱的、让人开心的 ---
	"bakery": {"name": "面包房", "wood": 45, "stone": 25, "foot": Vector2(2, 2), "art": "bakery", "food": 2.2},
	"fishing": {"name": "渔舍", "wood": 35, "stone": 5, "foot": Vector2(2, 2), "art": "fishing", "food": 2.6},
	"hunters": {"name": "猎人小屋", "wood": 40, "stone": 5, "foot": Vector2(2, 2), "art": "hunters", "food": 1.8, "wood_rate": 0.8},
	"carpenter": {"name": "木工坊", "wood": 40, "stone": 10, "foot": Vector2(2, 2), "art": "carpenter", "wood_rate": 3.0},
	"windmill": {"name": "风车", "wood": 60, "stone": 40, "foot": Vector2(2, 2), "art": "windmill", "food_bonus": 0.18},
	"vineyard": {"name": "葡萄园", "wood": 45, "stone": 10, "foot": Vector2(3, 3), "art": "vineyard", "gold": 0.3, "food": 0.6},
	"tailor": {"name": "裁缝铺", "wood": 40, "stone": 15, "foot": Vector2(2, 2), "art": "tailor", "gold": 0.35},
	"goldsmith": {"name": "金匠铺", "wood": 60, "stone": 50, "gold_cost": 25, "foot": Vector2(2, 2), "art": "goldsmith", "gold_rate": 6.0},
	"tradeguild": {"name": "商会", "wood": 80, "stone": 60, "gold_cost": 40, "foot": Vector2(3, 3), "art": "tradeguild", "gold": 0.8, "bonus": 0.05},
	"armory": {"name": "铁匠铺", "wood": 50, "stone": 60, "foot": Vector2(2, 2), "art": "armory", "bonus": 0.10},
	"tavern": {"name": "酒馆", "wood": 55, "stone": 30, "gold_cost": 15, "foot": Vector2(3, 3), "art": "tavern", "happy": 4, "gold": 0.45},
	"medic": {"name": "药房", "wood": 50, "stone": 35, "foot": Vector2(2, 2), "art": "medic", "happy": 6},
	"church": {"name": "教堂", "wood": 70, "stone": 90, "gold_cost": 20, "foot": Vector2(2, 2), "art": "church", "happy": 8},
	"monastery": {"name": "修道院", "wood": 90, "stone": 110, "gold_cost": 50, "foot": Vector2(3, 3), "art": "monastery", "happy": 10, "food": 1.0},
	"firewatch": {"name": "瞭望塔", "wood": 30, "stone": 45, "foot": Vector2(2, 2), "art": "firewatch", "happy": 3},
	# 修仙场 - the cultivation ground the villagers meditate in (《仙逆》体系)
	"xiuxian": {"name": "修仙场", "wood": 70, "stone": 60, "gold_cost": 30, "foot": Vector2(3, 3), "art": "xiuxian", "happy": 5},
	# 牧场 - 养羊的地方，羊自己会在村里晃悠（见 scripts/animal.gd）
	"pasture": {"name": "牧场", "wood": 45, "stone": 20, "foot": Vector2(3, 3), "art": "pasture", "food": 2.4, "happy": 3},
}

const BUILD_ORDER := [
	"house", "farm", "lumber", "quarry", "carpenter", "hunters", "fishing",
	"windmill", "bakery", "vineyard", "well", "market", "tradeguild", "warehouse",
	"tailor", "goldsmith", "armory", "tavern", "medic", "church", "monastery", "firewatch",
	"pasture", "xiuxian",
]

var build_defs := BUILD
var build_order := BUILD_ORDER

var terrain := []
var blocked := []
var rng := RandomNumberGenerator.new()

var object_layer: Node2D
var camera: Camera2D
var hud: CanvasLayer
var daynight: CanvasModulate
var ghost: Node2D
var ghost_art: Node2D        # 房子的半透明预览本体
var ghost_marker: Node2D     # 地面上的影子 + 占地圈
var ghost_shadow: Polygon2D
var ghost_outline: Line2D
var ghost_force_cell := Vector2i(-99999, -99999)   # 截图/调试时钉住预览位置
var fx: Node2D          # fireworks / camp fire / ripples / fishing lines
var town: Node2D        # the director that gives the villagers their plans

var wood := 140.0
var stone := 70.0
var food := 90.0
var gold := 0.0
var population := 6
var housing := 0
var happiness := 62.0

var hour := 7.0
var day_number := 1

var buildings: Array = []
var resources: Array = []
var villagers: Array = []
var animals: Array = []    # sheep, ducks, the dog and the cat, deer and boar

var roads := []            # true per cell: paved road
var lake_blocks: Array = []  # 2x2 water/shore blocks placed on the map
var lake_covered := []     # true per cell: already painted by a lake block
var sites: Array = []      # buildings under construction
var fields: Array = []     # the fenced corn fields (they grow and are harvested)
var water_cells: Array = [] # every tile that is water, for fishing and swimming
var shore_cells: Array = [] # walkable tiles that touch the water
var season := 0            # 0 spring, 1 summer, 2 autumn, 3 winter
var prop_nodes: Array = [] # {node, group} so props can change with the season
var speed_index := 0
var produce_slot := 0

# 林子：被砍掉多少，过一阵子就自己补种回来
var tree_target := 0
var plant_timer := 0.0
var immigrate_acc := 0.0     # 有空房时"下一位新村民"还要等多少游戏小时

# relocating a building: -1 when nothing is being moved
var move_index := -1
var move_kind := ""
var move_from := Vector2.ZERO
var camera_focus: Node2D = null   # 正在跟拍的村民（点"找到他"之后）
var camera_focus_t := 0.0
var selected_index := -1
var world_started := false

var build_kind := ""
var dragging := false
var left_down := false
var did_drag := false
var press_pos := Vector2.ZERO
var frames := 0
var shot_path := ""
var shot_frame := 60
var hover_cell := Vector2i(-99, -99)
var debug_stage := 99
var debug_grid := false
var calib_focus := Vector2.ZERO
var base_lift_bias := 0.0

func iso(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * HW, (cell.x + cell.y) * HH)

func _idx(x: int, y: int) -> int:
	return y * mw + x

func _inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < mw and y < mh

func _set_terrain(x: int, y: int, kind: String) -> void:
	if _inside(x, y):
		terrain[_idx(x, y)] = kind

# 开窗：窗口化（不是最大化）、居中、别超出屏幕，标题栏和右上角最小化/最大化/关闭
# 三个按钮都在；玩家自己按最大化时，画面铺满整屏，不留黑边也不被拉成别的比例。
func _setup_window(cargs) -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED or mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# 截图/标定的时候别折腾窗口
	if cargs.has("--shot") or cargs.has("--calib"):
		return
	var usable := DisplayServer.screen_get_usable_rect()
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var want := Vector2i(1280, 720)
	want.x = clampi(want.x, 800, maxi(800, usable.size.x - 40))
	want.y = clampi(want.y, 450, maxi(450, usable.size.y - 60))
	DisplayServer.window_set_size(want)
	DisplayServer.window_set_position(usable.position + (usable.size - want) / 2)
	print("窗口 %dx%d（屏幕可用 %dx%d）" % [want.x, want.y, usable.size.x, usable.size.y])

func _ready() -> void:
	rng.seed = 20260922
	# 画面流畅度：最高 60 帧（显示器刷新率低于 60 时就按显示器来）
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var cargs := OS.get_cmdline_user_args()
	_setup_window(cargs)
	var si := cargs.find("--stage")
	if si >= 0 and cargs.size() > si + 1:
		debug_stage = int(cargs[si + 1])
	_init_layers()
	debug_grid = cargs.has("--grid")
	var li := cargs.find("--lift")
	if li >= 0 and cargs.size() > li + 1:
		base_lift_bias = float(cargs[li + 1])
	debug_villagers = cargs.has("--debug-villagers")
	debug_harvest = cargs.has("--debug-harvest")
	debug_animals = cargs.has("--debug-animals")
	_setup_camera()
	_setup_hud()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and args.size() > i + 1:
		shot_path = args[i + 1]
	var fi := args.find("--shotframe")
	if fi >= 0 and args.size() > fi + 1:
		shot_frame = int(args[fi + 1])
	# screenshots and the diagnostics need a world right away; a normal launch
	# goes through the start menu instead
	var headless := cargs.has("--shot") or cargs.has("--calib") or cargs.has("--stage") \
		or cargs.has("--debug-build") or cargs.has("--debug-upgrade") \
		or cargs.has("--debug-time") or cargs.has("--debug-villagers") \
		or cargs.has("--debug-grow") or cargs.has("--debug-save") \
		or cargs.has("--debug-lake") or cargs.has("--debug-animals") \
		or cargs.has("--demo-menu") \
		or cargs.has("--demo-social") or cargs.has("--demo-site") \
		or cargs.has("--demo-cultivate") or cargs.has("--demo-fire") \
		or cargs.has("--demo-ui") or cargs.has("--demo-animals") \
		or cargs.has("--demo-field") or cargs.has("--debug-growth") \
		or cargs.has("--debug-life") or cargs.has("--demo-carry") \
		or cargs.has("--demo-growth") or cargs.has("--demo-mine") \
		or cargs.has("--demo-menu-click") \
		or cargs.has("--demo-harvest") \
		or cargs.has("--demo-build") \
		or cargs.has("--demo-place") \
		or cargs.has("--debug-site") \
		or cargs.has("--debug-population")
	if cargs.has("--start-menu"):
		headless = false
	if headless:
		start_world(debug_stage)
	else:
		hud.open_start_menu()
	if cargs.has("--debug-build"):
		call_deferred("_debug_build_checks")
	if cargs.has("--debug-upgrade"):
		call_deferred("_debug_upgrade_checks")
	if cargs.has("--debug-time"):
		call_deferred("_debug_time_checks")
	if cargs.has("--demo-menu"):
		call_deferred("_demo_menu")
	if cargs.has("--demo-social"):
		call_deferred("_demo_social")
	if cargs.has("--debug-save"):
		call_deferred("_debug_save_checks")
	if cargs.has("--debug-grow"):
		call_deferred("_debug_grow_checks")
	if cargs.has("--debug-lake"):
		call_deferred("_debug_lake_checks")
	if cargs.has("--debug-animals"):
		call_deferred("_debug_animal_checks")
	if cargs.has("--debug-growth"):
		call_deferred("_debug_growth_checks")
	if cargs.has("--debug-life"):
		call_deferred("_debug_life_checks")
	# demo hooks used while tuning the town life systems
	if cargs.has("--demo-site"):
		call_deferred("_demo_site")
	if cargs.has("--demo-cultivate"):
		call_deferred("_demo_cultivate")
	if cargs.has("--demo-fire"):
		call_deferred("_demo_fire")
	if cargs.has("--demo-ui"):
		call_deferred("_demo_ui")
	if cargs.has("--demo-animals"):
		call_deferred("_demo_animals")
	if cargs.has("--demo-field"):
		call_deferred("_demo_field")
	if cargs.has("--demo-harvest"):
		call_deferred("_demo_harvest")
	if cargs.has("--demo-build") or cargs.has("--demo-place"):
		call_deferred("_demo_build_preview")
	if cargs.has("--demo-carry"):
		call_deferred("_demo_carry")
	if cargs.has("--demo-growth"):
		call_deferred("_demo_growth")
	if cargs.has("--demo-mine"):
		call_deferred("_demo_mine")
	if cargs.has("--demo-menu-click"):
		call_deferred("_demo_menu_click")
	if cargs.has("--debug-population"):
		call_deferred("_debug_population_checks")
	if cargs.has("--debug-site"):
		call_deferred("_debug_site_checks")
	var hi := cargs.find("--hour")
	if hi >= 0 and cargs.size() > hi + 1:
		hour = float(cargs[hi + 1])
		_update_daylight()
	var di := cargs.find("--day")
	if di >= 0 and cargs.size() > di + 1:
		day_number = int(cargs[di + 1])
	var si2 := cargs.find("--season")
	if si2 >= 0 and cargs.size() > si2 + 1:
		season = clampi(int(cargs[si2 + 1]), 0, 3)
		if world_started:
			on_season_changed(season)
	var spi := cargs.find("--speed")
	if spi >= 0 and cargs.size() > spi + 1:
		speed_index = clampi(int(cargs[spi + 1]), 0, SPEEDS.size() - 1)
		_apply_time_scale()
	_refresh_hud()

# --- demo helpers (only used by the --demo-* switches while tuning) --------

func _demo_site() -> void:
	var spot := _nearest_free_rect(Vector2i(3, 3))
	if spot.x >= 0:
		_start_site("house", spot)
		print("DEMO SITE at ", spot.x, ",", spot.y)
		_flash("示范工地已开工", Color(0.9, 0.95, 1.0))

func _demo_cultivate() -> void:
	var spot := _nearest_free_rect(Vector2i(3, 3))
	if spot.x >= 0:
		_add_building("xiuxian", Vector2(spot))
		_rebuild_ground()
	for v in _live_villagers():
		if not v.child:
			town.assign_cultivation(v, true)
			break

func _demo_fire() -> void:
	day_number = 3
	hour = 19.8
	_update_daylight()
	town.fire_day = -99

func _demo_ui() -> void:
	if hud == null:
		return
	hud._toggle_xiuxian()
	var v = _live_villagers()[0] if not _live_villagers().is_empty() else null
	if v != null:
		focus_villager(v, 30.0)
		hud.open_villager_at_world(v)
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(v):
			print("FOCUS CHECK: %s 在 %s，镜头 %s，他画面位置 %s，还跟着=%s（差 %.0f 像素）" % [
				v.pname, str(v.grid_pos), str(camera.position), str(v.position),
				str(camera_focus == v), camera.position.distance_to(v.position)])

# builds a pen and moves the flock into it, for screenshots
func _demo_animals() -> void:
	var spot := _nearest_free_rect(Vector2i(3, 3))
	if spot.x < 0:
		return
	_add_building("pasture", Vector2(spot), true)
	_recompute_housing()
	_rebuild_ground()
	# the wild animals come down to the meadow in front of the village, so one
	# screenshot can show every species at once
	var wild := spot + Vector2i(6, 6)
	var i := 0
	for a in animals:
		if not is_instance_valid(a):
			continue
		var sp := String(a.species)
		if sp == "deer" or sp == "boar":
			a.setup(self, sp, Vector2(wild) + Vector2(0.9, 0.9) * i)
			i += 1
	print("DEMO PASTURE at ", spot.x, ",", spot.y)
	_flash("示范牧场已建好", Color(0.9, 0.95, 1.0))

# diagnostic: 房子多了人口会不会跟着涨（-- --debug-population）
func _debug_population_checks() -> void:
	await get_tree().create_timer(0.5).timeout
	print("POP TEST: 开局 人口 %d / 容量 %d（房子 %d 座），食物 %d 幸福 %d%%" % [
		population, housing, buildings.size(), int(food), int(happiness)])
	var added := 0
	for i in 3:
		var spot := _nearest_free_rect(Vector2i(3, 3))
		if spot.x < 0:
			break
		_add_building("house", Vector2(spot))
		added += 1
	print("  新盖 %d 座木屋 → 容量 %d" % [added, housing])
	# 快进 3 个游戏日（每步推进 0.25 个游戏小时，跟真实运行时的步长接近，
	# 不然一步就是一整个游戏小时，会把"多久来一个人"量得偏慢），看人口怎么走
	for step in 288:
		_advance_clock(0.25 / maxf(0.0001, _hours_per_second()))
		if (step + 1) % 48 == 0:
			print("  第 %d 个游戏小时（第 %d 天 %02d:00）→ 人口 %d/%d，村民 %d 个" % [
				(step + 1) / 4, day_number, int(hour), population, housing, _live_villagers().size()])
	print("POP TEST 结束：人口 %d / 容量 %d，实际村民 %d 个" % [
		population, housing, _live_villagers().size()])

# 诊断：房子一盖好，就不该再有人扛着木料往那个工地跑（-- --debug-site）
func _debug_site_checks() -> void:
	var spot := _nearest_free_rect(Vector2i(3, 3))
	if spot.x < 0:
		print("SITE TEST: 找不到空地")
		return
	_start_site("house", spot)
	var site: Node2D = sites[sites.size() - 1]
	camera.position = _building_origin("house", Vector2(spot)) + Vector2(0, -20)
	print("SITE TEST: 木屋工地放在 %d,%d，开工" % [spot.x, spot.y])
	var hauling_frames := 0
	var builders_seen := {}
	while is_instance_valid(site) and site.progress < 1.0:
		await get_tree().process_frame
		for v in _live_villagers():
			if not is_instance_valid(v) or v.build_site != site:
				continue
			builders_seen[v.pname] = true
			if v.carry_kind == "wood":
				hauling_frames += 1
	# 完工之后再盯一会儿：谁都不许再朝这栋已经盖好的房子走
	await get_tree().create_timer(3.0).timeout
	var late := 0
	for v in _live_villagers():
		if is_instance_valid(v.build_site) and v.build_site.progress >= 1.0:
			late += 1
			print("  完工后还在往工地跑的：%s  %s" % [v.pname, v.activity])
	print("SITE TEST: 参与施工 %d 人，施工期间见过扛木料的帧 %d 个；完工后仍在搬料去工地的人 = %d" % [
		builders_seen.size(), hauling_frames, late])

func _child_count() -> int:
	var n := 0
	for v in _live_villagers():
		if v.child:
			n += 1
	return n

# 真的把鼠标挪到一栋房子上、真的发一个右键事件，看菜单出不出来
# （房子贴图很高，这里底/中/顶三个高度都试一遍）
func _demo_menu_click() -> void:
	if buildings.is_empty():
		return
	await get_tree().create_timer(0.6).timeout
	# 房子贴图很高，点在屋顶上时鼠标底下那格会落在房子的"上后方"。这里直接
	# 按这种偏移算出格子，再走右键那套查找逻辑，看还能不能找到房子。
	var b: Dictionary = buildings[0]
	var base_cell := Vector2i(int(b["cell"].x), int(b["cell"].y))
	print("MENU TEST: 房子在 %s，占 %s" % [str(base_cell), str(b["foot"])])
	for back in range(0, 4):
		var hovered := base_cell - Vector2i(back, back)   # 点在房顶上方第 back 排
		# 和右键处理里一模一样的一段
		var found := -1
		for k in 4:
			var c := hovered + Vector2i(k, k)
			if _building_index_at(c) >= 0:
				found = _building_index_at(c)
				break
		print("  点在房顶上方 %d 格（格子 %s）→ 找到房子 index=%d %s" % [
			back, str(hovered), found, "→ 会弹菜单" if found >= 0 else "→ 弹不出来"])
	print("  菜单现在开着=%s（下面再真的开一次给截图）" % str(hud != null and hud.menu_open()))
	if hud != null:
		var bi := _building_index_at(base_cell)
		hud.open_menu("building", bi, Vector2(660, 250))

# 把树的一生摆一排：树桩 / 小树 / 大树，用来看"砍了会自己长回来"
func _demo_growth() -> void:
	var base := cross_cell + Vector2i(-4, -5)
	for attempt in 300:
		var c := cross_cell + Vector2i(rng.randi_range(-9, 9), rng.randi_range(-9, 9))
		if _grass_ok(c.x, c.y) and _grass_ok(c.x + 1, c.y) and _grass_ok(c.x + 2, c.y):
			base = c
			break
	for i in 3:
		var cell := Vector2i(base.x + i, base.y)
		for r in resources.duplicate():
			if Vector2i(int(round(Vector2(r["cell"]).x)), int(round(Vector2(r["cell"]).y))) == cell:
				_remove_resource(r)
		_add_tree(Vector2(cell), i, 0)
	camera.position = iso(Vector2(base) + Vector2(1, 0)) + Vector2(0, -6)
	print("DEMO GROWTH at ", base.x, ",", base.y)

# 六个村民分两排站着，手里分别扛木料/石料/粮食：前一排朝镜头，后一排背对镜头。
# 这两排正好是以前头顶粘着邻居碎片的那几个方向（比如 farmer_carry_3.2），
# 用来看搬运的贴图抠干净没有。
func _demo_carry() -> void:
	var vs := _live_villagers()
	if vs.is_empty():
		return
	var kinds := ["wood", "stone", "crop"]
	var base := cross_cell + Vector2i(3, -1)
	var slot := 0
	for d in [3, 1]:
		for k in kinds.size():
			if slot >= vs.size():
				break
			var v = vs[slot]
			slot += 1
			var cell := Vector2(base + Vector2i(k, 0 if d == 3 else 2))
			v.cancel_plan()
			v.grid_pos = cell
			v._apply_position()
			v.carry_kind = String(kinds[k])
			v.dir = d
			v.flip_h = false
			var cf: Array = v.bank.get("carry", {}).get(d, [])
			if cf.size() > 2:
				v.frame_i = 2
				v.texture = cf[2]
			elif not cf.is_empty():
				v.frame_i = 0
				v.texture = cf[0]
			v.run_plan([{"op": "wait", "secs": 90.0}])
	camera.position = iso(Vector2(base) + Vector2(1, 1)) + Vector2(0, -6)
	print("DEMO CARRY at ", base.x, ",", base.y)

# 让麦田长满，再派一个村民站进去，用来看"麦子挡腿"和收麦的过程
func _demo_field() -> void:
	if fields.is_empty():
		return
	for f in fields:
		f["growth"] = FIELD_GROW_HOURS
		_apply_crop_look(f)
	# 挑一格离房子远一点的田，不然村民会被房子挡住看不见
	var f0: Dictionary = fields[fields.size() / 2]
	for f in fields:
		var c: Vector2 = f["cell"]
		if not _building_near(int(c.x), int(c.y), 4):
			f0 = f
			break
	var cell: Vector2 = f0["cell"]
	var vs := _live_villagers()
	if not vs.is_empty():
		var v = vs[0]
		v.cancel_plan()
		v.grid_pos = cell
		v._apply_position()
		v.run_plan([{"op": "activity", "text": "站在麦田里"}, {"op": "wait", "secs": 60.0}])
	camera.position = iso(cell)
	print("DEMO FIELD at ", int(cell.x), ",", int(cell.y))

# 收割后的麦田长什么样（-- --demo-harvest）：先把田催熟，再按村民收割的方式
# 收掉一格，用来看"割完这一片矮下去"对不对。同一块田里的麦子必须一起变矮，
# 不然会高一块矮一块。
func _demo_harvest() -> void:
	if fields.is_empty():
		return
	for f in fields:
		f["growth"] = FIELD_GROW_HOURS
		_apply_crop_look(f)
	var mid: Dictionary = fields[fields.size() / 2]
	for f in fields:
		var c: Vector2 = f["cell"]
		if not _building_near(int(c.x), int(c.y), 4):
			mid = f
			break
	var cell: Vector2 = mid["cell"]
	print("DEMO HARVEST at %d,%d  plot=%d" % [
		int(cell.x), int(cell.y), _plot_index(int(cell.x), int(cell.y))])
	harvest_field(mid)
	var heights := {}
	for f in fields:
		var c: Vector2 = f["cell"]
		if _plot_index(int(c.x), int(c.y)) != _plot_index(int(cell.x), int(cell.y)):
			continue
		var sp = f["sprite"]
		var h := 0.0
		if is_instance_valid(sp):
			h = sp.region_rect.size.y * sp.scale.y
			if not sp.region_enabled:
				h = sp.texture.get_image().get_used_rect().size.y * sp.scale.y
		heights[int(round(h))] = int(heights.get(int(round(h)), 0)) + 1
	print("  同一块田里的麦子高度分布（像素:格数）: ", str(heights))
	print("  这块田 %d 格，村民来收一次大约得 %d 粮食（按格数给，和以前一格一格割的总量一样）" % [
		plot_cells(mid), int((5.0 + 3.5 * 0.5) * float(plot_cells(mid)))])
	camera.position = iso(cell)
	var vs := _live_villagers()
	if not vs.is_empty():
		var v = vs[0]
		v.cancel_plan()
		v.grid_pos = cell
		v._apply_position()
		v.run_plan([{"op": "activity", "text": "站在麦田里"}, {"op": "wait", "secs": 60.0}])

# 建造预览（-- --demo-build [建筑]）：把半透明的房子和地面上的"影子 + 占地圈"
# 摆出来，用来看新建时到底占哪几格、放得下放不下。
func _demo_build_preview() -> void:
	var cargs := OS.get_cmdline_user_args()
	var i := cargs.find("--demo-build")
	var place := cargs.has("--demo-place")
	if place and i < 0:
		i = cargs.find("--demo-place")
	var kind := "house"
	if i >= 0 and cargs.size() > i + 1:
		kind = String(cargs[i + 1])
	if not BUILD.has(kind):
		kind = "house"
	# 也可以点名放在某一格上（看"放不下"的红色圈）：--demo-build house 22 17
	if i >= 0 and cargs.size() > i + 3 and cargs[i + 2].is_valid_int() and cargs[i + 3].is_valid_int():
		if place:
			_add_building(kind, Vector2(Vector2i(int(cargs[i + 2]), int(cargs[i + 3]))))
			camera.position = _building_origin(kind, Vector2(Vector2i(int(cargs[i + 2]), int(cargs[i + 3])))) + Vector2(0, -30)
			print("DEMO PLACE %s at %s,%s" % [kind, cargs[i + 2], cargs[i + 3]])
			return
		ghost_force_cell = Vector2i(int(cargs[i + 2]), int(cargs[i + 3]))
		select_build(kind)
		_update_ghost()
		camera.position = _building_origin(kind, Vector2(ghost_force_cell)) + Vector2(0, -30)
		print("DEMO BUILD %s at %d,%d  ok=%s" % [
			kind, ghost_force_cell.x, ghost_force_cell.y, str(_can_build(kind, ghost_force_cell))])
		_ghost_geometry_report(kind, ghost_force_cell)
		return
	var spot := Vector2i(-1, -1)
	var centre := _map_center()
	for radius in range(3, 26):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var c := centre + Vector2i(dx, dy)
				if _can_build(kind, c):
					spot = c
					break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			break
	if spot.x < 0:
		return
	select_build(kind)
	if place:
		_add_building(kind, Vector2(spot))
		camera.position = _building_origin(kind, Vector2(spot)) + Vector2(0, -30)
		print("DEMO PLACE %s at %d,%d" % [kind, spot.x, spot.y])
		return
	ghost_force_cell = spot
	# 顺手在旁边摆一个"放不下"的红圈：挪一格盖在已有房子上
	_update_ghost()
	camera.position = _building_origin(kind, Vector2(spot)) + Vector2(0, -30)
	print("DEMO BUILD %s at %d,%d  ok=%s" % [
		kind, spot.x, spot.y, str(_can_build(kind, spot))])

func _building_near(x: int, y: int, r: int) -> bool:
	for b in buildings:
		var c: Vector2 = b["cell"]
		var f: Vector2 = b["foot"]
		if x >= int(c.x) - r and y >= int(c.y) - r \
			and x <= int(c.x + f.x) + r and y <= int(c.y + f.y) + r:
			return true
	return false

func _nearest_free_rect(foot: Vector2i) -> Vector2i:
	var centre := _map_center()
	for radius in range(4, 26):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var c := centre + Vector2i(dx, dy)
				if _can_build("house", c):
					return c
	return Vector2i(-1, -1)

# Builds a fresh world.  stage follows the old --stage debug switch (1 terrain,
# 2 +nature, 3 +village, 4 +villagers).
func start_world(stage: int) -> void:
	_init_arrays()
	_generate_terrain()
	var cargs := OS.get_cmdline_user_args()
	var calib := cargs.has("--calib")
	if calib:
		_calibrate()
	elif stage >= 3:
		_place_village()
	_build_roads()
	_build_ground_sprite()
	if not calib:
		if stage >= 2:
			_scatter_nature()
			tree_target = _count_trees()
		if stage >= 4:
			_spawn_villagers()
	if debug_grid:
		_draw_debug_grid()
	produce_slot = int(hour / PRODUCE_EVERY)
	_collect_water_and_shore()
	_collect_fields()
	if stage >= 3:
		_spawn_animals()
	_apply_season_props()
	if fx != null:
		fx.cam = camera
		_apply_weather()
	if town != null:
		town.setup(self)
	world_started = true

func new_game() -> void:
	reset_world()
	rng.seed = 20260922
	start_world(99)
	current_slot = _next_free_slot()
	camera.position = iso(_home_cell())
	_flash("新的小镇，加油！", Color(0.9, 0.96, 0.82))
	_refresh_hud()

# Anchor-tuning helper: lays one of every building out on a bare grid so the
# sprite base can be compared against its footprint outline (-- --calib --grid).
const CALIB_KINDS := ["house", "house_b", "house_c", "lumber", "quarry", "well", "warehouse", "market", "farm"]

func _calibrate() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--calib")
	var kind := "house"
	if idx >= 0 and args.size() > idx + 1 and not String(args[idx + 1]).begins_with("--"):
		kind = String(args[idx + 1])
	if kind == "none":
		# render an empty plot, so the calibration shot can be diffed against it
		calib_focus = iso(Vector2(_map_center())) + Vector2(0, HH - 60)
		return
	if not BUILD.has(kind):
		kind = "house"
	var spot := Vector2(_map_center() + Vector2i(-4, -4))
	_add_building(kind, spot, true)
	calib_focus = _building_origin(kind, spot) + Vector2(0, -60)
	_recompute_housing()

# Debug overlay used while tuning sprite anchors: outlines every tile diamond and
# tints the cells that count as blocked, so sprite bases can be compared with the
# grid they are supposed to sit on.  Enable with:  -- --grid
func _draw_debug_grid() -> void:
	var img_w := (mw + mh) * int(HW)
	var img_h := (mw + mh) * int(HH) + 64
	var canvas := Image.create_empty(img_w, img_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox := mh * int(HW)
	for y in mh:
		for x in mw:
			var c := iso(Vector2(x, y)) + Vector2(ox, 0)
			if blocked[_idx(x, y)]:
				_dbg_fill_diamond(canvas, c, Color(0.15, 0.35, 1.0, 0.28))
			_dbg_outline_diamond(canvas, c, Color(1.0, 0.85, 0.1, 0.55))
	var overlay := Sprite2D.new()
	overlay.name = "DebugGrid"
	overlay.texture = ImageTexture.create_from_image(canvas)
	overlay.centered = false
	overlay.position = Vector2(-mh * HW, 0.0)
	overlay.z_index = 900
	add_child(overlay)

func _dbg_set_px(canvas: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < canvas.get_width() and y < canvas.get_height():
		canvas.set_pixel(x, y, col)

func _dbg_outline_diamond(canvas: Image, c: Vector2, col: Color) -> void:
	var pts := [
		Vector2(c.x, c.y - HH),
		Vector2(c.x + HW, c.y),
		Vector2(c.x, c.y + HH),
		Vector2(c.x - HW, c.y),
	]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		for s in int(HW) + 1:
			var p := a.lerp(b, float(s) / float(HW))
			_dbg_set_px(canvas, int(round(p.x)), int(round(p.y)), col)

func _dbg_fill_diamond(canvas: Image, c: Vector2, col: Color) -> void:
	for dy in range(-int(HH), int(HH) + 1):
		var hw := int(HW * (1.0 - absf(float(dy)) / HH))
		for dx in range(-hw, hw + 1):
			_dbg_set_px(canvas, int(c.x) + dx, int(c.y) + dy, col)

func _init_arrays() -> void:
	terrain.resize(mw * mh)
	blocked.resize(mw * mh)
	roads.resize(mw * mh)
	lake_covered.resize(mw * mh)
	for i in terrain.size():
		terrain[i] = "grass"
		blocked[i] = false
		roads[i] = false
		lake_covered[i] = false

# Everything below is laid out relative to the map centre, so growing the map
# spreads the village, the fields and the lake out with it instead of pinning
# them to the north-west corner.
func _map_center() -> Vector2i:
	return Vector2i(mw / 2, mh / 2)

# corn fields: offset from the map centre + size in tiles
const FIELD_PLOTS := [
	{"cell": Vector2i(-15, -15), "size": Vector2i(8, 8)},
	{"cell": Vector2i(9, 10), "size": Vector2i(9, 9)},
]

func _plot_rect(plot: Dictionary) -> Rect2i:
	var off: Vector2i = plot["cell"]
	var size: Vector2i = plot["size"]
	return Rect2i(_map_center() + off, size)

# Camera home: the middle of the built-up part of the starting village, as an
# offset from the map centre.  The map centre itself is just the empty road
# crossing, and a plain centroid would be dragged off by the lumber camp and the
# farm, which sit far out at the corners.
const HOME_CELL := Vector2(4, -5)

# fixed once at world generation: growing the map must not move the village's
# road crossing or the camera's home position
var home_cell := Vector2.ZERO
var cross_cell := Vector2i(24, 24)

func _home_cell() -> Vector2:
	if home_cell == Vector2.ZERO:
		home_cell = Vector2(_map_center()) + HOME_CELL
	return home_cell

func _generate_terrain() -> void:
	var c := _map_center()
	cross_cell = c
	home_cell = Vector2.ZERO
	# the two main roads cross at the village centre
	for x in mw:
		_set_terrain(x, c.y, "path")
	for y in range(c.y - 6, mh):
		_set_terrain(c.x, y, "path")
	# fenced corn fields
	for plot in FIELD_PLOTS:
		var r := _plot_rect(plot)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_set_terrain(x, y, "field")
	# random tilled patches - one per ~20 tiles, so the density does not change
	# when the map grows
	for i in int(round(float(mw * mh) / 19.6)):
		var x := rng.randi_range(1, mw - 3)
		var y := rng.randi_range(1, mh - 3)
		for dy in 2:
			for dx in 2:
				if rng.randf() < 0.7 and terrain[_idx(x + dx, y + dy)] == "grass":
					_set_terrain(x + dx, y + dy, "dirt")
	_shape_lake()
	for i in terrain.size():
		if terrain[i] == "water":
			blocked[i] = true

func _popcount(v: int) -> int:
	var n := 0
	var x := v
	while x != 0:
		n += x & 1
		x >>= 1
	return n

# bit meaning taken from the measured table above: bit0 south, bit1 east,
# bit2 west, bit3 north
func _block_mask(bx: int, by: int) -> int:
	var m := 0
	if terrain[_idx(bx + 1, by + 1)] == "water":
		m |= 1
	if terrain[_idx(bx + 1, by)] == "water":
		m |= 2
	if terrain[_idx(bx, by + 1)] == "water":
		m |= 4
	if terrain[_idx(bx, by)] == "water":
		m |= 8
	return m

func _apply_block_mask(bx: int, by: int, mask: int) -> void:
	_set_terrain(bx + 1, by + 1, "water" if (mask & 1) != 0 else "grass")
	_set_terrain(bx + 1, by, "water" if (mask & 2) != 0 else "grass")
	_set_terrain(bx, by + 1, "water" if (mask & 4) != 0 else "grass")
	_set_terrain(bx, by, "water" if (mask & 8) != 0 else "grass")

# The atlas only ships some of the sixteen block shapes, so every block is
# snapped to the closest one it does ship and the terrain is rewritten to match:
# what you see on the water's edge is exactly what blocks walking.
func _snap_lake_mask(mask: int) -> int:
	var want := _popcount(mask)
	var best := -1
	var best_d := 99
	var best_same := -1
	var best_same_d := 99
	for key in LAKE_BLOCKS.keys():
		var k: int = key
		var d := _popcount(mask ^ k)
		if d < best_d:
			best_d = d
			best = k
		if _popcount(k) == want and d < best_same_d:
			best_same_d = d
			best_same = k
	if best_same >= 0:
		return best_same
	return best

# The lake is generated straight from the tile set: a circle in screen space
# decides, for every 2x2 block, whether it is open water, land, or one of the
# twelve bank shapes the atlas actually ships.  Because the shape is only ever
# made of shapes that exist, there is nothing to "snap" - which is what used to
# leave stray water blocks and stair-stepped shores behind.
func _shape_lake() -> void:
	lake_blocks.clear()
	for i in lake_covered.size():
		lake_covered[i] = false
	# The lake used to be assembled out of the original game's 2x2 bank blocks.
	# Those belong to its multi-level maps, so a pond built from them always came
	# out as a staircase of terraces with stray shallow pools.  Now the water is
	# one flat sheet of 1x1 water tiles with a clean isometric shoreline.
	var centre := iso(Vector2(float(cross_cell.x - 11), float(cross_cell.y + 15)))
	var radius := LAKE_RADIUS * HW
	for y in mh:
		for x in mw:
			var kind := String(terrain[_idx(x, y)])
			if kind != "grass" and kind != "field" and kind != "dirt":
				continue
			var screen := iso(Vector2(float(x), float(y))) + Vector2(0, HH)
			if screen.distance_to(centre) < radius:
				terrain[_idx(x, y)] = "water"
	# 别留下孤零零的一格水（地形上正好有块土斑时会被切断，看着像 bug）
	for y in mh:
		for x in mw:
			if terrain[_idx(x, y)] != "water":
				continue
			var lonely := true
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _inside(x + step.x, y + step.y) and terrain[_idx(x + step.x, y + step.y)] == "water":
					lonely = false
					break
			if lonely:
				terrain[_idx(x, y)] = "grass"

# Which bank shape to use for a block: convert "the middle of the lake lies that
# way" into the block's eight compass directions.  Every value returned exists in
# LAKE_BLOCKS.
func _shore_mask(towards_centre: Vector2) -> int:
	var dx := (towards_centre.x / HW + towards_centre.y / HH) * 0.5
	var dy := (towards_centre.y / HH - towards_centre.x / HW) * 0.5
	if absf(dx) > absf(dy) * 1.8:
		return 2 if dx > 0.0 else 4      # water to the east / west of the block
	if absf(dy) > absf(dx) * 1.8:
		return 1 if dy > 0.0 else 8      # water to the south / north
	if dx > 0.0:
		return 3 if dy > 0.0 else 10     # south-east / north-east
	return 5 if dy > 0.0 else 12        # south-west / north-west

func _init_layers() -> void:
	object_layer = Node2D.new()
	object_layer.name = "Objects"
	object_layer.y_sort_enabled = true
	add_child(object_layer)
	fx = Node2D.new()
	fx.name = "FX"
	fx.set_script(load("res://scripts/fx.gd"))
	add_child(fx)
	daynight = CanvasModulate.new()
	daynight.name = "DayNight"
	add_child(daynight)
	town = Node2D.new()
	town.name = "Town"
	town.set_script(load("res://scripts/town.gd"))
	add_child(town)
	ghost = Node2D.new()
	ghost.name = "Ghost"
	ghost.visible = false
	ghost.z_index = 50
	add_child(ghost)
	# 换建筑时只清"房子本体"那一个容器，地面上的那个"影子+占地圈"要一直在，
	# 不然鼠标一动就闪。占地圈画在房子底下（z 比本体小 1），玩家能一眼看出
	# 这栋房子会占哪几格。
	ghost_marker = Node2D.new()
	ghost_marker.name = "GhostGround"
	ghost_marker.visible = false
	# 挂在场景根上（不是 ghost 的子节点）：ghost 的 modulate 会染到子节点上，
	# 而且地面上的圈要跟着地砖一起参与 y 排序，压在树、房子下面才自然
	object_layer.add_child(ghost_marker)
	ghost_shadow = Polygon2D.new()
	ghost_shadow.name = "Shadow"
	ghost_shadow.antialiased = true
	ghost_marker.add_child(ghost_shadow)
	ghost_outline = Line2D.new()
	ghost_outline.name = "Outline"
	ghost_outline.width = 2.0
	ghost_outline.closed = true
	ghost_marker.add_child(ghost_outline)
	ghost_art = Node2D.new()
	ghost_art.name = "GhostArt"
	ghost.add_child(ghost_art)

func _build_ground_sprite() -> void:
	var tiles := _make_terrain_variants()
	var road_tiles := _make_road_variants()
	var img_w := (mw + mh) * int(HW)
	var img_h := (mw + mh) * int(HH) + 64
	var canvas := Image.create_empty(img_w, img_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox := mh * int(HW)
	for y in mh:
		for x in mw:
			var i := _idx(x, y)
			if lake_covered[i]:
				continue
			var kind := String(terrain[i])
			# every water cell uses the same flat tile, so the lake reads as one
			# sheet of water instead of a quilt of lighter diamonds
			_blit_tile(canvas, tiles[kind], x, y, ox, 0)
	# roads go over the ground but under every object
	for y in mh:
		for x in mw:
			var i := _idx(x, y)
			if not roads[i] or lake_covered[i]:
				continue
			_blit_tile(canvas, road_tiles, x, y, ox, 11)
	# 2x2 water blocks last: their banks and cliffs overhang the tiles behind
	for b in lake_blocks:
		_blit_block(canvas, b, ox)
	var ground := Sprite2D.new()
	ground.texture = ImageTexture.create_from_image(canvas)
	ground.centered = false
	ground.position = Vector2(-mh * HW, 0.0)
	ground.z_index = -100
	ground.name = "Ground"
	ground.self_modulate = _ground_tint()
	add_child(ground)

func _make_road_variants() -> Array:
	var out: Array = []
	for p in ROAD_TILES:
		var img: Image = load(TT_ROAD + p).get_image()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		out.append({"img": img, "used": img.get_used_rect()})
	return out

# ---------- map growth: the player pays to add a ring of land ----------

func grow_cost() -> Dictionary:
	var steps := float(mw - START_W) / float(GROW_STEP)
	var f := pow(GROW_STEP_COST_SCALE, steps)
	return {
		"gold": int(round(GROW_COST_GOLD * f)),
		"wood": int(round(GROW_COST_WOOD * f)),
		"stone": int(round(GROW_COST_STONE * f)),
	}

func can_grow() -> bool:
	if mw + GROW_STEP > MAX_W or mh + GROW_STEP > MAX_H:
		return false
	var c := grow_cost()
	return gold >= float(c["gold"]) and wood >= float(c["wood"]) and stone >= float(c["stone"])

func grow_map() -> void:
	if mw + GROW_STEP > MAX_W or mh + GROW_STEP > MAX_H:
		_flash("地图已经到上限 %d×%d" % [MAX_W, MAX_H], Color(1, 0.85, 0.45))
		return
	var c := grow_cost()
	if not can_grow():
		_flash("还差材料：需要 金%d 木%d 石%d" % [int(c["gold"]), int(c["wood"]), int(c["stone"])], Color(1, 0.55, 0.5))
		return
	gold -= float(c["gold"])
	wood -= float(c["wood"])
	stone -= float(c["stone"])
	_resize_map(mw + GROW_STEP, mh + GROW_STEP)
	_rebuild_ground()
	_refresh_hud()
	_flash("地图扩大到 %d×%d" % [mw, mh], Color(0.78, 0.95, 0.7))

# grows the grid to the south-east: every existing cell keeps its coordinates, so
# nothing already built has to move.  The arrays are rebuilt and the villagers are
# re-pointed at them.
func _resize_map(nw: int, nh: int) -> void:
	var old_w := mw
	var old_h := mh
	var nt: Array = []
	var nb: Array = []
	var nr: Array = []
	var nc: Array = []
	nt.resize(nw * nh)
	nb.resize(nw * nh)
	nr.resize(nw * nh)
	nc.resize(nw * nh)
	for y in nh:
		for x in nw:
			var i := y * nw + x
			if x < old_w and y < old_h:
				var oi := y * old_w + x
				nt[i] = terrain[oi]
				nb[i] = blocked[oi]
				nr[i] = roads[oi]
				nc[i] = lake_covered[oi]
			else:
				nt[i] = "grass"
				nb[i] = false
				nr[i] = false
				nc[i] = false
	mw = nw
	mh = nh
	terrain = nt
	blocked = nb
	roads = nr
	lake_covered = nc
	for v in villagers:
		if is_instance_valid(v):
			v.map_w = mw
			v.map_h = mh
			v.blocked_cells = blocked
			v.road_cells = roads
	_dress_new_land(old_w, old_h)

# the fresh strip gets the same kind of dressing as the original map: the village
# road carries on through it, plus wild trees, rocks and ground cover
func _dress_new_land(old_w: int, old_h: int) -> void:
	for x in mw:
		_road_cell(Vector2i(x, cross_cell.y))
	for y in range(cross_cell.y - 6, mh):
		_road_cell(Vector2i(cross_cell.x, y))
	for y in mh:
		for x in mw:
			if x < old_w and y < old_h:
				continue
			if not _free_area(x, y, 1, 1, "grass"):
				continue
			var roll := rng.randf()
			if roll < 0.055:
				_add_tree(Vector2(x, y))
			elif roll < 0.073:
				_add_resource("rock", "stone", Vector2(x, y), 14.0, 2)
			elif roll < 0.15:
				var r2 := rng.randf()
				_add_decor("flower" if r2 > 0.75 else ("mushroom" if r2 > 0.66 else "tuft"), Vector2(x, y))
	# 新地也是林子的一部分，补种的目标跟着涨
	tree_target = maxi(tree_target, _count_trees())

func _rebuild_ground() -> void:
	var old := get_node_or_null("Ground")
	if old:
		old.free()
	var grid := get_node_or_null("DebugGrid")
	if grid:
		grid.free()
	_build_ground_sprite()
	if debug_grid:
		_draw_debug_grid()

# Stamps one 2x2 lake block.  The block's own diamond spans 64px of height, its
# bottom vertex sitting 48px below the top vertex of its north cell, which is
# where iso() puts the block's top-left cell.
func _blit_block(canvas: Image, b: Dictionary, ox: int) -> void:
	var src: Image = load(TT_WATER + String(b["file"])).get_image().duplicate() as Image
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	if bool(b["mirror"]):
		src.flip_x()
	if bool(b.get("flip_v", false)):
		src.flip_y()
	var used := src.get_used_rect()
	var cell: Vector2i = b["cell"]
	var base := iso(Vector2(cell.x, cell.y))
	var dst := Vector2i(
		int(base.x) + ox - int(used.position.x) - int(used.size.x / 2),
		int(base.y) + 48 - int(used.position.y) - int(used.size.y)
	)
	canvas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), dst)

# Paved roads: the two main roads plus a spur from every building to the closest
# road, so the village ends up connected.  Villagers walk faster on them.
func _build_roads() -> void:
	for i in roads.size():
		roads[i] = false
	var c := cross_cell
	for x in mw:
		_road_cell(Vector2i(x, c.y))
	for y in range(c.y - 6, mh):
		_road_cell(Vector2i(c.x, y))
	for b in buildings:
		var foot: Vector2 = b["foot"]
		var cell: Vector2 = b["cell"]
		var door := Vector2i(int(cell.x) + int(foot.x) - 1, int(cell.y) + int(foot.y) - 1)
		var start := _free_door_cell(door)
		if start.x >= 0:
			_connect_road(start)

func _road_ok(x: int, y: int) -> bool:
	if not _inside(x, y):
		return false
	var i := _idx(x, y)
	return terrain[i] != "water" and not blocked[i] and not lake_covered[i]

func _road_cell(c: Vector2i) -> void:
	if _road_ok(c.x, c.y):
		roads[_idx(c.x, c.y)] = true

# nearest free tile in front of a building (the door tile itself is inside the
# building's own footprint, so look at its neighbours)
func _free_door_cell(door: Vector2i) -> Vector2i:
	for step in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, -1), Vector2i(-1, 0)]:
		var c: Vector2i = door + step
		if _road_ok(c.x, c.y):
			return c
	return Vector2i(-1, -1)

# Breadth-first search for the closest existing road, then pave the way there.
func _connect_road(start: Vector2i) -> void:
	if roads[_idx(start.x, start.y)]:
		return
	var came := {start: start}
	var queue: Array = [start]
	var found := Vector2i(-1, -1)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if roads[_idx(cur.x, cur.y)]:
			found = cur
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + step
			if came.has(nxt) or not _road_ok(nxt.x, nxt.y):
				continue
			came[nxt] = cur
			queue.append(nxt)
	if found.x < 0:
		return
	var node := found
	while node != start:
		roads[_idx(node.x, node.y)] = true
		node = came[node]

# Blends one isometric tile into the pre-rendered ground canvas, aligned by the
# tile's own transparent bbox so tiles with different internal padding still
# snap to the grid.
func _blit_tile(canvas: Image, options: Array, x: int, y: int, ox: int, salt: int) -> void:
	var hv: int = x * 374761393 + y * 668265263 + salt * 97
	hv = (hv ^ (hv >> 13)) * 1274126177
	var pick: int = absi(hv ^ (hv >> 16)) % options.size()
	var entry: Dictionary = options[pick]
	var base_img: Image = entry["img"]
	var used: Rect2i = entry["used"]
	var src: Image = base_img.duplicate() as Image
	if ((x * 31 + y * 17 + salt) % 2) == 0:
		src.flip_x()
	# NOTE: never flip vertically - a Townsmen tile keeps its diamond in the
	# upper half of the canvas, so a vertical flip would break the grid.
	var dst := Vector2i(
		int(iso(Vector2(x, y)).x) + ox - int(used.position.x) - int(used.size.x / 2),
		int(iso(Vector2(x, y)).y) - int(used.position.y) - int(HH)
	)
	canvas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), dst)

func _make_terrain_variants() -> Dictionary:
	var out := {}
	for kind in TT_TILES:
		var list: Array = []
		for p in TT_TILES[kind]:
			var img: Image = load(TT + _season_tile_path(String(p))).get_image()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			# tiles are not all anchored the same way inside their canvas, so
			# remember each one's own alpha box and align by the top vertex
			list.append({"img": img, "used": img.get_used_rect()})
		out[kind] = list
	return out

func _mark_blocked(cell: Vector2, foot: Vector2, value: bool = true) -> void:
	for dy in int(foot.y):
		for dx in int(foot.x):
			var x := int(cell.x) + dx
			var y := int(cell.y) + dy
			if _inside(x, y):
				blocked[_idx(x, y)] = value

func _free_area(cx: int, cy: int, w: int, h: int, want: String) -> bool:
	for dy in h:
		for dx in w:
			var x := cx + dx
			var y := cy + dy
			if not _inside(x, y):
				return false
			var i := _idx(x, y)
			if blocked[i] or terrain[i] != want or roads[i]:
				return false
	return true

func _can_build(kind: String, cell: Vector2i) -> bool:
	var foot: Vector2 = BUILD[kind]["foot"]
	for dy in int(foot.y):
		for dx in int(foot.x):
			var x := cell.x + dx
			var y := cell.y + dy
			if not _inside(x, y):
				return false
			var i := _idx(x, y)
			if blocked[i] or terrain[i] == "water":
				return false
			if _villager_on(x, y):
				return false
	if _too_close_to_building(cell, foot):
		return false
	return true

# One empty tile around every building.  A Townsmen building sprite is wider than
# its footprint (roof overhang, fences), so two buildings packed edge to edge
# visibly clip into each other - keeping a lane between them avoids that.
func _too_close_to_building(cell: Vector2i, foot: Vector2) -> bool:
	for idx in buildings.size():
		# the building being relocated must not block its own new spot
		if idx == move_index:
			continue
		var b: Dictionary = buildings[idx]
		var bf: Vector2 = b["foot"]
		var bx := int(b["cell"].x)
		var by := int(b["cell"].y)
		var gap_x := maxi(cell.x - (bx + int(bf.x)), bx - (cell.x + int(foot.x)))
		var gap_y := maxi(cell.y - (by + int(bf.y)), by - (cell.y + int(foot.y)))
		if gap_x < 1 and gap_y < 1:
			return true
	return false

func _villager_on(x: int, y: int) -> bool:
	for v in villagers:
		if not is_instance_valid(v):
			continue
		if absf(v.grid_pos.x - float(x)) < 0.9 and absf(v.grid_pos.y - float(y)) < 0.9:
			return true
	return false

# Builds a sprite whose alpha bounding box sits with its bottom-centre on the
# node origin, which is where an isometric object actually touches the ground.
func _tt_sprite(path: String) -> Sprite2D:
	var tex: Texture2D = load(TT + path)
	var img := tex.get_image()
	var used := img.get_used_rect()
	var size := Vector2(img.get_width(), img.get_height())
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	var anchor_x := float(used.position.x) + float(used.size.x) * 0.5
	var anchor_y := float(used.position.y) + float(used.size.y)
	s.offset = Vector2(size.x * 0.5 - anchor_x, size.y * 0.5 - anchor_y)
	return s

# Local offset from the footprint centre down to its front corner.
func _front_offset(foot: Vector2) -> Vector2:
	return Vector2((foot.x - foot.y) * HH, (foot.x + foot.y) * HH * 0.5 - HH)

func _make_building_node(kind: String) -> Node2D:
	var def: Dictionary = BUILD[kind]
	var foot: Vector2 = def["foot"]
	var node := Node2D.new()
	# the node origin is the footprint's front corner, so every child sits at a
	# small local offset from it (0 for a single sprite)
	var front := _front_offset(foot)
	if def["art"] == "farm":
		for j in int(foot.y):
			for i in int(foot.x):
				var sp := _tt_sprite(FARM_TILE)
				var cx := float(i) - foot.x * 0.5 + 0.5
				var cy := float(j) - foot.y * 0.5 + 0.5
				# each tile keeps its own ground anchor, expressed relative to the
				# footprint's front corner (which is the node origin)
				sp.position = Vector2((cx - cy) * HW, (cx + cy) * HH) - front
				node.add_child(sp)
	else:
		var info: Dictionary = TT_BUILDINGS[def["art"]]
		var sp := _tt_sprite(info["path"])
		sp.position = Vector2(0, -(float(info.get("base_lift", 0.0)) + base_lift_bias))
		node.add_child(sp)
		var pic := sp.texture.get_image().get_used_rect()
		node.set_meta("art_h", float(pic.size.y))
	return node

func _building_origin(kind: String, cell: Vector2) -> Vector2:
	var foot: Vector2 = BUILD[kind]["foot"]
	# the node origin doubles as the sprite's ground anchor and as its Y-sort key,
	# so it has to be the footprint's front corner - the point where the drawn
	# base actually touches the ground
	return iso(cell + foot * 0.5) + _front_offset(foot)

func _add_building(kind: String, cell: Vector2, silent: bool = false) -> void:
	var node := _make_building_node(kind)
	node.position = _building_origin(kind, cell)
	node.name = "B_" + kind
	object_layer.add_child(node)
	buildings.append({"kind": kind, "cell": cell, "node": node, "foot": BUILD[kind]["foot"]})
	_mark_blocked(cell, BUILD[kind]["foot"])
	if kind == "pasture":
		# a new pen means the flock moves in
		_move_flock_to(cell)
	if not silent:
		_recompute_housing()
		_refresh_hud()

# up to four sheep settle in a pen as soon as it is built
func _move_flock_to(cell: Vector2) -> void:
	var moved := 0
	for a in animals:
		if not is_instance_valid(a) or String(a.species) != "sheep":
			continue
		if moved >= 4:
			break
		a.setup(self, "sheep", cell + Vector2(1.5, 1.5) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9)))
		moved += 1

# starting village - spread out with a lane between buildings so their sprites
# do not run through each other
const VILLAGE_PLAN := [
	["lumber", Vector2(-20, -20)],
	["well", Vector2(-2, -7)],
	["house", Vector2(4, -10)],
	["house_b", Vector2(10, -6)],
	["market", Vector2(15, -15)],
	["warehouse", Vector2(7, 4)],
	["house_c", Vector2(-7, 6)],
	["house", Vector2(-17, 1)],
	["farm", Vector2(9, 10)],
	# 渔舍挨着湖，教堂在村东头，村民平时有地方去
	["fishing", Vector2(-13, 13)],
	["church", Vector2(19, 9)],
]

func _place_village() -> void:
	# offsets from the map centre, so the village keeps its shape and its lane
	# widths whatever the map size is
	var c := Vector2(_map_center())
	for entry in VILLAGE_PLAN:
		_place_at(entry[0], c + entry[1])
	_recompute_housing()

# Puts a building on (or as close as possible to) the wanted cell, so the
# starting village never ends up inside water, a tree or another building.
func _place_at(kind: String, cell: Vector2) -> void:
	var start := Vector2i(int(cell.x), int(cell.y))
	if _can_build(kind, start):
		_add_building(kind, Vector2(start), true)
		return
	for radius in range(1, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var c := Vector2i(start.x + dx, start.y + dy)
				if _can_build(kind, c):
					_add_building(kind, Vector2(c), true)
					return

func _level_of(b: Dictionary) -> int:
	return clampi(int(b.get("level", 1)), 1, MAX_LEVEL)

func _level_mult(b: Dictionary) -> float:
	return LEVEL_MULT[_level_of(b) - 1]

func _recompute_housing() -> void:
	var before := housing
	housing = 0
	for b in buildings:
		var base := int(BUILD[b["kind"]].get("housing", 0))
		if base > 0:
			housing += int(round(float(base) * _level_mult(b)))
	# 多出来的床位立刻开始"招人"：房子刚建好就有人来住
	if housing > before:
		stir_immigration()

func _scatter_nature() -> void:
	# densities stay constant per tile, so a bigger map means more forest, rocks
	# and ground cover instead of a bare plain
	var area_scale := float(mw * mh) / (28.0 * 28.0)
	var extra_tries := int(area_scale + 1.0)
	var placed := 0
	var tries := 0
	while placed < int(round(52.0 * area_scale)) and tries < 4000 * extra_tries:
		tries += 1
		var x := rng.randi_range(0, mw - 1)
		var y := rng.randi_range(0, mh - 1)
		if not _free_area(x, y, 1, 1, "grass"):
			continue
		_add_tree(Vector2(x, y))
		placed += 1
	placed = 0
	tries = 0
	while placed < int(round(16.0 * area_scale)) and tries < 2000 * extra_tries:
		tries += 1
		var x := rng.randi_range(0, mw - 1)
		var y := rng.randi_range(0, mh - 1)
		if not _free_area(x, y, 1, 1, "grass") and not _free_area(x, y, 1, 1, "dirt"):
			continue
		_add_resource("rock", "stone", Vector2(x, y), 14.0, 2)
		placed += 1
	# ground cover: tufts, flowers and mushrooms, like the real maps
	placed = 0
	tries = 0
	while placed < int(round(70.0 * area_scale)) and tries < 4000 * extra_tries:
		tries += 1
		var x := rng.randi_range(0, mw - 1)
		var y := rng.randi_range(0, mh - 1)
		if not _free_area(x, y, 1, 1, "grass"):
			continue
		var roll := rng.randf()
		var group := "tuft"
		if roll > 0.75:
			group = "flower"
		elif roll > 0.66:
			group = "mushroom"
		_add_decor(group, Vector2(x, y))
		placed += 1
	# 麦田四周原来围了整整一圈"行道树"，一大片树把田圈在中间，太挤也太怪。
	# 现在只在四个角各留一棵，田边空出来（也能腾地方盖房子）。
	for plot in FIELD_PLOTS:
		var r := _plot_rect(plot)
		_add_decor("avenue_tree", Vector2(r.position.x - 1, r.position.y - 1))
		_add_decor("avenue_tree", Vector2(r.end.x, r.position.y - 1))
		_add_decor("avenue_tree", Vector2(r.position.x - 1, r.end.y))
		_add_decor("avenue_tree", Vector2(r.end.x, r.end.y))

func _prop_sprite(group: String) -> Sprite2D:
	var list: Array = TT_PROPS[group]
	var p: String = list[rng.randi_range(0, list.size() - 1)]
	var sp := _tt_sprite(_season_prop_path(p))
	# remember where this prop came from so it can put on its autumn coat or
	# its winter snow when the season turns
	prop_nodes.append({"node": sp, "path": p, "group": group})
	return sp

func _add_decor(group: String, cell: Vector2) -> void:
	if not _inside(int(cell.x), int(cell.y)):
		return
	if blocked[_idx(int(cell.x), int(cell.y))] or roads[_idx(int(cell.x), int(cell.y))]:
		return
	var sprite := _prop_sprite(group)
	sprite.position = iso(cell) + Vector2(0, HH)
	sprite.flip_h = rng.randf() < 0.5
	object_layer.add_child(sprite)

func _add_resource(kind: String, group: String, cell: Vector2, amount: float, hits: int) -> void:
	var sprite := _prop_sprite(group)
	sprite.position = iso(cell) + Vector2(0, HH)
	var s := 0.92 + rng.randf() * 0.2
	sprite.scale = Vector2(s, s)
	sprite.flip_h = rng.randf() < 0.5
	object_layer.add_child(sprite)
	resources.append({
		"kind": kind, "resource": "wood" if kind == "tree" else "stone",
		"group": group,
		"cell": cell, "sprite": sprite, "amount": amount, "hits": hits,
		"base_scale": Vector2(s, s), "busy": false,
		"stage": 2, "regrow": 0.0,
	})
	_mark_blocked(cell, Vector2(1, 1))

# ---------- trees: 砍倒留桩，慢慢长回来 ----------

func _tree_path(kind: int, stage: int) -> String:
	var k: Dictionary = TREE_KINDS.get(kind, TREE_KINDS[0])
	return String(k[TREE_STAGE_KEYS[clampi(stage, 0, 2)]])

func _tree_next_hours(stage: int) -> float:
	if stage <= 0:
		return TREE_STUMP_HOURS
	if stage == 1:
		return TREE_YOUNG_HOURS
	return 0.0

func _add_tree(cell: Vector2, stage: int = 2, tree_kind: int = -1, grow_t: float = -1.0) -> void:
	if tree_kind < 0:
		tree_kind = int(TREE_KINDS.keys()[rng.randi_range(0, TREE_KINDS.size() - 1)])
	stage = clampi(stage, 0, 2)
	var p := _tree_path(tree_kind, stage)
	var sprite := _tt_sprite(_season_prop_path(p))
	sprite.position = iso(cell) + Vector2(0, HH)
	var s := 0.92 + rng.randf() * 0.2 if stage == 2 else 1.0
	sprite.scale = Vector2(s, s)
	sprite.flip_h = rng.randf() < 0.5
	object_layer.add_child(sprite)
	prop_nodes.append({"node": sprite, "path": p, "group": "tree"})
	resources.append({
		"kind": "tree", "resource": "wood", "group": "tree",
		"tree_kind": tree_kind, "stage": stage,
		"regrow": grow_t if grow_t >= 0.0 else 0.0,
		"cell": cell, "sprite": sprite,
		"amount": TREE_AMOUNT if stage == 2 else 0.0,
		"hits": TREE_HITS if stage == 2 else 0,
		"base_scale": Vector2(s, s), "busy": false,
	})
	_mark_blocked(cell, Vector2(1, 1), stage == 2)

# 砍秃的林子会慢慢补回来：每隔一段时间在空草地上冒一棵新苗
func _reforest() -> void:
	if _count_trees() >= tree_target or resources.is_empty():
		return
	# 新苗长在老树边上，看起来才像林子自己扩
	for attempt in 60:
		var base = resources[rng.randi_range(0, resources.size() - 1)]
		if String(base.get("kind", "")) != "tree":
			continue
		var c: Vector2 = base["cell"]
		var x := int(round(c.x)) + rng.randi_range(-3, 3)
		var y := int(round(c.y)) + rng.randi_range(-3, 3)
		if not _inside(x, y) or not _grass_ok(x, y):
			continue
		_add_tree(Vector2(x, y), 1)
		return

func _count_trees() -> int:
	var n := 0
	for r in resources:
		if String(r.get("kind", "")) == "tree":
			n += 1
	return n

func _count_big_trees() -> int:
	var n := 0
	for r in resources:
		if String(r.get("kind", "")) == "tree" and int(r.get("hits", 0)) > 0:
			n += 1
	return n

# 盖房子时清掉占地里的树苗和树桩（它们本来就不挡路）
func _clear_soft_trees(cell: Vector2, foot: Vector2) -> void:
	for i in range(resources.size() - 1, -1, -1):
		var r: Dictionary = resources[i]
		if String(r.get("kind", "")) != "tree" or int(r.get("stage", 2)) >= 2:
			continue
		var c: Vector2 = r["cell"]
		if c.x < cell.x or c.y < cell.y or c.x >= cell.x + foot.x or c.y >= cell.y + foot.y:
			continue
		_remove_resource(r)

# stage 0 = 刚砍倒的树桩, 1 = 小树, 2 = 大树。树桩和小树让出格子，走路不受影响。
func _set_tree_stage(r: Dictionary, stage: int) -> void:
	stage = clampi(stage, 0, 2)
	r["stage"] = stage
	r["regrow"] = 0.0
	var is_big := stage == 2
	r["hits"] = TREE_HITS if is_big else 0
	r["amount"] = TREE_AMOUNT if is_big else 0.0
	var s := Vector2(r.get("base_scale", Vector2.ONE))
	if not is_big:
		s = Vector2.ONE
	r["base_scale"] = s
	var p := _tree_path(int(r.get("tree_kind", 0)), stage)
	var sp = r.get("sprite")
	if is_instance_valid(sp):
		_apply_prop_texture(sp, _season_prop_path(p))
		sp.modulate = Color.WHITE
		sp.scale = s
		# 季节换装靠 prop_nodes 里记的路径，换阶段时也要跟着改
		for e in prop_nodes:
			if e["node"] == sp:
				e["path"] = p
				break
	_mark_blocked(Vector2(r["cell"]), Vector2(1, 1), is_big)

func _remove_resource(r: Dictionary) -> void:
	_mark_blocked(Vector2(r["cell"]), Vector2(1, 1), false)
	var sp = r.get("sprite")
	if is_instance_valid(sp):
		sp.queue_free()
	resources.erase(r)
	r["busy"] = false

func _grow_trees(hours: float) -> void:
	for r in resources:
		if String(r.get("kind", "")) != "tree" or int(r.get("stage", 2)) >= 2:
			continue
		var c: Vector2 = r["cell"]
		var x := int(round(c.x))
		var y := int(round(c.y))
		if not _inside(x, y):
			_remove_resource(r)
			continue
		# 有人站在树桩上、或者那块地已经盖了东西，就先别长
		if _villager_on(x, y) or blocked[_idx(x, y)]:
			continue
		r["regrow"] = float(r.get("regrow", 0.0)) + hours
		var stage := int(r.get("stage", 0))
		if float(r["regrow"]) >= _tree_next_hours(stage):
			_set_tree_stage(r, stage + 1)

func _spawn_villagers() -> void:
	for n in population:
		_spawn_one_villager()

func _spawn_one_villager(is_child: bool = false, near := Vector2.ZERO) -> void:
	var villager := Sprite2D.new()
	villager.set_script(load("res://scripts/villager.gd"))
	object_layer.add_child(villager)
	var start := _random_free_cell()
	if near != Vector2.ZERO and _inside(int(near.x), int(near.y)) and not blocked[_idx(int(near.x), int(near.y))]:
		start = near
	villager.setup(start, rng, mw, mh, blocked, roads)
	villager.raw_speed = 1.5 + rng.randf() * 0.9
	villager.set_identity(_make_name(), rng.randf() < 0.5, is_child, day_number)
	villager.set_traits(_random_traits(1 if is_child else 2))
	villager.mood = 80.0 if is_child else clampf(happiness + rng.randf_range(-12.0, 12.0), 10.0, 100.0)
	villager.mood_target = happiness
	villager.set_time_scale(time_scale())
	villager.refresh_skill()
	villagers.append(villager)

# two personality traits each - they colour the dialogue and how hard the
# villager works
func _random_traits(n: int) -> Array:
	var pool: Array = ["勤劳", "懒散", "开朗", "内向", "贪吃", "急性子", "慢性子",
		"爱干净", "爱热闹", "爱读书", "爱喝酒", "爱钓鱼"]
	if town != null and "TRAIT_POOL" in town:
		pool = (town.TRAIT_POOL as Array).duplicate()
	pool.shuffle()
	var out: Array = []
	for i in mini(n, pool.size()):
		out.append(pool[i])
	return out

func _random_free_cell() -> Vector2:
	for attempt in 600:
		var x := rng.randi_range(1, mw - 2)
		var y := rng.randi_range(1, mh - 2)
		if not blocked[_idx(x, y)]:
			return Vector2(x, y)
	return Vector2(mw * 0.5, mh * 0.5)

# ---------------------------------------------------------------- the animals
# Sheep graze on the meadow (and around the pen once one is built), ducks
# paddle about on the lake, the dog and the cat belong to the village, and deer
# and boar keep to the trees at the edge of the map.  behaviour lives in
# scripts/animal.gd.
const ANIMAL_PLAN := [
	["sheep", 4], ["duck", 3], ["dog", 1], ["cat", 1], ["deer", 2], ["boar", 1],
]

func _spawn_animals() -> void:
	for entry in ANIMAL_PLAN:
		var sp := String(entry[0])
		for n in int(entry[1]):
			# a little scatter so two animals never start on the same tile
			var jitter := Vector2.ZERO
			if sp != "duck":     # ducks stay on the water they were put in
				jitter = Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
			_spawn_animal(sp, _animal_home(sp) + jitter)

func _spawn_animal(sp: String, cell: Vector2) -> Node2D:
	var animal := Sprite2D.new()
	animal.name = "A_" + sp
	animal.set_script(load("res://scripts/animal.gd"))
	object_layer.add_child(animal)
	animal.setup(self, sp, cell)
	animals.append(animal)
	return animal

# where a species feels at home - picked off the map, so every new game starts
# with the flock on a different patch of grass
func _animal_home(sp: String) -> Vector2:
	match sp:
		"duck":
			if not water_cells.is_empty():
				return Vector2(water_cells[rng.randi_range(0, water_cells.size() - 1)])
			return Vector2(_map_center())
		"deer", "boar":
			var c := _map_center()
			for attempt in 400:
				var a := rng.randf() * TAU
				var r := rng.randf_range(15.0, 23.0)
				var x := int(round(c.x + cos(a) * r))
				var y := int(round(c.y + sin(a) * r))
				if _inside(x, y) and _wild_ok(x, y):
					return Vector2(x, y)
			return Vector2(c)
		"dog", "cat":
			var houses: Array = []
			for b in buildings:
				if BUILD[String(b["kind"])].has("housing"):
					houses.append(Vector2(b["cell"]))
			if not houses.is_empty():
				return houses[rng.randi_range(0, houses.size() - 1)] + Vector2(1, 1)
			return Vector2(_map_center())
		_:
			# the flock starts next to the pen when there is one
			var pen := building_spot("pasture")
			if pen.x >= 0:
				return Vector2(pen) + Vector2(1.5, 1.5)
			var m := _map_center()
			for attempt in 400:
				var p := m + Vector2i(rng.randi_range(-9, 9), rng.randi_range(-9, 9))
				if _inside(p.x, p.y) and _grass_ok(p.x, p.y):
					return Vector2(p)
			return Vector2(m)

func _grass_ok(x: int, y: int) -> bool:
	# keep a tile of margin so nothing ends up hugging the edge of the map
	if x < 1 or y < 1 or x > mw - 2 or y > mh - 2:
		return false
	return terrain[_idx(x, y)] == "grass" and not blocked[_idx(x, y)] and not roads[_idx(x, y)]

func _wild_ok(x: int, y: int) -> bool:
	return _grass_ok(x, y) and not lake_covered[_idx(x, y)]

# the pen is blocked for people, but the sheep are allowed to stand in it
func _in_pasture(x: int, y: int) -> bool:
	for b in buildings:
		if String(b["kind"]) != "pasture":
			continue
		var c: Vector2 = b["cell"]
		var f: Vector2 = b["foot"]
		if x >= int(c.x) and y >= int(c.y) and x < int(c.x + f.x) and y < int(c.y + f.y):
			return true
	return false

# a spot for an animal to wander to.  What counts as a nice spot depends on the
# species: sheep want open grass, ducks want water, the pets stick to the lanes
# and the wild animals stay on the meadow off the roads.
func animal_spot(around: Vector2i, radius: int, where: String, who = null) -> Vector2i:
	for attempt in 40:
		var x := around.x + rng.randi_range(-radius, radius)
		var y := around.y + rng.randi_range(-radius, radius)
		if not _inside(x, y) or x < 1 or y < 1 or x > mw - 2 or y > mh - 2:
			continue
		var i := _idx(x, y)
		# two animals on one tile looks broken, so skip a spot somebody has
		if not _animal_free(Vector2i(x, y), who):
			continue
		# 动物的贴图是侧视的：尽量别让它们沿屏幕的竖直方向挪，那样看着像横着走。
		# 前 32 次尝试只收"横向分量够大"的目标，实在找不到再放宽。
		if who != null and is_instance_valid(who) and attempt < 32:
			# 换成屏幕坐标比一比（横向 32 px/格、纵向 16 px/格）
			var sx: float = ((float(x) - who.grid_pos.x) - (float(y) - who.grid_pos.y)) * HW
			var sy: float = ((float(x) - who.grid_pos.x) + (float(y) - who.grid_pos.y)) * HH
			if absf(sx) < absf(sy) * 0.8:
				continue
		match where:
			"water":
				if terrain[i] == "water":
					return Vector2i(x, y)
			"village":
				if walkable(x, y) and _line_clear(who, Vector2(x, y)):
					return Vector2i(x, y)
			_:
				if _grass_ok(x, y) or _in_pasture(x, y):
					if _line_clear(who, Vector2(x, y)):
						return Vector2i(x, y)
	return Vector2i(-1, -1)

# animals walk in a straight line, so a leg of the trip must not cut across the
# lake - a sheep paddling through deep water looks broken
func _line_clear(who, to: Vector2) -> bool:
	if who == null or not is_instance_valid(who):
		return true
	var from: Vector2 = who.grid_pos
	var steps := maxi(2, int(ceil(from.distance_to(to) * 2.0)))
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		var x := int(round(p.x))
		var y := int(round(p.y))
		if not _inside(x, y) or terrain[_idx(x, y)] == "water":
			return false
		# 也别从树、石头、房子中间穿过去（羊圈除外，羊本来就该在圈里走）
		if blocked[_idx(x, y)] and not _in_pasture(x, y):
			return false
	return true

func _animal_free(cell: Vector2i, who) -> bool:
	for a in animals:
		if not is_instance_valid(a) or a == who:
			continue
		if a.grid_pos.distance_to(Vector2(cell)) < 0.9:
			return false
	return true

# the nearest animal to a villager, so somebody can walk over and pet it
func nearest_animal(from: Vector2, max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d
	for a in animals:
		if not is_instance_valid(a) or not a.visible:
			continue
		var d: float = a.grid_pos.distance_to(from)
		if d < best_d:
			best_d = d
			best = a
	return best

func _save_animals() -> Array:
	var out: Array = []
	for a in animals:
		if is_instance_valid(a):
			out.append(a.snapshot())
	return out
# The real game ships five facing directions: 0 back, 1 back-left, 2 left
# profile, 3 front-left, 4 front. Right-facing frames are mirrored at runtime.
func _villager_art() -> Array:
	var idle := {}
	var walk := {}
	for d in 5:
		var ip := "res://assets/tt/chars/craftsman_stand_%d.0.png" % d
		if ResourceLoader.exists(ip):
			idle[d] = load(ip)
		var frames: Array = []
		for f in 4:
			var wp := "res://assets/tt/chars/craftsman_walk_%d.%d.png" % [d, f]
			if ResourceLoader.exists(wp):
				frames.append(load(wp))
		walk[d] = frames
	return [idle, walk]

func _nearest_villager(pos: Vector2) -> Node:
	var best: Node = null
	var best_d := 1e9
	for v in villagers:
		if not is_instance_valid(v):
			continue
		var d: float = v.grid_pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = v
	return best

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2(1.7, 1.7)
	var args := OS.get_cmdline_user_args()
	var zi := args.find("--zoom")
	if zi >= 0 and args.size() > zi + 1:
		camera.zoom = Vector2(float(args[zi + 1]), float(args[zi + 1]))
	camera.position = calib_focus if calib_focus != Vector2.ZERO else iso(_home_cell())
	var ci := args.find("--cam")
	if ci >= 0 and args.size() > ci + 2:
		camera.position = iso(Vector2(float(args[ci + 1]), float(args[ci + 2])))
	add_child(camera)
	camera.make_current()

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/hud.gd"))
	add_child(hud)
	hud.setup(self)

func _refresh_hud() -> void:
	if hud and hud.has_method("update_state"):
		hud.update_state()

func _process(delta: float) -> void:
	frames += 1
	if shot_path != "" and frames == shot_frame:
		_capture()
	if debug_villagers and frames % 40 == 0:
		_report_villagers()
	if debug_villagers and frames % 120 == 0:
		for v in _live_villagers():
			print("  ", v.pname, " job=", v.job, " plan=", v.plan_i, "/", v.plan.size(),
				" act=", v.activity, " at=", int(v.grid_pos.x), ",", int(v.grid_pos.y))
	if debug_harvest and frames % 120 == 0:
		_auto_harvest()
	if debug_animals and frames % 120 == 0:
		_report_animals()
	if not world_started:
		return
	_advance_clock(delta)
	_tick_camera_focus(delta)
	_update_ghost()
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * 700.0 * delta / camera.zoom

# diagnostic: nobody may ever stand on a blocked tile (-- --debug-villagers)
var debug_villagers := false
var debug_harvest := false
var debug_animals := false

# ---------- 找到他：镜头跟住这个村民 ----------

# 修仙面板上的「找到他」会调这个：镜头立刻跳到村民身上，跟一小会儿，
# 脚下画个会呼吸的黄圈 + 冒一行名字，玩家自己推镜头（WASD/拖动）就放开。
func focus_villager(v, secs := 12.0) -> void:
	if not is_instance_valid(v):
		return
	camera_focus = v
	camera_focus_t = secs
	camera.position = _focus_anchor(v)
	if fx != null:
		fx.highlight(v.get_instance_id(), v.position, secs)
		fx.float_text(v.position + Vector2(0, -34), "%s 在这里" % v.display_name(),
			Color(1.0, 0.95, 0.66))

func _focus_anchor(v) -> Vector2:
	return v.position + Vector2(0, -6)

func _tick_camera_focus(delta: float) -> void:
	if camera_focus == null:
		return
	if not is_instance_valid(camera_focus):
		camera_focus = null
		return
	camera_focus_t -= delta
	var pushed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) \
		or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) \
		or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) \
		or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN)
	if camera_focus_t <= 0.0 or pushed or dragging:
		camera_focus = null
		return
	camera.position = _focus_anchor(camera_focus)
	if fx != null:
		fx.keep_highlight(camera_focus.get_instance_id(), camera_focus.position)

# diagnostic: exercises the build / spacing / demolish rules (-- --debug-build)
func _debug_build_checks() -> void:
	var spot := Vector2i(-1, -1)
	for y in range(3, mh - 4):
		for x in range(3, mw - 4):
			if _can_build("house", Vector2i(x, y)):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	if spot.x < 0:
		print("BUILD TEST: no free 3x3 spot found (unexpected)")
		return

	var w0 := wood
	print("BUILD TEST spot=", spot, " can_build=", _can_build("house", spot))
	select_build("house")
	_try_build(spot)
	var placed := _building_at(spot)
	print("  after build: buildings=", buildings.size(), " wood_spent=", int(w0 - wood), " blocked=", blocked[_idx(spot.x, spot.y)])

	print("  neighbour (spacing rule) should be blocked: ", not _can_build("house", Vector2i(spot.x + 3, spot.y)))
	print("  same cell again should be blocked: ", not _can_build("house", spot))

	var v: Node = villagers[0] if villagers.size() > 0 else null
	if v and is_instance_valid(v):
		var vc := Vector2i(int(round(v.grid_pos.x)), int(round(v.grid_pos.y)))
		print("  villager cell ", vc, " buildable? ", _can_build("house", vc), " (should be false when free)")

	if placed:
		select_build("")
		_try_demolish(spot)
		print("  after demolish: buildings=", buildings.size(), " wood_back=", int(wood - (w0 - float(BUILD["house"]["wood"]))), " blocked=", blocked[_idx(spot.x, spot.y)])

func _building_at(cell: Vector2i) -> bool:
	for b in buildings:
		if Vector2i(int(b["cell"].x), int(b["cell"].y)) == cell:
			return true
	return false

# diagnostic: upgrade the first building twice and report what it changed
# (-- --debug-upgrade)
func _debug_upgrade_checks() -> void:
	if buildings.is_empty():
		print("UPGRADE TEST: no buildings")
		return
	var b: Dictionary = buildings[0]
	print("UPGRADE TEST: %s lv%d housing_total=%d effect=%s" % [
		String(b["kind"]), _level_of(b), housing, _effect_text(b)
	])
	wood = 9999.0
	stone = 9999.0
	for step in MAX_LEVEL - 1:
		upgrade_building(0)
		var cur: Dictionary = buildings[0]
		print("  after upgrade %d: lv=%d housing_total=%d effect=%s next_cost=%s" % [
			step + 1, _level_of(cur), housing, _effect_text(cur), str(upgrade_cost(0))
		])
	var refund := _demolish_refund(buildings[0])
	print("  demolish would refund wood=%d stone=%d" % [int(refund["wood"]), int(refund["stone"])])

# diagnostic: simulate one full day of clock ticks and print the result
# (-- --debug-time)
func _debug_time_checks() -> void:
	var secs_per_hour := DAY_SECONDS / ((NIGHT_START - DAY_START) + (24.0 - (NIGHT_START - DAY_START)) / NIGHT_RATE)
	print("TIME TEST: one game day = %.1f real seconds = %.2f h" % [DAY_SECONDS, DAY_SECONDS / 3600.0])
	print("  hours per real second: day=%.4f night=%.4f" % [1.0 / secs_per_hour, NIGHT_RATE / secs_per_hour])
	var start_day := day_number
	var start_pop := population
	for i in int(DAY_SECONDS):
		_advance_clock(1.0)
	print("  after %d real seconds: day %d -> %d, hour %.2f, pop %d -> %d, food %d, wood %d" % [
		int(DAY_SECONDS), start_day, day_number, hour, start_pop, population, int(food), int(wood)
	])

# diagnostic: pop the right-click menu open so it can be screenshotted
# (-- --demo-menu)
func _demo_menu() -> void:
	await get_tree().process_frame
	if buildings.is_empty():
		hud.open_menu("resource", 0, Vector2(620, 240))
	else:
		hud.open_menu("building", 0, Vector2(560, 220))

# diagnostic: force a couple of conversations so the speech bubbles can be
# screenshotted (-- --demo-social)
func _demo_social() -> void:
	await get_tree().create_timer(0.4).timeout
	var live := _live_villagers()
	if live.size() < 4:
		return
	# line four of them up so the bubbles are all in one screenshot
	var spot := Vector2(24, 22)
	for i in 4:
		live[i].grid_pos = spot + Vector2(float(i) * 2.5 - 3.5, 0.0)
		live[i].path = []
		live[i]._apply_position()
	_run_chat(live[0], live[1])
	_run_joke(live[2], live[3])

# diagnostic: save, scramble, load, and report whether everything came back
# (-- --debug-save)
func _debug_save_checks() -> void:
	await get_tree().create_timer(0.3).timeout
	var w0 := wood
	var g0 := gold
	var b0 := buildings.size()
	var v0 := villagers.size()
	var a0 := animals.size()
	var p0 := population
	var m0 := "%dx%d" % [mw, mh]
	save_game(3)
	wood = 1.0
	gold = 999.0
	_add_building("house", Vector2(3, mh - 4), true)
	_grow_children()
	load_game(3)
	print("SAVE TEST: buildings %d->%d  villagers %d->%d  pop %d->%d" % [b0, buildings.size(), v0, villagers.size(), p0, population])
	print("  wood %.0f->%.0f  gold %.0f->%.0f  map %s->%s  terrain=%d" % [
		w0, wood, g0, gold, m0, "%dx%d" % [mw, mh], terrain.size()
	])
	print("  villagers have names: ", villagers.size() > 0 and villagers[0].pname != "")
	print("  animals %d->%d (%s)" % [a0, animals.size(), str(_animal_counts())])
	print("  ok: ", buildings.size() == b0 and villagers.size() == v0 and animals.size() == a0 \
		and absf(wood - w0) < 0.01 and absf(gold - g0) < 0.01)

# diagnostic: pay for three map expansions and report the result
# (-- --debug-grow)
func _debug_grow_checks() -> void:
	gold = 99999.0
	wood = 99999.0
	stone = 99999.0
	var cells0 := terrain.size()
	var pops0 := villager_cell_ok()
	var b0 := buildings.size()
	for i in 3:
		var c := grow_cost()
		grow_map()
		print("  grow %d -> %dx%d  (paid 金%d 木%d 石%d)" % [i + 1, mw, mh, int(c["gold"]), int(c["wood"]), int(c["stone"])])
	print("GROW TEST: cells %d -> %d, terrain=%d roads=%d blocked=%d" % [
		cells0, terrain.size(), terrain.size(), roads.size(), blocked.size()
	])
	print("  buildings kept: %s  villagers kept: %s" % [buildings.size() == b0, pops0 == villager_cell_ok()])
	print("  next cost: ", str(grow_cost()))

# every villager must still stand on a valid cell after the grid grew
func villager_cell_ok() -> int:
	var ok := 0
	for v in _live_villagers():
		var x := int(round(v.grid_pos.x))
		var y := int(round(v.grid_pos.y))
		if _inside(x, y) and not blocked[_idx(x, y)]:
			ok += 1
	return ok

# diagnostic: the lake has to stay a closed, self-consistent body of water
# (-- --debug-lake)
func _debug_lake_checks() -> void:
	_collect_water_and_shore()
	var water := 0
	var stray := 0
	for i in terrain.size():
		if terrain[i] == "water":
			water += 1
			# every wet tile must belong to a lake block, otherwise the shore
			# atlas has no idea what to paint there
			if not lake_covered[i]:
				stray += 1
	var mismatch := 0
	# 湖必须是一整片连着的水：所有水格用四邻域洪水填充，连通块只能是 1 块
	var seen := {}
	var lakes := 0
	for c in water_cells:
		if seen.has(c):
			continue
		lakes += 1
		var queue: Array = [c]
		seen[c] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cur + step
				if not _inside(n.x, n.y):
					continue
				if seen.has(n):
					continue
				if terrain[_idx(n.x, n.y)] != "water":
					continue
				seen[n] = true
				queue.append(n)
	# 岸上的格子不能被算成水，否则村民会站到水里去
	for s in shore_cells:
		if terrain[_idx(s.x, s.y)] == "water":
			mismatch += 1
	var in_water := 0
	for v in _live_villagers():
		var x := int(round(v.grid_pos.x))
		var y := int(round(v.grid_pos.y))
		if _inside(x, y) and terrain[_idx(x, y)] == "water":
			in_water += 1
	var built_in_water := 0
	for b in buildings:
		var c: Vector2 = b["cell"]
		var foot: Vector2 = b["foot"]
		var fx := maxi(1, int(round(foot.x)))
		var fy := maxi(1, int(round(foot.y)))
		for dy in fy:
			for dx in fx:
				var bx := int(round(c.x)) + dx
				var by := int(round(c.y)) + dy
				if _inside(bx, by) and terrain[_idx(bx, by)] == "water":
					built_in_water += 1
	print("LAKE TEST: blocks=%d  water=%d  shore=%d  water_cells=%d" % [
		lake_blocks.size(), water, shore_cells.size(), water_cells.size()])
	if not water_cells.is_empty():
		var lo: Vector2i = water_cells[0]
		var hi: Vector2i = water_cells[0]
		for c in water_cells:
			lo.x = mini(lo.x, c.x)
			lo.y = mini(lo.y, c.y)
			hi.x = maxi(hi.x, c.x)
			hi.y = maxi(hi.y, c.y)
		print("  lake spans %d,%d .. %d,%d" % [lo.x, lo.y, hi.x, hi.y])
	print("  水体块数：%d（理想是 1 片）" % lakes)
	for body in _water_bodies():
		print("    一块 %d 格，范围 %s" % [body[0], body[1]])
	if not lake_blocks.is_empty():
		print("  没被湖瓦片盖住的水格：%d（应为 0）" % stray)
	print("  buildings in water: %d   villagers in water: %d (should be 0)" % [built_in_water, in_water])
	print("  shore cells that are water: %d (should be 0)" % mismatch)

# diagnostic: 砍掉的树会留树桩、长成小树、再长回大树（-- --debug-growth）
func _debug_growth_checks() -> void:
	await get_tree().create_timer(0.5).timeout
	var names := ["树桩", "小树", "大树"]
	var picked: Array = []
	for r in resources:
		if String(r["kind"]) == "tree" and int(r["stage"]) == 2 and picked.size() < 3:
			picked.append(r)
	print("GROWTH TEST: 地图上 %d 棵树（能砍的 %d 棵，挑 %d 棵做试验），补种目标 %d" % [
		_count_trees(), _count_big_trees(), picked.size(), tree_target])
	for r in picked:
		var c := Vector2(r["cell"])
		var i := _idx(int(c.x), int(c.y))
		print("  砍之前：%s  hits=%d  挡路=%s  贴图=%s" % [
			names[int(r["stage"])], int(r["hits"]), str(blocked[i]),
			_tree_path(int(r["tree_kind"]), int(r["stage"]))])
		while int(r["hits"]) > 0:
			take_harvest(r)
		print("  砍倒：  %s  hits=%d  挡路=%s  贴图=%s" % [
			names[int(r["stage"])], int(r["hits"]), str(blocked[i]),
			_tree_path(int(r["tree_kind"]), int(r["stage"]))])
		_grow_trees(TREE_STUMP_HOURS + 1.0)
		print("  +%d 小时：%s  贴图=%s  挡路=%s" % [
			int(TREE_STUMP_HOURS + 1.0), names[int(r["stage"])],
			_tree_path(int(r["tree_kind"]), int(r["stage"])), str(blocked[i])])
		_grow_trees(TREE_YOUNG_HOURS + 1.0)
		print("  +%d 小时：%s  贴图=%s  hits=%d  挡路=%s" % [
			int(TREE_YOUNG_HOURS + 1.0), names[int(r["stage"])],
			_tree_path(int(r["tree_kind"]), int(r["stage"])), int(r["hits"]), str(blocked[i])])
	# 盖房子会把树桩清掉（树上少了），这时林子要自己补种
	var before := _count_trees()
	var cleared := 0
	for r in resources.duplicate():
		if String(r["kind"]) == "tree" and int(r["stage"]) == 2 and cleared < 6:
			_remove_resource(r)
			cleared += 1
	print("  推掉 %d 棵：%d → %d 棵（补种目标 %d）" % [
		cleared, before, _count_trees(), tree_target])
	for i in 4:
		_reforest()
	print("  补种 4 次后：%d 棵" % _count_trees())
	# 麦田：割完要明显矮一截，过一阵再长回来
	if not fields.is_empty():
		var f: Dictionary = fields[0]
		f["growth"] = FIELD_GROW_HOURS
		_apply_crop_look(f)
		var sp = f["sprite"]
		print("FIELD TEST: 长满时 麦子高度=%d%%  可收割=%s" % [
			int(sp.scale.y * 100.0), str(f["ripe"])])
		harvest_field(f)
		print("  刚割完：麦子高度=%d%%  可收割=%s" % [
			int(sp.scale.y * 100.0), str(f["ripe"])])
		_grow_fields(FIELD_GROW_HOURS + 1.0)
		print("  过 %d 小时：麦子高度=%d%%  可收割=%s" % [
			int(FIELD_GROW_HOURS + 1.0), int(sp.scale.y * 100.0), str(f["ripe"])])

# diagnostic: 村民真的会自己出门（去集市/爬山/湖边/看动物）（-- --debug-life）
func _debug_life_checks() -> void:
	if town == null:
		return
	town.debug_stats = true
	await get_tree().create_timer(70.0).timeout
	if town == null:
		return
	print("LIFE TEST（这一段的时间是傍晚，看大家自己出去玩什么）: ", town.stats_report())
	var doing := {}
	for v in _live_villagers():
		var key := String(v.activity)
		doing[key] = int(doing.get(key, 0)) + 1
	print("  此刻在做：", str(doing))
	# 缺料测试：把木料石料吃到见底，看村民会不会自己转去补缺口
	hour = 9.0
	_update_daylight()
	wood = 0.0
	stone = 0.0
	food = 0.0
	var needs: Dictionary = town.need_scores()
	print("  资源清零后缺口分数：", str(needs))
	town.stats.clear()
	await get_tree().create_timer(40.0).timeout
	if town == null:
		return
	print("  缺料后大家在干：", town.stats_report())
	var doing2 := {}
	for v in _live_villagers():
		var key := String(v.activity)
		doing2[key] = int(doing2.get(key, 0)) + 1
	print("  此刻在做：", str(doing2))

# diagnostic: the animals have to stay on the map, out of the water (unless they
# are ducks) and every species has to have found its art.
# (-- --debug-animals)
func _debug_animal_checks() -> void:
	await get_tree().create_timer(1.0).timeout
	print("ANIMALS: %d" % animals.size())
	var counts := _animal_counts()
	for k in counts.keys():
		print("  %s: %d" % [String(k), int(counts[k])])
	print("  pasture built: %s" % (building_spot("pasture").x >= 0))
	_report_animals()
	# end to end: send somebody over to pet an animal and see it happen
	var vs := _live_villagers()
	if vs.is_empty() or town == null:
		print("  no villagers to send")
		return
	var v = vs[0]
	var pet = nearest_animal(v.grid_pos, 999.0)
	if pet == null:
		print("  no animal to pet")
		return
	print("  nearest animal to %s (at %s): %s at %s, %.1f tiles away" % [
		v.pname, str(v.grid_pos), String(pet.species), str(pet.grid_pos),
		v.grid_pos.distance_to(pet.grid_pos)])
	var before := int(pet.petted)
	var plan: Array = town._animal_plan_for(v, pet)
	print("  pet plan: %d steps, first = %s" % [plan.size(), String(plan[0].get("text", plan[0].get("op", "")))])
	v.run_plan(plan)
	await get_tree().create_timer(40.0).timeout
	print("  after the walk: %s is '%s', animal petted %d->%d  -> %s" % [
		v.pname, String(v.activity), before, int(pet.petted),
		"OK" if int(pet.petted) > before else "FAILED"])

# 每片水体多大、在哪儿——用来确认湖是不是连成一片
func _water_bodies() -> Array:
	var out: Array = []
	var seen := {}
	for c in water_cells:
		if seen.has(c):
			continue
		var lo: Vector2i = c
		var hi: Vector2i = c
		var n := 0
		var queue: Array = [c]
		seen[c] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			n += 1
			lo.x = mini(lo.x, cur.x)
			lo.y = mini(lo.y, cur.y)
			hi.x = maxi(hi.x, cur.x)
			hi.y = maxi(hi.y, cur.y)
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: Vector2i = cur + step
				if not _inside(nx.x, nx.y) or seen.has(nx):
					continue
				if terrain[_idx(nx.x, nx.y)] != "water":
					continue
				seen[nx] = true
				queue.append(nx)
		out.append([n, "%d,%d..%d,%d" % [lo.x, lo.y, hi.x, hi.y]])
	out.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	return out

func _animal_counts() -> Dictionary:
	var counts := {}
	for a in animals:
		if is_instance_valid(a):
			counts[a.species] = int(counts.get(a.species, 0)) + 1
	return counts

func _report_animals() -> void:
	var blank := 0
	var off_map := 0
	var in_water := 0
	var in_pen := 0
	for a in animals:
		if not is_instance_valid(a):
			continue
		if a.texture == null:
			blank += 1
		var x := int(round(a.grid_pos.x))
		var y := int(round(a.grid_pos.y))
		if not _inside(x, y):
			off_map += 1
			continue
		if terrain[_idx(x, y)] == "water":
			if String(a.species) == "duck":
				pass
			else:
				in_water += 1
		elif _in_pasture(x, y):
			in_pen += 1
	print("  frame %d: no art: %d   off map: %d   land animal in water: %d   in the pen: %d" % [
		frames, blank, off_map, in_water, in_pen])
	for a in animals:
		if is_instance_valid(a):
			var art := ""
			if a.texture != null:
				art = a.texture.resource_path.get_file()
			print("    %s at %d,%d  state=%s  朝左=%s 朝镜头=%s 贴图=%s" % [
				String(a.species), int(round(a.grid_pos.x)), int(round(a.grid_pos.y)),
				String(a.state), str(a.facing_left), str(a.moving_toward), art])

# diagnostic: keeps sending somebody to chop the next tree (-- --debug-harvest)
func _auto_harvest() -> void:
	for r in resources:
		if int(r["hits"]) > 0 and not r["busy"]:
			print("harvest order -> cell ", r["cell"], " kind=", r["kind"])
			_try_harvest(Vector2i(r["cell"]))
			return
	print("no resource left to harvest")

func _report_villagers() -> void:
	var bad := 0
	var walking := 0
	var working := 0
	var idle := 0
	for v in villagers:
		if not is_instance_valid(v):
			continue
		var cx := int(round(v.grid_pos.x))
		var cy := int(round(v.grid_pos.y))
		if _inside(cx, cy) and blocked[_idx(cx, cy)]:
			bad += 1
			print("  villager inside blocked cell ", cx, ",", cy)
		if not v.path.is_empty():
			walking += 1
		elif v.plan_active():
			working += 1
		else:
			idle += 1
	print("frame ", frames, ": villagers=", villagers.size(), " walking=", walking, " working=", working, " idle=", idle, " standing_in_blocked=", bad)

# Game hours per real second.  A day is 16 day-hours plus 8 night-hours, and the
# night ones run NIGHT_RATE times faster so a night flashes past while the
# working day feels long.  The whole cycle adds up to DAY_SECONDS (2.5 hours).
func _hours_per_second() -> float:
	var day_hours := NIGHT_START - DAY_START
	var night_hours := 24.0 - day_hours
	var secs_per_hour := DAY_SECONDS / (day_hours + night_hours / NIGHT_RATE)
	var night := hour >= NIGHT_START or hour < DAY_START
	var mult: float = NIGHT_RATE if night else 1.0
	return mult * float(SPEEDS[speed_index]) / secs_per_hour

func _advance_clock(delta: float) -> void:
	var before := hour
	hour += delta * _hours_per_second()
	var dh := hour - before
	if dh > 0.0:
		# everybody gets older, and the crops grow, as the game clock runs
		_grow_fields(dh)
		_grow_trees(dh)
		for v in _live_villagers():
			v.life_hours += dh
	# 林子砍秃了，过一阵子自己冒新苗
	plant_timer += dh
	if plant_timer >= REFOREST_HOURS:
		plant_timer = 0.0
		_reforest()
	_immigration(dh)
	var slot := int(hour / PRODUCE_EVERY)
	if slot != produce_slot:
		produce_slot = slot
		_produce()
	if hour >= 24.0:
		hour -= 24.0
		day_number += 1
		produce_slot = 0
		_grow_children()
		for v in _live_villagers():
			v.refresh_skill()
	_update_daylight()

func _update_daylight() -> void:
	var night := Color(0.40, 0.46, 0.68)
	var c := Color.WHITE
	if hour < 5.0 or hour >= 21.0:
		c = night
	elif hour < 7.0:
		c = night.lerp(Color.WHITE, (hour - 5.0) / 2.0)
	elif hour >= 19.0:
		c = Color.WHITE.lerp(night, (hour - 19.0) / 2.0)
	daynight.color = c

func _produce() -> void:
	# called every PRODUCE_EVERY game hours, so each call earns 1/6 of a day
	var slice := PRODUCE_EVERY / 24.0
	var bonus := 1.0
	var happy_bonus := 0.0
	var food_bonus := 1.0
	var gold_flat := 0.0
	for b in buildings:
		var def: Dictionary = BUILD[b["kind"]]
		if def.has("bonus"):
			bonus += float(def["bonus"]) * _level_mult(b)
		if def.has("happy"):
			happy_bonus += float(def["happy"]) * _level_mult(b)
		if def.has("food_bonus"):
			food_bonus += float(def["food_bonus"]) * _level_mult(b)
		if def.has("gold_rate"):
			gold_flat += float(def["gold_rate"]) * _level_mult(b)
	var gain_food := 0.0
	var gain_gold := 0.0
	var gain_wood := 0.0
	var gain_stone := 0.0
	for b in buildings:
		var def: Dictionary = BUILD[b["kind"]]
		var m := _level_mult(b)
		gain_food += float(def.get("food", 0.0)) * m
		gain_gold += float(def.get("gold", 0.0)) * m * float(population)
		gain_wood += float(def.get("wood_rate", 0.0)) * m
		gain_stone += float(def.get("stone_rate", 0.0)) * m
	food += gain_food * bonus * food_bonus * slice
	gold += (gain_gold * bonus + gold_flat) * slice
	wood += gain_wood * bonus * slice
	stone += gain_stone * bonus * slice
	food -= float(population) * 0.6 * slice
	if food <= 0.0:
		food = 0.0
		happiness = maxf(0.0, happiness - 4.0 * slice)
	elif food > 40.0:
		happiness = minf(100.0, happiness + 0.7 * slice)
	if happy_bonus > 0.0:
		happiness = minf(100.0, happiness + happy_bonus * 0.06 * slice)
	_refresh_hud()

# 有空房子就有人搬进来（人口上限由房子决定）。以前一天才可能来一个，
# 一个游戏日是 2.5 小时真实时间，玩家根本看不到涨，所以改成按游戏小时算：
# 每 IMMIGRATE_HOURS 个游戏小时最多来一个，房子住满就停。
# 另外，**刚盖好一座房子**会把这个倒计时直接推到只剩 NEW_HOUSE_WAIT 小时，
# 所以"木屋一盖好就很快有人搬进来"，而不是还要干等一下午。
const IMMIGRATE_HOURS := 1.5
const NEW_HOUSE_WAIT := 0.4

func _immigration(dh: float) -> void:
	immigrate_acc += dh
	if immigrate_acc < IMMIGRATE_HOURS:
		return
	immigrate_acc = 0.0
	if housing <= population or food <= 10.0 or happiness <= 40.0:
		return
	population += 1
	_spawn_one_villager()
	var reason := "新村民搬来了" if housing > population else "新村民搬来了（快住满了）"
	_flash("%s  人口 %d/%d" % [reason, population, housing], Color(0.75, 0.95, 0.6))

# 刚盖好 / 刚升级的房子：把"下一位新村民"的倒计时往前拨，只留一小会儿
func stir_immigration() -> void:
	# 开局和读档时也会重算容量，那两次不算"新盖了房子"，别一进游戏就冒人
	if not world_started or housing <= population:
		return
	immigrate_acc = maxf(immigrate_acc, IMMIGRATE_HOURS - NEW_HOUSE_WAIT)

func _hover() -> Vector2i:
	var world := camera.get_global_mouse_position()
	var x := (world.x / HW + world.y / HH) / 2.0
	var y := (world.y / HH - world.x / HW) / 2.0
	var f := Vector2(floorf(x), floorf(y))
	if build_kind != "":
		var foot: Vector2 = BUILD[build_kind]["foot"]
		f -= Vector2(floorf((foot.x - 1) * 0.5), floorf((foot.y - 1) * 0.5))
	return Vector2i(f)

func _update_ghost() -> void:
	if build_kind == "":
		ghost.visible = false
		ghost_marker.visible = false
		return
	hover_cell = ghost_force_cell if ghost_force_cell.x > -9999 else _hover()
	var def: Dictionary = BUILD[build_kind]
	var ok := _can_build(build_kind, hover_cell) \
		and wood >= float(def["wood"]) and stone >= float(def["stone"]) \
		and gold >= float(def.get("gold_cost", 0))
	if str(ghost.get_meta("kind", "")) != build_kind:
		for child in ghost_art.get_children():
			child.queue_free()
		ghost_art.add_child(_make_building_node(build_kind))
		ghost.set_meta("kind", build_kind)
	ghost.visible = true
	ghost.position = _building_origin(build_kind, Vector2(hover_cell))
	ghost_marker.visible = true
	ghost_marker.position = ghost.position
	ghost.modulate = Color(0.65, 1.0, 0.65, 0.62) if ok else Color(1.0, 0.45, 0.4, 0.62)
	_update_ghost_ground(hover_cell, def["foot"], ok)

# 地面上的影子 + 占地圈：房子贴图很高，光看那栋半透明的房子根本不知道它落
# 在哪几格。这里把占地面积画成一个菱形阴影，边上再描一圈（能放=绿，放不下=红）。
func _update_ghost_ground(cell: Vector2i, foot: Vector2, ok: bool) -> void:
	var pts := _foot_polygon(cell, foot, ghost_marker.position)
	ghost_shadow.polygon = pts
	# 影子稍微偏右下一点，看着像是斜着打下来的
	ghost_shadow.position = Vector2(3, 3)
	ghost_shadow.color = Color(0.04, 0.05, 0.09, 0.30 if ok else 0.24)
	ghost_outline.points = pts
	ghost_outline.default_color = Color(0.55, 1.0, 0.55, 0.95) if ok else Color(1.0, 0.42, 0.36, 0.95)

# 占地范围在屏幕上其实是"这几格地砖拼起来的外框"，四个顶点分别是：最上面那格
# 的上角、最右边那格、最下面那格、最左边那格。这样算出来的框一定和地砖对得上
# （正方的占地看起来是菱形，长方形的占地是个斜的平行四边形）。传进来的 origin
# 是建筑节点的原点，返回的是相对它的局部坐标，可以直接喂给 Polygon2D / Line2D。
func _foot_polygon(cell: Vector2i, foot: Vector2, origin: Vector2, scale_f: float = 1.0) -> PackedVector2Array:
	var fx := int(foot.x)
	var fy := int(foot.y)
	var mid := Vector2(0, HH) - _front_offset(foot) - origin
	var pts := PackedVector2Array([
		iso(Vector2(cell)) + Vector2(0, -HH) - origin,
		iso(Vector2(cell.x + fx - 1, cell.y)) + Vector2(HW, 0) - origin,
		iso(Vector2(cell.x + fx - 1, cell.y + fy - 1)) + Vector2(0, HH) - origin,
		iso(Vector2(cell.x, cell.y + fy - 1)) + Vector2(-HW, 0) - origin,
	])
	if scale_f == 1.0:
		return pts
	var out := PackedVector2Array()
	for p in pts:
		out.append(mid + (p - mid) * scale_f)
	return out

# 诊断：把"占地圈"和它应该盖住的那几格的角点都算出来，看看对不对得上
func _ghost_geometry_report(kind: String, cell: Vector2i) -> void:
	var foot: Vector2 = BUILD[kind]["foot"]
	var fx := int(foot.x)
	var fy := int(foot.y)
	var org := _building_origin(kind, Vector2(cell))
	var pts := _foot_polygon(cell, foot, org)
	var tile_n := iso(Vector2(cell)) + Vector2(0, -HH)
	var tile_e := iso(Vector2(cell.x + fx - 1, cell.y)) + Vector2(HW, 0)
	var tile_s := iso(Vector2(cell.x + fx - 1, cell.y + fy - 1)) + Vector2(0, HH)
	var tile_w := iso(Vector2(cell.x, cell.y + fy - 1)) + Vector2(-HW, 0)
	print("  GEOM 格子角点(世界坐标): N=%s E=%s S=%s W=%s" % [tile_n, tile_e, tile_s, tile_w])
	print("  GEOM 占地圈:           N=%s E=%s S=%s W=%s" % [
		org + pts[0], org + pts[1], org + pts[2], org + pts[3]])
	print("  GEOM 偏差(圈-格子): N=%s E=%s S=%s W=%s" % [
		org + pts[0] - tile_n, org + pts[1] - tile_e,
		org + pts[2] - tile_s, org + pts[3] - tile_w])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.12).clamp(Vector2(0.45, 0.45), Vector2(3.0, 3.0))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.12).clamp(Vector2(0.45, 0.45), Vector2(3.0, 3.0))
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				press_pos = mb.position
				left_down = true
				did_drag = false
			else:
				left_down = false
				# a click is a press and release in the same spot; anything else
				# was the player dragging the map around
				if not did_drag:
					_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if move_index >= 0:
				cancel_move()
				return
			if build_kind != "":
				select_build("")
				return
			var cell := _hover()
			# 房子的贴图很高（屋顶画在格子的上后方），点屋顶时鼠标底下那格
			# 其实落在房子背后。所以往屏幕下方（+）找几格，先找到谁就点谁。
			for back in 4:
				var c := cell + Vector2i(back, back)
				var si := _site_index_at(c)
				if si >= 0:
					hud.open_site(si, mb.position)
					return
				var bi := _building_index_at(c)
				if bi >= 0:
					hud.open_menu("building", bi, mb.position)
					return
				var ri := _resource_index_at(c)
				if ri >= 0:
					hud.open_menu("resource", ri, mb.position)
					return
			if hud:
				hud.close_menu()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if left_down and not did_drag and mm.position.distance_to(press_pos) > 7.0:
			did_drag = true
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT and did_drag:
			camera.position -= mm.relative / camera.zoom
		elif dragging:
			camera.position -= mm.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			if move_index >= 0:
				cancel_move()
			else:
				select_build("")
			if hud:
				hud.close_menu()
		elif k == KEY_X:
			select_build("")
		elif k == KEY_MINUS:
			cycle_speed(-1)
		elif k == KEY_EQUAL or k == KEY_KP_ADD:
			cycle_speed(1)
		elif k == KEY_S and (event as InputEventKey).ctrl_pressed:
			save_game()
		elif k == KEY_0:
			if BUILD_ORDER.size() > 9:
				select_build(String(BUILD_ORDER[9]))
		elif k == KEY_1:
			select_build(String(BUILD_ORDER[0]))
		elif k == KEY_2:
			select_build(String(BUILD_ORDER[1]))
		elif k == KEY_3:
			select_build(String(BUILD_ORDER[2]))
		elif k == KEY_4:
			select_build(String(BUILD_ORDER[3]))
		elif k == KEY_5:
			select_build(String(BUILD_ORDER[4]))
		elif k == KEY_6:
			select_build(String(BUILD_ORDER[5]))
		elif k == KEY_7:
			select_build(String(BUILD_ORDER[6]))
		elif k == KEY_8:
			select_build(String(BUILD_ORDER[7]))
		elif k == KEY_9:
			select_build(String(BUILD_ORDER[8]))
		elif k == KEY_C:
			camera.position = iso(_home_cell())

# ---------- left click: talk to people, look at things, drag the map -------

func _left_click(screen_pos: Vector2) -> void:
	if hud:
		hud.close_menu()
		hud.close_villager()
	if build_kind != "":
		_try_build(_hover())
		return
	var v := _villager_at()
	if v != null:
		if hud:
			hud.open_villager(v, screen_pos)
		return
	var cell := _hover()
	var si := _site_index_at(cell)
	if si >= 0:
		if hud:
			hud.open_site(si, screen_pos)
		return
	var bi := _building_index_at(cell)
	if bi >= 0:
		if hud:
			hud.open_menu("building", bi, screen_pos)
		return
	var ri := _resource_index_at(cell)
	if ri >= 0:
		_try_harvest(cell)
		return
	# bare ground or water: do nothing, the press already panned the map

func _villager_at() -> Node:
	var wp := camera.get_global_mouse_position()
	var best: Node = null
	var best_d := 1e9
	for v in _live_villagers():
		if not v.visible:
			continue
		var head: Vector2 = v.position + Vector2(0, -v.art_h * 0.45)
		var d: float = wp.distance_to(head)
		if d < 30.0 and d < best_d:
			best_d = d
			best = v
	return best

func select_build(kind: String) -> void:
	# picking another building while one is being relocated puts it back first
	if move_index >= 0 and kind != move_kind:
		cancel_move()
		return
	build_kind = kind
	ghost.set_meta("kind", "")
	_refresh_hud()

func _try_build(cell: Vector2i) -> void:
	if move_index >= 0:
		_finish_move(cell)
		return
	if not _can_build(build_kind, cell):
		_flash("这里放不下", Color(1, 0.55, 0.5))
		return
	var def: Dictionary = BUILD[build_kind]
	if wood < float(def["wood"]) or stone < float(def["stone"]) or gold < float(def.get("gold_cost", 0)):
		_flash("材料不够", Color(1, 0.55, 0.5))
		return
	wood -= float(def["wood"])
	stone -= float(def["stone"])
	gold -= float(def.get("gold_cost", 0))
	# 盖房子会把占地里的树桩和小树清掉
	_clear_soft_trees(cell, def["foot"])
	_start_site(build_kind, cell)
	_flash("开工了：%s，等村民来施工" % str(def["name"]), Color(0.85, 0.95, 0.65))
	_refresh_hud()

# ---------- building sites ------------------------------------------------
# Nothing appears out of thin air any more: paying for a building only stakes
# out the plot.  A site node draws the dug foundation and the progress bar, and
# the villagers from town.gd dig, haul the timber over and raise the walls.

func _start_site(kind: String, cell: Vector2i) -> void:
	var site := Node2D.new()
	site.set_script(load("res://scripts/site.gd"))
	object_layer.add_child(site)
	site.setup(self, kind, cell)
	site.name = "Site_" + kind
	sites.append(site)
	_mark_blocked(Vector2(cell), BUILD[kind]["foot"])
	_refresh_hud()

func _finish_site(site) -> void:
	if not is_instance_valid(site):
		return
	var idx := sites.find(site)
	if idx < 0:
		return
	sites.remove_at(idx)
	# 房子已经盖好了，还在往这儿搬木料的人当场收工（别扛着料走到新房前）
	if town != null:
		var stopped: int = town.abort_build_plans(site)
		if debug_villagers:
			print("SITE DONE: %s 完工，当场叫停 %d 个还在搬料的村民" % [String(site.kind), stopped])
	var kind: String = site.kind
	var cell: Vector2i = site.cell
	_mark_blocked(Vector2(cell), BUILD[kind]["foot"], false)
	site.queue_free()
	_add_building(kind, Vector2(cell))
	_build_roads()
	_rebuild_ground()
	var name := String(BUILD[kind]["name"])
	_flash("%s 建好了！大家来道喜" % name, Color(0.95, 0.98, 0.7))
	if town != null:
		town.celebrate(Vector2(cell) + BUILD[kind]["foot"] * 0.5, name)
	_recompute_housing()
	_refresh_hud()

func _site_index_at(cell: Vector2i) -> int:
	for i in range(sites.size() - 1, -1, -1):
		var s = sites[i]
		if not is_instance_valid(s):
			continue
		var foot: Vector2 = BUILD[s.kind]["foot"]
		if cell.x >= s.cell.x and cell.x < s.cell.x + int(foot.x) \
				and cell.y >= s.cell.y and cell.y < s.cell.y + int(foot.y):
			return i
	return -1

func _cancel_site(site) -> void:
	var idx := sites.find(site)
	if idx < 0:
		return
	sites.remove_at(idx)
	var def: Dictionary = BUILD[site.kind]
	wood += floorf(float(def["wood"]) * 0.5)
	stone += floorf(float(def["stone"]) * 0.5)
	gold += floorf(float(def.get("gold_cost", 0)) * 0.5)
	_mark_blocked(Vector2(site.cell), def["foot"], false)
	site.queue_free()
	_flash("取消建造，退回一半材料", Color(0.95, 0.85, 0.6))
	_refresh_hud()

func site_info(index: int) -> Dictionary:
	if index < 0 or index >= sites.size():
		return {"title": "工地", "lines": []}
	var s = sites[index]
	var def: Dictionary = BUILD[s.kind]
	return {
		"title": "%s（施工中）" % String(def["name"]),
		"lines": [
			"进度：%d%%（%s）" % [int(round(s.progress * 100.0)), s.phase_text()],
			"等村民过来施工，木料要从仓库搬过来",
		],
		"progress": s.progress,
		"phase": s.phase_text(),
		"kind": s.kind,
	}

func _try_demolish(cell: Vector2i) -> void:
	for i in range(buildings.size() - 1, -1, -1):
		var b: Dictionary = buildings[i]
		var foot: Vector2 = b["foot"]
		var bx := int(b["cell"].x)
		var by := int(b["cell"].y)
		if cell.x >= bx and cell.x < bx + int(foot.x) and cell.y >= by and cell.y < by + int(foot.y):
			var refund := _demolish_refund(b)
			wood += float(refund["wood"])
			stone += float(refund["stone"])
			_mark_blocked(b["cell"], foot, false)
			b["node"].queue_free()
			buildings.remove_at(i)
			if selected_index == i:
				selected_index = -1
			elif selected_index > i:
				selected_index -= 1
			_recompute_housing()
			_flash("拆除，返还 木%d 石%d" % [int(refund["wood"]), int(refund["stone"])], Color(0.95, 0.85, 0.6))
			_refresh_hud()
			return
	_flash("这里没有建筑", Color(1, 0.8, 0.5))

# half of everything ever spent on the building, upgrades included
func _demolish_refund(b: Dictionary) -> Dictionary:
	var def: Dictionary = BUILD[b["kind"]]
	var w := float(def["wood"])
	var s := float(def["stone"])
	for i in range(_level_of(b) - 1):
		w += float(UPGRADE_COST[i]["wood"])
		s += float(UPGRADE_COST[i]["stone"])
	return {"wood": floorf(w * 0.5), "stone": floorf(s * 0.5)}

# ---------- right-click actions: info / upgrade / move / demolish ----------

func _building_index_at(cell: Vector2i) -> int:
	for i in range(buildings.size() - 1, -1, -1):
		var b: Dictionary = buildings[i]
		var foot: Vector2 = b["foot"]
		var bx := int(b["cell"].x)
		var by := int(b["cell"].y)
		if cell.x >= bx and cell.x < bx + int(foot.x) and cell.y >= by and cell.y < by + int(foot.y):
			return i
	return -1

func _resource_index_at(cell: Vector2i) -> int:
	for i in range(resources.size() - 1, -1, -1):
		var r: Dictionary = resources[i]
		if int(r["cell"].x) == cell.x and int(r["cell"].y) == cell.y:
			return i
	return -1

func _effect_text(b: Dictionary) -> String:
	var def: Dictionary = BUILD[b["kind"]]
	var parts: Array = []
	if int(def.get("housing", 0)) > 0:
		parts.append("可住 %d 人" % int(round(float(def["housing"]) * _level_mult(b))))
	if def.has("food"):
		parts.append("食物 +%.2f/天" % (float(def["food"]) * _level_mult(b)))
	if def.has("food_bonus"):
		parts.append("全村食物 +%d%%" % int(round(float(def["food_bonus"]) * _level_mult(b) * 100.0)))
	if def.has("wood_rate"):
		parts.append("木材 +%.2f/天" % (float(def["wood_rate"]) * _level_mult(b)))
	if def.has("stone_rate"):
		parts.append("石料 +%.2f/天" % (float(def["stone_rate"]) * _level_mult(b)))
	if def.has("gold"):
		parts.append("金币 +%.2f/人/天" % (float(def["gold"]) * _level_mult(b)))
	if def.has("gold_rate"):
		parts.append("金币 +%.2f/天" % (float(def["gold_rate"]) * _level_mult(b)))
	if def.has("bonus"):
		parts.append("全村产出 +%d%%" % int(round(float(def["bonus"]) * _level_mult(b) * 100.0)))
	if def.has("happy"):
		parts.append("幸福 +%.1f/天" % (float(def["happy"]) * _level_mult(b) * 0.06))
	return "，".join(parts)

func building_info(index: int) -> Dictionary:
	var b: Dictionary = buildings[index]
	var def: Dictionary = BUILD[b["kind"]]
	return {
		"title": "%s  Lv%d" % [str(def["name"]), _level_of(b)],
		"lines": [
			_effect_text(b),
			"位置 单元格 %d,%d" % [int(b["cell"].x), int(b["cell"].y)],
		],
		"level": _level_of(b),
		"max_level": MAX_LEVEL,
		"upgrade": upgrade_cost(index),
	}

func resource_info(index: int) -> Dictionary:
	var r: Dictionary = resources[index]
	var is_wood := String(r["kind"]) == "tree"
	return {
		"title": "树木" if is_wood else "石堆",
		"lines": [
			"剩余 %d 次采集" % int(r["hits"]),
			"每次产出约 %d %s" % [int(round(float(r["amount"]) / 3.0)), "木材" if is_wood else "石料"],
		],
	}

func upgrade_cost(index: int) -> Dictionary:
	var lv := _level_of(buildings[index])
	if lv >= MAX_LEVEL:
		return {}
	return UPGRADE_COST[lv - 1]

func upgrade_building(index: int) -> void:
	if index < 0 or index >= buildings.size():
		return
	var cost := upgrade_cost(index)
	if cost.is_empty():
		_flash("已经是最高等级", Color(1, 0.85, 0.4))
		return
	if wood < float(cost["wood"]) or stone < float(cost["stone"]):
		_flash("材料不够升级（需 木%d 石%d）" % [int(cost["wood"]), int(cost["stone"])], Color(1, 0.55, 0.5))
		return
	wood -= float(cost["wood"])
	stone -= float(cost["stone"])
	var b: Dictionary = buildings[index]
	b["level"] = _level_of(b) + 1
	_refresh_building_look(b)
	_recompute_housing()
	_refresh_hud()
	_flash("%s 升到 %d 级" % [str(BUILD[b["kind"]]["name"]), int(b["level"])], Color(0.72, 0.95, 0.68))

# levels are shown by growing the sprite a little and hanging a star above it
func _refresh_building_look(b: Dictionary) -> void:
	var node: Node2D = b["node"]
	var lv := _level_of(b)
	node.scale = Vector2.ONE * (1.0 + 0.07 * float(lv - 1))
	var old := node.get_node_or_null("Level")
	if old:
		old.queue_free()
	if lv <= 1:
		return
	var label := Label.new()
	label.name = "Level"
	label.text = "★".repeat(lv - 1)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.position = Vector2(-16.0, -float(node.get_meta("art_h", 60.0)) - 22.0)
	node.add_child(label)

# 移动: lift the building off the grid, then drop it with the next left click
func begin_move(index: int) -> void:
	if index < 0 or index >= buildings.size():
		return
	var b: Dictionary = buildings[index]
	move_index = index
	move_kind = String(b["kind"])
	move_from = b["cell"]
	b["node"].visible = false
	_mark_blocked(move_from, b["foot"], false)
	select_build(move_kind)
	_flash("搬到哪里？左键放下，右键/Esc 取消", Color(0.8, 0.9, 1.0))

func cancel_move() -> void:
	if move_index < 0:
		return
	var b: Dictionary = buildings[move_index]
	_mark_blocked(move_from, b["foot"], true)
	b["node"].visible = true
	move_index = -1
	move_kind = ""
	select_build("")

func _finish_move(cell: Vector2i) -> void:
	if not _can_build(move_kind, cell):
		_flash("这里放不下", Color(1, 0.55, 0.5))
		return
	var b: Dictionary = buildings[move_index]
	b["cell"] = Vector2(cell)
	_mark_blocked(Vector2(cell), b["foot"], true)
	var node: Node2D = b["node"]
	node.position = _building_origin(move_kind, Vector2(cell))
	node.visible = true
	move_index = -1
	move_kind = ""
	select_build("")
	_flash("搬好了", Color(0.85, 0.95, 0.65))

func cycle_speed(step: int) -> void:
	speed_index = clampi(speed_index + step, 0, SPEEDS.size() - 1)
	_apply_time_scale()
	_flash("时间速度 %s" % speed_text(), Color(0.85, 0.92, 1.0))
	_refresh_hud()

func cycle_speed_wrap() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	_apply_time_scale()
	_flash("时间速度 %s" % speed_text(), Color(0.85, 0.92, 1.0))
	_refresh_hud()

# Speeding the clock up speeds the people up with it - at 2x the villagers
# really do walk twice as fast.
func _apply_time_scale() -> void:
	for v in _live_villagers():
		v.set_time_scale(time_scale())

func speed_text() -> String:
	return "%.0fx" % float(SPEEDS[speed_index])

func is_night() -> bool:
	return hour >= NIGHT_START or hour < DAY_START

func _try_harvest(cell: Vector2i) -> void:
	for r in resources:
		if r["hits"] <= 0 or r["busy"]:
			continue
		if Vector2i(r["cell"]) == cell:
			var v := _nearest_villager(r["cell"])
			if v == null:
				return
			r["busy"] = true
			var rec: Dictionary = r
			v.assign(r["cell"], 2.0, func() -> void: _finish_harvest(rec))
			return

# One swing of the axe or the pick.  The lumberjack in town.gd calls this for
# every swing and carries whatever comes out back to the warehouse.
func take_harvest(r: Dictionary) -> Dictionary:
	if not resources.has(r):
		return {"gain": 0.0, "kind": "", "felled": false}
	if int(r["hits"]) <= 0:
		return {"gain": 0.0, "kind": "", "felled": true}
	r["hits"] = int(r["hits"]) - 1
	var is_wood: bool = r["resource"] == "wood"
	var gain := float(r["amount"]) * (0.6 + 0.4 * rng.randf())
	var felled := int(r["hits"]) <= 0
	if felled:
		if String(r["kind"]) == "tree":
			# 砍倒的树留个树桩，过一天冒小树，再过两天长回大树
			_set_tree_stage(r, 0)
		else:
			_mark_blocked(Vector2(r["cell"]), Vector2(1, 1), false)
			_remove_resource(r)
		r["busy"] = false
	elif is_instance_valid(r["sprite"]):
		r["sprite"].scale = Vector2(r["base_scale"]) * (0.72 + 0.28 * float(int(r["hits"])) / 3.0)
	return {"gain": gain, "kind": "wood" if is_wood else "stone", "felled": felled}

func _finish_harvest(r: Dictionary) -> void:
	r["busy"] = false
	var got := take_harvest(r)
	grant(String(got["kind"]), float(got["gain"]), Vector2(r["cell"]))
	r["busy"] = false

# goods arriving in the store room, with the little floating label
func grant(kind: String, amount: float, at: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0:
		return
	var label := ""
	var color := Color(0.96, 0.92, 0.62)
	match kind:
		"wood":
			wood += amount
			label = "+%d 木材" % int(amount)
		"stone":
			stone += amount
			label = "+%d 石料" % int(amount)
			color = Color(0.86, 0.90, 0.96)
		"food":
			food += amount
			label = "+%d 食物" % int(amount)
			color = Color(0.84, 0.96, 0.68)
		"gold":
			gold += amount
			label = "+%d 金币" % int(amount)
			color = Color(1.0, 0.92, 0.55)
		"crop":
			food += amount
			label = "+%d 粮食" % int(amount)
			color = Color(0.98, 0.94, 0.62)
	if fx != null and label != "":
		fx.float_text(iso(at) + Vector2(0, 2), label, color)
	_refresh_hud()

func _flash(text: String, color: Color) -> void:
	if hud and hud.has_method("flash"):
		hud.flash(text, color)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("screenshot saved: ", shot_path)
	get_tree().quit()

# ===========================================================================
# 存档：继续上次的小镇，或者开一局新的
# ===========================================================================

const SAVE_DIR := "user://saves"
const SAVE_SLOTS := 3

var current_slot := 1

func save_path(slot: int) -> String:
	return "%s/save_%d.json" % [SAVE_DIR, slot]

func _next_free_slot() -> int:
	for slot in range(1, SAVE_SLOTS + 1):
		if not FileAccess.file_exists(save_path(slot)):
			return slot
	return 1

func list_saves() -> Array:
	var out: Array = []
	for slot in range(1, SAVE_SLOTS + 1):
		var p := save_path(slot)
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var d = JSON.parse_string(txt)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var h := float(d.get("hour", 7.0))
		out.append({
			"slot": slot,
			"label": "继续 %s（第%d天 %02d:%02d，%d 人）" % [
				String(d.get("real_time", "存档")), int(d.get("day", 1)),
				int(h), int(fmod(h, 1.0) * 60.0), int(d.get("population", 0)),
			],
		})
	return out

func save_game(slot: int = -1) -> bool:
	var s := slot if slot > 0 else current_slot
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": 1,
		"real_time": Time.get_datetime_string_from_system(false, true).replace("T", " "),
		"day": day_number,
		"hour": hour,
		"mw": mw,
		"mh": mh,
		"cross": [cross_cell.x, cross_cell.y],
		"home": [home_cell.x, home_cell.y],
		"wood": wood, "stone": stone, "food": food, "gold": gold,
		"population": population, "happiness": happiness, "speed": speed_index,
		"terrain": terrain,
		"blocked": blocked,
		"roads": roads,
		"covered": lake_covered,
		"season": season,
		"lake": _save_lake(),
		"sites": _save_sites(),
		"buildings": _save_buildings(),
		"resources": _save_resources(),
		"villagers": _save_villagers(),
		"animals": _save_animals(),
		"fields": _save_fields(),
	}
	var f := FileAccess.open(save_path(s), FileAccess.WRITE)
	if f == null:
		_flash("存档写入失败", Color(1, 0.6, 0.5))
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	current_slot = s
	_flash("已保存到存档 %d" % s, Color(0.86, 0.95, 1.0))
	return true

func _save_lake() -> Array:
	var out: Array = []
	for b in lake_blocks:
		var c: Vector2i = b["cell"]
		out.append({
			"cell": [c.x, c.y], "mask": int(b["mask"]), "file": String(b["file"]),
			"mirror": bool(b["mirror"]), "flip_v": bool(b.get("flip_v", false)),
		})
	return out

func _save_sites() -> Array:
	var out: Array = []
	for s in sites:
		if not is_instance_valid(s):
			continue
		out.append({"kind": String(s.kind), "cell": [s.cell.x, s.cell.y], "progress": float(s.progress)})
	return out

func _save_fields() -> Array:
	var out: Array = []
	for f in fields:
		var c: Vector2 = f["cell"]
		out.append({"cell": [int(c.x), int(c.y)], "ripe": bool(f["ripe"]), "growth": float(f.get("growth", 0.0))})
	return out

func _save_buildings() -> Array:
	var out: Array = []
	for b in buildings:
		var c: Vector2 = b["cell"]
		out.append({"kind": String(b["kind"]), "cell": [int(c.x), int(c.y)], "level": _level_of(b)})
	return out

func _save_resources() -> Array:
	var out: Array = []
	for r in resources:
		var c: Vector2 = r["cell"]
		out.append({
			"kind": String(r["kind"]), "group": String(r.get("group", "tree")),
			"cell": [int(c.x), int(c.y)], "amount": float(r["amount"]), "hits": int(r["hits"]),
			# 树还要记住品种和长到哪一步了
			"tree_kind": int(r.get("tree_kind", -1)), "stage": int(r.get("stage", 2)),
			"grow_t": float(r.get("regrow", 0.0)),
		})
	return out

func _save_villagers() -> Array:
	var out: Array = []
	for v in villagers:
		if not is_instance_valid(v):
			continue
		out.append({
			"name": String(v.pname), "female": bool(v.female), "child": bool(v.child),
			"x": v.grid_pos.x, "y": v.grid_pos.y, "mood": v.mood, "speed": v.raw_speed,
			"partner": String(v.partner), "friends": v.friends,
			"born_day": int(v.born_day), "spouse_day": int(v.spouse_day),
			"home_x": v.home_cell.x, "home_y": v.home_cell.y,
			"life_hours": v.life_hours, "realm": v.realm, "layer": v.layer,
			"xp": v.xp, "xp_need": v.xp_need, "cultivate": v.cultivate,
			"job": String(v.job), "traits": v.traits,
		})
	return out

func load_game(slot: int) -> void:
	var p := save_path(slot)
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		_flash("存档读不出来", Color(1, 0.6, 0.5))
		return
	reset_world()
	mw = int(d.get("mw", START_W))
	mh = int(d.get("mh", START_H))
	var cross: Array = d.get("cross", [mw / 2, mh / 2])
	cross_cell = Vector2i(int(cross[0]), int(cross[1]))
	var home: Array = d.get("home", [mw / 2, mh / 2])
	home_cell = Vector2(float(home[0]), float(home[1]))
	terrain = (d["terrain"] as Array).duplicate()
	blocked = (d["blocked"] as Array).duplicate()
	roads = (d["roads"] as Array).duplicate()
	lake_covered = (d["covered"] as Array).duplicate()
	lake_blocks.clear()
	for b in d.get("lake", []):
		var c: Array = b["cell"]
		lake_blocks.append({
			"cell": Vector2i(int(c[0]), int(c[1])), "mask": int(b["mask"]),
			"file": String(b["file"]), "mirror": bool(b["mirror"]),
			"flip_v": bool(b.get("flip_v", false)),
		})
	wood = float(d.get("wood", 0.0))
	stone = float(d.get("stone", 0.0))
	food = float(d.get("food", 0.0))
	gold = float(d.get("gold", 0.0))
	population = int(d.get("population", 0))
	happiness = float(d.get("happiness", 60.0))
	speed_index = clampi(int(d.get("speed", 0)), 0, SPEEDS.size() - 1)
	season = clampi(int(d.get("season", 0)), 0, 3)
	day_number = int(d.get("day", 1))
	hour = float(d.get("hour", 7.0))
	produce_slot = int(hour / PRODUCE_EVERY)
	# buildings
	for b in d.get("buildings", []):
		var bc: Array = b["cell"]
		_add_building(String(b["kind"]), Vector2(float(bc[0]), float(bc[1])), true)
		var idx := buildings.size() - 1
		buildings[idx]["level"] = clampi(int(b.get("level", 1)), 1, MAX_LEVEL)
		_refresh_building_look(buildings[idx])
	# unfinished building sites come back as they were left
	for s in d.get("sites", []):
		var sc: Array = s["cell"]
		var site := Node2D.new()
		site.set_script(load("res://scripts/site.gd"))
		object_layer.add_child(site)
		site.setup(self, String(s["kind"]), Vector2i(int(sc[0]), int(sc[1])))
		site.add_progress(float(s.get("progress", 0.0)))
		sites.append(site)
	# resources (their cells are already marked blocked in the saved grid)
	for r in d.get("resources", []):
		var rc: Array = r["cell"]
		var cell := Vector2(float(rc[0]), float(rc[1]))
		if String(r["kind"]) == "tree":
			_add_tree(cell, int(r.get("stage", 2)), int(r.get("tree_kind", -1)),
				float(r.get("grow_t", -1.0)))
		else:
			_add_resource(String(r["kind"]), String(r.get("group", "stone")),
				cell, float(r["amount"]), int(r["hits"]))
	# people
	for v in d.get("villagers", []):
		var node := Sprite2D.new()
		node.set_script(load("res://scripts/villager.gd"))
		object_layer.add_child(node)
		node.setup(Vector2(float(v["x"]), float(v["y"])), rng, mw, mh, blocked, roads)
		node.raw_speed = float(v.get("speed", 2.0))
		node.set_identity(String(v["name"]), bool(v["female"]), bool(v["child"]), int(v.get("born_day", 1)))
		node.mood = float(v.get("mood", 60.0))
		node.mood_target = happiness
		node.partner = String(v.get("partner", ""))
		node.spouse_day = int(v.get("spouse_day", -1))
		node.home_cell = Vector2i(int(v.get("home_x", -1)), int(v.get("home_y", -1)))
		node.life_hours = float(v.get("life_hours", 0.0))
		node.realm = int(v.get("realm", 0))
		node.layer = int(v.get("layer", 1))
		node.xp = float(v.get("xp", 0.0))
		node.xp_need = float(v.get("xp_need", 22.0))
		node.cultivate = bool(v.get("cultivate", false))
		node.job = String(v.get("job", "none"))
		var tr = v.get("traits", [])
		node.set_traits(tr if typeof(tr) == TYPE_ARRAY else [])
		node.set_time_scale(time_scale())
		node.refresh_skill()
		node.apply_skin(skin_for_job(node.job, node.female))
		var fr = v.get("friends", {})
		if typeof(fr) == TYPE_DICTIONARY:
			node.friends = fr
		used_names[node.pname] = true
		villagers.append(node)
	# the animals
	for a in d.get("animals", []):
		_spawn_animal(String(a.get("species", "sheep")),
			Vector2(float(a.get("x", mw * 0.5)), float(a.get("y", mh * 0.5))))
	# the corn fields: regrow from the saved state
	_collect_water_and_shore()
	_collect_fields()
	for saved_field in d.get("fields", []):
		var fc: Array = saved_field["cell"]
		for local in fields:
			if Vector2i(local["cell"]) == Vector2i(int(fc[0]), int(fc[1])):
				local["growth"] = float(saved_field.get("growth", 0.0))
				_apply_crop_look(local)
	_recompute_housing()
	_rebuild_ground()
	_apply_season_props()
	_apply_weather()
	if town != null:
		town.setup(self)
	world_started = true
	current_slot = slot
	camera.position = iso(_home_cell())
	_flash("继续第 %d 天的小镇" % day_number, Color(0.88, 0.96, 0.84))
	_refresh_hud()

func reset_world() -> void:
	if object_layer:
		for child in object_layer.get_children():
			child.free()
	var old_ground := get_node_or_null("Ground")
	if old_ground:
		old_ground.free()
	var old_grid := get_node_or_null("DebugGrid")
	if old_grid:
		old_grid.free()
	buildings.clear()
	resources.clear()
	villagers.clear()
	animals.clear()
	for s in sites:
		if is_instance_valid(s):
			s.free()
	sites.clear()
	fields.clear()
	water_cells.clear()
	shore_cells.clear()
	prop_nodes.clear()
	season = 0
	if town != null:
		town.chatter.clear()
		town.thought_cd.clear()
		town.meal_done.clear()
		town.events.clear()
		town.fire_night = false
		town.fire_day = -99
		town.season = 0
		town.season_day = 0
		town.last_day = 1
		town.setup(self)
	if fx != null:
		fx.put_out_fire()
	lake_blocks.clear()
	used_names.clear()
	mw = START_W
	mh = START_H
	cross_cell = Vector2i(mw / 2, mh / 2)
	home_cell = Vector2.ZERO
	wood = 140.0
	stone = 70.0
	food = 90.0
	gold = 0.0
	population = 6
	housing = 0
	happiness = 62.0
	hour = 7.0
	day_number = 1
	speed_index = 0
	build_kind = ""
	move_index = -1
	move_kind = ""
	selected_index = -1
	produce_slot = 0
	social_timer = 2.0

func build_button_text(kind: String) -> String:
	var def: Dictionary = BUILD[kind]
	var line := "木%d 石%d" % [int(def["wood"]), int(def["stone"])]
	if float(def.get("gold_cost", 0)) > 0.0:
		line += " 金%d" % int(def["gold_cost"])
	return "%s\n%s" % [str(def["name"]), line]

# ===========================================================================
# 村民的社会生活：名字、情绪、朋友、聊天、玩耍、吵架、打架、结婚、生子
# ===========================================================================

const NAME_POOL := [
	"阿福", "小翠", "大牛", "春妮", "铁柱", "二丫", "明哥", "花姐", "狗蛋", "秀兰",
	"阿泰", "小雨", "石头", "桂香", "三顺", "玉梅", "阿贵", "翠花", "栓子", "月牙",
]
const SOCIAL_TICK_MIN := 1.6
const SOCIAL_TICK_MAX := 3.4
const TALK_RANGE := 3.6

var social_timer := 2.0
var used_names := {}
var last_event := ""

func _make_name() -> String:
	for attempt in 40:
		var base: String = NAME_POOL[rng.randi_range(0, NAME_POOL.size() - 1)]
		var n := base
		var i := 2
		while used_names.has(n):
			n = "%s%d" % [base, i]
			i += 1
		used_names[n] = true
		return n
	return "村民%d" % villagers.size()

func _live_villagers() -> Array:
	var out: Array = []
	for v in villagers:
		if is_instance_valid(v):
			out.append(v)
	return out

func _social_tick(delta: float) -> void:
	social_timer -= delta
	if social_timer > 0.0:
		return
	social_timer = rng.randf_range(SOCIAL_TICK_MIN, SOCIAL_TICK_MAX)
	var night := is_night()
	for v in _live_villagers():
		v.mood_target = happiness
		if v.busy:
			continue
		if night and not v.working and not v.sleeping:
			v.sleeping = true
			v.path = []
			v.say("天黑了，回屋睡觉", 2.4)
		elif not night and v.sleeping:
			v.sleeping = false
			v.say("早上好！", 2.2)
	if rng.randf() < 0.45:
		_roll_thought()
	if not night:
		_start_social_event()
	_check_families()

# ---- 一个人待着的时候会想事情 ----
func _roll_thought() -> void:
	var pool: Array = []
	for v in _live_villagers():
		if v.is_free() and not v.sleeping:
			pool.append(v)
	if pool.is_empty():
		return
	var v = pool[rng.randi_range(0, pool.size() - 1)]
	v.say_thought(_thought_line(v), 3.4)

func _thought_line(v) -> String:
	if food <= 5.0:
		return "肚子好饿呀"
	if happiness < 45.0:
		return "大家最近好像不太高兴"
	if v.mood >= 80.0:
		return "今天心情特别好"
	if population >= housing:
		return "房子不够住了，得再盖几间"
	if gold >= grow_cost()["gold"]:
		return "金币够了，可以找村长扩地盘了"
	if v.partner != "":
		return "和%s过日子真不错" % v.partner
	var generic := [
		"今天的风真舒服", "想去湖边转一圈", "希望能多认识几个朋友",
		"要是村里有座教堂就好了", "木头不够用啊", "听说北边林子很密",
	]
	return String(generic[rng.randi_range(0, generic.size() - 1)])

# ---- 找两个人凑一桌 ----
func _start_social_event() -> void:
	var pool: Array = []
	for v in _live_villagers():
		if v.is_free() and not v.sleeping and not v.child:
			pool.append(v)
	if pool.size() < 2:
		return
	var a = pool[rng.randi_range(0, pool.size() - 1)]
	var b = null
	var best := 1e9
	for v in pool:
		if v == a:
			continue
		var d: float = a.grid_pos.distance_to(v.grid_pos)
		if d < best:
			best = d
			b = v
	if b == null or best > 9.0:
		return
	if a.partner == "" and b.partner == "" and a.friendship(b.pname) >= 70.0:
		_run_marry(a, b)
		return
	if best > TALK_RANGE:
		_run_gather(a, b)
		return
	match _pick_event(a, b):
		"fight":
			_run_fight(a, b)
		"argue":
			_run_argue(a, b)
		"play":
			_run_play(a, b)
		"joke":
			_run_joke(a, b)
		_:
			_run_chat(a, b)

func _pick_event(a, b) -> String:
	var avg: float = (a.mood + b.mood) * 0.5
	var r := rng.randf()
	if avg < 25.0:
		return "fight" if r < 0.4 else "argue"
	if avg < 45.0:
		if r < 0.12:
			return "fight"
		if r < 0.5:
			return "argue"
		return "chat" if r < 0.85 else "play"
	if avg > 70.0:
		if r < 0.3:
			return "play"
		if r < 0.6:
			return "joke"
		return "chat"
	return "chat" if r < 0.65 else ("play" if r < 0.9 else "argue")

func _hold(a, b, state_name: String) -> void:
	for v in [a, b]:
		v.busy = true
		v.working = false
		v.path = []
		v.state = state_name
		v.face_cell((b if v == a else a).grid_pos)

func _alive(a, b) -> bool:
	return is_instance_valid(a) and is_instance_valid(b)

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

# 远处的人会先走到一块儿再聊（聚在一起）
func _run_gather(a, b) -> void:
	_hold(a, b, "approach")
	var mid: Vector2 = (a.grid_pos + b.grid_pos) * 0.5
	var spot := Vector2i(int(round(mid.x)), int(round(mid.y)))
	var picked := Vector2i(-1, -1)
	for radius in range(0, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := spot + Vector2i(dx, dy)
				if _inside(c.x, c.y) and not blocked[_idx(c.x, c.y)]:
					picked = c
					break
			if picked.x >= 0:
				break
		if picked.x >= 0:
			break
	if picked.x < 0:
		a.release()
		b.release()
		return
	var arrived := [0]
	var cb := func() -> void: arrived[0] += 1
	a.go_to(Vector2(picked), cb)
	b.go_to(Vector2(picked), cb)
	var waited := 0.0
	while arrived[0] < 2 and waited < 12.0:
		await _wait(0.25)
		waited += 0.25
		if not _alive(a, b):
			return
	_hold(a, b, "talk")
	a.say("正好，一起聊聊", 2.4)
	await _wait(2.6)
	if _alive(a, b):
		_run_chat(a, b)

func _chat_line(v, other) -> String:
	var lines := [
		"今天收成不错", "你家房子盖得真漂亮", "听说%s最近发财了" % other.pname,
		"盖房子真费木头", "有空多来坐坐", "你最近气色不错啊",
	]
	if v.friendship(other.pname) >= 70.0:
		lines.append("跟你聊天最舒服了")
	if v.mood >= 80.0:
		lines.append("哈哈哈，今天太开心了")
	if v.mood < 40.0:
		lines.append("唉，日子有点难过")
	return String(lines[rng.randi_range(0, lines.size() - 1)])

func _run_chat(a, b) -> void:
	_hold(a, b, "talk")
	last_event = "chat"
	for i in rng.randi_range(2, 3):
		if not _alive(a, b):
			return
		var speaker = a if i % 2 == 0 else b
		var other = b if speaker == a else a
		speaker.face_cell(other.grid_pos)
		speaker.say(_chat_line(speaker, other), 2.5)
		await _wait(2.7)
	var f: float = a.add_friend(b.pname, 7.0)
	b.add_friend(a.pname, 7.0)
	a.mood = minf(100.0, a.mood + 4.0)
	b.mood = minf(100.0, b.mood + 4.0)
	if f >= 70.0 and rng.randf() < 0.4:
		a.say("我们做朋友吧！", 2.6)
		await _wait(2.4)
		if _alive(a, b):
			b.say("好啊，以后互相照应", 2.6)
			await _wait(2.6)
	if _alive(a, b):
		a.release()
		b.release()

func _run_joke(a, b) -> void:
	_hold(a, b, "laugh")
	last_event = "joke"
	var jokes := [
		"我给你讲个笑话：有个人把斧头掉进湖里了……", "你猜石头为什么掉水里？因为它太重了",
		"今天我在林子里差点撞上一头鹿", "刚才我看到%s走路撞树了，哈哈" % b.pname,
	]
	a.say(String(jokes[rng.randi_range(0, jokes.size() - 1)]), 3.0)
	await _wait(3.2)
	if not _alive(a, b):
		return
	b.say("哈哈哈哈哈！", 2.4)
	await _wait(1.2)
	if not _alive(a, b):
		return
	a.say("哈哈，笑死我了", 2.4)
	a.mood = minf(100.0, a.mood + 8.0)
	b.mood = minf(100.0, b.mood + 8.0)
	a.add_friend(b.pname, 5.0)
	b.add_friend(a.pname, 5.0)
	happiness = minf(100.0, happiness + 0.2)
	await _wait(2.4)
	if _alive(a, b):
		a.release()
		b.release()

func _run_play(a, b) -> void:
	_hold(a, b, "play")
	last_event = "play"
	a.say("来玩个游戏吧！", 2.4)
	await _wait(2.2)
	if not _alive(a, b):
		return
	b.say("好啊，追我呀！", 2.4)
	var spots: Array = []
	for i in 3:
		var c := _random_free_cell_near(a.grid_pos, 6.0)
		spots.append(c)
	for i in 1:
		if not _alive(a, b):
			return
		var target: Vector2 = spots[i % spots.size()]
		a.hop = 0.01
		b.hop = 0.01
		var arrived := [0]
		var cb := func() -> void: arrived[0] += 1
		a.go_to(target, cb)
		b.go_to(target + Vector2(1, 1), cb)
		var waited := 0.0
		while arrived[0] < 2 and waited < 9.0:
			await _wait(0.3)
			waited += 0.3
			if not _alive(a, b):
				return
		if _alive(a, b):
			a.hop = 0.0
			b.hop = 0.0
			a.say("好玩好玩！", 2.4)
			b.say("再来一次！", 2.4)
		await _wait(2.4)
	a.mood = minf(100.0, a.mood + 7.0)
	b.mood = minf(100.0, b.mood + 7.0)
	a.add_friend(b.pname, 8.0)
	b.add_friend(a.pname, 8.0)
	happiness = minf(100.0, happiness + 0.15)
	if _alive(a, b):
		a.release()
		b.release()

func _run_argue(a, b) -> void:
	_hold(a, b, "argue")
	last_event = "argue"
	var lines_a := ["你怎么又占了我的料场！", "这活儿明明该你干", "别以为我好说话！"]
	var lines_b := ["谁占你的了？", "胡说，我干得比你多", "你才不讲理呢"]
	a.say(String(lines_a[rng.randi_range(0, lines_a.size() - 1)]), 2.5)
	await _wait(2.6)
	if not _alive(a, b):
		return
	b.say(String(lines_b[rng.randi_range(0, lines_b.size() - 1)]), 2.5)
	await _wait(2.6)
	if not _alive(a, b):
		return
	a.say("哼！", 2.0)
	a.add_friend(b.pname, -6.0)
	b.add_friend(a.pname, -8.0)
	a.mood = maxf(0.0, a.mood - 6.0)
	b.mood = maxf(0.0, b.mood - 8.0)
	happiness = maxf(0.0, happiness - 0.25)
	if rng.randf() < 0.3:
		await _wait(2.2)
		if _alive(a, b):
			a.release()
			b.release()
			_run_fight(a, b)
		return
	await _wait(2.0)
	if _alive(a, b):
		a.release()
		b.release()

func _run_fight(a, b) -> void:
	_hold(a, b, "fight")
	last_event = "fight"
	a.say("看招！", 2.0)
	b.say("哎哟！", 2.0)
	a.jitter = 2.4
	b.jitter = 2.4
	await _wait(1.4)
	if not _alive(a, b):
		return
	a.say("服不服？", 2.0)
	b.say("不服！", 2.0)
	await _wait(1.6)
	a.jitter = 0.0
	b.jitter = 0.0
	a.mood = maxf(0.0, a.mood - 14.0)
	b.mood = maxf(0.0, b.mood - 16.0)
	a.add_friend(b.pname, -18.0)
	b.add_friend(a.pname, -20.0)
	happiness = maxf(0.0, happiness - 0.8)
	_flash("有人打起来了！", Color(1.0, 0.6, 0.5))
	await _wait(1.6)
	if not _alive(a, b):
		return
	a.say("算了，不跟你计较", 2.4)
	b.say("下次别这样了", 2.4)
	await _wait(2.4)
	if _alive(a, b):
		a.release()
		b.release()

func _run_marry(a, b) -> void:
	_hold(a, b, "marry")
	last_event = "marry"
	a.say("和你在一起真好……我们结婚吧？", 3.2)
	await _wait(3.4)
	if not _alive(a, b):
		return
	b.say("我愿意！", 3.0)
	await _wait(2.8)
	if not _alive(a, b):
		return
	a.partner = b.pname
	b.partner = a.pname
	a.spouse_day = day_number
	b.spouse_day = day_number
	a.mood = 100.0
	b.mood = 100.0
	happiness = minf(100.0, happiness + 5.0)
	_flash("村里办了婚礼：%s 和 %s" % [a.pname, b.pname], Color(1.0, 0.86, 0.62))
	a.say("我们结婚啦！", 3.0)
	b.say("谢谢大家来喝喜酒！", 3.0)
	await _wait(3.2)
	if _alive(a, b):
		a.release()
		b.release()

# ---- 婚后有孩子、孩子会长大 ----
func _check_families() -> void:
	for v in _live_villagers():
		if v.child or v.partner == "" or v.spouse_day < 0:
			continue
		if String(v.pname) > String(v.partner):
			continue   # only the alphabetically-first spouse rolls
		if day_number - v.spouse_day < 1:
			continue
		if population + 1 > housing:
			if rng.randf() < 0.05:
				v.say("房子不够住，先不添孩子了", 3.0)
			continue
		if rng.randf() < 0.3:
			v.spouse_day = day_number
			var p: Node = _partner_of(v)
			v.say("我们家要有小宝宝了！", 3.2)
			population += 1
			_spawn_one_villager(true, v.grid_pos)
			_flash("新生了一个小村民", Color(0.86, 0.98, 0.76))
			await _wait(2.0)
			if p != null and is_instance_valid(p):
				p.say("太好了！", 2.6)
			return

func _partner_of(v):
	for other in _live_villagers():
		if other.pname == v.partner:
			return other
	return null

func _grow_children() -> void:
	for v in _live_villagers():
		if v.child and day_number - v.born_day >= 4:
			v.become_adult()
			v.say("我长大了！", 2.6)

func _random_free_cell_near(around: Vector2, radius: float) -> Vector2:
	for attempt in 80:
		var a := rng.randf() * TAU
		var r := rng.randf() * radius
		var c := around + Vector2(cos(a), sin(a)) * r
		var x := int(round(c.x))
		var y := int(round(c.y))
		if _inside(x, y) and not blocked[_idx(x, y)] and terrain[_idx(x, y)] != "water":
			return Vector2(x, y)
	return around

# ======================================================================
# Everything below is the interface the town director uses: where things
# are, what can be walked on, the seasons and the fields.
# ======================================================================

func time_scale() -> float:
	return float(SPEEDS[speed_index])

func hours_per_second() -> float:
	return _hours_per_second()

func walkable(x: int, y: int) -> bool:
	if not _inside(x, y):
		return false
	var i := _idx(x, y)
	return not blocked[i] and terrain[i] != "water"

func _free_cell_near(around: Vector2, radius: float) -> Vector2:
	var base := Vector2i(int(round(around.x)), int(round(around.y)))
	if walkable(base.x, base.y):
		return Vector2(base)
	for r in range(1, int(radius) + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := base + Vector2i(dx, dy)
				if walkable(c.x, c.y):
					return Vector2(c)
	return around

func open_spot_near(around: Vector2, radius: float) -> Vector2i:
	var base := Vector2i(int(round(around.x)), int(round(around.y)))
	for r in range(1, int(radius) + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := base + Vector2i(dx, dy)
				if walkable(c.x, c.y) and not roads[_idx(c.x, c.y)]:
					return c
	return Vector2i(-1, -1)

# Somewhere to stroll to: a few tiles away, never the tile the villager is
# standing on, so the walk really happens.
func wander_spot(from: Vector2) -> Vector2:
	for attempt in 24:
		var a := rng.randf() * TAU
		var r := 3.0 + rng.randf() * 6.0
		var c := from + Vector2(cos(a), sin(a)) * r
		var x := int(round(c.x))
		var y := int(round(c.y))
		if walkable(x, y) and Vector2(x, y).distance_to(from) > 2.0:
			return Vector2(x, y)
	return _free_cell_near(from + Vector2(4, 0), 5.0)

# A free tile close to a spot the villager wants to use, picked at random so a
# crowd does not all pile onto the same tile.
func random_spot_near(around: Vector2, radius: float) -> Vector2:
	var base := Vector2i(int(round(around.x)), int(round(around.y)))
	for attempt in 20:
		var c := base + Vector2i(rng.randi_range(-int(radius), int(radius)), rng.randi_range(-int(radius), int(radius)))
		if walkable(c.x, c.y):
			return Vector2(c)
	return _free_cell_near(around, radius + 1.0)

# The far corner of the map stands in for the mountains: villagers walk out
# there to go hiking or to set off on a journey.
func scenic_spot(from: Vector2) -> Vector2:
	var best := from
	var best_d := -1.0
	var edge := 3
	for y in range(edge, mh - edge):
		for x in [edge, mw - 1 - edge]:
			if not walkable(x, y):
				continue
			var d := Vector2(x, y).distance_to(from)
			if d > best_d:
				best_d = d
				best = Vector2(x, y)
	for x in range(edge, mw - edge):
		for y in [edge, mh - 1 - edge]:
			if not walkable(x, y):
				continue
			var d2 := Vector2(x, y).distance_to(from)
			if d2 > best_d:
				best_d = d2
				best = Vector2(x, y)
	return best

func building_door_cell(b: Dictionary) -> Vector2i:
	var foot: Vector2 = b["foot"]
	var cell: Vector2 = b["cell"]
	var door := Vector2i(int(cell.x) + int(foot.x) - 1, int(cell.y) + int(foot.y) - 1)
	var c := _free_door_cell(door)
	if c.x >= 0:
		return c
	# cramped corner of the village: take any free tile around the footprint
	for radius in range(1, 6):
		for dy in range(-radius, int(foot.y) + radius):
			for dx in range(-radius, int(foot.x) + radius):
				if dx >= 0 and dx < int(foot.x) and dy >= 0 and dy < int(foot.y):
					continue
				var cc := Vector2i(int(cell.x) + dx, int(cell.y) + dy)
				if not _inside(cc.x, cc.y):
					continue
				if _road_ok(cc.x, cc.y):
					return cc
	return Vector2i(-1, -1)

func building_spot(kind: String) -> Vector2i:
	for b in buildings:
		if String(b["kind"]) == kind:
			var c := building_door_cell(b)
			if c.x >= 0:
				return c
	return Vector2i(-1, -1)

func warehouse_cell() -> Vector2i:
	var c := building_spot("warehouse")
	if c.x < 0:
		c = building_spot("market")
	if c.x < 0:
		c = open_spot_near(Vector2(cross_cell), 4.0)
	return c

func job_for_building(kind: String) -> String:
	match kind:
		"lumber", "carpenter":
			return "lumber"
		"quarry":
			return "quarry"
		"farm", "bakery", "windmill", "vineyard":
			return "farm"
		"fishing":
			return "fish"
		"market", "tradeguild", "tavern", "tailor", "goldsmith", "armory":
			return "trade"
		"hunters", "medic", "monastery":
			return "herb"
		_:
			return ""

func skin_for_job(job: String, female: bool) -> String:
	match job:
		"lumber", "quarry", "build":
			return "lumberjack"
		"farm":
			return "farmer"
		"fish":
			return "hunter"
		"trade":
			return "female_01" if female else "townie"
		"herb":
			return "female_02" if female else "monk"
		_:
			return "female_02" if female else "craftsman"

# ---------- water ----------

func lake_any() -> bool:
	return not water_cells.is_empty()

func water_next_to(cell: Vector2i, away: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = cell + Vector2i(step)
		if c == away:
			continue
		if _inside(c.x, c.y) and terrain[_idx(c.x, c.y)] == "water":
			return c
	return Vector2i(-1, -1)

func fishing_spot_near(from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	for c in shore_cells:
		var d: float = Vector2(c).distance_to(from)
		if d < best_d:
			best_d = d
			best = c
	return best

func _collect_water_and_shore() -> void:
	water_cells.clear()
	shore_cells.clear()
	for y in mh:
		for x in mw:
			if terrain[_idx(x, y)] == "water":
				water_cells.append(Vector2i(x, y))
			elif walkable(x, y) and water_next_to(Vector2i(x, y)).x >= 0:
				shore_cells.append(Vector2i(x, y))

func _water_touches_land(x: int, y: int) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = Vector2i(x, y) + Vector2i(step)
		if not _inside(c.x, c.y):
			return true
		if String(terrain[_idx(c.x, c.y)]) != "water":
			return true
	return false

# ---------- the corn fields ----------

func _collect_fields() -> void:
	fields.clear()
	# 一块田里的麦子一起长，不然同一个田块会花花的
	var plot_growth := {}
	for y in mh:
		for x in mw:
			if terrain[_idx(x, y)] != "field":
				continue
			var pi := _plot_index(x, y)
			if not plot_growth.has(pi):
				plot_growth[pi] = FIELD_GROW_HOURS * rng.randf_range(0.25, 1.0)
			var f := {
				"cell": Vector2(x, y), "ripe": false,
				"growth": float(plot_growth[pi]), "sprite": null,
				"busy": false, "busy_hours": 0.0,
			}
			_add_crop_sprite(f)
			_apply_crop_look(f)
			fields.append(f)

func _plot_index(x: int, y: int) -> int:
	var c := Vector2i(x, y)
	for i in FIELD_PLOTS.size():
		if _plot_rect(FIELD_PLOTS[i]).has_point(c):
			return i
	return 0

func _add_crop_sprite(f: Dictionary) -> void:
	var sp := _tt_sprite("buildings03/cornfield_1x1_00.2.png")
	# 麦子跟房子、村民一起按 y 排序：人站进田里，麦子就自然挡在人前面，
	# 比单独糊一块矩形贴图真实得多
	sp.position = iso(f["cell"]) + Vector2(0, HH + 2)
	object_layer.add_child(sp)
	f["sprite"] = sp

# 麦子按生长进度换高度：刚割完是矮茬，然后越长越高。收割看得见的"少一截"
# 就靠这个（地面那层是翻好的土）。
func _field_ratio(f: Dictionary) -> float:
	return clampf(float(f.get("growth", 0.0)) / FIELD_GROW_HOURS, 0.0, 1.0)

func _apply_crop_look(f: Dictionary) -> void:
	var r := _field_ratio(f)
	# 已经有人去收这一块田了（busy），就别再标成"熟了"，不然第二个人也会
	# 跑来割同一格，一块地会被割两遍
	f["ripe"] = r >= 1.0 and not bool(f.get("busy", false))
	var sp = f.get("sprite")
	if not is_instance_valid(sp):
		return
	# 麦子到腰那么高：既挡得住腿，又能看见人（太高会把村民整个埋掉）
	var s := 0.16
	if r >= 0.85:
		s = 0.56
	elif r >= 0.55:
		s = 0.44
	elif r >= 0.25:
		s = 0.30
	sp.visible = season != 3
	sp.scale = Vector2(1.0, s)

# 收割：割完田里立刻矮下去，过一阵再长回来。
# 一块田里的麦子是一起长的，所以也得一起割 —— 只把村民脚下那一格压矮的话，
# 同一块田就变成高一块矮一块的大花脸，看着像出了 bug。
func harvest_field(f: Dictionary) -> void:
	var pi := _plot_index(int(Vector2(f["cell"]).x), int(Vector2(f["cell"]).y))
	for g in fields:
		var c: Vector2 = g["cell"]
		if _plot_index(int(c.x), int(c.y)) != pi:
			continue
		g["growth"] = 0.0
		g["ripe"] = false
		g["busy"] = false
		g["busy_hours"] = 0.0
		_apply_crop_look(g)

func next_ripe_field() -> Dictionary:
	for f in fields:
		if bool(f["ripe"]) and not bool(f.get("busy", false)):
			return f
	return {}

# 村民去收这块田之前先"认领"：同一块田里的麦子一起割，所以整块一起认领
func claim_field(f: Dictionary) -> void:
	var pi := _plot_index(int(Vector2(f["cell"]).x), int(Vector2(f["cell"]).y))
	for g in fields:
		var c: Vector2 = g["cell"]
		if _plot_index(int(c.x), int(c.y)) != pi:
			continue
		g["busy"] = true
		g["busy_hours"] = 0.0
		g["ripe"] = false

# 锄草 / 浇水：整块田一起快一点，别只给村民脚下那一格加进度
func tend_field(f: Dictionary) -> void:
	var pi := _plot_index(int(Vector2(f["cell"]).x), int(Vector2(f["cell"]).y))
	for g in fields:
		var c: Vector2 = g["cell"]
		if _plot_index(int(c.x), int(c.y)) != pi:
			continue
		if bool(g.get("busy", false)):
			continue
		g["growth"] = float(g.get("growth", 0.0)) + 0.6
		_apply_crop_look(g)

# 这块田一共有多少格。收割是整块一起割的，所以粮食也按格数给，
# 免得"只改画面"却把产量一起砍掉了。
func plot_cells(f: Dictionary) -> int:
	var pi := _plot_index(int(Vector2(f["cell"]).x), int(Vector2(f["cell"]).y))
	var n := 0
	for g in fields:
		var c: Vector2 = g["cell"]
		if _plot_index(int(c.x), int(c.y)) == pi:
			n += 1
	return maxi(1, n)

func next_field() -> Dictionary:
	if fields.is_empty():
		return {}
	return fields[rng.randi_range(0, fields.size() - 1)]

func _grow_fields(hours: float) -> void:
	if season == 3:
		return      # 冬天庄稼不长
	var changed := false
	for f in fields:
		if bool(f.get("busy", false)):
			# 有人正在收这块田，先别急着长，也别把 ripe 又标回去；
			# 万一那个人半路被打断了，过一阵自动放开，免得这块田卡死。
			f["busy_hours"] = float(f.get("busy_hours", 0.0)) + hours
			if float(f["busy_hours"]) > FIELD_CLAIM_HOURS:
				f["busy"] = false
				f["busy_hours"] = 0.0
				f["ripe"] = _field_ratio(f) >= 1.0
			continue
		if bool(f["ripe"]):
			continue
		f["growth"] = float(f.get("growth", 0.0)) + hours
		_apply_crop_look(f)
		changed = true

# ---------- the four seasons ----------

const SEASON_NAMES := ["春天", "夏天", "秋天", "冬天"]
const SEASON_PROPS := {
	0: "props_spring/",
	2: "props_autumn/",
	3: "props_winter/",
}

func season_name() -> String:
	return SEASON_NAMES[clampi(season, 0, 3)]

# spring/summer/autumn keep the green atlas (autumn just wears a warm tint),
# winter swaps in the snow tiles sliced from the winter atlas
func _season_tile_path(p: String) -> String:
	if season == 3:
		var name := p.get_file()
		if name.begins_with("tile_1x1_g_"):
			var cand := "winter1/" + name
			if ResourceLoader.exists(TT + cand):
				return cand
		# 农田在冬天只剩雪下的空地
		if name.begins_with("cornfield_1x1_"):
			return "winter1/tile_1x1_g_4_0_00.png"
	return p

func _season_prop_path(p: String) -> String:
	var dir := String(SEASON_PROPS.get(season, ""))
	if dir == "":
		return p
	var name := p.get_file()
	var cand := dir + name
	if ResourceLoader.exists(TT + cand):
		return cand
	return p

func _apply_prop_texture(sp: Sprite2D, path: String) -> void:
	var tex: Texture2D = load(TT + path)
	if tex == null:
		return
	sp.texture = tex
	var img := tex.get_image()
	var used := img.get_used_rect()
	var size := Vector2(img.get_width(), img.get_height())
	var ax := float(used.position.x) + float(used.size.x) * 0.5
	var ay := float(used.position.y + used.size.y)
	sp.offset = Vector2(size.x * 0.5 - ax, size.y * 0.5 - ay)

func _apply_season_props() -> void:
	for e in prop_nodes:
		var sp = e["node"]
		if not is_instance_valid(sp):
			continue
		_apply_prop_texture(sp, _season_prop_path(String(e["path"])))

func on_season_changed(s: int) -> void:
	season = clampi(s, 0, 3)
	if town != null:
		town.season = season
	# 冬天田里没有青苗
	for f in fields:
		_apply_crop_look(f)
	_rebuild_ground()
	_apply_season_props()
	_apply_weather()
	_flash("%s到了" % season_name(), Color(0.92, 0.96, 1.0))
	_refresh_hud()

func _apply_weather() -> void:
	if fx == null:
		return
	# 天上飘花瓣/落叶/雪花的粒子已经关掉了：一屏几百个粒子既占内存又没什么用，
	# 季节从地面配色、树和植被本身就能看出来。
	fx.set_weather("")

func _ground_tint() -> Color:
	match season:
		0:
			return Color(0.98, 1.04, 0.96)
		2:
			return Color(1.08, 0.94, 0.76)
		3:
			return Color(0.96, 1.0, 1.06)
		_:
			return Color.WHITE

# ======================================================================
# Talking to a villager: the panel reads this, and typed orders are parsed
# here into a plan the villager then walks through.
# ======================================================================

func villager_info(v) -> Dictionary:
	var realm_txt := "未入道"
	if v.cultivate or v.realm > 0:
		realm_txt = "%s（%s）" % [
			town.realm_name(v), "在修仙场修炼" if v.cultivate else "闲时修炼"]
	return {
		"title": "%s    %s" % [v.display_name(), v.job_text()],
		"lines": [
			"活了 %d 小时（第 %d 天出生）  ·  能力 %.2f 倍" % [
				int(v.life_hours), int(v.born_day), v.skill],
			"住处：%s      婚姻：%s" % [v.home_text(), v.partner_text()],
			"性格：%s      心情：%s（%d%%）" % [v.traits_text(), v.mood_word(), int(v.mood)],
			"现在：%s" % v.activity_text(),
			"他心里在想：%s" % ("——" if v.last_thought == "" else v.last_thought),
			"修仙：%s" % realm_txt,
		],
	}

func _said(text: String, keys: Array) -> bool:
	for k in keys:
		if text.contains(String(k)):
			return true
	return false

# The player types something at a villager and he answers and does it.
func command_villager(v, text: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return "（他没听清）"
	if _said(t, ["砍树", "伐木", "木头", "木材"]):
		v.job = "lumber"
		v.apply_skin("lumberjack")
		v.cancel_plan()
		return "好，我去砍树！"
	if _said(t, ["采石", "石头", "矿"]):
		v.job = "quarry"
		v.apply_skin("lumberjack")
		v.cancel_plan()
		return "行，我去采石头！"
	if _said(t, ["庄稼", "收成", "收粮", "种地", "农田", "锄草"]):
		v.job = "farm"
		v.apply_skin("farmer")
		v.cancel_plan()
		return "好，我去田里干活！"
	if _said(t, ["钓鱼", "捕鱼", "鱼"]):
		v.job = "fish"
		v.apply_skin("hunter")
		v.cancel_plan()
		return "行，我去湖边钓鱼！"
	if _said(t, ["市集", "生意", "买卖", "卖", "赚钱"]):
		v.job = "trade"
		v.apply_skin(skin_for_job("trade", v.female))
		v.cancel_plan()
		return "好，我去市集摆摊！"
	if _said(t, ["采药", "草药"]):
		v.job = "herb"
		v.apply_skin(skin_for_job("herb", v.female))
		v.cancel_plan()
		return "行，我去林子里采药！"
	if _said(t, ["盖房", "工地", "建造", "帮忙"]):
		var site = town.next_site() if town != null else null
		if site != null:
			v.job = "build"
			v.apply_skin("lumberjack")
			v.cancel_plan()
			v.run_plan(town._build_plan_for(v, site))
			return "我这就去工地！"
		return "现在没有工地要我干。"
	if _said(t, ["游泳", "玩水"]):
		v.cancel_plan()
		v.run_plan(town._lake_plan(v))
		return "好，我去湖边玩水！"
	if _said(t, ["爬山", "上山", "远足"]):
		v.cancel_plan()
		v.run_plan(town._hike_plan(v))
		return "好，我上山转转！"
	if _said(t, ["旅游", "旅行", "出门", "见世面"]):
		v.cancel_plan()
		v.run_plan(town._travel_plan(v))
		return "好，我出去走走！"
	if _said(t, ["修仙", "修炼", "打坐", "渡劫"]):
		if town.cultivation_place().x >= 0:
			town.assign_cultivation(v, true)
			v.cancel_plan()
			v.run_plan(town._cultivate_plan(v))
			return "好，我去修仙场修炼！"
		return "村里还没有修仙场，先建一座吧。"
	if _said(t, ["别修", "停止修炼", "不修了"]):
		town.assign_cultivation(v, false)
		return "好，我先不修了。"
	if _said(t, ["回家", "休息", "睡觉", "歇"]):
		v.cancel_plan()
		v.run_plan([
			{"op": "say", "text": "那我先回屋歇会儿", "secs": 2.4},
			{"op": "goto", "cell": town._home_spot(v)},
			{"op": "hide"},
			{"op": "call", "fn": func() -> void: v.sleeping = true},
		])
		return "我回去歇会儿。"
	if _said(t, ["市集逛逛", "去玩", "逛逛"]):
		v.cancel_plan()
		v.run_plan(town._market_plan(v))
		return "那我去市集转转。"
	if _said(t, ["过来", "跟我", "来这里", "这边"]):
		v.cancel_plan()
		v.run_plan([
			{"op": "say", "text": "来了来了！", "secs": 2.2},
			{"op": "goto", "cell": _free_cell_near(camera.position, 3.0)},
		])
		return "我这就过来。"
	if _said(t, ["你好", "在干嘛", "干什么", "忙什么"]):
		v.say("我在%s呢" % v.activity_text(), 3.0)
		return "我%s呢。" % v.activity_text()
	return "这个我听不太懂，你说得具体点？"

func nudge_site(index: int) -> void:
	if index < 0 or index >= sites.size():
		return
	var site = sites[index]
	var best = null
	var best_d := 1e9
	for v in _live_villagers():
		if v.child or v.sleeping:
			continue
		var d: float = v.grid_pos.distance_to(Vector2(site.cell))
		if d < best_d:
			best_d = d
			best = v
	if best == null:
		return
	best.cancel_plan()
	best.run_plan(town._build_plan_for(best, site))
	_flash("%s 去工地干活了" % best.pname, Color(0.9, 0.96, 1.0))

func cancel_site_at(index: int) -> void:
	if index >= 0 and index < sites.size():
		_cancel_site(sites[index])
