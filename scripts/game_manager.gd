extends Node
class_name GameManager

## Controlador central da partida RTS: economia (comida, madeira, ouro, pedra), mercado, seleção,
## formações, ghost de construção, grades espaciais, alertas e vitória/derrota.

signal resources_changed()
signal selection_changed()
signal alert_posted(message: String, color: Color)
signal game_over(player_won: bool, stats: Dictionary)
signal decree_available(pending_count: int)
signal decree_applied(decree_id: String, info: Dictionary)

const MAX_POP_LIMIT: int = 100
const MAP_HALF: float = 100.0
const TERRAIN_HALF: float = 130.0
const UNIT_BOUND: float = 96.0
const BUILD_BOUND: float = 94.0
const RES_TYPES: Array[String] = ["food", "wood", "gold", "stone"]
const RES_NAMES: Dictionary = {"food": "Comida", "wood": "Madeira", "gold": "Ouro", "stone": "Pedra"}
const RES_SHORT: Dictionary = {"food": "C", "wood": "M", "gold": "O", "stone": "P"}
const RES_COLORS: Dictionary = {
	"food": Color(1.0, 0.56, 0.46),
	"wood": Color(0.55, 0.92, 0.45),
	"gold": Color(1.0, 0.85, 0.25),
	"stone": Color(0.80, 0.82, 0.88),
}
const START_RESOURCES: Dictionary = {"food": 200, "wood": 200, "gold": 100, "stone": 100}
const MARKET_FEE: float = 0.3
const MARKET_LOT: int = 100
const MARKET_BASE: Dictionary = {"food": 100.0, "wood": 100.0, "stone": 130.0}
const OBS_CELL: float = 8.0
const UNIT_CELL: float = 4.0

const BOUNTY_TABLE: Dictionary = {
	"scout": 8, "spearman": 10, "soldier": 12, "archer": 14, "knight": 25, "ram": 35, "captain": 100,
}

const ROYAL_DECREES: Array[Dictionary] = [
	{
		"id": "tempered_steel", "title": "Aço Temperado", "icon": "stat_attack", "repeatable": false,
		"desc": "+20% de dano corpo-a-corpo para Batedores, Espadachins, Lanceiros e Paladinos.",
	},
	{
		"id": "yew_longbows", "title": "Arcos Longos de Teixo", "icon": "stat_range", "repeatable": false,
		"desc": "+20% de dano e +2.5 m de alcance para Arqueiros, Torres, Salões e Castelos.",
	},
	{
		"id": "plate_forging", "title": "Forja de Placas Reais", "icon": "stat_armor", "repeatable": false,
		"desc": "+2 de armadura e +15% de vida máxima para todas as tropas militares.",
	},
	{
		"id": "iron_tools", "title": "Ferramentas de Ferro", "icon": "cmd_gather", "repeatable": false,
		"desc": "+25% de velocidade de coleta para todos os Camponeses.",
	},
	{
		"id": "granite_masonry", "title": "Alvenaria de Granito", "icon": "res_stone", "repeatable": false,
		"desc": "+30% de vida nas construções e +35% de rapidez para erguer e reparar.",
	},
	{
		"id": "swift_muster", "title": "Recrutamento Relâmpago", "icon": "stat_speed", "repeatable": false,
		"desc": "-25% de tempo de treino em Salões Reais, Quartéis, Campos de Tiro e Castelos.",
	},
	{
		"id": "siege_engineers", "title": "Engenheiros de Cerco", "icon": "tab_mil", "repeatable": false,
		"desc": "+35% de dano contra prédios e +20% de velocidade de marcha para Aríetes.",
	},
	{
		"id": "war_spoils", "title": "Espólios de Guerra", "icon": "res_gold", "repeatable": false,
		"desc": "Ouro em dobro ao abater inimigos em batalha e ao saquear covis.",
	},
	{
		"id": "forced_march", "title": "Marcha Forçada", "icon": "cmd_attack_move", "repeatable": false,
		"desc": "+15% de velocidade de deslocamento para todas as tropas militares.",
	},
	{
		"id": "castle_garrison", "title": "Guarda das Ameias", "icon": "ui_base", "repeatable": false,
		"desc": "+1 flecha extra por salva disparada por Salões Reais, Torres e Castelos.",
	},
	{
		"id": "royal_reinforcements", "title": "Reforço da Coroa", "icon": "emblem_crown", "repeatable": true,
		"desc": "Recebe imediatamente 3 Espadachins e 2 Arqueiros no Salão Real (sem travar população).",
	},
	{
		"id": "royal_convoy", "title": "Comboio de Suprimentos", "icon": "market_buy", "repeatable": true,
		"desc": "Entrega imediata de +250 Madeira, +200 Comida, +150 Ouro e +100 Pedra.",
	},
]

var units: Array[RTSUnit] = []
var buildings: Array[RTSBuilding] = []
var resources: Array[RTSResourceNode] = []
var caches: Array = []
var static_obstacles: Array[Dictionary] = []

var selected_units: Array[RTSUnit] = []
var selected_building: Variant = null
var selected_resource: Variant = null

var team_data: Dictionary = {}
var team_stats: Dictionary = {}
var stats: Dictionary = {}
var gather_mult: Dictionary = {0: 1.0, 1: 1.0}
var player_mods: Dictionary = _default_player_mods()
var active_decrees: Array[String] = []
var pending_decrees: int = 0
var _current_decree_choices: Array[Dictionary] = []
var _first_decree_granted: bool = false
var _kills_toward_decree: int = 0
var war_cry_cd: float = 0.0
var defense_bell_cd: float = 0.0
var defense_bell_active: float = 0.0
var market_prices: Dictionary = MARKET_BASE.duplicate()
var team_base_pos: Dictionary = {0: Vector3(-66.0, 0.0, 66.0), 1: Vector3(66.0, 0.0, -66.0)}

var match_time: float = 0.0
var match_started: bool = false
var is_game_over: bool = false
var winner_team: int = -1
var lairs_total: int = 0
var difficulty: String = "normal"
var attack_move_mode: bool = false
var pending_building_type: String = ""

var world_root: Node3D = null
var camera_rig: RTSCamera = null
var sfx: SFXManager = null
var vfx: VFXManager = null
var ai_controller: Node = null
var ai_controllers: Dictionary = {}
var hud: Node = null
var fog: FogOfWar = null
var nav: NavGrid = null

var pings: Array[Dictionary] = []
var last_alert_pos: Vector3 = Vector3(INF, 0.0, INF)
var _alert_cooldowns: Dictionary = {}
var _market_drift_timer: float = 0.0

var _obs_grid: Dictionary = {}
var _obs_by_ref: Dictionary = {}
var _query_stamp: int = 0
var _unit_grid: Dictionary = {}
var _unit_grid_keys: Array[Vector2i] = []

var _ghost_node: Node3D = null
var _ghost_mat: StandardMaterial3D = null
var _is_dragging_box: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _last_click_time: float = 0.0
var _last_clicked_unit: Variant = null
var _idle_worker_cycle_idx: int = 0
var _control_groups: Dictionary = {}
var _last_group_tap_time: float = 0.0
var _last_group_tap_id: int = -1
var _hover_ring: MeshInstance3D = null
var _hover_ring_mat: StandardMaterial3D = null
var _last_cursor_shape: int = -1
var _decree_rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func _default_player_mods() -> Dictionary:
	return {
		"melee_dmg_mult": 1.0,
		"ranged_dmg_mult": 1.0,
		"ranged_range_bonus": 0.0,
		"army_armor_bonus": 0,
		"army_hp_mult": 1.0,
		"army_speed_mult": 1.0,
		"siege_dmg_mult": 1.0,
		"siege_speed_mult": 1.0,
		"build_speed_mult": 1.0,
		"building_hp_mult": 1.0,
		"train_time_mult": 1.0,
		"bounty_mult": 1.0,
		"extra_arrows": 0,
	}


func _init() -> void:
	for t in [0, 1]:
		var d: Dictionary = {"pop_used": 0, "pop_cap": 0}
		for r in RES_TYPES:
			d[r] = int(START_RESOURCES[r])
		team_data[t] = d
		team_stats[t] = _new_stats()
	stats = team_stats[0]


func _new_stats() -> Dictionary:
	return {
		"units_trained": 0, "enemies_slain": 0, "units_lost": 0,
		"buildings_built": 0, "buildings_destroyed": 0, "buildings_lost": 0,
		"food_gathered": 0, "wood_gathered": 0, "gold_gathered": 0, "stone_gathered": 0,
		"lairs_destroyed": 0,
	}


func _ready() -> void:
	process_physics_priority = -10
	_decree_rng.randomize()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.25, 0.95, 0.45, 0.52)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _physics_process(_delta: float) -> void:
	_rebuild_unit_grid()


func _process(delta: float) -> void:
	if match_started and not is_game_over:
		match_time += delta
		if war_cry_cd > 0.0:
			war_cry_cd = maxf(0.0, war_cry_cd - delta)
		if defense_bell_cd > 0.0:
			defense_bell_cd = maxf(0.0, defense_bell_cd - delta)
		if defense_bell_active > 0.0:
			defense_bell_active = maxf(0.0, defense_bell_active - delta)
		if not _first_decree_granted and not ai_controllers.has(0) and match_time >= 75.0:
			_first_decree_granted = true
			grant_royal_decree("Carta Régia da Fronteira pronta!")
		_market_drift_timer += delta
		if _market_drift_timer >= 8.0:
			_market_drift_timer = 0.0
			for r in market_prices.keys():
				var base: float = float(MARKET_BASE[r])
				market_prices[r] = move_toward(float(market_prices[r]), base, 1.0)
	if pending_building_type != "" and _ghost_node != null:
		_update_ghost_position()
	if camera_rig != null:
		camera_rig.block_edge_pan = is_drawing_selection_box() or _is_pointer_over_hud()
	if match_started and not is_game_over and DisplayServer.get_name() != "headless":
		_update_hover_feedback()
	for i in range(pings.size() - 1, -1, -1):
		pings[i]["t"] = float(pings[i]["t"]) + delta
		if float(pings[i]["t"]) > 5.0:
			pings.remove_at(i)


