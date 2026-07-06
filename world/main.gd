extends Node2D
## 월드 코디네이터 (계획서 §7, §8, §9). 전역 자정 로직·집회 배분·번식·건축·렌더링 조립.
## 개별 주민 AI는 villager.gd, 수요는 RequestBroker/PressureBoard가 담당한다.

const VillagerScene := preload("res://sim/villager.gd")
const GroundRenderer := preload("res://world/ground_renderer.gd")
const EntityView := preload("res://world/entity_view.gd")
const CameraScript := preload("res://world/camera.gd")
const Hud := preload("res://ui/hud.gd")

var _ground
var _entities: Node2D            # Y-sort 컨테이너 (건물·자원·주민)
var _modulate: CanvasModulate
var _cam
var _hud

var _occupied: Dictionary = {}   # Vector2i -> true (건물 점유 셀)
var _surplus_streak: int = 0
var _recent_house: Array = []    # 직전 프리팹 id (중복 방지)
var _recent_farm: Array = []
var _house_shortage_posted := false

func _ready() -> void:
	_setup_font()
	_build_scene_nodes()
	start_game(RNGService.seed_value)
	# 시그널 연결은 노드 생성(_build_scene_nodes) 이후에 해야 _hud 등이 유효하다.
	GameClock.phase_changed.connect(_on_phase)
	GameClock.hour_changed.connect(_on_hour)
	GameClock.day_changed.connect(_on_day_end)
	RequestBroker.request_posted.connect(_on_request_posted)
	_hud.regenerate_requested.connect(func(s): start_game(s))

## 한글·이모지 렌더링 보장: OS 시스템 폰트를 엔진 전역 폴백으로 지정.
## (Godot 기본 내장 폰트는 라틴 전용이라 한글이 □로 깨진다)
func _setup_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR",
		"Noto Sans KR", "NanumGothic", "Segoe UI", "sans-serif"])
	f.allow_system_fallback = true
	ThemeDB.fallback_font = f
	ThemeDB.fallback_font_size = 14

func _build_scene_nodes() -> void:
	_modulate = CanvasModulate.new()
	add_child(_modulate)

	_ground = GroundRenderer.new()
	add_child(_ground)

	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	add_child(_entities)

	_cam = CameraScript.new()
	add_child(_cam)

	_hud = Hud.new()
	add_child(_hud)

# ── 게임 시작/재생성 ──
func start_game(s: int) -> void:
	# 정리
	for c in _entities.get_children():
		c.queue_free()
	_occupied.clear()
	_recent_house.clear()
	_recent_farm.clear()
	_surplus_streak = 0
	_house_shortage_posted = false
	RequestBroker.clear()
	PressureBoard.reset()

	MapGen.generate(s)
	Village.reset()
	Village.hall_cell = MapGen.start_cell

	_ground.roads.clear()
	_ground.queue_redraw()
	_spawn_resource_views()
	_place_initial_settlement()
	_spawn_initial_villagers()

	_cam.position = Iso.cell_to_world(Village.hall_cell)
	_cam.zoom = Vector2(1.6, 1.6)
	GameClock.day = 1
	GameClock.minute = Defs.T_WAKE
	GameClock.set_speed(GameClock.Speed.X1)
	PressureBoard.update_daily()

func _spawn_resource_views() -> void:
	for cell in MapGen.resources:
		var v = EntityView.new()
		_entities.add_child(v)
		v.setup_resource(MapGen.resources[cell]["type"], cell)

# ── 초기 정착지 (§3.2) ──
func _place_initial_settlement() -> void:
	var hc := Village.hall_cell
	var hall := Building.new()
	hall.category = &"HALL"
	hall.cell = hc - Vector2i(1, 1)
	hall.size = Vector2i(3, 3)
	hall.built = true
	hall.capacity = 0
	_add_building(hall)
	_mark_occupied(hall)

	# 도로 십자
	for d in range(-6, 7):
		_ground.add_road(hc + Vector2i(d, 0))
		_ground.add_road(hc + Vector2i(0, d))

	# 초기 주택 4채
	var offsets := [Vector2i(4, 2), Vector2i(-5, 2), Vector2i(3, -5), Vector2i(-5, -5)]
	for off in offsets:
		var p := Prefabs.houses()[0]
		var b := Building.from_prefab(p, hc + off)
		b.built = true
		b.road_connected = true
		_add_building(b)
		_mark_occupied(b)

	# 초기 밭 2구획 (농부 2명 담당) — 없으면 식량 적자로 마을 붕괴 (§10)
	var farm_offsets := [Vector2i(8, -2), Vector2i(-9, -1)]
	for off in farm_offsets:
		var fp := Prefabs.farms()[0]
		var fb := Building.from_prefab(fp, hc + off)
		fb.built = true
		_add_building(fb)
		_mark_occupied(fb)

