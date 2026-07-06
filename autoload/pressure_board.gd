extends Node
## 직업 압력 계산·임명/전직 판정 싱글톤 (계획서 §6.4~6.7).

signal pressure_updated(p: Dictionary)
signal villager_appointed(v, job: StringName)
signal villager_reassigned(v, from_job: StringName, to_job: StringName)

var P: Dictionary = {}             # job -> float 압력
var _bottleneck_streak: int = 0    # 병목 연속일 (히스테리시스)
var _bottleneck_job: StringName = &""
var _reassign_cooldown: int = 0    # 전직 글로벌 쿨다운

func _ready() -> void:
	for j in Defs.JOBS:
		P[j] = 0.0

func reset() -> void:
	for j in Defs.JOBS:
		P[j] = 0.0
	_bottleneck_streak = 0
	_bottleneck_job = &""
	_reassign_cooldown = 0

## 자정마다 호출: 압력 갱신 → 전직 판정.
func update_daily() -> void:
	_recompute_pressure()
	_maybe_reassign()
	if _reassign_cooldown > 0:
		_reassign_cooldown -= 1
	pressure_updated.emit(P)

func _recompute_pressure() -> void:
	var d := Village.daily
	for job in Defs.JOBS:
		var backlog := 0.0
		for r in RequestBroker.open_for(job):
			backlog += r.effective_priority(GameClock.day) * (mini(r.qty, 5) / 5.0)
		var bonus := _event_bonus(job, d)
		# 하드 제약 미달도 압력에 반영
		bonus += _quota_pressure(job)
		P[job] = Defs.P_DECAY * P[job] + backlog + bonus

func _event_bonus(job: StringName, d: Dictionary) -> float:
	var b := 0.0
	match job:
		Defs.JOB_FARMER:
			b += d["hungry_count"] * Defs.BONUS_HUNGRY
			b += d["field_unworked"] * Defs.BONUS_FIELD_UNWORKED
		Defs.JOB_HUNTER:
			b += d["hungry_count"] * Defs.BONUS_HUNGRY
		Defs.JOB_MANAGER:
			b += d["manager_overflow"] * Defs.BONUS_MANAGER_OVERFLOW
			b += d["road_wait_days"] * Defs.BONUS_ROAD_WAIT
			b += (Defs.BONUS_DEBRIS if d["debris"] > 30 else 0)
		Defs.JOB_BUILDER:
			b += d["couple_nohouse"] * Defs.BONUS_COUPLE_NOHOUSE
			b += d["farmer_nofield"] * Defs.BONUS_FARMER_NOFIELD
		Defs.JOB_ARTISAN:
			b += d["artisan_carryover"] * Defs.BONUS_ARTISAN_CARRYOVER
		Defs.JOB_GUARD:
			b += d["wolf_attacks"] * Defs.BONUS_WOLF_ATTACK
	b += float(d["vacancies"].get(job, 0)) * Defs.BONUS_JOB_VACANCY
	return b

## 하드 제약 미달분을 압력으로 환산 (정원 부족 시 강한 수요)
func _quota_pressure(job: StringName) -> float:
	var pop := Village.population()
	var have := Village.count_job(job)
	var need := 0
	match job:
		Defs.JOB_GUARD: need = Defs.guard_quota(pop)
		Defs.JOB_MANAGER: need = Defs.manager_quota(pop)
		_: need = 0
	if job == Defs.JOB_FARMER or job == Defs.JOB_HUNTER:
		var food_have := Village.count_job(Defs.JOB_FARMER) + Village.count_job(Defs.JOB_HUNTER)
		var food_need := Defs.food_quota(pop)
		if food_have < food_need:
			return (food_need - food_have) * 90.0
	if need > have:
		return (need - have) * 90.0
	return 0.0

# ── 임명 (§6.6) ──────────────────────────────────────────
## 신규 성인의 직업 결정.
func appoint(v) -> StringName:
	var pop := Village.population()
	var job := _hard_constraint_pick(pop)
	if job == &"":
		job = _argmax_pressure()
	if job == &"":
		job = Defs.JOB_FARMER
	v.set_job(job)
	villager_appointed.emit(v, job)
	return job