# ==============================================================================
# ECONOMIA, CUSTOS E POPULAÇÃO
# ==============================================================================

func get_res(team: int, r_type: String) -> int:
	var d: Dictionary = team_data[team]
	return int(d.get(r_type, 0))


func get_team_gold(team: int) -> int:
	return get_res(team, "gold")


func get_team_wood(team: int) -> int:
	return get_res(team, "wood")


func get_team_pop_used(team: int) -> int:
	var d: Dictionary = team_data[team]
	return int(d["pop_used"])


func get_team_pop_cap(team: int) -> int:
	var d: Dictionary = team_data[team]
	return mini(MAX_POP_LIMIT, int(d["pop_cap"]))


func get_gather_mult(team: int) -> float:
	return float(gather_mult.get(team, 1.0))


func add_resource(team: int, r_type: String, amount: int) -> void:
	if amount <= 0 or not RES_TYPES.has(r_type):
		return
	var d: Dictionary = team_data[team]
	d[r_type] = int(d[r_type]) + amount
	var st: Dictionary = team_stats[team]
	var key: String = r_type + "_gathered"
	st[key] = int(st.get(key, 0)) + amount
	if team == 0:
		resources_changed.emit()


func can_afford_cost(team: int, cost: Dictionary) -> bool:
	var d: Dictionary = team_data[team]
	for r in cost.keys():
		if int(d.get(r, 0)) < int(cost[r]):
			return false
	return true


func spend_cost(team: int, cost: Dictionary) -> bool:
	if not can_afford_cost(team, cost):
		return false
	var d: Dictionary = team_data[team]
	for r in cost.keys():
		d[r] = int(d[r]) - int(cost[r])
	if team == 0:
		resources_changed.emit()
	return true


func refund_cost(team: int, cost: Dictionary) -> void:
	var d: Dictionary = team_data[team]
	for r in cost.keys():
		d[r] = int(d.get(r, 0)) + int(cost[r])
	if team == 0:
		resources_changed.emit()


## Compatibilidade: custo em ouro/madeira.
func can_afford(team: int, gold_cost: int, wood_cost: int) -> bool:
	return can_afford_cost(team, {"gold": gold_cost, "wood": wood_cost})


func spend(team: int, gold_cost: int, wood_cost: int) -> bool:
	return spend_cost(team, {"gold": gold_cost, "wood": wood_cost})


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RES_TYPES:
		if cost.has(r) and int(cost[r]) > 0:
			parts.append("%d%s" % [int(cost[r]), String(RES_SHORT[r])])
	return " ".join(parts) if not parts.is_empty() else "Grátis"


static func format_cost_long(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RES_TYPES:
		if cost.has(r) and int(cost[r]) > 0:
			parts.append("%d %s" % [int(cost[r]), String(RES_NAMES[r])])
	return ", ".join(parts) if not parts.is_empty() else "Grátis"


func missing_cost_text(team: int, cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RES_TYPES:
		if cost.has(r):
			var miss: int = int(cost[r]) - get_res(team, r)
			if miss > 0:
				parts.append("%d %s" % [miss, String(RES_NAMES[r])])
	return ", ".join(parts)


func can_afford_building(team: int, b_type: String) -> bool:
	var cfg: Dictionary = RTSBuilding.STATS.get(b_type, {})
	if cfg.is_empty():
		return false
	return can_afford_cost(team, cfg["cost"])


func can_afford_unit(team: int, u_type: String) -> bool:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	if cfg.is_empty():
		return false
	return can_afford_cost(team, cfg["cost"])


func spend_for_unit(team: int, u_type: String) -> bool:
	return spend_cost(team, RTSUnit.get_cost(u_type))


func refund_unit(team: int, u_type: String) -> void:
	refund_cost(team, RTSUnit.get_cost(u_type))


func get_unit_train_time(u_type: String, team: int = 0) -> float:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	var base_t: float = float(cfg.get("train_time", 10.0))
	if team == 0:
		base_t *= float(player_mods.get("train_time_mult", 1.0))
	return maxf(3.0, base_t)


func get_unit_pop_cost(u_type: String) -> int:
	var cfg: Dictionary = RTSUnit.STATS.get(u_type, {})
	return int(cfg.get("pop", 1))


func has_pop_space(team: int, needed: int) -> bool:
	return get_team_pop_used(team) + needed <= get_team_pop_cap(team)


func recalculate_population() -> void:
	for t in [0, 1]:
		var d: Dictionary = team_data[t]
		d["pop_used"] = 0
		d["pop_cap"] = 0
	for u in units:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.hp > 0.0:
			var d: Dictionary = team_data[u.team]
			d["pop_used"] = int(d["pop_used"]) + u.pop_cost
	for b in buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.is_constructed and b.hp > 0.0:
			var d: Dictionary = team_data[b.team]
			d["pop_cap"] = int(d["pop_cap"]) + b.pop_bonus
	resources_changed.emit()


# ==============================================================================
# MERCADO
# ==============================================================================

func get_market_buy_cost(r_type: String) -> int:
	return int(round(float(market_prices.get(r_type, 100.0)) * (1.0 + MARKET_FEE)))


func get_market_sell_gain(r_type: String) -> int:
	return int(round(float(market_prices.get(r_type, 100.0)) * (1.0 - MARKET_FEE)))


func market_buy(team: int, r_type: String) -> bool:
	if not market_prices.has(r_type):
		return false
	var cost: int = get_market_buy_cost(r_type)
	if not spend_cost(team, {"gold": cost}):
		return false
	add_resource(team, r_type, MARKET_LOT)
	market_prices[r_type] = clampf(float(market_prices[r_type]) + 5.0, 25.0, 400.0)
	if team == 0:
		resources_changed.emit()
		if sfx != null:
			sfx.play_market_trade()
	return true


func market_sell(team: int, r_type: String) -> bool:
	if not market_prices.has(r_type):
		return false
	if not spend_cost(team, {r_type: MARKET_LOT}):
		return false
	var d: Dictionary = team_data[team]
	d["gold"] = int(d["gold"]) + get_market_sell_gain(r_type)
	market_prices[r_type] = clampf(float(market_prices[r_type]) - 5.0, 25.0, 400.0)
	if team == 0:
		resources_changed.emit()
		if sfx != null:
			sfx.play_market_trade()
	return true


# ==============================================================================
# SPAWN DE ENTIDADES
# ==============================================================================

func spawn_unit(u_type: String, pos: Vector3, team: int) -> RTSUnit:
	if world_root == null:
		return null
	var u: RTSUnit = RTSUnit.new()
	u.position = Vector3(clampf(pos.x, -UNIT_BOUND, UNIT_BOUND), 0.0, clampf(pos.z, -UNIT_BOUND, UNIT_BOUND))
	if nav != null and not nav.is_walkable_world(u.position):
		var free: Vector3 = _nearest_free_point(u.position, 0.6)
		u.position = free
	world_root.add_child(u)
	u.setup(u_type, team, self)
	units.append(u)
	if fog != null and team != 0 and fog.enabled and not fog.is_visible_at(u.position):
		u.set_fog_hidden(true)
	recalculate_population()
	return u


func _nearest_free_point(p: Vector3, radius: float) -> Vector3:
	if nav == null:
		return p
	for ring in range(1, 8):
		for i in range(12):
			var a: float = TAU * float(i) / 12.0
			var q: Vector3 = p + Vector3(cos(a), 0.0, sin(a)) * (float(ring) * 1.5)
			if nav.is_walkable_world(q) and query_obstacles_overlap(q, radius).is_empty():
				return q
	return p


func place_building_at(b_type: String, pos: Vector3, team: int, start_built: bool = false) -> RTSBuilding:
	if world_root == null:
		return null
	var b: RTSBuilding = RTSBuilding.new()
	b.position = Vector3(clampf(pos.x, -BUILD_BOUND, BUILD_BOUND), 0.0, clampf(pos.z, -BUILD_BOUND, BUILD_BOUND))
	world_root.add_child(b)
	b.setup(b_type, team, start_built, self)
	buildings.append(b)
	if b_type != "farm":
		_obs_add({"pos": b.position, "radius": b.footprint_radius, "kind": "building", "ref": b})
	if not start_built and match_started:
		var st: Dictionary = team_stats[team]
		st["buildings_built"] = int(st["buildings_built"]) + 1
	if fog != null and team != 0 and fog.enabled:
		b.set_fog_hidden(not b.discovered)
	recalculate_population()
	return b


func spawn_resource(kind: String, pos: Vector3, amount: int = -1, owner_team: int = -1) -> RTSResourceNode:
	if world_root == null:
		return null
	var r: RTSResourceNode = RTSResourceNode.new()
	r.position = Vector3(pos.x, 0.0, pos.z)
	world_root.add_child(r)
	r.setup(kind, amount, self, owner_team)
	resources.append(r)
	if not r.walkable:
		_obs_add({"pos": r.position, "radius": r.collision_radius, "kind": "resource", "ref": r})
	return r


func spawn_cache(kind: String, pos: Vector3) -> FrontierCache:
	if world_root == null:
		return null
	var c: FrontierCache = FrontierCache.new()
	c.position = Vector3(pos.x, 0.0, pos.z)
	world_root.add_child(c)
	c.setup(kind, self)
	caches.append(c)
	if fog != null and not fog.enabled:
		c.discovered = true
		c.set_fog_hidden(false)
	return c


func register_static_obstacle(pos: Vector3, radius: float, kind: String = "prop") -> void:
	var entry: Dictionary = {"pos": Vector3(pos.x, 0.0, pos.z), "radius": radius, "kind": kind, "ref": null}
	static_obstacles.append(entry)
	_obs_add(entry)


func spawn_projectile(from_pos: Vector3, target: Variant, damage: float, attacker: Variant, team: int) -> void:
	if world_root == null:
		return
	var p: RTSProjectile = RTSProjectile.new()
	world_root.add_child(p)
	p.launch(from_pos, target, damage, attacker, team, sfx)


func spawn_floating_text(pos: Vector3, text: String, color: Color) -> void:
	if world_root == null or DisplayServer.get_name() == "headless":
		return
	var lbl: Label3D = Label3D.new()
	lbl.text = text
	lbl.font_size = 38
	lbl.outline_size = 8
	lbl.modulate = color
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = pos
	world_root.add_child(lbl)

	var tw: Tween = lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y + 1.8, 1.1)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(lbl.queue_free)


func _spawn_order_ring(pos: Vector3, color: Color) -> void:
	if world_root == null or DisplayServer.get_name() == "headless":
		return
	var wrap: Node3D = Node3D.new()
	wrap.position = Vector3(pos.x, 0.08, pos.z)
	world_root.add_child(wrap)

	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.56
	torus.outer_radius = 0.78
	torus.rings = 22
	torus.ring_segments = 6
	ring.mesh = torus
	ring.scale = Vector3(0.45, 0.14, 0.45)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	ring.material_override = mat
	wrap.add_child(ring)

	# Seta vertical invertida que pousa no solo dando leitura tátil instantânea ao clique
	var chevron: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.02
	cone.height = 0.52
	cone.radial_segments = 6
	chevron.mesh = cone
	chevron.position = Vector3(0.0, 0.82, 0.0)
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	chevron.material_override = cmat
	wrap.add_child(chevron)

	var tw: Tween = wrap.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.55, 0.14, 1.55), 0.40).set_ease(Tween.EASE_OUT)
	tw.tween_property(chevron, "position:y", 0.24, 0.28).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.40)
	tw.tween_property(cmat, "albedo_color:a", 0.0, 0.40)
	tw.chain().tween_callback(wrap.queue_free)