# ── 초기 주민 7인 (§10) ──
func _spawn_initial_villagers() -> void:
	var roster := [
		Defs.JOB_MANAGER, Defs.JOB_ARTISAN, Defs.JOB_FARMER, Defs.JOB_FARMER,
		Defs.JOB_HUNTER, Defs.JOB_CARPENTER, Defs.JOB_MINER,
	]
	var houses := _houses()
	for i in roster.size():
		var v = _make_villager(Village.hall_cell + Vector2i(RNGService.randi_range(-2, 2),
			RNGService.randi_range(-2, 2)))
		v.age_days = RNGService.randf_range(8.0, 40.0)
		v.set_job(roster[i])
		# 초기 도구 지급
		var tool: StringName = Defs.JOB_PRIMARY_TOOL.get(roster[i], &"")
		if tool != &"":
			v.tool_item = tool
			v.tool_dur = Defs.TOOLS[tool]["durability"]
		# 농부는 초기 밭 배정 (식량 흑자 확보)
		if roster[i] == Defs.JOB_FARMER:
			var farm = Village.unassigned_farm()
			if farm:
				farm.assigned_to = v.vid
		# 주택 배정
		var home = houses[i % houses.size()]
		v.home = home
		if not home.occupants.has(v.vid):
			home.occupants.append(v.vid)

func _make_villager(cell: Vector2i):
	var v = VillagerScene.new()
	var id := Village.next_id()
	v.setup(id, NameGen.given(), NameGen.family(), RNGService.randi_range(0, 1), cell)
	_entities.add_child(v)
	Village.villagers.append(v)
	return v

func _houses() -> Array:
	var h := []
	for b in Village.buildings:
		if b.category == &"HOUSE":
			h.append(b)
	return h

# ── 건물 등록/렌더 ──
func _add_building(b) -> void:
	Village.buildings.append(b)
	var view = EntityView.new()
	_entities.add_child(view)
	view.setup_building(b)
	b.view = view

func _mark_occupied(b) -> void:
	for dy in b.size.y:
		for dx in b.size.x:
			_occupied[b.cell + Vector2i(dx, dy)] = true

func _cell_free(cell: Vector2i, size: Vector2i) -> bool:
	for dy in size.y:
		for dx in size.x:
			var c := cell + Vector2i(dx, dy)
			if not MapGen.in_bounds(c.x, c.y):
				return false
			if _occupied.has(c):
				return false
			var b := MapGen.get_biome(c.x, c.y)
			if b == MapGen.Biome.WATER or b == MapGen.Biome.ROCK:
				return false
			if MapGen.resources.has(c):
				return false
	return true

# ── 페이즈: 집회 배분 ──
func _on_phase(phase: StringName) -> void:
	if phase == &"MEETING_AM" or phase == &"MEETING_NOON":
		_distribute_food()

func _distribute_food() -> void:
	var pop := Village.population()
	if pop == 0:
		return
	var per: float = minf(1.5, Village.food_fu / pop)
	var managers := Village.count_job(Defs.JOB_MANAGER)
	if managers == 0 and Village.food_fu > 0.0:
		Village.daily["manager_overflow"] += 1
	var given := 0.0
	for v in Village.villagers:
		var take: float = minf(per, maxf(0.0, v.fu_need() - v.fed_today))
		v.receive_ration(take)
		given += take
	Village.food_fu = maxf(0.0, Village.food_fu - given)
	Village.stock_changed.emit()

# ── 매시: 주야 연출 + 자재 하울링 + 자재요청 정산 ──
func _on_hour(_day: int, _hour: int) -> void:
	_update_daynight()
	_haul_materials()
	_settle_material_requests()

func _update_daynight() -> void:
	var f := GameClock.day_fraction()
	# 06→새벽, 12→낮, 18→노을, 22→밤 (밤도 가시성 위해 너무 어둡지 않게)
	var night := Color("#6b76a0")
	var col: Color
	if f < 0.25:
		col = night
	elif f < 0.30:
		col = night.lerp(Color("#b8cbe4"), (f - 0.25) / 0.05)
	elif f < 0.5:
		col = Color("#b8cbe4").lerp(Color("#ffffff"), (f - 0.30) / 0.20)
	elif f < 0.75:
		col = Color("#ffffff").lerp(Color("#ffc79a"), (f - 0.5) / 0.25)
	elif f < 0.92:
		col = Color("#ffc79a").lerp(night, (f - 0.75) / 0.17)
	else:
		col = night
	_modulate.color = col

