extends SceneTree

## Verificação E2E headless do RTS 'Coroa de Ferro' (modo base-builder com ondas e covis).
## Uso: godot --headless --path . --script tools/verify_project.gd

var _main: Node = null
var _gm: GameManager = null


func _fail(msg: String) -> void:
	printerr("TEST_FAILED: ", msg)
	quit(1)


func _init() -> void:
	call_deferred("_run_tests")


## Avança a simulação de forma síncrona (determinística e rápida) para as unidades informadas.
func _step(units_list: Array, seconds: float, dt: float = 0.05) -> void:
	var steps: int = int(ceil(seconds / dt))
	for _i in range(steps):
		_gm._rebuild_unit_grid()
		for u in units_list:
			if is_instance_valid(u) and not u._dead:
				u._physics_process(dt)


func _load_main(seed_v: int) -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return null
	var m: Node = scene.instantiate()
	m.set("auto_start", true)
	m.set("map_seed", seed_v)
	root.add_child(m)
	return m


func _run_tests() -> void:
	_main = _load_main(4242)
	if _main == null:
		_fail("Não foi possível carregar res://scenes/main.tscn")
		return
	await process_frame
	await process_frame

	_gm = _main.get_node_or_null("GameManager") as GameManager
	var director: WaveDirector = _main.get_node_or_null("WaveDirector") as WaveDirector
	var cam: RTSCamera = _main.get_node_or_null("CameraRig") as RTSCamera
	var hud: RTSHUD = _main.get_node_or_null("HUD") as RTSHUD
	var fog: FogOfWar = _main.get_node_or_null("FogOfWar") as FogOfWar
	if _gm == null or director == null or cam == null or hud == null or fog == null:
		_fail("Subsistemas principais ausentes (GameManager, WaveDirector, CameraRig, HUD ou FogOfWar)")
		return
	if not _gm.match_started or paused:
		_fail("Partida não iniciou com auto_start")
		return
	if _gm.nav == null:
		_fail("Grade de navegação não foi criada")
		return

	# 1. Condições iniciais: jogador com poucas unidades; inimigo só com covis + guarnições
	var counts0: Dictionary = {}
	for u in _gm.units:
		if u.team == 0:
			counts0[u.unit_type] = int(counts0.get(u.unit_type, 0)) + 1
		elif u.unit_type == "worker":
			_fail("O inimigo não deveria ter camponeses no modo de ondas")
			return
	if int(counts0.get("worker", 0)) != 3 or int(counts0.get("scout", 0)) != 1 or counts0.size() != 2:
		_fail("Jogador deveria começar com 3 camponeses e 1 batedor: %s" % str(counts0))
		return
	var p_tc: RTSBuilding = null
	var lair_list: Array[RTSBuilding] = []
	for b in _gm.buildings:
		var vis: Node = b.get_node_or_null("VisualRoot")
		if vis == null or vis.get_child_count() == 0:
			_fail("Prédio sem malha visual 3D: " + b.building_type)
			return
		if b.team == 0:
			if b.building_type != "town_center" or not b.is_constructed:
				_fail("Jogador deveria começar só com o Salão Real")
				return
			p_tc = b
		else:
			if b.building_type != "lair":
				_fail("O inimigo só deveria ter covis (achou %s)" % b.building_type)
				return
			lair_list.append(b)
	var expected_lairs: int = int(WaveDirector.DIFFICULTY["normal"]["lairs"])
	if lair_list.size() != expected_lairs or _gm.lairs_total != expected_lairs:
		_fail("Deveriam existir %d covis no Normal (há %d)" % [expected_lairs, lair_list.size()])
		return
	for r in GameManager.RES_TYPES:
		if _gm.get_res(0, r) != int(GameManager.START_RESOURCES[r]):
			_fail("Recursos iniciais incorretos (%s)" % r)
			return
	if _gm.get_team_pop_cap(0) != 10 or _gm.get_team_pop_used(0) != 4:
		_fail("População inicial esperada 4/10, obtida %d/%d" % [_gm.get_team_pop_used(0), _gm.get_team_pop_cap(0)])
		return

	# 2. Covis do outro lado do rio, longe da base e entre si, com guarnição e mina rica
	var s_p: float = RTSUnit.river_signed_at(p_tc.global_position.x, p_tc.global_position.z)
	_gm._rebuild_unit_grid()
	for i in range(lair_list.size()):
		var l: RTSBuilding = lair_list[i]
		if RTSUnit.river_signed_at(l.global_position.x, l.global_position.z) * s_p >= 0.0:
			_fail("Covil do mesmo lado do rio que o jogador")
			return
		if l.global_position.distance_to(p_tc.global_position) < 70.0:
			_fail("Covil perto demais da base do jogador")
			return
		for j in range(i + 1, lair_list.size()):
			if l.global_position.distance_to(lair_list[j].global_position) < 35.0:
				_fail("Covis muito próximos entre si")
				return
		var guards: int = 0
		for u in _gm.units:
			if u.team == 1 and not u._dead and u.global_position.distance_to(l.global_position) < 14.0:
				guards += 1
		if guards < 2:
			_fail("Covil sem guarnição")
			return
		var rich: bool = false
		for r in _gm.resources:
			if r.kind == "gold_mine" and r.global_position.distance_to(l.global_position) < 32.0 and r.max_amount >= 2000:
				rich = true
		if not rich:
			_fail("Covil sem mina rica por perto (os melhores recursos ficam longe da base)")
			return

	# 3. Sorteio: covis variam entre partidas e sempre do lado oposto ao do jogador
	var mg: MapGenerator = MapGenerator.new()
	if not mg.load_layout() or mg.slots.size() != 6:
		_fail("Layout do mapa inválido (esperadas 6 posições de base)")
		return
	var first_spots: Dictionary = {}
	for seed_i in range(16):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 2000 + seed_i
		var pick: Dictionary = mg.choose_start_slots(rng)
		var ps: Dictionary = mg.get_slot(int(pick["player"]))
		var cands: Array[Vector3] = mg.lair_candidates(int(ps["side"]), rng)
		if cands.size() < 5:
			_fail("Poucos pontos candidatos a covil")
			return
		var ppos: Vector3 = ps["pos"]
		var pside: float = RTSUnit.river_signed_at(ppos.x, ppos.z)
		for c in cands:
			if RTSUnit.river_signed_at(c.x, c.z) * pside >= 0.0:
				_fail("Candidato a covil do mesmo lado do jogador")
				return
		first_spots[str(snapped(cands[0], Vector3(1, 1, 1)))] = true
	if first_spots.size() < 4:
		_fail("Sorteio dos covis pouco variado")
		return
	for i in range(RTSUnit.BRIDGES.size()):
		var jb: Array = mg.layout["bridges"][i]
		if Vector2(float(jb[0]), float(jb[1])).distance_to(Vector2(RTSUnit.BRIDGES[i].x, RTSUnit.BRIDGES[i].z)) > 0.1:
			_fail("Pontes do layout JSON divergem de RTSUnit.BRIDGES")
			return

	# 4. Recursos do mapa
	var kind_count: Dictionary = {}
	for r in _gm.resources:
		kind_count[r.kind] = int(kind_count.get(r.kind, 0)) + 1
		if not r.walkable and RTSUnit.is_in_river_water(r.global_position.x, r.global_position.z, 1.0):
			_fail("Recurso dentro do rio em " + str(r.global_position))
			return
	if int(kind_count.get("gold_mine", 0)) < 12 or int(kind_count.get("stone_quarry", 0)) < 10 or int(kind_count.get("berry_bush", 0)) < 40 or int(kind_count.get("tree", 0)) < 120:
		_fail("Quantidade de recursos insuficiente no mapa: %s" % str(kind_count))
		return

	# 5. Névoa: covis e guarnições escondidos no início; batedor revela e o covil fica marcado
	fog.update_now()
	for l in lair_list:
		if not l.fog_hidden or l.discovered:
			_fail("Covil deveria começar escondido na névoa")
			return
	for u in _gm.units:
		if u.team == 1 and not u.fog_hidden:
			_fail("Unidade inimiga visível no início")
			return
	var scout: RTSUnit = null
	for u in _gm.units:
		if u.team == 0 and u.unit_type == "scout":
			scout = u
	var scout_home: Vector3 = scout.global_position
	scout.global_position = lair_list[0].global_position + Vector3(12.0, 0.0, 12.0)
	fog.update_now()
	if lair_list[0].fog_hidden or not lair_list[0].discovered:
		_fail("Batedor perto do covil não o revelou")
		return
	director._update(_gm.match_time)
	if int(director.get_threat_info()["lairs_found"]) != 1:
		_fail("WaveDirector não contou o covil encontrado")
		return
	scout.global_position = scout_home
	fog.update_now()
	if lair_list[0].fog_hidden:
		_fail("Covil descoberto deveria continuar marcado após sair da visão")
		return

	# 6. Esqueleto, animações e cores de time (inclui Lanceiro, Batedor e Capitão do Corvo)
	var probe_pos: Vector3 = p_tc.global_position + (Vector3.ZERO - p_tc.global_position).normalized() * 9.0
	var probes: Array[RTSUnit] = []
	for u_type in ["worker", "scout", "soldier", "spearman", "archer", "knight", "captain"]:
		for t_id in [0, 1]:
			var pu: RTSUnit = _gm.spawn_unit(u_type, probe_pos, t_id)
			probes.append(pu)
			var skel: Skeleton3D = _find_node_of_type(pu, "Skeleton3D") as Skeleton3D
			if skel == null or skel.get_bone_count() < 15:
				_fail("Skeleton3D ausente ou incompleto em %s" % u_type)
				return
			var ap: AnimationPlayer = _find_node_of_type(pu, "AnimationPlayer") as AnimationPlayer
			if ap == null:
				_fail("AnimationPlayer ausente em %s" % u_type)
				return
			for aname in ["Idle", "Walk", "Attack", "Death"]:
				if not ap.has_animation(aname):
					_fail("Animação '%s' ausente em %s" % [aname, u_type])
					return
			var team_mat: StandardMaterial3D = _find_team_primary_override(pu, t_id)
			if team_mat == null:
				_fail("Override Mat_TeamPrimary ausente em %s time %d" % [u_type, t_id])
				return
			if t_id == 0 and team_mat.albedo_color.b <= team_mat.albedo_color.r:
				_fail("Cor do time 0 não é azul em %s" % u_type)
				return
			if t_id == 1 and team_mat.albedo_color.r <= team_mat.albedo_color.b:
				_fail("Cor do time 1 não é vermelha em %s" % u_type)
				return
			if u_type == "captain":
				var model: Node3D = pu.get_node("VisualRoot").get_child(0) as Node3D
				if model == null or model.scale.x < 1.15:
					_fail("Capitão do Corvo deveria ser maior que o Paladino")
					return
	var ram: RTSUnit = _gm.spawn_unit("ram", probe_pos, 0)
	probes.append(ram)
	if ram.get_node_or_null("VisualRoot") == null or _find_team_primary_override(ram, 0) == null:
		_fail("Aríete sem modelo 3D ou sem cor de time")
		return
	for pu in probes:
		_gm.units.erase(pu)
		pu.queue_free()
	_gm.recalculate_population()

	# 7. Prédios do jogador; fazenda vira campo de cultivo; covil não aparece no cartão de construções
	_gm.refund_cost(0, {"food": 5000, "wood": 5000, "gold": 5000, "stone": 5000})
	var to_center: Vector3 = (Vector3.ZERO - p_tc.global_position).normalized()
	var placed: Dictionary = {}
	for b_type in ["house", "mill", "lumber_camp", "mining_camp", "barracks", "archery_range", "siege_workshop", "market", "tower", "castle", "farm"]:
		var rad: float = float(RTSBuilding.STATS[b_type]["radius"])
		var spot: Vector3 = _find_spot(p_tc.global_position + to_center * 16.0, rad)
		if spot.x == INF:
			_fail("Sem espaço válido para testar " + b_type)
			return
		if not _gm.spend_cost(0, RTSBuilding.get_cost(b_type)):
			_fail("Falha ao pagar custo de " + b_type)
			return
		var nb: RTSBuilding = _gm.place_building_at(b_type, spot, 0, false)
		if nb == null or nb.is_constructed:
			_fail("Falha ao posicionar " + b_type)
			return
		nb.advance_construction(500.0)
		placed[b_type] = nb
	var farm_res: RTSResourceNode = null
	for r in _gm.resources:
		if r.kind == "farm" and r.owner_team == 0:
			farm_res = r
	if farm_res == null or farm_res.can_be_gathered_by(1):
		_fail("Fazenda concluída não virou campo exclusivo do jogador")
		return
	if not placed["mill"].accepts_resource("food") or not placed["mining_camp"].accepts_resource("stone") or not placed["lumber_camp"].accepts_resource("wood"):
		_fail("Pontos de entrega aceitam recursos errados")
		return
	if "lair" in RTSHUD.ECO_BUILDINGS or "lair" in RTSHUD.MIL_BUILDINGS:
		_fail("Covil não pode ser construído pelo jogador")
		return

	# 8. Produção
	var train_map: Dictionary = {
		"town_center": ["worker"], "barracks": ["soldier", "spearman", "scout"],
		"archery_range": ["archer"], "castle": ["knight"], "siege_workshop": ["ram"],
	}
	for b_type in train_map.keys():
		var pb: RTSBuilding = p_tc if b_type == "town_center" else placed[b_type]
		for u_type in train_map[b_type]:
			var before: Dictionary = {}
			for r in GameManager.RES_TYPES:
				before[r] = _gm.get_res(0, r)
			if not pb.queue_unit(u_type):
				_fail("%s não conseguiu treinar %s" % [b_type, u_type])
				return
			var cost: Dictionary = RTSUnit.get_cost(u_type)
			for r in GameManager.RES_TYPES:
				if _gm.get_res(0, r) != int(before[r]) - int(cost.get(r, 0)):
					_fail("Custo de %s cobrado incorretamente (%s)" % [u_type, r])
					return

	# 9. Coleta completa com ponto de entrega
	var worker: RTSUnit = null
	for u in _gm.units:
		if u.team == 0 and u.unit_type == "worker" and not u._dead:
			worker = u
			break
	var berry: RTSResourceNode = null
	var best_bd: float = 1e9
	for r in _gm.resources:
		if r.kind == "berry_bush" and r.global_position.distance_to(p_tc.global_position) < best_bd:
			best_bd = r.global_position.distance_to(p_tc.global_position)
			berry = r
	var mill_spot: Vector3 = _find_spot(berry.global_position, float(RTSBuilding.STATS["mill"]["radius"]), 4.0)
	_gm.place_building_at("mill", mill_spot, 0, true)
	worker.global_position = berry.global_position + Vector3(3.0, 0.0, 0.0)
	var food_before: int = _gm.get_res(0, "food")
	worker.command_gather(berry)
	_step([worker], 40.0)
	if _gm.get_res(0, "food") < food_before + 10:
		_fail("Ciclo de coleta não entregou comida (estado %s)" % worker.get_state_label())
		return

	# 10. Mercado
	var gold0: int = _gm.get_res(0, "gold")
	var price0: int = _gm.get_market_buy_cost("wood")
	if not _gm.market_buy(0, "wood") or _gm.get_res(0, "gold") != gold0 - price0:
		_fail("Compra no mercado incorreta")
		return

	# 11. Combate: bônus do lanceiro, aríete contra covil e resistência a flechas
	var spear: RTSUnit = _gm.spawn_unit("spearman", probe_pos, 0)
	var knight: RTSUnit = _gm.spawn_unit("knight", probe_pos + Vector3(2, 0, 0), 1)
	var soldier_e: RTSUnit = _gm.spawn_unit("soldier", probe_pos + Vector3(-2, 0, 0), 1)
	var ram0: RTSUnit = _gm.spawn_unit("ram", probe_pos + Vector3(0, 0, 3), 0)
	var archer0: RTSUnit = _gm.spawn_unit("archer", probe_pos + Vector3(0, 0, -3), 0)
	if spear.compute_damage_against(knight) <= spear.compute_damage_against(soldier_e) + 15.0:
		_fail("Lanceiro sem bônus contra Paladino")
		return
	if ram0.compute_damage_against(lair_list[1]) < 60.0 or archer0.compute_damage_against(lair_list[1]) > 5.0:
		_fail("Multiplicador de dano contra prédios incorreto")
		return
	var ram_hp: float = ram0.hp
	ram0.take_damage(40.0, archer0, true)
	if ram_hp - ram0.hp > 12.0:
		_fail("Aríete deveria resistir a flechas")
		return
	for cu in [spear, knight, soldier_e, ram0, archer0]:
		_gm.units.erase(cu)
		cu.queue_free()
	_gm.recalculate_population()

	# 12. Navegação pela ponte
	var west: Vector3 = Vector3(-34.0, 0.0, -8.0)
	var east: Vector3 = Vector3(-8.0, 0.0, -34.0)
	var path: PackedVector3Array = _gm.nav.find_path(west, east)
	if path.is_empty():
		_fail("A* não encontrou rota atravessando o rio")
		return
	var prev: Vector3 = west
	for pt in path:
		var steps: int = int(ceil(prev.distance_to(pt) / 0.5))
		for k in range(1, steps + 1):
			var q: Vector3 = prev.lerp(pt, float(k) / float(steps))
			if RTSUnit.is_in_river_water(q.x, q.z, -0.3):
				_fail("Rota A* passa pela água em " + str(q))
				return
		prev = pt
	var nav_u: RTSUnit = _gm.spawn_unit("soldier", west, 0)
	nav_u.command_move(east)
	var crossed: bool = false
	for _i in range(900):
		_step([nav_u], 0.05)
		if RTSUnit.is_in_river_water(nav_u.global_position.x, nav_u.global_position.z, -0.1):
			_fail("Unidade caiu na água em " + str(nav_u.global_position))
			return
		if nav_u.global_position.distance_to(east) < 3.0:
			crossed = true
			break
	if not crossed:
		_fail("Unidade não completou a travessia: " + str(nav_u.global_position))
		return

	# 13. Colisão sólida contra prédio e mina
	var gold_mine: RTSResourceNode = null
	for r in _gm.resources:
		if r.kind == "gold_mine":
			gold_mine = r
			break
	for ct in [
		{"pos": placed["barracks"].global_position, "radius": placed["barracks"].footprint_radius, "label": "Quartel"},
		{"pos": gold_mine.global_position, "radius": gold_mine.collision_radius, "label": "Mina de Ouro"},
	]:
		var opos: Vector3 = ct["pos"]
		var orad: float = float(ct["radius"])
		var min_allowed: float = orad + nav_u.body_radius - 0.08
		nav_u.global_position = Vector3(opos.x, 0.0, opos.z + orad + nav_u.body_radius + 1.8)
		nav_u.command_move(Vector3(opos.x, 0.0, opos.z - (orad + nav_u.body_radius + 2.6)))
		for _f in range(90):
			_step([nav_u], 0.05)
			if Vector2(nav_u.global_position.x, nav_u.global_position.z).distance_to(Vector2(opos.x, opos.z)) < min_allowed:
				_fail("Unidade atravessou %s" % String(ct["label"]))
				return

	# 14. Câmera, terreno multi-escala, folhagem instanciada, VFX e névoa
	cam.focus_on(Vector3(-20.0, 0.0, 20.0), true)
	if cam.global_position.distance_to(Vector3(-20.0, 0.0, 20.0)) > 0.1 or cam.get_view_polygon_world().size() != 4:
		_fail("Câmera não respondeu corretamente")
		return
	var terrain_mesh: MeshInstance3D = _main.get_node_or_null("WorldRoot/Ground/TerrainMesh") as MeshInstance3D
	if terrain_mesh == null or not (terrain_mesh.material_override is ShaderMaterial):
		_fail("TerrainMesh sem ShaderMaterial")
		return
	var t_mat: ShaderMaterial = terrain_mesh.material_override as ShaderMaterial
	for t_param in ["baked_albedo", "detail_normal", "splat_mask", "cobble_albedo", "cobble_normal", "micro_detail"]:
		if t_mat.get_shader_parameter(t_param) == null:
			_fail("Parâmetro de textura do terreno ausente: " + t_param)
			return
	var wf: WorldFoliage = _main.get_node_or_null("WorldRoot/SceneryLandmarks/WorldFoliage") as WorldFoliage
	if wf == null or wf.instanced_groups < 4 or wf.total_instances < 2000:
		_fail("WorldFoliage ausente ou insuficiente")
		return
	var vfx_m: VFXManager = _main.get_node_or_null("VFXManager") as VFXManager
	if vfx_m == null or _gm.vfx != vfx_m:
		_fail("VFXManager ausente ou não vinculado ao GameManager")
		return
	if _main.get_node_or_null("FogOverlay") == null:
		_fail("Sobreposição da névoa de guerra ausente")
		return

	# 15. Ritmo das ondas: trégua inicial, onda reunida no covil e marchando contra a base
	var info: Dictionary = director.get_threat_info()
	if float(info["peace_left"]) < 500.0 or int(info["waves"]) != 0:
		_fail("Normal deveria ter ~10 min de trégua sem ondas: %s" % str(info))
		return
	var src: RTSBuilding = lair_list[1]
	var st: Dictionary = director._state[src.get_instance_id()]
	st["next_wave"] = _gm.match_time + 1.0
	director._update(_gm.match_time)
	var gathered: Array = (st["gathering"] as Array).duplicate()
	if gathered.is_empty():
		_fail("Covil não reuniu tropas para a onda")
		return
	for g in gathered:
		if (g as RTSUnit).global_position.distance_to(src.global_position) > 14.0:
			_fail("Tropas da onda deveriam surgir junto ao covil")
			return
	director._update(_gm.match_time + WaveDirector.GATHER_TIME + 1.0)
	if int(director.get_threat_info()["waves"]) != 1:
		_fail("Onda não foi lançada após a reunião")
		return
	var marching: int = 0
	for g in gathered:
		var gu: RTSUnit = g
		if is_instance_valid(gu) and (gu.state == RTSUnit.State.ATTACK_MOVING or gu.state == RTSUnit.State.CHASING):
			marching += 1
	if marching == 0:
		_fail("Tropas da onda não marcharam contra a base do jogador")
		return
	var late: Array[String] = director._compose_wave(float(WaveDirector.DIFFICULTY["normal"]["first_wave"]) + 40.0 * 60.0)
	if not ("ram" in late) or late.size() < 20:
		_fail("Ondas tardias deveriam ser grandes e trazer aríetes: %s" % str(late))
		return

	# 15b. Trompa do covil: atacado, convoca defensores, e só convoca de novo após a espera
	var alarm_lair: RTSBuilding = lair_list[lair_list.size() - 1]
	var ast: Dictionary = director._state[alarm_lair.get_instance_id()]
	var guards_before: int = director._alive_count(ast["guards"])
	var raider: RTSUnit = _gm.spawn_unit("soldier", alarm_lair.global_position + Vector3(7.5, 0.0, 0.0), 0)
	alarm_lair.take_damage(30.0, raider)
	var guards_after: int = director._alive_count(ast["guards"])
	if guards_after < guards_before + 3:
		_fail("Covil atacado não convocou defensores (%d -> %d)" % [guards_before, guards_after])
		return
	alarm_lair.take_damage(30.0, raider)
	if director._alive_count(ast["guards"]) != guards_after:
		_fail("A trompa do covil deveria esperar antes de convocar de novo")
		return

	# 16. HUD: cartões de comando
	_gm.clear_selection()
	worker.set_selected(true)
	_gm.selected_units.append(worker)
	_gm.selection_changed.emit()
	if hud._cmd_actions.size() < 10:
		_fail("Cartão do camponês incompleto")
		return
	_gm.clear_selection()
	_gm.selected_building = placed["barracks"]
	_gm.selection_changed.emit()
	if hud._cmd_actions.size() != 4:
		_fail("Quartel deveria ter 3 unidades + cancelar")
		return
	_gm.clear_selection()
	_gm.selected_building = placed["market"]
	_gm.selection_changed.emit()
	if hud._cmd_actions.size() != 6:
		_fail("Mercado deveria ter 6 botões de troca")
		return
	_gm.clear_selection()

	# 16b. Áudio espacial e assets visuais do HUD
	var sfx: SFXManager = _main.get_node_or_null("SFXManager") as SFXManager
	if sfx == null:
		_fail("SFXManager ausente em Main")
		return
	var bank_info: Dictionary = sfx.get_loaded_bank_counts()
	if int(bank_info.get("banks", 0)) < 28 or int(bank_info.get("streams", 0)) != 51:
		_fail("Bancos de SFX incorretos: %s" % str(bank_info))
		return
	if not sfx.toggle_muted() or sfx.toggle_muted():
		_fail("toggle_muted() não alternou estado de mudo corretamente")
		return
	var listener: AudioListener3D = cam.get_node_or_null("AudioListener3D") as AudioListener3D
	if listener == null or not listener.is_current():
		_fail("CameraRig sem AudioListener3D ativo")
		return
	for p_need in ["unit_worker", "building_town_center", "building_lair", "resource_gold_mine"]:
		if not hud._portraits.has(p_need):
			_fail("Retrato 3D do HUD não carregado: " + p_need)
			return
	for ic_need in ["res_food", "res_wood", "res_gold", "res_stone", "emblem_crown"]:
		if not hud._icons.has(ic_need):
			_fail("Ícone do HUD não carregado: " + ic_need)
			return
	for ch_need in ["panel_ornate", "slot_normal"]:
		if not hud._chrome.has(ch_need):
			_fail("Chrome do HUD não carregado: " + ch_need)
			return

	# 16c. Pontos de interesse vivos, Decretos Reais, Veterania, Táticas Ativas, Formação e Onda Antecipada
	if _gm.caches.size() < 6:
		_fail("Deveriam existir pelo menos 6 pontos de interesse no mapa (há %d)" % _gm.caches.size())
		return
	var first_cache: FrontierCache = null
	for fc in _gm.caches:
		if not is_instance_valid(fc):
			_fail("Cache inválida na lista")
			return
		if RTSUnit.is_in_river_water(fc.global_position.x, fc.global_position.z, 0.2):
			_fail("Ponto de interesse dentro da água em " + str(fc.global_position))
			return
		if first_cache == null and fc.cache_kind == "supplies":
			first_cache = fc
	if first_cache == null:
		first_cache = _gm.caches[0]
	var food_pre_cache: int = _gm.get_res(0, "food")
	var wood_pre_cache: int = _gm.get_res(0, "wood")
	var gold_pre_cache: int = _gm.get_res(0, "gold")
	var caches_before: int = _gm.caches.size()
	first_cache.claim(scout)
	if _gm.caches.size() != caches_before - 1:
		_fail("Ponto de interesse coletado não foi removido de GameManager.caches")
		return
	if _gm.get_res(0, "food") <= food_pre_cache and _gm.get_res(0, "wood") <= wood_pre_cache and _gm.get_res(0, "gold") <= gold_pre_cache:
		_fail("Ponto de interesse coletado não concedeu recursos")
		return

	_gm.grant_royal_decree("Teste E2E")
	var d_choices: Array[Dictionary] = _gm.get_or_roll_decree_choices()
	if d_choices.size() != 3:
		_fail("Decreto Real deveria sortear exatamente 3 opções (veio %d)" % d_choices.size())
		return
	if not _gm.apply_royal_decree("iron_tools") or _gm.get_gather_mult(0) <= 1.2:
		_fail("Aplicar Decreto Real 'iron_tools' falhou")
		return

	var vet_u: RTSUnit = _gm.spawn_unit("soldier", probe_pos, 0)
	var base_hp_v: float = vet_u.max_hp
	var base_dmg_v: float = vet_u.attack_damage
	var base_spd_v: float = vet_u.move_speed
	vet_u.register_kill()
	vet_u.register_kill()
	if vet_u.vet_rank != 1 or vet_u.max_hp <= base_hp_v or vet_u.attack_damage <= base_dmg_v:
		_fail("Veterania após 2 abates falhou (rank=%d)" % vet_u.vet_rank)
		return

	_gm.clear_selection()
	vet_u.set_selected(true)
	_gm.selected_units.append(vet_u)
	if not _gm.trigger_war_cry() or _gm.war_cry_cd <= 0.0 or vet_u.move_speed <= base_spd_v:
		_fail("Grito de Guerra / Investida falhou")
		return
	if not _gm.toggle_selected_hold_position() or not vet_u.hold_position:
		_fail("Alternar postura Manter Posição falhou")
		return
	if not _gm.trigger_defense_bell() or _gm.defense_bell_active <= 0.0:
		_fail("Sino de Defesa falhou")
		return

	var form_units: Array[RTSUnit] = [vet_u]
	for _fi in range(3):
		form_units.append(_gm.spawn_unit("archer", probe_pos + Vector3(float(_fi) * 0.5, 0.0, 1.0), 0))
	var f_map: Dictionary = _gm.assign_formation_targets(form_units, probe_pos + Vector3(12.0, 0.0, -8.0))
	if f_map.size() != 4:
		_fail("assign_formation_targets deveria mapear todas as 4 unidades")
		return
	var f_pts: Array[Vector3] = []
	for fu in form_units:
		var fp: Vector3 = f_map[fu]
		for prev_fp in f_pts:
			if fp.distance_to(prev_fp) < 1.0:
				_fail("Slots de formação sobrepostos: " + str(f_pts))
				return
		f_pts.append(fp)
	for fu in form_units:
		_gm.units.erase(fu)
		fu.queue_free()
	_gm.clear_selection()
	_gm.recalculate_population()

	var gold_pre_wave: int = _gm.get_res(0, "gold")
	var early_res: Dictionary = director.call_next_wave_early()
	if not bool(early_res.get("ok", false)) or _gm.get_res(0, "gold") <= gold_pre_wave:
		_fail("Convocar onda antecipada deveria conceder Ouro bônus: %s" % str(early_res))
		return

	# 17. Vitória: destruir todos os covis encerra a partida a favor do jogador
	var won: Array = [false]
	_gm.game_over.connect(func(player_won: bool, _st: Dictionary) -> void:
		won[0] = player_won
	)
	# O primeiro covil é destruído e liberado da memória; o diretor precisa seguir com os outros
	lair_list[0].take_damage(1.0e7, null)
	await create_timer(1.8).timeout
	if is_instance_valid(lair_list[0]):
		_fail("Covil destruído não foi removido da cena")
		return
	director._update(_gm.match_time)
	var info_after: Dictionary = director.get_threat_info()
	if int(info_after.get("lairs_alive", -1)) != lair_list.size() - 1 or int(info_after.get("lairs_destroyed", -1)) != 1:
		_fail("WaveDirector não lidou com o covil destruído: %s" % str(info_after))
		return
	if _gm.is_game_over:
		_fail("Partida acabou antes de destruir todos os covis")
		return
	for i in range(1, lair_list.size()):
		lair_list[i].take_damage(1.0e7, null)
		if i < lair_list.size() - 1 and _gm.is_game_over:
			_fail("Partida acabou antes de destruir todos os covis")
			return
	if not _gm.is_game_over or _gm.winner_team != 0 or not bool(won[0]) or int(_gm.stats["lairs_destroyed"]) != lair_list.size():
		_fail("Destruir todos os covis deveria dar vitória ao jogador")
		return

	# 18. Derrota (nova partida): perder o Salão Real encerra a partida a favor do Barão
	_main.queue_free()
	await process_frame
	_main = _load_main(77)
	await process_frame
	await process_frame
	_gm = _main.get_node_or_null("GameManager") as GameManager
	var lost: Array = [false]
	_gm.game_over.connect(func(player_won: bool, _st: Dictionary) -> void:
		lost[0] = not player_won
	)
	for b in _gm.buildings.duplicate():
		if b.team == 0 and b.is_main_structure:
			b.take_damage(1.0e7, null)
	if not _gm.is_game_over or _gm.winner_team != 1 or not bool(lost[0]):
		_fail("Perder o último Salão Real deveria encerrar a partida com derrota")
		return

	print("ALL_RTS_TESTS_PASSED")
	quit(0)