# ==============================================================================
# GRADES ESPACIAIS (OBSTÁCULOS E UNIDADES)
# ==============================================================================

func _obs_add(entry: Dictionary) -> void:
	var p: Vector3 = entry["pos"]
	var r: float = float(entry["radius"])
	var k0: Vector2i = Vector2i(floori((p.x - r) / OBS_CELL), floori((p.z - r) / OBS_CELL))
	var k1: Vector2i = Vector2i(floori((p.x + r) / OBS_CELL), floori((p.z + r) / OBS_CELL))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var k: Vector2i = Vector2i(kx, kz)
			if not _obs_grid.has(k):
				_obs_grid[k] = []
			(_obs_grid[k] as Array).append(entry)
	entry["q"] = 0
	var ref: Variant = entry.get("ref", null)
	if ref != null:
		_obs_by_ref[(ref as Object).get_instance_id()] = entry
	if nav != null:
		nav.add_circle(p, r)


func _obs_remove_ref(ref: Object) -> void:
	var id: int = ref.get_instance_id()
	if not _obs_by_ref.has(id):
		return
	var entry: Dictionary = _obs_by_ref[id]
	_obs_by_ref.erase(id)
	var p: Vector3 = entry["pos"]
	var r: float = float(entry["radius"])
	var k0: Vector2i = Vector2i(floori((p.x - r) / OBS_CELL), floori((p.z - r) / OBS_CELL))
	var k1: Vector2i = Vector2i(floori((p.x + r) / OBS_CELL), floori((p.z + r) / OBS_CELL))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var k: Vector2i = Vector2i(kx, kz)
			if _obs_grid.has(k):
				(_obs_grid[k] as Array).erase(entry)
	if nav != null:
		nav.remove_circle(p, r)


## Obstáculos (prédios, recursos sólidos e cenário) cujas caixas tocam a área center ± margin.
func query_obstacles(center: Vector3, margin: float) -> Array:
	_query_stamp += 1
	var out: Array = []
	var k0: Vector2i = Vector2i(floori((center.x - margin) / OBS_CELL), floori((center.z - margin) / OBS_CELL))
	var k1: Vector2i = Vector2i(floori((center.x + margin) / OBS_CELL), floori((center.z + margin) / OBS_CELL))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var arr: Variant = _obs_grid.get(Vector2i(kx, kz))
			if arr == null:
				continue
			for e in arr:
				if int(e["q"]) == _query_stamp:
					continue
				e["q"] = _query_stamp
				var op: Vector3 = e["pos"]
				var lim: float = float(e["radius"]) + margin
				if absf(op.x - center.x) < lim and absf(op.z - center.z) < lim:
					out.append(e)
	return out


func query_obstacles_overlap(center: Vector3, radius: float) -> Array:
	var out: Array = []
	for e in query_obstacles(center, radius + 0.5):
		var op: Vector3 = e["pos"]
		if Vector2(op.x - center.x, op.z - center.z).length() < float(e["radius"]) + radius:
			out.append(e)
	return out


func _rebuild_unit_grid() -> void:
	for k in _unit_grid_keys:
		(_unit_grid[k] as Array).clear()
	_unit_grid_keys.clear()
	for u in units:
		if not is_instance_valid(u) or u._dead:
			continue
		var p: Vector3 = u.global_position
		var k: Vector2i = Vector2i(floori(p.x / UNIT_CELL), floori(p.z / UNIT_CELL))
		var arr: Variant = _unit_grid.get(k)
		if arr == null:
			arr = []
			_unit_grid[k] = arr
		if (arr as Array).is_empty():
			_unit_grid_keys.append(k)
		(arr as Array).append(u)