func _haul_materials() -> void:
	for b in Village.buildings:
		if b.built:
			continue
		for mat in b.missing_materials():
			var lack: int = b.missing_materials()[mat]
			var avail: int = Village.res.get(mat, 0)
			var move: int = mini(lack, avail)
			if move > 0:
				Village.take_res(mat, move)
				b.deliver(mat, move)

## 자재 요청은 창고 재고가 있으면 충족 처리(체인 해소) — 소비는 실제 사용처에서 발생.
func _settle_material_requests() -> void:
	var mats := [&"나무", &"돌", &"철", &"석탄"]
	for job in [Defs.JOB_CARPENTER, Defs.JOB_MINER]:
		for r in RequestBroker.open_for(job):
			if mats.has(r.item) and Village.has_res(r.item, r.qty):
				RequestBroker.fulfill(r)

# ── 요청 게시 → 건축 부지 생성 ──
func _on_request_posted(req) -> void:
	if req.item == &"밭건설":
		_create_build_site(&"FARM", req)
	elif req.item == &"집건설":
		_create_build_site(&"HOUSE", req)

func _create_build_site(category: StringName, req) -> void:
	var prefab
	if category == &"FARM":
		prefab = Prefabs.pick_weighted(Prefabs.farms(), _recent_farm)
		_push_recent(_recent_farm, prefab.id)
	else:
		prefab = Prefabs.pick_weighted(Prefabs.houses(), _recent_house)
		_push_recent(_recent_house, prefab.id)
	var cell := _find_site_cell(category, prefab.size)
	if cell.x < 0:
		return
	var b := Building.from_prefab(prefab, cell)
	b.build_req_id = req.id if req else -1
	_add_building(b)
	_mark_occupied(b)
	# 자재 요청 파생 (목수/광부 압력 유발)
	for mat in b.cost:
		var provider := Defs.JOB_CARPENTER if mat == &"나무" else Defs.JOB_MINER
		RequestBroker.post(mat, b.cost[mat], -1, provider, Defs.PRI_BUILD_MATERIAL,
			req.chain_id if req else 0)
	# 주택은 도로 연결 요청 (관리자 압력)
	if category == &"HOUSE":
		RequestBroker.post(&"도로", 1, -1, Defs.JOB_MANAGER, Defs.PRI_ROAD, 0,
			{"target": b.cell})

func _push_recent(arr: Array, id: StringName) -> void:
	arr.append(id)
	if arr.size() > 2:
		arr.pop_front()

func _find_site_cell(category: StringName, size: Vector2i) -> Vector2i:
	var hc := Village.hall_cell
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for r in range(3, 24):
		for a in range(0, 360, 30):
			var rad := deg_to_rad(a)
			var cell := hc + Vector2i(int(cos(rad) * r), int(sin(rad) * r))
			if not _cell_free(cell, size):
				continue
			var score := 1.0 - (r / 24.0) * 0.4
			if category == &"FARM":
				score += _near_water(cell) * 0.4
			else:
				score += _near_road(cell) * 0.3
			if score > best_score:
				best_score = score
				best = cell
		if best.x >= 0 and r > 6:
			break
	return best

func _near_water(cell: Vector2i) -> float:
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if MapGen.get_biome(cell.x + dx, cell.y + dy) == MapGen.Biome.WATER:
				return 1.0
	return 0.0

func _near_road(cell: Vector2i) -> float:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if _ground.roads.has(cell + Vector2i(dx, dy)):
				return 1.0
	return 0.0

# ── 자정 종합 처리 ──
func _on_day_end(_day: int) -> void:
	_aggregate_events()
	_reproduction_step()
	_build_progress_step()
	_appoint_new_adults()
	_death_step()
	_regen_resources()
	Village.apply_spoilage()
	# 개인 자정 처리 (aging/hunger) — 코디네이터가 집계 후 호출
	for v in Village.villagers:
		v.end_of_day()
	PressureBoard.update_daily()
	Village.reset_daily()
	# 밭 미경작 플래그 리셋
	for b in Village.buildings:
		if b.category == &"FARM":
			b.worked_today = false

func _aggregate_events() -> void:
	var d := Village.daily
	for v in Village.villagers:
		if v.fed_today < v.fu_need() * 0.99:
			d["hungry_count"] += 1
		if v.is_worker() and v.job == Defs.JOB_FARMER and Village.farm_for(v.vid) == null:
			d["farmer_nofield"] += 1
	for b in Village.buildings:
		if b.category == &"FARM" and b.built and b.assigned_to != -1 and not b.worked_today:
			d["field_unworked"] += 1
	# 미청소 잔해 (간이): 인구 비례 잡초 누적치를 근사
	d["debris"] = int(Village.population() * 0.8)

