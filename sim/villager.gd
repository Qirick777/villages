class_name Villager
extends Node2D
## 주민 — 시뮬레이션 상태 + 시각 표현 + 개인 AI (계획서 §8, §11).
## 상위 FSM은 GameClock의 시간표 기반, WORK 내부는 직업별 생산 루프.

# ── 정체성 ──
var vid: int = 0
var vname: String = ""
var sex: int = 0                    # 0=female 1=male
var family_name: String = ""
var age_days: float = 6.0           # 성인부터 시작 가능

# ── 직업 ──
var job: StringName = &""
var is_appointed: bool = false      # 성인 임명 완료
var pending_job_change: bool = false

# ── 도구 ──
var tool_item: StringName = &""
var tool_dur: int = 0
var _preventive_posted: bool = false

# ── 허기 ──
var fed_today: float = 0.0          # 오늘 배급받은 FU
var starve_days: int = 0            # 연속 결식
var work_penalty: float = 1.0       # 결식/노년/임신 반영 효율

# ── 번식 ──
var partner_id: int = -1
var couple_gauge: float = 0.0
var pregnant_days: int = -1         # -1=비임신
var reproduce_cd: int = 0
var home = null                     # Building
var death_age: int = 0             # elder 진입 시 66~72로 확정

# ── 생산 누적 ──
var carry_food: float = 0.0         # 미납품 식량
var produced_today: float = 0.0

# ── 이동 ──
var cell: Vector2i = Vector2i.ZERO
var _target_world: Vector2 = Vector2.ZERO
var _move_speed: float = 46.0
var _work_cell: Vector2i = Vector2i.ZERO
var _farm_requested: bool = false
var _anchor_cell: Vector2i = Vector2i.ZERO   # 배회 기준점(회관/집/작업지)
var _jitter: Vector2 = Vector2.ZERO          # 겹침 방지 개인 오프셋
var _wander_t: float = 0.0
var _anim_t: float = 0.0
var _walking: bool = false
var _action: StringName = &""                # 현재 행동(아이콘 표시)
# 연출용 RNG — 렌더 틱에서 랜덤을 뽑아도 시뮬 결정론(RNGService)을 오염시키지 않음
var _fx := RandomNumberGenerator.new()

# ── 시각 ──
var _body: Polygon2D
var _shadow: Polygon2D
var _bubble: Label
var _status: Label

const WORK_MINUTES := 570.0

func _ready() -> void:
	_fx.seed = vid * 2654435761
	_jitter = Vector2(_fx.randf_range(-13, 13), _fx.randf_range(-7, 7))
	_anchor_cell = cell
	_build_visual()
	position = Iso.cell_to_world(cell) + _jitter
	_target_world = position
	GameClock.tick.connect(_on_tick)
	GameClock.phase_changed.connect(_on_phase)
	# 자정 처리는 코디네이터(main.gd)가 순서를 통제하며 end_of_day()로 호출한다.

func setup(p_id: int, p_name: String, p_family: String, p_sex: int, p_cell: Vector2i) -> void:
	vid = p_id
	vname = p_name
	family_name = p_family
	sex = p_sex
	cell = p_cell

# ── 생애주기 ──
func life_stage() -> StringName:
	return Defs.life_stage(int(age_days))

func is_worker() -> bool:
	return is_appointed and (life_stage() == &"adult" or life_stage() == &"elder")

func is_adult_like() -> bool:
	var s := life_stage()
	return s == &"adult" or s == &"elder"

func set_job(j: StringName) -> void:
	job = j
	is_appointed = true
	_preventive_posted = false
	_farm_requested = false
	if _body:
		_body.color = Defs.JOB_COLORS.get(j, Color.WHITE)

## 전직(§6.7): 기존 도구 창고 반납 → 직업 변경 → 신규 도구 요청.
func change_job(j: StringName) -> void:
	if tool_item != &"" and tool_dur > 0:
		Village.return_tool(tool_item, tool_dur)
	tool_item = &""
	tool_dur = 0
	set_job(j)
	pending_job_change = true
	if Defs.JOB_PRIMARY_TOOL.has(j):
		_ensure_tool_request(false)