## Unidades nas células que tocam o quadrado center ± radius (filtragem fina fica com quem chama).
func query_units(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var k0: Vector2i = Vector2i(floori((center.x - radius) / UNIT_CELL), floori((center.z - radius) / UNIT_CELL))
	var k1: Vector2i = Vector2i(floori((center.x + radius) / UNIT_CELL), floori((center.z + radius) / UNIT_CELL))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var arr: Variant = _unit_grid.get(Vector2i(kx, kz))
			if arr != null and not (arr as Array).is_empty():
				out.append_array(arr)
	return out


func find_resource_near(pos: Vector3, radius: float, team: int) -> RTSResourceNode:
	var best: RTSResourceNode = null
	var best_d: float = radius
	for r in resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion() or r.amount_left <= 0 or not r.can_be_gathered_by(team):
			continue
		var d: float = Vector2(r.global_position.x - pos.x, r.global_position.z - pos.z).length() - r.collision_radius
		if d < best_d:
			best_d = d
			best = r
	return best


# ==============================================================================
# EVENTOS DE ENTIDADES, ALERTAS E VITÓRIA / DERROTA
# ==============================================================================

func on_unit_trained(u: RTSUnit, _from: RTSBuilding) -> void:
	if not match_started:
		return
	var st: Dictionary = team_stats[u.team]
	st["units_trained"] = int(st["units_trained"]) + 1
	if u.team == 0 and sfx != null:
		sfx.play_unit_ready()


func on_building_completed(b: RTSBuilding) -> void:
	if b.building_type == "farm":
		_convert_farm(b)
		return
	recalculate_population()
	if b.team == 0:
		post_alert("Construção concluída: %s" % b.get_display_name(), Color(0.45, 0.92, 0.55))
		if sfx != null:
			sfx.play_build_complete(b.global_position)
	selection_changed.emit()


func _convert_farm(b: RTSBuilding) -> void:
	var pos: Vector3 = b.global_position
	var team: int = b.team
	var food: int = int(RTSBuilding.STATS["farm"].get("farm_food", 450))
	var builders: Array[RTSUnit] = []
	for u in units:
		if is_instance_valid(u) and not u._dead and u.target_building == b:
			builders.append(u)
	var was_selected: bool = selected_building == b
	buildings.erase(b)
	if was_selected:
		selected_building = null
	b.remove_silently()
	var farm_res: RTSResourceNode = spawn_resource("farm", pos, food, team)
	for w in builders:
		w.target_building = null
		w.command_gather(farm_res)
	if was_selected and farm_res != null:
		selected_resource = farm_res
		farm_res.set_selected(true)
	if team == 0 and sfx != null:
		sfx.play_build_complete(pos)
	recalculate_population()
	selection_changed.emit()


func on_building_destroyed(b: RTSBuilding) -> void:
	buildings.erase(b)
	_obs_remove_ref(b)
	for unit in units:
		if is_instance_valid(unit):
			if unit.target_enemy == b:
				unit.target_enemy = null
			if unit.target_building == b:
				unit.target_building = null
	if selected_building == b:
		selected_building = null
		selection_changed.emit()
	var other: int = 1 - b.team
	(team_stats[b.team] as Dictionary)["buildings_lost"] = int(team_stats[b.team]["buildings_lost"]) + 1
	(team_stats[other] as Dictionary)["buildings_destroyed"] = int(team_stats[other]["buildings_destroyed"]) + 1
	if match_started and b.team == 0:
		post_alert("%s foi destruído(a)!" % b.get_display_name(), Color(1.0, 0.38, 0.30))
		add_ping(b.global_position, Color(1.0, 0.25, 0.2))
	elif match_started and b.team == 1 and b.is_main_structure:
		post_alert("%s inimigo destruído!" % b.get_display_name(), Color(1.0, 0.86, 0.35))
	if camera_rig != null and not b.fog_hidden:
		camera_rig.add_trauma(0.42 if b.building_type == "lair" else 0.22)
	if b.building_type == "lair":
		(team_stats[other] as Dictionary)["lairs_destroyed"] = int(team_stats[other].get("lairs_destroyed", 0)) + 1
		if match_started:
			var b_mult: float = float(player_mods.get("bounty_mult", 1.0))
			var gold_loot: int = int(round(220.0 * b_mult))
			add_resource(0, "gold", gold_loot)
			add_resource(0, "stone", 180)
			add_resource(0, "food", 150)
			spawn_floating_text(b.global_position + Vector3(0.0, 3.4, 0.0), "+%d Ouro +180 Pedra!" % gold_loot, Color(1.0, 0.88, 0.32))
		var director: Node = ai_controllers.get(b.team, null)
		if director != null and director.has_method("on_lair_destroyed"):
			director.on_lair_destroyed(b)
	recalculate_population()
	if match_started:
		_check_victory_defeat()
		if b.building_type == "lair" and not is_game_over and not ai_controllers.has(0):
			grant_royal_decree("Covil saqueado! Escolha um novo Decreto Real!")


func on_unit_destroyed(u: RTSUnit) -> void:
	units.erase(u)
	for unit in units:
		if is_instance_valid(unit) and unit.target_enemy == u:
			unit.target_enemy = null
	if _last_clicked_unit == u:
		_last_clicked_unit = null
	if u in selected_units:
		selected_units.erase(u)
		selection_changed.emit()
	if match_started:
		var other: int = 1 - u.team
		(team_stats[u.team] as Dictionary)["units_lost"] = int(team_stats[u.team]["units_lost"]) + 1
		(team_stats[other] as Dictionary)["enemies_slain"] = int(team_stats[other]["enemies_slain"]) + 1
		if u.team == 1 and u._last_attacker_team == 0:
			var base_b: float = float(BOUNTY_TABLE.get(u.unit_type, 10))
			var bounty: int = maxi(1, int(round(base_b * float(player_mods.get("bounty_mult", 1.0)))))
			add_resource(0, "gold", bounty)
			if not u.fog_hidden:
				spawn_floating_text(u.global_position + Vector3(0.0, 2.0, 0.0), "+%d Ouro" % bounty, Color(1.0, 0.88, 0.32))
			if is_instance_valid(u._last_attacker) and u._last_attacker is RTSUnit:
				var killer: RTSUnit = u._last_attacker as RTSUnit
				if not killer._dead and killer.team == 0:
					killer.register_kill()
			if not ai_controllers.has(0):
				_kills_toward_decree += 1
				if _kills_toward_decree >= 12:
					_kills_toward_decree = 0
					grant_royal_decree("Vitórias na fronteira desbloquearam um Decreto Real!")
	recalculate_population()


func on_resource_depleted(r: RTSResourceNode) -> void:
	resources.erase(r)
	_obs_remove_ref(r)
	for unit in units:
		if is_instance_valid(unit) and unit.target_resource == r:
			unit.target_resource = null
	if selected_resource == r:
		selected_resource = null
		selection_changed.emit()
	if r.kind == "farm" and r.owner_team == 0 and match_started:
		_throttled_alert("farm", 10.0, "Uma fazenda se esgotou. Construa outra para manter a comida.", Color(1.0, 0.75, 0.4), r.global_position)


func on_entity_damaged(victim: Variant, attacker: Variant) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var v_team: int = int(victim.team)
	var ai: Node = ai_controllers.get(v_team, null)
	if ai != null and ai.has_method("on_ai_entity_damaged"):
		ai.on_ai_entity_damaged(victim, attacker)
	if v_team == 0 and match_started and not ai_controllers.has(0):
		var pos: Vector3 = (victim as Node3D).global_position
		if victim is RTSBuilding:
			_throttled_alert("bld", 14.0, "Sua base está sob ataque! [H] para ver", Color(1.0, 0.35, 0.28), pos, true)
		elif victim is RTSUnit and (victim as RTSUnit).unit_type == "worker":
			_throttled_alert("wrk", 14.0, "Seus camponeses estão sob ataque! [H] para ver", Color(1.0, 0.45, 0.30), pos, true)
		else:
			_throttled_alert("army", 16.0, "Suas tropas entraram em combate! [H] para ver", Color(1.0, 0.6, 0.35), pos, false)


func _throttled_alert(key: String, cooldown: float, msg: String, color: Color, pos: Vector3, horn: bool = false) -> void:
	var now: float = match_time
	if now - float(_alert_cooldowns.get(key, -999.0)) < cooldown:
		add_ping(pos, color, false)
		return
	_alert_cooldowns[key] = now
	post_alert(msg, color)
	add_ping(pos, color)
	if horn and sfx != null:
		sfx.play_horn_alert()


func add_ping(pos: Vector3, color: Color, remember: bool = true) -> void:
	pings.append({"pos": Vector3(pos.x, 0.0, pos.z), "color": color, "t": 0.0})
	if pings.size() > 24:
		pings.pop_front()
	if remember:
		last_alert_pos = Vector3(pos.x, 0.0, pos.z)


func team_has_main_structure(t: int) -> bool:
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == t and b.is_main_structure:
			return true
	return false


func count_team_buildings(t: int) -> int:
	var n: int = 0
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == t:
			n += 1
	return n


func count_team_buildings_of_type(t: int, b_type: String) -> int:
	var n: int = 0
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == t and b.building_type == b_type:
			n += 1
	return n


## Modo ondas (docs/DESIGN.md): o jogador vence ao destruir todos os covis e perde
## ao ficar sem Salões Reais e Castelos.
func _check_victory_defeat() -> void:
	if is_game_over or not match_started:
		return
	var alive0: bool = team_has_main_structure(0)
	if not alive0:
		end_match(1)
		return
	if lairs_total > 0:
		if count_team_buildings_of_type(1, "lair") == 0:
			end_match(0)
	elif not team_has_main_structure(1) and count_team_buildings(1) == 0:
		end_match(0)


func end_match(winner: int) -> void:
	if is_game_over:
		return
	is_game_over = true
	winner_team = winner
	cancel_building_placement()
	var loser: int = 1 - winner
	for u in units:
		if is_instance_valid(u) and not u._dead and u.team == loser:
			u.command_stop()
	game_over.emit(winner == 0, stats)


# ==============================================================================
# MODO DE CONSTRUÇÃO (GHOST 3D)
# ==============================================================================

func start_building_placement(b_type: String) -> void:
	cancel_building_placement()
	var cfg_b: Dictionary = RTSBuilding.STATS.get(b_type, {})
	if cfg_b.is_empty():
		return
	if not can_afford_building(0, b_type):
		post_alert("Recursos insuficientes para %s! Falta: %s." % [String(cfg_b["name"]), missing_cost_text(0, cfg_b["cost"])], Color(1.0, 0.45, 0.35))
		if sfx != null:
			sfx.play_ui_error()
		return

	pending_building_type = b_type
	attack_move_mode = false
	_ghost_node = Node3D.new()
	var packed: PackedScene = load(String(cfg_b["model"])) as PackedScene
	if packed != null:
		var inst: Node3D = packed.instantiate() as Node3D
		if inst != null:
			_apply_material_recursive(inst, _ghost_mat)
			_ghost_node.add_child(inst)
	world_root.add_child(_ghost_node)
	_update_ghost_position()
	post_alert("Clique para posicionar %s (Shift mantém o modo; botão direito/ESC cancela)." % String(cfg_b["name"]), Color(0.95, 0.85, 0.4))


func cancel_building_placement() -> void:
	pending_building_type = ""
	if is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	_ghost_node = null


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in node.get_children():
		_apply_material_recursive(ch, mat)


func _update_ghost_position() -> void:
	if _ghost_node == null:
		return
	var ground_pos: Variant = _raycast_ground(get_viewport().get_mouse_position())
	if ground_pos == null:
		return
	var p: Vector3 = ground_pos as Vector3
	_ghost_node.global_position = Vector3(p.x, 0.0, p.z)
	var cfg: Dictionary = RTSBuilding.STATS.get(pending_building_type, RTSBuilding.STATS["house"])
	var rad: float = float(cfg["radius"])
	var ok: bool = is_valid_building_spot(_ghost_node.global_position, rad, 0)
	_ghost_mat.albedo_color = Color(0.25, 0.95, 0.45, 0.52) if ok else Color(0.95, 0.25, 0.22, 0.55)


func is_valid_building_spot(pos: Vector3, radius: float, team: int = -1) -> bool:
	if absf(pos.x) > BUILD_BOUND - radius * 0.5 or absf(pos.z) > BUILD_BOUND - radius * 0.5:
		return false
	# Não construir dentro do rio ou sobre as pontes
	if RTSUnit.river_distance_at(pos.x, pos.z) < 7.5 + radius * 1.414:
		return false
	for bp in RTSUnit.BRIDGES:
		if Vector2(pos.x - bp.x, pos.z - bp.z).length() < 11.0 + radius:
			return false
	if team == 0 and fog != null and fog.enabled and not ai_controllers.has(0) and not fog.is_explored_at(pos):
		return false
	for b in buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b._dead:
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2(b.global_position.x, b.global_position.z)) < (radius + b.footprint_radius + 1.1):
			return false
	for r in resources:
		if not is_instance_valid(r) or r.is_queued_for_deletion():
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2(r.global_position.x, r.global_position.z)) < (radius + r.collision_radius + 0.8):
			return false
	for obs in query_obstacles(pos, radius + 4.0):
		if obs.get("ref", null) != null:
			continue
		var op: Vector3 = obs["pos"]
		var orad: float = float(obs["radius"])
		if Vector2(pos.x, pos.z).distance_to(Vector2(op.x, op.z)) < (radius + orad + 0.6):
			return false
	for u in query_units(pos, radius + 1.0):
		if is_instance_valid(u) and not u._dead and u.team != team and team >= 0:
			if Vector2(pos.x - u.global_position.x, pos.z - u.global_position.z).length() < radius + u.body_radius:
				return false
	return true