# ── 번식 (§8.1) ──
func _reproduction_step() -> void:
	var pop := Village.population()
	var surplus_threshold: float = pop * Defs.ADULT_FU_PER_DAY * 2.0
	if Village.food_fu >= surplus_threshold:
		_surplus_streak += 1
	else:
		_surplus_streak = 0
	# 임신 진행 → 출산
	for v in Village.villagers.duplicate():
		if v.pregnant_days >= 0:
			v.pregnant_days += 1
			if v.pregnant_days >= Defs.PREGNANCY_DAYS:
				v.pregnant_days = -1
				v.reproduce_cd = Defs.REPRODUCE_COOLDOWN_DAYS
				_birth(v)
	if _surplus_streak < 2:
		return
	_match_couples()
	# 커플 게이지 진행
	var houses_available := Village.empty_house() != null
	var advanced := {}
	for v in Village.villagers:
		if v.partner_id < 0 or advanced.has(v.vid):
			continue
		var partner = _find_villager(v.partner_id)
		if partner == null:
			v.partner_id = -1
			continue
		advanced[v.vid] = true
		advanced[partner.vid] = true
		if v.reproduce_cd > 0 or partner.reproduce_cd > 0:
			continue
		if v.couple_gauge < 100.0:
			v.couple_gauge += Defs.COUPLE_GAUGE_PER_DAY
			partner.couple_gauge = v.couple_gauge
		if v.couple_gauge >= 100.0:
			var house = Village.empty_house()
			if house != null:
				v.couple_gauge = 0.0
				partner.couple_gauge = 0.0
				var mother = v if v.sex == 0 else partner
				mother.pregnant_days = 0
				mother.home = house
				partner.home = house
				if not house.occupants.has(v.vid):
					house.occupants.append(v.vid)
				if not house.occupants.has(partner.vid):
					house.occupants.append(partner.vid)
			else:
				# 빈집 없음 → 건축가 압력 + 주택 건설 요청 (§8.1)
				Village.daily["couple_nohouse"] += 1
				if not _house_shortage_posted:
					RequestBroker.post(&"집건설", 1, v.vid, Defs.JOB_BUILDER,
						Defs.PRI_BUILD_HOUSE)
					_house_shortage_posted = true

func _match_couples() -> void:
	var singles := []
	for v in Village.villagers:
		if v.is_adult_like() and v.partner_id < 0 and v.life_stage() != &"elder":
			singles.append(v)
	# 나이차 최소 + 비혈연(성 다름) 우선 매칭
	for i in singles.size():
		var a = singles[i]
		if a.partner_id >= 0:
			continue
		var best = null
		var best_diff := 9999.0
		for j in range(i + 1, singles.size()):
			var b = singles[j]
			if b.partner_id >= 0:
				continue
			if b.family_name == a.family_name:
				continue  # 혈연 근사 회피
			if b.sex == a.sex:
				continue
			var diff: float = abs(a.age_days - b.age_days)
			if diff < best_diff:
				best_diff = diff
				best = b
		if best != null:
			a.partner_id = best.vid
			best.partner_id = a.vid

func _birth(mother) -> void:
	var cell = mother.home.center() if mother.home else Village.hall_cell
	var baby = _make_villager(cell)
	baby.age_days = 0.0
	baby.family_name = mother.family_name
	baby.vname = NameGen.given()
	baby.home = mother.home
	if mother.home:
		mother.home.occupants.append(baby.vid)
	Village.villager_born.emit(baby)
	_house_shortage_posted = false

# ── 건축 완공 판정 ──
func _build_progress_step() -> void:
	# 도로 연결 (관리자 있을 때) — 주택 착공 조건
	var managers := Village.count_job(Defs.JOB_MANAGER)
	for b in Village.buildings:
		if b.category == &"HOUSE" and not b.built and not b.road_connected:
			if managers > 0:
				_connect_road(b)
			else:
				Village.daily["road_wait_days"] += 1
	# 완공 판정
	for b in Village.buildings:
		if b.built:
			continue
		if b.materials_ready() and b.progress() >= 1.0:
			b.built = true
			if b.category == &"FARM":
				_assign_farm(b)
			if b.build_req_id >= 0 and RequestBroker.requests.has(b.build_req_id):
				RequestBroker.fulfill(RequestBroker.requests[b.build_req_id])
			if b.view:
				b.view.setup_building(b)
			Village.building_completed.emit(b)
		elif b.view:
			b.view.setup_building(b)  # 진행 단계 갱신