func _hard_constraint_pick(pop: int) -> StringName:
	var deficits := {}
	# 경비
	var g_need := Defs.guard_quota(pop)
	var g_have := Village.count_job(Defs.JOB_GUARD)
	if g_have < g_need:
		deficits[Defs.JOB_GUARD] = float(g_need - g_have) / maxf(g_need, 1)
	# 관리자
	var m_need := Defs.manager_quota(pop)
	var m_have := Village.count_job(Defs.JOB_MANAGER)
	if m_have < m_need:
		deficits[Defs.JOB_MANAGER] = float(m_need - m_have) / maxf(m_need, 1)
	# 식량직
	var f_need := Defs.food_quota(pop)
	var f_have := Village.count_job(Defs.JOB_FARMER) + Village.count_job(Defs.JOB_HUNTER)
	if f_have < f_need:
		var ratio := float(f_need - f_have) / maxf(f_need, 1)
		# 농부/사냥꾼 중 압력 높은 쪽
		var fj := Defs.JOB_FARMER if P[Defs.JOB_FARMER] >= P[Defs.JOB_HUNTER] else Defs.JOB_HUNTER
		deficits[fj] = ratio
	# 인구 8 이상이면 전 직업 최소 1명
	if pop >= 8:
		for j in Defs.JOBS:
			if Village.count_job(j) == 0 and not deficits.has(j):
				deficits[j] = 0.5
	if deficits.is_empty():
		return &""
	var best := &""
	var best_v := -1.0
	for j in deficits:
		if deficits[j] > best_v:
			best_v = deficits[j]
			best = j
	return best

func _argmax_pressure() -> StringName:
	var best := &""
	var best_p := -1.0
	for j in Defs.JOBS:
		var p: float = P[j]
		if p > best_p:
			best_p = p
			best = j
		elif is_equal_approx(p, best_p):
			# 동률: (현재/목표비) 최저 직업
			if _fill_ratio(j) < _fill_ratio(best):
				best = j
	return best

func _fill_ratio(job: StringName) -> float:
	var pop := maxi(Village.population(), 1)
	var target: float = Defs.JOB_TARGET_RATIO.get(job, 0.1) * pop
	return Village.count_job(job) / maxf(target, 0.5)

# ── 전직 (§6.7) ──────────────────────────────────────────
func _maybe_reassign() -> void:
	if _reassign_cooldown > 0:
		return
	var avg := 0.0
	for j in Defs.JOBS:
		avg += P[j]
	avg /= Defs.JOBS.size()
	if avg <= 0.0:
		_bottleneck_streak = 0
		return
	var hot := _argmax_pressure()
	# 조건1: max >= 3×평균
	if P[hot] < 3.0 * avg:
		_bottleneck_streak = 0
		_bottleneck_job = &""
		return
	# 조건2: 3일 연속 유지
	if hot == _bottleneck_job:
		_bottleneck_streak += 1
	else:
		_bottleneck_job = hot
		_bottleneck_streak = 1
	if _bottleneck_streak < 3:
		return
	# 조건3: 공여 직업 = min(P) 이며 하드제약/최소1명 안 깨는 직업
	var donor := _pick_donor()
	if donor == &"":
		return
	# 전직 실행
	var cand = _pick_reassign_candidate(donor)
	if cand == null:
		return
	var from_job: StringName = cand.job
	cand.change_job(hot)
	_reassign_cooldown = 2
	_bottleneck_streak = 0
	villager_reassigned.emit(cand, from_job, hot)

func _pick_donor() -> StringName:
	var pop := Village.population()
	var best := &""
	var best_p := INF
	for j in Defs.JOBS:
		if Village.count_job(j) <= 0:
			continue
		if _breaks_hard_constraint_if_reduced(j, pop):
			continue
		if P[j] < best_p:
			best_p = P[j]
			best = j
	return best

func _breaks_hard_constraint_if_reduced(job: StringName, pop: int) -> bool:
	var have := Village.count_job(job)
	if have <= 1 and pop >= 8:
		return true  # 최소 1명 유지
	match job:
		Defs.JOB_GUARD:
			return (have - 1) < Defs.guard_quota(pop)
		Defs.JOB_MANAGER:
			return (have - 1) < Defs.manager_quota(pop)
		Defs.JOB_FARMER, Defs.JOB_HUNTER:
			var food_have := Village.count_job(Defs.JOB_FARMER) + Village.count_job(Defs.JOB_HUNTER)
			return (food_have - 1) < Defs.food_quota(pop)
	return false

func _pick_reassign_candidate(donor: StringName):
	# 비노년 성인 우선
	for v in Village.villagers:
		if v.is_worker() and v.job == donor and v.life_stage() == &"adult":
			return v
	return null