func _confirm_building_placement() -> void:
	if pending_building_type == "" or _ghost_node == null:
		return
	var pos: Vector3 = _ghost_node.global_position
	var b_type: String = pending_building_type
	var cfg: Dictionary = RTSBuilding.STATS.get(b_type, RTSBuilding.STATS["house"])
	var rad: float = float(cfg["radius"])
	if not is_valid_building_spot(pos, rad, 0):
		var why: String = "Local inválido! Escolha terreno livre, explorado, fora do rio e longe de outras estruturas."
		post_alert(why, Color(1.0, 0.4, 0.3))
		if sfx != null:
			sfx.play_ui_error()
		return

	if not spend_cost(0, cfg["cost"]):
		post_alert("Recursos insuficientes! Falta: %s." % missing_cost_text(0, cfg["cost"]), Color(1.0, 0.4, 0.3))
		if sfx != null:
			sfx.play_ui_error()
		cancel_building_placement()
		return

	var keep_placing: bool = Input.is_key_pressed(KEY_SHIFT) and can_afford_cost(0, cfg["cost"])
	if not keep_placing:
		cancel_building_placement()
	var new_b: RTSBuilding = place_building_at(b_type, pos, 0, false)
	if new_b != null:
		post_alert("Construção iniciada: %s" % new_b.get_display_name(), Color(0.55, 0.85, 1.0))
		_assign_worker_to_build(new_b)
		if sfx != null:
			sfx.play_build_place(pos)


func _assign_worker_to_build(b: RTSBuilding) -> void:
	var assigned: int = 0
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0 and u.unit_type == "worker":
			u.command_build(b)
			assigned += 1
	if assigned > 0:
		return
	var best_worker: RTSUnit = null
	var best_score: float = 999999.0
	for u in units:
		if not is_instance_valid(u) or u._dead or u.team != 0 or u.unit_type != "worker":
			continue
		var d: float = u.global_position.distance_to(b.global_position)
		if u.state != RTSUnit.State.IDLE:
			d += 120.0
		if d < best_score:
			best_score = d
			best_worker = u
	if best_worker != null:
		best_worker.command_build(b)


# ==============================================================================
# INPUT DE SELEÇÃO, CAIXA 2D, ORDENS E GRUPOS
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if is_game_over or not match_started:
		return

	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo:
			_handle_hotkey(ek)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if pending_building_type != "":
					_confirm_building_placement()
					return
				if attack_move_mode and selected_units.size() > 0:
					_issue_attack_move_click(mb.position)
					attack_move_mode = false
					return
				_is_dragging_box = true
				_drag_start = mb.position
				_drag_current = mb.position
			else:
				if _is_dragging_box:
					_is_dragging_box = false
					var dist: float = _drag_start.distance_to(mb.position)
					if dist > 12.0:
						_select_units_in_rect(_make_rect(_drag_start, mb.position))
					else:
						_handle_single_left_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if pending_building_type != "":
				cancel_building_placement()
				return
			if attack_move_mode:
				attack_move_mode = false
			_handle_right_click(mb.position)

	elif event is InputEventMouseMotion and _is_dragging_box:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_drag_current = mm.position


func _handle_hotkey(ek: InputEventKey) -> void:
	if ek.keycode == KEY_ESCAPE:
		if pending_building_type != "":
			cancel_building_placement()
		elif attack_move_mode:
			attack_move_mode = false
		else:
			clear_selection()
		return

	if ek.keycode == KEY_SPACE or ek.keycode == KEY_HOME:
		focus_camera_on_base()
		return

	if ek.keycode == KEY_H:
		focus_last_alert()
		return

	if ek.keycode == KEY_TAB:
		select_next_idle_worker()
		return

	if ek.keycode == KEY_F and camera_rig != null:
		if camera_rig.is_following():
			camera_rig.stop_following()
			post_alert("Câmera liberada.", Color(0.75, 0.9, 1.0))
		elif selected_units.size() > 0 and is_instance_valid(selected_units[0]):
			camera_rig.start_following(selected_units[0])
			post_alert("Seguindo unidade (mova a câmera ou pressione [F] para soltar).", Color(0.6, 0.92, 1.0))
		return

	# Grupos de controle (Ctrl + 1..5 / 1..5)
	var group_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
	var g_idx: int = group_keys.find(ek.keycode)
	if g_idx != -1:
		var grp_id: int = g_idx + 1
		if ek.ctrl_pressed:
			_save_control_group(grp_id)
		else:
			_recall_control_group(grp_id)
		return


func focus_last_alert() -> void:
	if camera_rig == null or last_alert_pos.x == INF:
		post_alert("Nenhum alerta recente.", Color(0.75, 0.9, 1.0))
		return
	camera_rig.focus_on(last_alert_pos)


func _save_control_group(grp_id: int) -> void:
	var valid: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u._dead and u.team == 0:
			valid.append(u)
	_control_groups[grp_id] = valid
	if valid.size() > 0:
		post_alert("Grupo %d salvo (%d unidades)." % [grp_id, valid.size()], Color(0.7, 0.88, 1.0))


func _recall_control_group(grp_id: int) -> void:
	if not _control_groups.has(grp_id):
		return
	var raw: Array = _control_groups[grp_id]
	var alive: Array[RTSUnit] = []
	for u in raw:
		if is_instance_valid(u) and not u.is_queued_for_deletion() and u.hp > 0.0 and not u._dead:
			alive.append(u)
	_control_groups[grp_id] = alive
	if alive.is_empty():
		return
	clear_selection()
	for u in alive:
		u.set_selected(true)
		selected_units.append(u)
	selection_changed.emit()
	if sfx != null:
		sfx.play_select_unit(alive[0].unit_type)

	var now: float = Time.get_ticks_msec() * 0.001
	if _last_group_tap_id == grp_id and (now - _last_group_tap_time) < 0.45 and camera_rig != null:
		camera_rig.focus_on(alive[0].global_position)
	_last_group_tap_id = grp_id
	_last_group_tap_time = now


func is_drawing_selection_box() -> bool:
	return _is_dragging_box and _drag_start.distance_to(_drag_current) > 12.0


func get_selection_box_rect() -> Rect2:
	return _make_rect(_drag_start, _drag_current)


func _make_rect(a: Vector2, b: Vector2) -> Rect2:
	var tl: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var sz: Vector2 = Vector2(absf(b.x - a.x), absf(b.y - a.y))
	return Rect2(tl, sz)


func clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()
	if is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	if is_instance_valid(selected_resource):
		selected_resource.set_selected(false)
	selected_resource = null
	selection_changed.emit()


func _select_units_in_rect(rect: Rect2) -> void:
	if camera_rig == null or camera_rig.camera == null:
		return
	var cam: Camera3D = camera_rig.camera
	var add_mode: bool = Input.is_key_pressed(KEY_SHIFT)
	if not add_mode:
		clear_selection()
	else:
		if is_instance_valid(selected_building):
			selected_building.set_selected(false)
			selected_building = null
		if is_instance_valid(selected_resource):
			selected_resource.set_selected(false)
			selected_resource = null

	for u in units:
		if not is_instance_valid(u) or u._dead or u.team != 0 or u.hp <= 0.0:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		var screen_pt: Vector2 = cam.unproject_position(u.global_position + Vector3(0.0, 0.7, 0.0))
		if rect.has_point(screen_pt):
			if not (u in selected_units):
				u.set_selected(true)
				selected_units.append(u)

	if selected_units.size() > 0 and sfx != null:
		sfx.play_select_unit(selected_units[0].unit_type)
	selection_changed.emit()


