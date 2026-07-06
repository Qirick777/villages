extends Node
## 인구·건물·창고 데이터 싱글톤 (계획서 §1.4, §4, §7).

signal villager_born(v)
signal villager_died(v)
signal building_completed(b)
signal stock_changed()

# 창고 원자재  (StringName -> int)
var res: Dictionary = {&"나무": 0, &"돌": 0, &"철": 0, &"석탄": 0}
# 창고 식량 (FU)
var food_fu: float = 0.0
# 창고 도구 풀 (전직/사망 반납분 + 신규 제작분) : Array[{item, dur}]
var tool_pool: Array = []

# 등록된 주민 노드
var villagers: Array = []
# 건물 (Building 인스턴스)
var buildings: Array = []
var hall_cell: Vector2i = Vector2i.ZERO

# 하루 단위 집계 (압력 이벤트용)
var daily := {
	"hungry_count": 0,
	"manager_overflow": 0,
	"road_wait_days": 0,
	"couple_nohouse": 0,
	"artisan_carryover": 0,
	"wolf_attacks": 0,
	"debris": 0,
	"farmer_nofield": 0,
	"field_unworked": 0,
	"vacancies": {},        # job -> count
}
var _next_villager_id: int = 1

func reset() -> void:
	res = {&"나무": 0, &"돌": 0, &"철": 0, &"석탄": 0}
	food_fu = Defs.START_FOOD_FU
	tool_pool.clear()
	villagers.clear()
	buildings.clear()
	reset_daily()

func reset_daily() -> void:
	daily = {
		"hungry_count": 0, "manager_overflow": 0, "road_wait_days": 0,
		"couple_nohouse": 0, "artisan_carryover": 0, "wolf_attacks": 0,
		"debris": 0, "farmer_nofield": 0, "field_unworked": 0, "vacancies": {},
	}

func next_id() -> int:
	var i := _next_villager_id
	_next_villager_id += 1
	return i

# ── 인구 ────────────────────────────────────────────────
func population() -> int:
	return villagers.size()

func adults() -> Array:
	var a := []
	for v in villagers:
		if v.life_stage() == &"adult" or v.life_stage() == &"elder":
			a.append(v)
	return a

func count_job(job: StringName) -> int:
	var c := 0
	for v in villagers:
		if v.is_worker() and v.job == job:
			c += 1
	return c

func job_counts() -> Dictionary:
	var d := {}
	for j in Defs.JOBS:
		d[j] = 0
	for v in villagers:
		if v.is_worker():
			d[v.job] = d.get(v.job, 0) + 1
	return d

# ── 창고 자원 ─────────────────────────────────────────────
func add_res(item: StringName, qty: int) -> void:
	res[item] = res.get(item, 0) + qty
	stock_changed.emit()

func take_res(item: StringName, qty: int) -> bool:
	if res.get(item, 0) >= qty:
		res[item] -= qty
		stock_changed.emit()
		return true
	return false

func has_res(item: StringName, qty: int) -> bool:
	return res.get(item, 0) >= qty

func add_food(fu: float) -> void:
	food_fu += fu
	stock_changed.emit()

func food_cap() -> float:
	return maxf(30.0, population() * Defs.ADULT_FU_PER_DAY * Defs.STORE_DAYS)

# 자정 부패 처리 (§4.2)
func apply_spoilage() -> void:
	var cap := food_cap()
	if food_fu > cap:
		var excess := food_fu - cap
		food_fu -= excess * Defs.SPOILAGE_RATE
		stock_changed.emit()

# ── 도구 풀 ───────────────────────────────────────────────
func craft_tool_to_pool(item: StringName) -> void:
	var dur: int = Defs.TOOLS[item]["durability"]
	tool_pool.append({"item": item, "dur": dur})

func return_tool(item: StringName, dur: int) -> void:
	tool_pool.append({"item": item, "dur": maxi(dur, 0)})

## 풀에서 특정 도구 하나 꺼내기 (내구 높은 것 우선)
func take_tool(item: StringName) -> Dictionary:
	var best_i := -1
	var best_dur := -1
	for i in tool_pool.size():
		if tool_pool[i]["item"] == item and tool_pool[i]["dur"] > best_dur:
			best_dur = tool_pool[i]["dur"]
			best_i = i
	if best_i >= 0:
		return tool_pool.pop_at(best_i)
	return {}

func tool_available(item: StringName) -> bool:
	for t in tool_pool:
		if t["item"] == item:
			return true
	return false

# ── 주택 ─────────────────────────────────────────────────
func empty_house():
	for b in buildings:
		if b.category == &"HOUSE" and b.built and b.road_connected and b.occupants.size() < b.capacity:
			return b
	return null

func house_count() -> int:
	var c := 0
	for b in buildings:
		if b.category == &"HOUSE":
			c += 1
	return c

func farm_for(villager_id: int):
	for b in buildings:
		if b.category == &"FARM" and b.assigned_to == villager_id:
			return b
	return null

func unassigned_farm():
	for b in buildings:
		if b.category == &"FARM" and b.built and b.assigned_to == -1:
			return b
	return null