func fu_need() -> float:
	return Defs.fu_consumption(int(age_days))

# ── 틱: 작업 생산만 (이동은 _process에서 프레임 보간) ──
func _on_tick(_day: int, _minute: int) -> void:
	var phase := GameClock.phase
	if phase == &"WORK_AM" or phase == &"WORK_PM":
		if is_worker():
			_work_tick()

# ── 프레임 보간 이동 + 배회 + 걷기 애니메이션 ──
func _process(delta: float) -> void:
	var mult := GameClock.speed_mult()
	if mult <= 0.0:
		return
	_anim_t += delta
	# 사교 시간(집회/휴식)엔 기준점 주변을 서성이며 무리 형성
	if _is_social_phase():
		_wander_t -= delta * mult
		if _wander_t <= 0.0:
			_wander_t = _fx.randf_range(0.9, 2.4)
			var r := _fx.randf_range(6.0, 30.0)
			var a := _fx.randf_range(0.0, TAU)
			_target_world = Iso.cell_to_world(_anchor_cell) + Vector2(cos(a) * r, sin(a) * r * 0.55)
			_set_action(&"🗣")

	var mv := _move_speed * delta * clampf(mult, 1.0, 4.0)
	var dist := position.distance_to(_target_world)
	_walking = dist > 2.0
	if _walking:
		position = position.move_toward(_target_world, mv)
		cell = Iso.world_to_cell(position)

	# 걷기 상하 흔들림(살아있는 느낌) + 정지 시 미세 호흡
	if _body:
		if _walking:
			_body.position.y = -abs(sin(_anim_t * 12.0)) * 2.2
		else:
			_body.position.y = sin(_anim_t * 2.0) * 0.6

func _move_to(target_cell: Vector2i) -> void:
	_work_cell = target_cell
	_target_world = Iso.cell_to_world(target_cell) + _jitter

func _is_social_phase() -> bool:
	var p := GameClock.phase
	return p == &"MEETING_AM" or p == &"MEETING_NOON" or p == &"REST"

# ── 페이즈 전이 ──
func _on_phase(phase: StringName) -> void:
	match phase:
		&"WAKE", &"MEETING_AM", &"MEETING_NOON":
			_anchor_cell = Village.hall_cell
			_move_to(Village.hall_cell)
			if phase == &"MEETING_AM" or phase == &"MEETING_NOON":
				_set_action(&"🍽")
				_attend_meeting()
			else:
				_set_action(&"🚶")
		&"WORK_AM", &"WORK_PM":
			if is_worker():
				_pick_work_site()
			else:
				# 아동·청소년은 회관 주변 배회
				_anchor_cell = Village.hall_cell
				_set_action(_stage_icon())
		&"REST":
			if home:
				_anchor_cell = home.center()
				_move_to(home.center())
			_set_action(&"🗣")
		&"SLEEP":
			if home:
				_move_to(home.center())
			_set_action(&"💤")

# ── 집회: 식량 납품 + 요청 수령 ──
func _attend_meeting() -> void:
	# 식량직은 보유 식량을 관리자/창고에 전달
	if carry_food > 0.0:
		Village.add_food(carry_food)
		carry_food = 0.0
	# 공급자는 자기 직업 요청 확인 (연출: 말풍선)
	if is_worker():
		var req = RequestBroker.pull_for(job, vid)
		if req:
			_show_bubble(req.item)
			# 즉시 처리 불가 항목은 작업 큐로 (작업 틱에서 소진). 여기선 도로 반납.
			RequestBroker.release(req)