func _handle_single_left_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	var add_mode: bool = Input.is_key_pressed(KEY_SHIFT)
	var col: Object = hit.get("collider", null) if not hit.is_empty() else null
	if not (col is RTSUnit) and not (col is RTSBuilding) and not (col is RTSResourceNode) and not (col is FrontierCache):
		var near_ally: RTSUnit = _pick_unit_near_screen_pos(screen_pos, 26.0, 0)
		if near_ally != null:
			col = near_ally
		else:
			var near_enemy: RTSUnit = _pick_unit_near_screen_pos(screen_pos, 22.0, 1)
			if near_enemy != null:
				col = near_enemy

	if col == null:
		if not add_mode:
			clear_selection()
		return

	if col is RTSUnit:
		var u: RTSUnit = col as RTSUnit
		var now: float = Time.get_ticks_msec() * 0.001
		if u.team == 0 and u == _last_clicked_unit and (now - _last_click_time) < 0.38:
			_select_all_visible_of_type(u.unit_type)
			_last_clicked_unit = null
			return
		_last_clicked_unit = u
		_last_click_time = now

		if not add_mode or u.team != 0:
			clear_selection()
		if not (u in selected_units):
			u.set_selected(true)
			selected_units.append(u)
		if sfx != null:
			sfx.play_select_unit(u.unit_type)
		selection_changed.emit()
		return

	if col is RTSBuilding:
		var b: RTSBuilding = col as RTSBuilding
		clear_selection()
		selected_building = b
		b.set_selected(true)
		if sfx != null:
			sfx.play_select_building()
		selection_changed.emit()
		return

	if col is RTSResourceNode:
		var r: RTSResourceNode = col as RTSResourceNode
		if fog != null and not fog.is_explored_at(r.global_position):
			if not add_mode:
				clear_selection()
			return
		clear_selection()
		selected_resource = r
		r.set_selected(true)
		if sfx != null:
			sfx.play_select_resource()
		selection_changed.emit()
		return

	if col is FrontierCache:
		var fc: FrontierCache = col as FrontierCache
		if not fc.fog_hidden and not fc.claimed:
			var cfg_fc: Dictionary = FrontierCache.CACHE_TYPES.get(fc.cache_kind, {})
			post_alert("%s — Aproxime qualquer tropa aliada (clique direito) para coletar!" % String(cfg_fc.get("name", "Suprimentos")), Color(1.0, 0.86, 0.36))
			_spawn_order_ring(fc.global_position, Color(1.0, 0.86, 0.34, 0.9))
			if sfx != null:
				sfx.play_select_resource()
		return

	if not add_mode:
		clear_selection()


func _select_all_visible_of_type(u_type: String) -> void:
	if camera_rig == null or camera_rig.camera == null:
		return
	var cam: Camera3D = camera_rig.camera
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	clear_selection()
	for u in units:
		if not is_instance_valid(u) or u._dead or u.team != 0 or u.unit_type != u_type or u.hp <= 0.0:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		var pt: Vector2 = cam.unproject_position(u.global_position)
		if vp_rect.has_point(pt):
			u.set_selected(true)
			selected_units.append(u)
	if selected_units.size() > 0 and sfx != null:
		sfx.play_select_unit(u_type)
	selection_changed.emit()


func _issue_attack_move_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider", null)
	if not ((col is RTSUnit and (col as RTSUnit).team != 0) or (col is RTSBuilding and (col as RTSBuilding).team != 0)):
		var near_e: RTSUnit = _pick_unit_near_screen_pos(screen_pos, 24.0, 1)
		if near_e != null:
			col = near_e

	var my_units: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u._dead and u.team == 0:
			my_units.append(u)
	if my_units.is_empty():
		return

	if (col is RTSUnit and (col as RTSUnit).team != 0) or (col is RTSBuilding and (col as RTSBuilding).team != 0):
		for u in my_units:
			u.command_attack(col as Node3D)
		_spawn_order_ring((col as Node3D).global_position, Color(1.0, 0.25, 0.22, 0.9))
	else:
		var pos: Vector3 = hit["position"]
		var slot_map: Dictionary = assign_formation_targets(my_units, pos)
		for u in my_units:
			u.command_attack_move(slot_map.get(u, pos))
		_spawn_order_ring(pos, Color(1.0, 0.35, 0.25, 0.9))
	if sfx != null:
		sfx.play_cmd_attack()


func _handle_right_click(screen_pos: Vector2) -> void:
	var hit: Dictionary = _raycast_world(screen_pos)
	if hit.is_empty():
		return

	var col: Object = hit.get("collider", null)
	var pos: Vector3 = hit["position"]

	# Ponto de reunião de prédio de produção selecionado
	if is_instance_valid(selected_building) and selected_building.team == 0 and selected_units.is_empty():
		if not selected_building.trainable.is_empty():
			var rally_pos: Vector3 = pos
			if col is RTSResourceNode:
				rally_pos = (col as RTSResourceNode).global_position
			elif col is FrontierCache:
				rally_pos = (col as FrontierCache).global_position
			selected_building.set_rally_point(rally_pos)
			_spawn_order_ring(rally_pos, Color(1.0, 0.85, 0.25, 0.9))
			if sfx != null:
				sfx.play_cmd_rally()
		return

	if selected_units.is_empty():
		return

	var my_units: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u._dead and u.team == 0:
			my_units.append(u)
	if my_units.is_empty():
		return

	if not (col is RTSUnit) and not (col is RTSBuilding) and not (col is RTSResourceNode) and not (col is FrontierCache):
		var near_e: RTSUnit = _pick_unit_near_screen_pos(screen_pos, 24.0, 1)
		if near_e != null:
			col = near_e

	# Clique direito em inimigo visível
	if (col is RTSUnit and (col as RTSUnit).team != 0) or (col is RTSBuilding and (col as RTSBuilding).team != 0):
		for u in my_units:
			u.command_attack(col as Node3D)
		_spawn_order_ring((col as Node3D).global_position, Color(1.0, 0.25, 0.25, 0.92))
		if sfx != null:
			sfx.play_cmd_attack()
		return

	# Clique direito em Caravana / Baú da Fronteira
	if col is FrontierCache:
		var fc: FrontierCache = col as FrontierCache
		var slot_map_fc: Dictionary = assign_formation_targets(my_units, fc.global_position)
		for u in my_units:
			u.command_move(slot_map_fc.get(u, fc.global_position))
		_spawn_order_ring(fc.global_position, Color(1.0, 0.86, 0.30, 0.95))
		if sfx != null:
			sfx.play_cmd_move()
		return

	# Clique direito em recurso
	if col is RTSResourceNode:
		var res: RTSResourceNode = col as RTSResourceNode
		var workers_sent: int = 0
		for u in my_units:
			if u.unit_type == "worker" and res.can_be_gathered_by(0):
				u.command_gather(res)
				workers_sent += 1
			else:
				u.command_move(res.global_position + Vector3(res.collision_radius + 1.5, 0.0, res.collision_radius + 1.5))
		var ring_col: Color = Color(1.0, 0.85, 0.2, 0.9) if workers_sent > 0 else Color(0.3, 0.85, 1.0, 0.9)
		_spawn_order_ring(res.global_position, ring_col)
		if sfx != null:
			if workers_sent > 0:
				sfx.play_cmd_gather()
			else:
				sfx.play_cmd_move()
		return

	# Clique direito em prédio aliado (construir, reparar ou entregar carga)
	if col is RTSBuilding and (col as RTSBuilding).team == 0:
		var ally_b: RTSBuilding = col as RTSBuilding
		var any_order: bool = false
		for u in my_units:
			if u.unit_type != "worker":
				continue
			if not ally_b.is_constructed or ally_b.hp < ally_b.max_hp:
				u.command_build(ally_b)
				any_order = true
			elif u.carrying_amount > 0 and ally_b.accepts_resource(u.carrying_type):
				u._target_depot = ally_b
				u.state = RTSUnit.State.RETURNING_RESOURCE
				any_order = true
		if any_order:
			_spawn_order_ring(ally_b.global_position, Color(0.4, 0.95, 0.55, 0.9))
			if sfx != null:
				sfx.play_cmd_gather()
			return

	# Movimento em formação inteligente orientada à marcha
	var slot_map: Dictionary = assign_formation_targets(my_units, pos)
	for u in my_units:
		u.command_move(slot_map.get(u, pos))
	_spawn_order_ring(pos, Color(0.32, 0.92, 0.48, 0.9))
	if sfx != null:
		sfx.play_cmd_move()


func issue_minimap_move(world_pos: Vector3) -> void:
	var my_units: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u._dead and u.team == 0:
			my_units.append(u)
	if my_units.is_empty():
		if is_instance_valid(selected_building) and selected_building.team == 0 and not selected_building.trainable.is_empty():
			selected_building.set_rally_point(world_pos)
			_spawn_order_ring(world_pos, Color(1.0, 0.85, 0.25, 0.9))
			if sfx != null:
				sfx.play_cmd_rally()
		return
	var was_atk: bool = attack_move_mode
	var slot_map: Dictionary = assign_formation_targets(my_units, world_pos)
	for u in my_units:
		var dest_u: Vector3 = slot_map.get(u, world_pos)
		if attack_move_mode:
			u.command_attack_move(dest_u)
		else:
			u.command_move(dest_u)
	attack_move_mode = false
	_spawn_order_ring(world_pos, Color(0.32, 0.92, 0.48, 0.9))
	if sfx != null:
		if was_atk:
			sfx.play_cmd_attack()
		else:
			sfx.play_cmd_move()


func get_formation_offsets(count: int) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if count <= 1:
		res.append(Vector3.ZERO)
		return res
	var cols: int = ceili(sqrt(float(count)))
	var spacing: float = 1.65
	for i in range(count):
		var row: int = i / cols
		var col_idx: int = i % cols
		var ox: float = (float(col_idx) - float(cols - 1) * 0.5) * spacing
		var oz: float = (float(row) - float(cols - 1) * 0.5) * spacing
		res.append(Vector3(ox, 0.0, oz))
	return res


