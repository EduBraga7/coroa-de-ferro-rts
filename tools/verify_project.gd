extends SceneTree

## Script headless de verificação automatizada E2E do RTS 'Coroa de Ferro'.

func _fail(msg: String) -> void:
	printerr("TEST_FAILED: ", msg)
	quit(1)


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Não foi possível carregar res://scenes/main.tscn")
		return

	var main_node: Node = scene.instantiate()
	root.add_child(main_node)

	await process_frame
	await process_frame

	var gm: GameManager = main_node.get_node_or_null("GameManager") as GameManager
	var ai: AIController = main_node.get_node_or_null("AIController") as AIController
	var cam: RTSCamera = main_node.get_node_or_null("CameraRig") as RTSCamera
	var hud: RTSHUD = main_node.get_node_or_null("HUD") as RTSHUD

	if gm == null or ai == null or cam == null or hud == null:
		_fail("Subsistemas principais ausentes (GameManager, AIController, CameraRig ou HUD)")
		return

	# 1. Verificar entidades iniciais de ambos os times
	var p_buildings: Dictionary = {}
	var ai_buildings: Dictionary = {}
	for b in gm.buildings:
		if b.team == 0:
			p_buildings[b.building_type] = int(p_buildings.get(b.building_type, 0)) + 1
		else:
			ai_buildings[b.building_type] = int(ai_buildings.get(b.building_type, 0)) + 1

		var vis: Node = b.get_node_or_null("VisualRoot")
		if vis == null or vis.get_child_count() == 0:
			_fail("Prédio sem malha visual 3D: " + b.building_type)
			return

	for req_b in ["town_center", "house", "tower"]:
		if int(p_buildings.get(req_b, 0)) < 1 or int(ai_buildings.get(req_b, 0)) < 1:
			_fail("Prédio inicial ausente: " + req_b)
			return

	var p_units: Dictionary = {}
	var ai_units: Dictionary = {}
	for u in gm.units:
		if u.team == 0:
			p_units[u.unit_type] = int(p_units.get(u.unit_type, 0)) + 1
		else:
			ai_units[u.unit_type] = int(ai_units.get(u.unit_type, 0)) + 1

		var vis_u: Node = u.get_node_or_null("VisualRoot")
		if vis_u == null or vis_u.get_child_count() == 0:
			_fail("Unidade sem malha visual 3D: " + u.unit_type)
			return

	for req_u in ["worker", "soldier", "archer"]:
		if int(p_units.get(req_u, 0)) < 1 or int(ai_units.get(req_u, 0)) < 1:
			_fail("Unidade inicial ausente: " + req_u)
			return

	# 1b. Verificar esqueleto, animações reais e materiais de time em todas as 4 classes
	var test_k0: RTSUnit = gm.spawn_unit("knight", Vector3(-66.0, 0.0, 66.0), 0)
	var test_k1: RTSUnit = gm.spawn_unit("knight", Vector3(66.0, 0.0, -66.0), 1)
	if test_k0 == null or test_k1 == null:
		_fail("Falha ao instanciar Paladino Real para verificação de rig")
		return

	for u_type in ["worker", "soldier", "archer", "knight"]:
		for t_id in [0, 1]:
			var found_u: RTSUnit = null
			for u in gm.units:
				if is_instance_valid(u) and u.unit_type == u_type and u.team == t_id:
					found_u = u
					break
			if found_u == null:
				_fail("Unidade ausente para verificação de rig: %s time %d" % [u_type, t_id])
				return
			var skel: Skeleton3D = _find_node_of_type(found_u, "Skeleton3D") as Skeleton3D
			if skel == null or skel.get_bone_count() < 15:
				_fail("Skeleton3D ausente ou incompleto em %s" % u_type)
				return
			var ap: AnimationPlayer = _find_node_of_type(found_u, "AnimationPlayer") as AnimationPlayer
			if ap == null:
				_fail("AnimationPlayer ausente em %s" % u_type)
				return
			var req_anims: Array[String] = ["Idle", "Walk", "Attack", "Death"]
			if u_type == "worker":
				req_anims.append("Gather")
			for aname in req_anims:
				if not ap.has_animation(aname):
					_fail("Animação '%s' ausente em %s" % [aname, u_type])
					return
			var team_mat: StandardMaterial3D = _find_team_primary_override(found_u, t_id)
			if team_mat == null:
				_fail("Override Mat_TeamPrimary ausente em %s time %d" % [u_type, t_id])
				return
			if t_id == 0 and team_mat.albedo_color.b <= team_mat.albedo_color.r:
				_fail("Cor do time 0 não é azul em %s" % u_type)
				return
			if t_id == 1 and team_mat.albedo_color.r <= team_mat.albedo_color.b:
				_fail("Cor do time 1 não é vermelha em %s" % u_type)
				return

	gm.units.erase(test_k0)
	gm.units.erase(test_k1)
	test_k0.queue_free()
	test_k1.queue_free()
	gm.recalculate_population()

	# 2. Testar comando de coleta
	var test_worker: RTSUnit = null
	for u in gm.units:
		if u.team == 0 and u.unit_type == "worker":
			test_worker = u
			break
	var gold_mine: RTSResourceNode = null
	for r in gm.resources:
		if r.resource_type == "gold":
			gold_mine = r
			break
	if test_worker == null or gold_mine == null:
		_fail("Camponês ou Mina de Ouro não encontrados")
		return

	test_worker.command_gather(gold_mine)
	if test_worker.state != RTSUnit.State.GATHERING:
		_fail("Camponês não entrou no estado GATHERING")
		return

	var start_gold: int = gold_mine.amount_left
	var harvested: int = gold_mine.harvest(10)
	if harvested != 10 or gold_mine.amount_left != start_gold - 10:
		_fail("Falha na extração de recurso")
		return

	# 3. Testar construção e produção de Quartel + treino de Paladino
	var build_pos: Vector3 = Vector3(-48.0, 0.0, 62.0)
	if not gm.is_valid_building_spot(build_pos, 2.8):
		build_pos = Vector3(-42.0, 0.0, 62.0)
	var barracks: RTSBuilding = gm.place_building_at("barracks", build_pos, 0, false)
	if barracks == null or barracks.is_constructed:
		_fail("Falha ao posicionar Quartel em construção")
		return

	test_worker.command_build(barracks)
	if test_worker.state != RTSUnit.State.BUILDING:
		_fail("Camponês não entrou em estado BUILDING")
		return

	barracks.advance_construction(20.0)
	if not barracks.is_constructed:
		_fail("Quartel não completou construção após advance_construction")
		return

	if not barracks.queue_unit("knight"):
		_fail("Falha ao enfileirar Paladino no Quartel")
		return
	if barracks.production_queue.size() != 1:
		_fail("Fila de produção do Quartel incorreta")
		return

	# 4. Testar upgrade de Era Real
	var upgraded: bool = gm.upgrade_age(0)
	if not upgraded or gm.get_team_age(0) != 2:
		_fail("Falha ao evoluir para Era Real")
		return

	# 5. Testar combate entre unidades e destruição de alvo com múltiplos atacantes
	var p_soldier: RTSUnit = null
	var p_archer: RTSUnit = null
	var e_soldier: RTSUnit = null
	for u in gm.units:
		if u.team == 0 and u.unit_type == "soldier" and p_soldier == null:
			p_soldier = u
		elif u.team == 0 and u.unit_type == "archer" and p_archer == null:
			p_archer = u
		elif u.team == 1 and u.unit_type == "soldier" and e_soldier == null:
			e_soldier = u
	if p_soldier == null or p_archer == null or e_soldier == null:
		_fail("Unidades de combate não encontradas")
		return

	p_soldier.command_attack(e_soldier)
	p_archer.command_attack(e_soldier)
	if p_soldier.state != RTSUnit.State.CHASING or p_soldier.target_enemy != e_soldier:
		_fail("Espadachim não entrou em perseguição ao inimigo")
		return

	var prev_hp: float = e_soldier.hp
	e_soldier.take_damage(25.0, p_soldier)
	if e_soldier.hp >= prev_hp:
		_fail("Dano em combate não reduziu HP do inimigo")
		return

	# Força estado ATTACKING em ambos atacantes + dispara projétil e mata o alvo no meio do combate
	p_soldier.global_position = e_soldier.global_position + Vector3(1.2, 0.0, 0.0)
	p_soldier.state = RTSUnit.State.ATTACKING
	p_archer.state = RTSUnit.State.ATTACKING
	gm.spawn_projectile(p_archer.global_position + Vector3(0.0, 1.3, 0.0), e_soldier, 15.0, p_archer, 0)
	e_soldier.take_damage(999.0, p_soldier)

	if not e_soldier._dead or (e_soldier in gm.units):
		_fail("Unidade morta não entrou imediatamente em estado _dead ou permaneceu em gm.units")
		return
	if e_soldier._anim_player == null or e_soldier._current_anim != "Death":
		_fail("Unidade morta não iniciou animação 'Death'")
		return

	for _f in range(12):
		await physics_frame
		await process_frame

	if not is_instance_valid(p_soldier) or not is_instance_valid(p_archer):
		_fail("Atacantes foram invalidados incorretamente após morte do alvo")
		return

	# 6. Testar mecânicas da câmera RTS avançada
	cam.focus_on(Vector3(-20.0, 0.0, 20.0), true)
	if cam.global_position.distance_to(Vector3(-20.0, 0.0, 20.0)) > 0.1:
		_fail("Câmera não respondeu a focus_on instantâneo")
		return

	var poly: PackedVector2Array = cam.get_view_polygon_world()
	if poly.size() != 4:
		_fail("Trapézio de visão da câmera no minimapa inválido")
		return

	cam.start_following(p_soldier)
	if not cam.is_following():
		_fail("Modo seguir unidade falhou")
		return
	cam.stop_following()

	cam.save_bookmark(2)
	cam.focus_on(Vector3(10.0, 0.0, -10.0), true)
	if not cam.load_bookmark(2):
		_fail("Bookmark de câmera falhou")
		return

	cam.target_yaw = 1.2
	cam.reset_orientation()
	if absf(cam.target_yaw) > 0.001 or absf(cam.target_pitch_offset_deg) > 0.001:
		_fail("Reset de orientação para o Norte falhou")
		return

	# 7. Verificar texturas do terreno e marcos 3D
	var terrain_mesh: MeshInstance3D = main_node.get_node_or_null("WorldRoot/Ground/TerrainMesh") as MeshInstance3D
	if terrain_mesh == null or not (terrain_mesh.material_override is ShaderMaterial):
		_fail("TerrainMesh sem ShaderMaterial")
		return
	var t_mat: ShaderMaterial = terrain_mesh.material_override as ShaderMaterial
	if t_mat.get_shader_parameter("baked_albedo") == null or t_mat.get_shader_parameter("detail_normal") == null:
		_fail("Texturas PBR do terreno não foram vinculadas ao ShaderMaterial")
		return
	var landmarks: Node3D = main_node.get_node_or_null("WorldRoot/SceneryLandmarks") as Node3D
	if landmarks == null or landmarks.get_child_count() < 20:
		_fail("Marcos 3D do cenário não foram instanciados")
		return

	# 8. Testar bloqueio do rio, roteamento pelas pontes e colisão sólida com objetos
	if gm.static_obstacles.size() < 20:
		_fail("Obstáculos estáticos do cenário não foram registrados em GameManager")
		return

	var nav_u: RTSUnit = gm.spawn_unit("soldier", Vector3(-15.0, 0.0, -8.2), 0)
	if nav_u == null:
		_fail("Falha ao criar unidade para teste de navegação e colisão")
		return

	# 8a. Clique direto na água do rio deve ser sanitizado para fora da água
	nav_u.command_move(Vector3(-12.0, 0.0, -12.0))
	if RTSUnit.is_in_river_water(nav_u.move_target.x, nav_u.move_target.z, -0.05):
		_fail("Destino clicado na água não foi sanitizado para fora do rio")
		return

	# 8b. Ordem atravessando o rio longe da ponte deve rotear para a ponte sem pisar na água
	nav_u.global_position = Vector3(-15.0, 0.0, -8.2)
	var start_dist_bridge: float = nav_u.global_position.distance_to(Vector3(0.0, 0.0, 0.0))
	nav_u.command_move(Vector3(-8.2, 0.0, -15.0))
	for _f in range(45):
		await physics_frame
		if RTSUnit.is_in_river_water(nav_u.global_position.x, nav_u.global_position.z, -0.1):
			_fail("Unidade entrou na água do rio durante roteamento pela ponte em " + str(nav_u.global_position))
			return
	if nav_u.global_position.distance_to(Vector3(0.0, 0.0, 0.0)) >= start_dist_bridge - 0.5:
		_fail("Unidade não avançou em direção à ponte central ao tentar cruzar o rio")
		return

	# 8c. Travessia real pela ponte central deve levar ao outro lado mantendo-se fora da água
	nav_u.global_position = Vector3(-7.0, 0.0, 5.0)
	nav_u.command_move(Vector3(7.0, 0.0, -5.0))
	for _f in range(180):
		await physics_frame
		if RTSUnit.is_in_river_water(nav_u.global_position.x, nav_u.global_position.z, -0.1):
			_fail("Unidade caiu na água ao atravessar a ponte em " + str(nav_u.global_position))
			return
		if RTSUnit.river_signed_at(nav_u.global_position.x, nav_u.global_position.z) > 6.5:
			break
	if RTSUnit.river_signed_at(nav_u.global_position.x, nav_u.global_position.z) <= 2.0:
		_fail("Unidade não completou travessia da ponte central: " + str(nav_u.global_position))
		return

	# 8d. Colisão sólida contra prédio, recurso e obstáculo de cenário (ruína/penhasco)
	var ruin_obs: Dictionary = {}
	for obs in gm.static_obstacles:
		if String(obs.get("kind", "")) == "ruin":
			ruin_obs = obs
			break
	if ruin_obs.is_empty():
		_fail("Nenhuma ruína registrada em static_obstacles")
		return

	var col_targets: Array[Dictionary] = [
		{"pos": barracks.global_position, "radius": barracks.footprint_radius, "label": "Prédio (Quartel)"},
		{"pos": gold_mine.global_position, "radius": gold_mine.collision_radius, "label": "Recurso (Mina de Ouro)"},
		{"pos": ruin_obs["pos"], "radius": float(ruin_obs["radius"]), "label": "Cenário (Ruína)"},
	]
	for ct in col_targets:
		var opos: Vector3 = ct["pos"]
		var orad: float = float(ct["radius"])
		var cname: String = String(ct["label"])
		var min_allowed: float = orad + nav_u.body_radius - 0.08
		nav_u.global_position = Vector3(opos.x, 0.0, opos.z + orad + nav_u.body_radius + 1.8)
		nav_u.command_move(Vector3(opos.x, 0.0, opos.z - (orad + nav_u.body_radius + 2.6)))
		for _f in range(45):
			await physics_frame
			var d_obs: float = Vector2(nav_u.global_position.x, nav_u.global_position.z).distance_to(Vector2(opos.x, opos.z))
			if d_obs < min_allowed:
				_fail("Unidade atravessou colisão de %s (dist=%.2f < min=%.2f)" % [cname, d_obs, min_allowed])
				return

	print("ALL_RTS_TESTS_PASSED")
	quit(0)


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