# ── 작업지 선택 ──
func _pick_work_site() -> void:
	_set_action(_job_icon())
	match job:
		Defs.JOB_CARPENTER:
			var t := MapGen.nearest_resource(cell, MapGen.Res.TREE)
			_goto_work(t if t.x >= 0 else Village.hall_cell)
		Defs.JOB_MINER:
			var m := MapGen.nearest_resource(cell, MapGen.Res.STONE)
			_goto_work(m if m.x >= 0 else Village.hall_cell)
		Defs.JOB_HUNTER:
			var a := MapGen.nearest_resource(cell, MapGen.Res.ANIMAL)
			_goto_work(a if a.x >= 0 else Village.hall_cell)
		Defs.JOB_FARMER:
			var farm = Village.farm_for(vid)
			if farm:
				_goto_work(farm.center())
			else:
				_ensure_farm_request()
				_goto_work(Village.hall_cell)
		Defs.JOB_BUILDER:
			var site = _find_build_site()
			_goto_work(site.center() if site else Village.hall_cell)
		_:
			_goto_work(Village.hall_cell)

func _goto_work(target_cell: Vector2i) -> void:
	_anchor_cell = target_cell
	_move_to(target_cell)

# ── 작업 틱: 직업별 생산 ──
func _work_tick() -> void:
	var minutes := (Defs.TICK_SECONDS / Defs.DAY_SECONDS) * Defs.MINUTES_PER_DAY
	var eff := _efficiency()
	match job:
		Defs.JOB_FARMER: _produce_farmer(minutes, eff)
		Defs.JOB_HUNTER: _produce_carry(minutes, eff, 7.0)
		Defs.JOB_CARPENTER: _produce_material(minutes, eff, &"나무", 20.0)
		Defs.JOB_MINER: _produce_miner(minutes, eff)
		Defs.JOB_ARTISAN: _work_artisan(minutes, eff)
		Defs.JOB_BUILDER: _work_builder(minutes, eff)
		Defs.JOB_MANAGER: _work_manager(minutes, eff)
		Defs.JOB_GUARD: pass  # 순찰은 이동으로 연출, 습격은 코디네이터 처리

func _efficiency() -> float:
	var e := work_penalty
	var st := life_stage()
	if st == &"elder":
		e *= 0.7
	if pregnant_days >= 0:
		e *= 0.75
	# 도구 필요 직업이 도구 없으면 맨손 25%
	if Defs.JOB_PRIMARY_TOOL.has(job) and tool_dur <= 0:
		e *= Defs.BAREHAND_EFF
	return e

func _consume_tool(swings: float) -> void:
	if not Defs.JOB_PRIMARY_TOOL.has(job):
		return
	if tool_dur <= 0:
		_ensure_tool_request(true)
		return
	tool_dur -= int(ceil(swings))
	var max_dur: int = Defs.TOOLS[Defs.JOB_PRIMARY_TOOL[job]]["durability"]
	if tool_dur <= 0:
		tool_dur = 0
		_ensure_tool_request(true)      # 파손
	elif float(tool_dur) / max_dur <= 0.2 and not _preventive_posted:
		_ensure_tool_request(false)     # 예방적 교체

func _ensure_tool_request(broken: bool) -> void:
	var tool: StringName = Defs.JOB_PRIMARY_TOOL.get(job, &"")
	if tool == &"":
		return
	# 창고에 여분 도구 있으면 즉시 수령
	if Village.tool_available(tool):
		var t := Village.take_tool(tool)
		if not t.is_empty():
			tool_item = tool
			tool_dur = t["dur"]
			_preventive_posted = false
			return
	var pri := Defs.PRI_TOOL_BROKEN if broken else Defs.PRI_TOOL_PREVENTIVE
	var chain_req = RequestBroker.post(tool, 1, vid, Defs.JOB_ARTISAN, pri)
	# 재료 조달 체인 파생
	RequestBroker.request_tool_materials(tool, vid, chain_req.chain_id)
	_show_bubble(tool)
	if not broken:
		_preventive_posted = true

func _produce_farmer(minutes: float, eff: float) -> void:
	carry_food += (8.0 / WORK_MINUTES) * minutes * eff
	produced_today += (8.0 / WORK_MINUTES) * minutes * eff
	var farm = Village.farm_for(vid)
	if farm:
		farm.worked_today = true
	_consume_tool((16.0 / WORK_MINUTES) * minutes)

func _produce_carry(minutes: float, eff: float, daily: float) -> void:
	carry_food += (daily / WORK_MINUTES) * minutes * eff
	produced_today += (daily / WORK_MINUTES) * minutes * eff
	_consume_tool((12.0 / WORK_MINUTES) * minutes)

