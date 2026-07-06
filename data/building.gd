class_name Building
extends RefCounted
## 건물/건축 부지 상태 (계획서 §9). 회관·주택·밭 공통.

var category: StringName = &"HOUSE"  # HOUSE / FARM / HALL / HALL_EXT
var cell: Vector2i = Vector2i.ZERO   # 좌상단 점유 셀
var size: Vector2i = Vector2i(4, 4)
var prefab: BuildPrefab = null
var color: Color = Color("#a86f42")

# 건축 진행
var built: bool = false
var labor_done: float = 0.0
var labor_needed: float = 16.0
var cost: Dictionary = {}
var delivered: Dictionary = {}       # 현장 도착 자재
var road_connected: bool = false     # 밭은 항상 true 처리

# 주택
var capacity: int = 2
var occupants: Array = []            # villager id

# 밭
var assigned_to: int = -1
var worked_today: bool = false

# 건축 요청 추적
var build_req_id: int = -1
var view = null                      # EntityView 노드 참조

func center() -> Vector2i:
	return cell + size / 2

## 자재가 모두 도착했는가
func materials_ready() -> bool:
	for mat in cost:
		if delivered.get(mat, 0) < cost[mat]:
			return false
	return true

func deliver(mat: StringName, qty: int) -> void:
	delivered[mat] = delivered.get(mat, 0) + qty

## 부족 자재 목록
func missing_materials() -> Dictionary:
	var m := {}
	for mat in cost:
		var lack: int = cost[mat] - delivered.get(mat, 0)
		if lack > 0:
			m[mat] = lack
	return m

func progress() -> float:
	if labor_needed <= 0.0:
		return 1.0
	return clampf(labor_done / labor_needed, 0.0, 1.0)

func stage_index() -> int:
	var p := progress()
	if p < 0.34: return 0   # 기초 / 말뚝
	elif p < 0.9: return 1  # 골조 / 울타리
	else: return 2          # 완성 / 경작지

static func from_prefab(p: BuildPrefab, at: Vector2i) -> Building:
	var b := Building.new()
	b.category = p.category
	b.cell = at
	b.size = p.size
	b.prefab = p
	b.color = p.color
	b.cost = p.cost.duplicate()
	b.labor_needed = p.labor_hours
	b.capacity = p.capacity
	b.road_connected = (p.category == &"FARM")  # 밭은 도로 불요(§9.3)
	return b