## Distribui unidades por faixa tática (linha de frente, apoio, arqueiros) orientada à marcha,
## atribuindo cada unidade ao slot mais próximo para eliminar cruzamentos e empurra-empurra.
func assign_formation_targets(unit_list: Array[RTSUnit], dest: Vector3) -> Dictionary:
	var out: Dictionary = {}
	var valid: Array[RTSUnit] = []
	for u in unit_list:
		if is_instance_valid(u) and not u._dead:
			valid.append(u)
	if valid.is_empty():
		return out
	if valid.size() == 1:
		out[valid[0]] = Vector3(dest.x, 0.0, dest.z)
		return out

	var center: Vector3 = Vector3.ZERO
	for u in valid:
		center += u.global_position
	center /= float(valid.size())
	var fwd: Vector3 = Vector3(dest.x - center.x, 0.0, dest.z - center.z)
	if fwd.length_squared() < 0.04:
		fwd = Vector3(0.0, 0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var right: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)

	var front: Array[RTSUnit] = []
	var mid: Array[RTSUnit] = []
	var back: Array[RTSUnit] = []
	for u in valid:
		if u.is_ranged:
			back.append(u)
		elif u.unit_type == "worker" or u.unit_type == "scout":
			mid.append(u)
		else:
			front.append(u)

	var tiers: Array = []
	for grp in [front, mid, back]:
		if not (grp as Array).is_empty():
			tiers.append(grp)

	var spacing: float = 1.78
	var max_cols: int = clampi(ceili(sqrt(float(valid.size())) * 1.35), 2, 7)
	var total_rows: int = 0
	for grp in tiers:
		total_rows += ceili(float((grp as Array).size()) / float(max_cols))

	var row_cursor: int = 0
	for grp in tiers:
		var group_units: Array[RTSUnit] = grp
		var slots: Array[Vector3] = []
		var rem: int = group_units.size()
		var idx0: int = 0
		while idx0 < group_units.size():
			var in_row: int = mini(max_cols, rem)
			var row_off: float = (float(row_cursor) - float(total_rows - 1) * 0.5) * spacing
			for c in range(in_row):
				var col_off: float = (float(c) - float(in_row - 1) * 0.5) * spacing
				var slot_pos: Vector3 = Vector3(dest.x, 0.0, dest.z) - fwd * row_off + right * col_off
				slots.append(slot_pos)
			idx0 += in_row
			rem -= in_row
			row_cursor += 1

		# Atribui cada unidade ao slot disponível mais próximo
		var used_slots: Array[bool] = []
		used_slots.resize(slots.size())
		used_slots.fill(false)
		for u in group_units:
			var best_s: int = 0
			var best_d: float = 1.0e9
			for s_i in range(slots.size()):
				if used_slots[s_i]:
					continue
				var d: float = Vector2(u.global_position.x - slots[s_i].x, u.global_position.z - slots[s_i].z).length()
				if d < best_d:
					best_d = d
					best_s = s_i
			used_slots[best_s] = true
			out[u] = slots[best_s]
	return out


func get_idle_workers(team: int = 0) -> Array[RTSUnit]:
	var list: Array[RTSUnit] = []
	for u in units:
		if is_instance_valid(u) and not u._dead and u.team == team and u.unit_type == "worker" and u.state == RTSUnit.State.IDLE:
			list.append(u)
	return list


func select_next_idle_worker() -> void:
	var idle_list: Array[RTSUnit] = get_idle_workers(0)
	if idle_list.is_empty():
		post_alert("Todos os camponeses já estão trabalhando!", Color(0.75, 0.9, 1.0))
		return
	_idle_worker_cycle_idx = _idle_worker_cycle_idx % idle_list.size()
	var w: RTSUnit = idle_list[_idle_worker_cycle_idx]
	_idle_worker_cycle_idx += 1
	clear_selection()
	w.set_selected(true)
	selected_units.append(w)
	if camera_rig != null:
		camera_rig.focus_on(w.global_position)
	selection_changed.emit()
	if sfx != null:
		sfx.play_select_unit(w.unit_type)


func focus_camera_on_base() -> void:
	if camera_rig == null:
		return
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0 and b.building_type == "town_center":
			camera_rig.focus_on(b.global_position)
			return
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0 and b.is_main_structure:
			camera_rig.focus_on(b.global_position)
			return
	camera_rig.focus_on(team_base_pos.get(0, Vector3.ZERO))


func command_selected_stop() -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0:
			u.command_stop()
	attack_move_mode = false


func command_selected_auto_gather(r_type: String = "") -> void:
	for u in selected_units:
		if is_instance_valid(u) and u.team == 0 and u.unit_type == "worker":
			u.command_auto_gather_near(r_type)
	if sfx != null:
		sfx.play_cmd_gather()


func post_alert(msg: String, color: Color = Color(1.0, 0.88, 0.45)) -> void:
	alert_posted.emit(msg, color)


# ==============================================================================
# DECRETOS REAIS (PROGRESSÃO ROGUELITE DA COROA)
# ==============================================================================

func grant_royal_decree(reason: String = "Decreto Real disponível!") -> void:
	if ai_controllers.has(0):
		return
	pending_decrees += 1
	post_alert("★ %s Pressione [N] ou clique no selo no topo para escolher." % reason, Color(1.0, 0.88, 0.34))
	if sfx != null:
		sfx.play_unit_ready()
	decree_available.emit(pending_decrees)


func get_decree_info(decree_id: String) -> Dictionary:
	for d in ROYAL_DECREES:
		if String(d["id"]) == decree_id:
			return d
	return {}


func get_or_roll_decree_choices() -> Array[Dictionary]:
	if pending_decrees <= 0:
		return []
	if _current_decree_choices.size() == 3:
		return _current_decree_choices

	var pool: Array[Dictionary] = []
	for d in ROYAL_DECREES:
		var did: String = String(d["id"])
		var rep: bool = bool(d.get("repeatable", false))
		if rep or not (did in active_decrees):
			pool.append(d)

	# Embaralha via Fisher-Yates determinístico/_decree_rng
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _decree_rng.randi_range(0, i)
		var tmp: Dictionary = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	_current_decree_choices.clear()
	for k in range(mini(3, pool.size())):
		_current_decree_choices.append(pool[k])
	return _current_decree_choices


func apply_royal_decree(decree_id: String) -> bool:
	if pending_decrees <= 0:
		return false
	var info: Dictionary = get_decree_info(decree_id)
	if info.is_empty():
		return false

	pending_decrees -= 1
	_current_decree_choices.clear()
	if not bool(info.get("repeatable", false)) and not (decree_id in active_decrees):
		active_decrees.append(decree_id)

	match decree_id:
		"tempered_steel":
			player_mods["melee_dmg_mult"] = float(player_mods["melee_dmg_mult"]) + 0.20
		"yew_longbows":
			player_mods["ranged_dmg_mult"] = float(player_mods["ranged_dmg_mult"]) + 0.20
			player_mods["ranged_range_bonus"] = float(player_mods["ranged_range_bonus"]) + 2.5
		"plate_forging":
			player_mods["army_armor_bonus"] = int(player_mods["army_armor_bonus"]) + 2
			player_mods["army_hp_mult"] = float(player_mods["army_hp_mult"]) + 0.15
		"iron_tools":
			gather_mult[0] = float(gather_mult.get(0, 1.0)) + 0.25
		"granite_masonry":
			player_mods["building_hp_mult"] = float(player_mods["building_hp_mult"]) + 0.30
			player_mods["build_speed_mult"] = float(player_mods["build_speed_mult"]) + 0.35
		"swift_muster":
			player_mods["train_time_mult"] = maxf(0.45, float(player_mods["train_time_mult"]) * 0.75)
		"siege_engineers":
			player_mods["siege_dmg_mult"] = float(player_mods["siege_dmg_mult"]) + 0.35
			player_mods["siege_speed_mult"] = float(player_mods["siege_speed_mult"]) + 0.20
		"war_spoils":
			player_mods["bounty_mult"] = float(player_mods["bounty_mult"]) * 2.0
		"forced_march":
			player_mods["army_speed_mult"] = float(player_mods["army_speed_mult"]) + 0.15
		"castle_garrison":
			player_mods["extra_arrows"] = int(player_mods["extra_arrows"]) + 1
		"royal_reinforcements":
			var anchor: Vector3 = team_base_pos.get(0, Vector3.ZERO)
			for b in buildings:
				if is_instance_valid(b) and not b._dead and b.team == 0 and b.is_main_structure:
					anchor = b.global_position
					break
			var to_mid: Vector3 = (Vector3.ZERO - anchor)
			to_mid.y = 0.0
			if to_mid.length_squared() < 0.1:
				to_mid = Vector3(1.0, 0.0, -1.0)
			to_mid = to_mid.normalized()
			var rally_spot: Vector3 = anchor + to_mid * 7.2
			var squad_types: Array[String] = ["soldier", "soldier", "soldier", "archer", "archer"]
			for i in range(squad_types.size()):
				var ang: float = (float(i) - 2.0) * 0.42
				var off: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * 1.8
				var ru: RTSUnit = spawn_unit(squad_types[i], rally_spot + off, 0)
				if ru != null:
					ru.command_attack_move(rally_spot + to_mid * 3.0)
			_spawn_order_ring(rally_spot, Color(1.0, 0.86, 0.32, 0.95))
		"royal_convoy":
			add_resource(0, "wood", 250)
			add_resource(0, "food", 200)
			add_resource(0, "gold", 150)
			add_resource(0, "stone", 100)

	_reapply_all_kingdom_modifiers()
	post_alert("Decreto promulgado: %s — %s" % [String(info["title"]), String(info["desc"])], Color(1.0, 0.88, 0.36))
	if sfx != null:
		sfx.play_age_up()
	decree_applied.emit(decree_id, info)
	decree_available.emit(pending_decrees)
	resources_changed.emit()
	selection_changed.emit()
	return true