func _produce_material(minutes: float, eff: float, item: StringName, daily: float) -> void:
	var amt := (daily / WORK_MINUTES) * minutes * eff
	produced_today += amt
	_deposit_material(item, amt)
	_consume_tool((20.0 / WORK_MINUTES) * minutes)
	# 시각: 인접 나무 벌목
	_harvest_nearby(MapGen.Res.TREE)

func _produce_miner(minutes: float, eff: float) -> void:
	# 철곡괭이면 철+석탄, 아니면 돌
	if tool_item == Defs.TOOL_IRON_PICK and tool_dur > 0:
		_deposit_material(&"철", (8.0 / WORK_MINUTES) * minutes * eff)
		_deposit_material(&"석탄", (4.0 / WORK_MINUTES) * minutes * eff)
		_consume_tool((12.0 / WORK_MINUTES) * minutes)
	else:
		# 돌곡괭이: 돌 위주 + 철·석탄 소량(0.5 효율 혼합 채광, §4.1) → 철 경제 미고갈 보장
		_deposit_material(&"돌", (12.0 / WORK_MINUTES) * minutes * eff)
		_deposit_material(&"철", (2.0 / WORK_MINUTES) * minutes * eff)
		_deposit_material(&"석탄", (2.0 / WORK_MINUTES) * minutes * eff)
		_consume_tool((15.0 / WORK_MINUTES) * minutes)
	_harvest_nearby(MapGen.Res.STONE)

var _material_accum: Dictionary = {}
func _deposit_material(item: StringName, amt: float) -> void:
	_material_accum[item] = _material_accum.get(item, 0.0) + amt
	var whole := int(_material_accum[item])
	if whole >= 1:
		Village.add_res(item, whole)
		_material_accum[item] -= whole

func _harvest_nearby(res_type: int) -> void:
	# 저확률로 인접 노드 소량 채취 (연출 + 고갈/재생 구동)
	if RNGService.chance(0.02):
		var c := MapGen.nearest_resource(cell, res_type, 6)
		if c.x >= 0:
			MapGen.harvest(c, 1)

# ── 장인: 도구 제작 (최대 3/일) ──
var crafts_today: int = 0
func _work_artisan(_minutes: float, _eff: float) -> void:
	if crafts_today >= 3:
		return
	var req = RequestBroker.pull_for(Defs.JOB_ARTISAN, vid)
	if req == null:
		return
	var tool: StringName = req.item
	if not Defs.TOOLS.has(tool):
		RequestBroker.release(req)
		return
	var cost: Dictionary = Defs.TOOLS[tool]["cost"]
	# 재료 확인
	var ok := true
	for mat in cost:
		if not Village.has_res(mat, cost[mat]):
			ok = false
	if ok:
		for mat in cost:
			Village.take_res(mat, cost[mat])
		Village.craft_tool_to_pool(tool)
		crafts_today += 1
		RequestBroker.fulfill(req)
		_show_bubble(tool)
	else:
		# 재료 파생 후 요청 반납 (다음 집회에 재시도)
		RequestBroker.request_tool_materials(tool, vid, req.chain_id)
		RequestBroker.release(req)

# ── 건축가: 건축 노동 ──
func _work_builder(minutes: float, eff: float) -> void:
	var site = _find_build_site()
	if site == null:
		return
	_move_to(site.center())
	if site.materials_ready():
		var hours := (minutes / 60.0) * eff
		site.labor_done += hours
		_consume_tool((minutes / WORK_MINUTES) * 6.0)

func _find_build_site():
	# 우선순위: 밭 > 주택, 자재 도착 우선
	var best = null
	var best_score := -1.0
	for b in Village.buildings:
		if b.built:
			continue
		# 주택은 도로 연결이 착공 조건(§5.2)
		if b.category == &"HOUSE" and not b.road_connected:
			continue
		var s := (2.0 if b.category == &"FARM" else 1.0)
		if b.materials_ready():
			s += 5.0
		s += b.progress()
		if s > best_score:
			best_score = s
			best = b
	return best