func _connect_road(b) -> void:
	var hc := Village.hall_cell
	var c: Vector2i = b.cell
	# L자 경로
	var x := hc.x
	while x != c.x:
		_ground.add_road(Vector2i(x, hc.y))
		x += signi(c.x - x)
	var y := hc.y
	while y != c.y:
		_ground.add_road(Vector2i(c.x, y))
		y += signi(c.y - y)
	b.road_connected = true
	# 대응하는 도로 요청 충족 (관리자 압력 해소)
	for r in RequestBroker.open_for(Defs.JOB_MANAGER):
		if r.item == &"도로" and r.payload.get("target", Vector2i(-1, -1)) == b.cell:
			RequestBroker.fulfill(r)
			break

func _assign_farm(b) -> void:
	# 담당 밭 없는 농부에게 배정
	for v in Village.villagers:
		if v.is_worker() and v.job == Defs.JOB_FARMER and Village.farm_for(v.vid) == null:
			b.assigned_to = v.vid
			return

# ── 신규 성인 임명 (§6.6) ──
func _appoint_new_adults() -> void:
	for v in Village.villagers:
		if v.is_adult_like() and not v.is_appointed:
			var job := PressureBoard.appoint(v)
			# 도구 요청 자동 등록
			if Defs.JOB_PRIMARY_TOOL.has(job):
				v._ensure_tool_request(false)
			# 집 없으면 빈집 배정
			if v.home == null:
				var h = Village.empty_house()
				if h:
					v.home = h
					h.occupants.append(v.vid)

# ── 사망 (§8.4) ──
func _death_step() -> void:
	for v in Village.villagers.duplicate():
		if v.life_stage() == &"elder" and v.death_age == 0:
			v.death_age = RNGService.randi_range(Defs.AGE_DEATH_MIN, Defs.AGE_DEATH_MAX)
		if v.death_age > 0 and v.age_days >= v.death_age:
			_kill(v)

func _kill(v) -> void:
	# 도구 반납
	if v.tool_item != &"" and v.tool_dur > 0:
		Village.return_tool(v.tool_item, v.tool_dur)
	# 직업 공석 이벤트
	if v.is_worker():
		var vac: Dictionary = Village.daily["vacancies"]
		vac[v.job] = vac.get(v.job, 0) + 1
	# 주택 정리
	if v.home and v.home.occupants.has(v.vid):
		v.home.occupants.erase(v.vid)
	# 배우자 해제
	if v.partner_id >= 0:
		var p = _find_villager(v.partner_id)
		if p:
			p.partner_id = -1
			p.reproduce_cd = 3
	# 밭 회수
	var farm = Village.farm_for(v.vid)
	if farm:
		farm.assigned_to = -1
	Village.villagers.erase(v)
	Village.villager_died.emit(v)
	v.queue_free()

# ── 자원 재생 (§3.3) ──
func _regen_resources() -> void:
	# 동물 스폰: 0.5 × (1 + 인구/20)
	var spawn := 0.5 * (1.0 + Village.population() / 20.0)
	var n := int(spawn)
	if RNGService.chance(spawn - n):
		n += 1
	for _i in n:
		_spawn_animal()
	# 나무/광맥 재생은 간이: 저확률 신규 노출
	if RNGService.chance(0.3):
		_respawn_ore()

func _spawn_animal() -> void:
	for _try in 10:
		var x := RNGService.randi_range(2, MapGen.MAP_W - 2)
		var y := RNGService.randi_range(2, MapGen.MAP_H - 2)
		var cell := Vector2i(x, y)
		if MapGen.get_biome(x, y) == MapGen.Biome.GRASS and not MapGen.resources.has(cell):
			MapGen.resources[cell] = {"type": MapGen.Res.ANIMAL, "amount": 1}
			var view = EntityView.new()
			_entities.add_child(view)
			view.setup_resource(MapGen.Res.ANIMAL, cell)
			return

func _respawn_ore() -> void:
	for _try in 10:
		var x := RNGService.randi_range(2, MapGen.MAP_W - 2)
		var y := RNGService.randi_range(2, MapGen.MAP_H - 2)
		var cell := Vector2i(x, y)
		if MapGen.get_biome(x, y) == MapGen.Biome.ROCK and not MapGen.resources.has(cell):
			MapGen.resources[cell] = {"type": MapGen.Res.STONE, "amount": 200}
			var view = EntityView.new()
			_entities.add_child(view)
			view.setup_resource(MapGen.Res.STONE, cell)
			return

func _find_villager(id: int):
	for v in Village.villagers:
		if v.vid == id:
			return v
	return null
