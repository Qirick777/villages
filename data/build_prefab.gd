class_name BuildPrefab
extends RefCounted
## 건축 프리팹 정의 (계획서 §9.1). 실제 게임에선 Godot Resource/JSON으로 로드하나,
## 초기 탑재분은 코드 테이블(Prefabs.gd)로 제공한다.

var id: StringName = &""
var category: StringName = &""      # HOUSE / FARM / HALL_EXT
var size: Vector2i = Vector2i(4, 4) # 점유 타일
var cost: Dictionary = {}           # {"나무":20, "돌":10}
var labor_hours: float = 8.0
var weight: float = 1.0             # 랜덤 선택 가중치
var capacity: int = 2               # HOUSE=거주정원 / FARM=경작타일수
var color: Color = Color.WHITE      # 플레이스홀더 렌더 색

func _init(p_id: StringName, p_cat: StringName, p_size: Vector2i,
		p_cost: Dictionary, p_labor: float, p_weight: float,
		p_capacity: int, p_color: Color) -> void:
	id = p_id
	category = p_cat
	size = p_size
	cost = p_cost
	labor_hours = p_labor
	weight = p_weight
	capacity = p_capacity
	color = p_color