# ── 관리자: (배분은 코디네이터, 여기선 도로/청소 연출) ──
func _work_manager(_minutes: float, _eff: float) -> void:
	pass

# ── 밭 건설 요청 ──
func _ensure_farm_request() -> void:
	if _farm_requested:
		return
	if Village.unassigned_farm():
		return
	RequestBroker.post(&"밭건설", 1, vid, Defs.JOB_BUILDER, Defs.BONUS_FARMER_NOFIELD,
		0, {"kind": "FARM"})
	_show_bubble(&"밭 필요")
	_farm_requested = true

# ── 일일 갱신 (자정) — 코디네이터가 호출 ──
func end_of_day() -> void:
	age_days += 1.0
	crafts_today = 0
	_apply_scale()
	# 허기 판정: 오늘 먹은 FU가 필요량 미달이면 결식
	if fed_today < fu_need() * 0.99:
		starve_days += 1
	else:
		starve_days = 0
	fed_today = 0.0
	# 결식 페널티 (§5)
	if starve_days >= 3:
		work_penalty = 0.25
	elif starve_days >= 1:
		work_penalty = 0.5
	else:
		work_penalty = 1.0
	if reproduce_cd > 0:
		reproduce_cd -= 1
	produced_today = 0.0

# ── 배급 수령 (코디네이터 호출) ──
func receive_ration(fu: float) -> void:
	fed_today += fu

# ── 시각 ──
func _build_visual() -> void:
	_shadow = Polygon2D.new()
	_shadow.polygon = PackedVector2Array([
		Vector2(-9, 0), Vector2(0, 5), Vector2(9, 0), Vector2(0, -5)])
	_shadow.color = Color(0, 0, 0, 0.28)
	_shadow.position = Vector2(0, 2)
	add_child(_shadow)

	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-6, -4), Vector2(6, -4), Vector2(5, -26), Vector2(-5, -26)])
	_body.color = Defs.JOB_COLORS.get(job, Color("#cccccc"))
	add_child(_body)

	var head := Polygon2D.new()
	head.polygon = _circle_points(5, Vector2(0, -30))
	head.color = Color("#e8c9a0")
	add_child(head)

	# 상시 상태 아이콘 (머리 위) — "뭘 하는지" 표시
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.position = Vector2(-8, -46)
	add_child(_status)

	# 요청/대사 말풍선 (임시)
	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 11)
	_bubble.add_theme_color_override("font_color", Color("#fff2c0"))
	_bubble.position = Vector2(-10, -62)
	_bubble.visible = false
	add_child(_bubble)
	_apply_scale()
	_set_action(_stage_icon())

func _apply_scale() -> void:
	var s: float = Defs.SPRITE_SCALE.get(life_stage(), 1.0)
	scale = Vector2(s, s)

func _circle_points(r: float, off: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(off + Vector2(cos(a), sin(a)) * r)
	return pts

func _show_bubble(item: StringName) -> void:
	if not _bubble:
		return
	_bubble.text = "💬%s" % item
	_bubble.visible = true
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(_bubble):
			_bubble.visible = false)

func _set_action(icon: StringName) -> void:
	_action = icon
	if _status:
		_status.text = icon

## 직업별 작업 아이콘
func _job_icon() -> StringName:
	match job:
		Defs.JOB_FARMER: return &"🌾"
		Defs.JOB_HUNTER: return &"🏹"
		Defs.JOB_CARPENTER: return &"🪓"
		Defs.JOB_MINER: return &"⛏"
		Defs.JOB_ARTISAN: return &"🛠"
		Defs.JOB_BUILDER: return &"🔨"
		Defs.JOB_MANAGER: return &"📦"
		Defs.JOB_GUARD: return &"🛡"
		_: return &"🚶"

## 생애 단계 아이콘 (비노동 연령)
func _stage_icon() -> StringName:
	match life_stage():
		&"infant": return &"👶"
		&"child": return &"🧒"
		&"teen": return &"🧑"
		_: return &"🙂"