func _find_spot(center: Vector3, rad: float, start_ring: float = 0.0) -> Vector3:
	var ring: float = start_ring
	while ring < 40.0:
		var steps: int = maxi(8, int(ring * 1.5))
		for i in range(steps):
			var ang: float = TAU * float(i) / float(steps)
			var c: Vector3 = center + Vector3(cos(ang), 0.0, sin(ang)) * ring
			if _gm.is_valid_building_spot(c, rad, 0):
				return c
		ring += 2.0
	return Vector3(INF, 0.0, INF)


func _find_node_of_type(root_node: Node, type_name: String) -> Node:
	if root_node.is_class(type_name):
		return root_node
	for child in root_node.get_children():
		var found: Node = _find_node_of_type(child, type_name)
		if found != null:
			return found
	return null


func _find_team_primary_override(root_node: Node, t_id: int) -> StandardMaterial3D:
	if root_node is MeshInstance3D:
		var mi: MeshInstance3D = root_node as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var ov: Material = mi.get_surface_override_material(s)
				if ov is StandardMaterial3D and ov.resource_name == ("%d_Mat_TeamPrimary" % t_id):
					return ov as StandardMaterial3D
	for child in root_node.get_children():
		var found: StandardMaterial3D = _find_team_primary_override(child, t_id)
		if found != null:
			return found
	return null