func _reapply_all_kingdom_modifiers() -> void:
	for u in units:
		if is_instance_valid(u) and not u._dead and u.team == 0:
			u.apply_kingdom_modifiers()
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0:
			b.apply_kingdom_modifiers()


# ==============================================================================
# TÁTICAS ATIVAS DO COMANDANTE (INVESTIDA, MANTER POSIÇÃO, SINO DE DEFESA)
# ==============================================================================

func trigger_war_cry() -> bool:
	if war_cry_cd > 0.0:
		post_alert("Investida em recarga (%ds)." % ceili(war_cry_cd), Color(1.0, 0.65, 0.35))
		if sfx != null:
			sfx.play_ui_error()
		return false

	var affected: Array[RTSUnit] = []
	for u in selected_units:
		if not is_instance_valid(u) or u._dead or u.team != 0 or u.unit_type == "worker":
			continue
		if not (u in affected):
			affected.append(u)
		for near_u in query_units(u.global_position, 10.5):
			if is_instance_valid(near_u) and not near_u._dead and near_u.team == 0 and near_u.unit_type != "worker":
				if not (near_u in affected):
					affected.append(near_u)

	if affected.is_empty():
		post_alert("Selecione tropas militares para comandar Investida!", Color(1.0, 0.65, 0.35))
		return false

	war_cry_cd = 26.0
	var center: Vector3 = Vector3.ZERO
	for u in affected:
		u.apply_war_cry(6.5)
		center += u.global_position
		if vfx != null:
			vfx.spawn_hit_sparks(u.global_position)
	center /= float(affected.size())
	_spawn_order_ring(center, Color(1.0, 0.85, 0.25, 0.96))
	spawn_floating_text(center + Vector3(0.0, 2.5, 0.0), "INVESTIDA! (+Velocidade/+Ataque)", Color(1.0, 0.88, 0.30))
	post_alert("Investida Real! %d tropas com +28%% velocidade e ataque rápido por 6.5s!" % affected.size(), Color(1.0, 0.86, 0.35))
	if sfx != null:
		sfx.play_horn_alert()
	if camera_rig != null:
		camera_rig.add_trauma(0.10)
	selection_changed.emit()
	return true


func toggle_selected_hold_position() -> bool:
	var mil: Array[RTSUnit] = []
	for u in selected_units:
		if is_instance_valid(u) and not u._dead and u.team == 0 and u.unit_type != "worker":
			mil.append(u)
	if mil.is_empty():
		return false
	var enable_hold: bool = false
	for u in mil:
		if not u.hold_position:
			enable_hold = true
			break
	for u in mil:
		u.set_hold_position(enable_hold)
	if enable_hold:
		post_alert("Postura: Manter Posição (tropas seguram a linha sem perseguir).", Color(0.72, 0.90, 1.0))
	else:
		post_alert("Postura: Avanço Livre (tropas perseguem inimigos próximos).", Color(0.72, 0.95, 0.72))
	selection_changed.emit()
	return enable_hold


func trigger_defense_bell() -> bool:
	if defense_bell_cd > 0.0:
		post_alert("Sino de Defesa em recarga (%ds)." % ceili(defense_bell_cd), Color(1.0, 0.65, 0.35))
		if sfx != null:
			sfx.play_ui_error()
		return false
	defense_bell_cd = 55.0
	defense_bell_active = 12.0
	for b in buildings:
		if is_instance_valid(b) and not b._dead and b.team == 0 and b.is_constructed and b.attack_damage > 0.0:
			_spawn_order_ring(b.global_position, Color(0.55, 0.90, 1.0, 0.95))
	post_alert("Sino de Defesa badalado! Salões Reais, Torres e Castelos disparam +50%% mais rápido por 12s!", Color(0.58, 0.92, 1.0))
	if sfx != null:
		sfx.play_horn_alert()
	selection_changed.emit()
	return true


# ==============================================================================
# SELEÇÃO ASSISTIDA, HOVER 3D E RAYCAST 3D
# ==============================================================================

func _is_pointer_over_hud() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	return vp.gui_get_hovered_control() != null


func _pick_unit_near_screen_pos(screen_pos: Vector2, max_px: float = 26.0, team_filter: int = -1) -> RTSUnit:
	if camera_rig == null or camera_rig.camera == null:
		return null
	var cam: Camera3D = camera_rig.camera
	var best: RTSUnit = null
	var best_d: float = max_px
	for u in units:
		if not is_instance_valid(u) or u._dead or u.hp <= 0.0 or u.fog_hidden:
			continue
		if team_filter >= 0 and u.team != team_filter:
			continue
		if cam.is_position_behind(u.global_position):
			continue
		var spt: Vector2 = cam.unproject_position(u.global_position + Vector3(0.0, 0.85, 0.0))
		var d: float = spt.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = u
	return best


func _ensure_hover_ring() -> void:
	if _hover_ring != null or world_root == null:
		return
	_hover_ring = MeshInstance3D.new()
	_hover_ring.name = "HoverIndicator"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 0.98
	torus.rings = 26
	torus.ring_segments = 5
	_hover_ring.mesh = torus
	_hover_ring.scale = Vector3(1.0, 0.12, 1.0)
	_hover_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover_ring_mat = StandardMaterial3D.new()
	_hover_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_ring_mat.albedo_color = Color(0.5, 0.9, 1.0, 0.7)
	_hover_ring.material_override = _hover_ring_mat
	_hover_ring.visible = false
	world_root.add_child(_hover_ring)


func _set_cursor_shape(shape: int) -> void:
	if _last_cursor_shape == shape:
		return
	_last_cursor_shape = shape
	Input.set_default_cursor_shape(shape as Input.CursorShape)


func _update_hover_feedback() -> void:
	_ensure_hover_ring()
	if _hover_ring == null:
		return
	if get_tree().paused or _is_pointer_over_hud() or is_drawing_selection_box() or pending_building_type != "":
		_hover_ring.visible = false
		_set_cursor_shape(Input.CURSOR_CROSS if attack_move_mode else Input.CURSOR_ARROW)
		return

	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var mp: Vector2 = vp.get_mouse_position()
	var hit: Dictionary = _raycast_world(mp)
	var col: Object = hit.get("collider", null) if not hit.is_empty() else null
	if not (col is RTSUnit) and not (col is RTSBuilding) and not (col is RTSResourceNode) and not (col is FrontierCache):
		var nu: RTSUnit = _pick_unit_near_screen_pos(mp, 24.0, -1)
		if nu != null:
			col = nu

	var target_pos: Vector3 = Vector3.ZERO
	var rad: float = 0.0
	var hcol: Color = Color(0.45, 0.92, 1.0, 0.68)
	var cursor: int = Input.CURSOR_CROSS if attack_move_mode else Input.CURSOR_ARROW

	if col is RTSUnit:
		var u: RTSUnit = col as RTSUnit
		target_pos = u.global_position
		rad = u.body_radius * 1.48
		if u.team != 0:
			hcol = Color(1.0, 0.34, 0.28, 0.85)
			cursor = Input.CURSOR_CROSS if not selected_units.is_empty() else Input.CURSOR_POINTING_HAND
		else:
			cursor = Input.CURSOR_POINTING_HAND
	elif col is RTSBuilding:
		var b: RTSBuilding = col as RTSBuilding
		target_pos = b.global_position
		rad = b.footprint_radius * 1.15
		if b.team != 0:
			hcol = Color(1.0, 0.34, 0.28, 0.85)
			cursor = Input.CURSOR_CROSS if not selected_units.is_empty() else Input.CURSOR_POINTING_HAND
		else:
			cursor = Input.CURSOR_POINTING_HAND
	elif col is FrontierCache and not (col as FrontierCache).fog_hidden:
		var fc: FrontierCache = col as FrontierCache
		target_pos = fc.global_position
		rad = 1.55
		hcol = Color(1.0, 0.86, 0.32, 0.85)
		cursor = Input.CURSOR_POINTING_HAND
	elif col is RTSResourceNode:
		var r: RTSResourceNode = col as RTSResourceNode
		if fog == null or fog.is_explored_at(r.global_position):
			target_pos = r.global_position
			rad = r.collision_radius * 1.12
			hcol = Color(1.0, 0.86, 0.34, 0.72)
			cursor = Input.CURSOR_POINTING_HAND

	_set_cursor_shape(cursor)
	if rad > 0.0:
		_hover_ring.visible = true
		_hover_ring.position = Vector3(target_pos.x, 0.07, target_pos.z)
		_hover_ring.scale = Vector3(rad, 0.12, rad)
		_hover_ring_mat.albedo_color = hcol
	else:
		_hover_ring.visible = false


# ==============================================================================
# RAYCAST 3D
# ==============================================================================

func _raycast_world(screen_pos: Vector2) -> Dictionary:
	if camera_rig == null or camera_rig.camera == null or world_root == null:
		return {}
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var space_state: PhysicsDirectSpaceState3D = world_root.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 320.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


func _raycast_ground(screen_pos: Vector2) -> Variant:
	if camera_rig == null or camera_rig.camera == null:
		return null
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var plane: Plane = Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(from, dir)
