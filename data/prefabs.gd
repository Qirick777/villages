class_name Prefabs
extends RefCounted
## 프리팹 라이브러리 (계획서 §9.2). 가중 랜덤 + 직전 2회 중복 금지로 시각 다양성 확보.

static func houses() -> Array[BuildPrefab]:
	return [
		BuildPrefab.new(&"오두막", &"HOUSE", Vector2i(4, 4),
			{&"나무": 20, &"돌": 10}, 16.0, 1.0, 2, Color("#b07a4a")),
		BuildPrefab.new(&"기본형", &"HOUSE", Vector2i(5, 4),
			{&"나무": 20, &"돌": 10}, 16.0, 1.0, 3, Color("#a86f42")),
		BuildPrefab.new(&"L자형", &"HOUSE", Vector2i(6, 5),
			{&"나무": 24, &"돌": 12}, 18.0, 0.7, 4, Color("#9c6238")),
		BuildPrefab.new(&"2층집", &"HOUSE", Vector2i(5, 5),
			{&"나무": 30, &"돌": 15}, 20.0, 0.5, 5, Color("#8a5530")),
		BuildPrefab.new(&"롱하우스", &"HOUSE", Vector2i(7, 4),
			{&"나무": 24, &"돌": 12}, 18.0, 0.6, 4, Color("#a06840")),
	]

static func farms() -> Array[BuildPrefab]:
	return [
		BuildPrefab.new(&"소형밭", &"FARM", Vector2i(4, 4),
			{&"나무": 6}, 6.0, 1.0, 12, Color("#7a9e4a")),
		BuildPrefab.new(&"넓은밭", &"FARM", Vector2i(6, 3),
			{&"나무": 8}, 7.0, 0.8, 14, Color("#83a850")),
		BuildPrefab.new(&"안뜰밭", &"FARM", Vector2i(5, 5),
			{&"나무": 10}, 8.0, 0.6, 16, Color("#6f9243")),
	]

## 가중 랜덤 선택 (직전 2회 프리팹 id 회피).
static func pick_weighted(pool: Array[BuildPrefab], recent: Array) -> BuildPrefab:
	var candidates: Array[BuildPrefab] = []
	for p in pool:
		if not recent.has(p.id):
			candidates.append(p)
	if candidates.is_empty():
		candidates = pool
	var total := 0.0
	for p in candidates:
		total += p.weight
	var roll := RNGService.randf() * total
	var acc := 0.0
	for p in candidates:
		acc += p.weight
		if roll <= acc:
			return p
	return candidates[-1]
