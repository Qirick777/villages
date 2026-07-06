extends Node
## 절차적 맵 생성 싱글톤 (계획서 §3). 시드 기반 결정론.
## 성능을 위해 기본 맵 크기를 96×96으로 두되 상수로 조정 가능(계획서 목표 256×256).

signal map_generated()

enum Biome { WATER, SAND, GRASS, FOREST, ROCK }

const MAP_W: int = 96
const MAP_H: int = 96

# 자원 노드 종류
enum Res { TREE, STONE, IRON, COAL, ANIMAL }

var biome: PackedByteArray = PackedByteArray()   # MAP_W*MAP_H
var height: PackedFloat32Array = PackedFloat32Array()
var moisture: PackedFloat32Array = PackedFloat32Array()

# 자원 노드: key = Vector2i(cell) -> {type, amount}
var resources: Dictionary = {}
var start_cell: Vector2i = Vector2i(MAP_W / 2, MAP_H / 2)

func idx(x: int, y: int) -> int:
	return y * MAP_W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < MAP_W and y >= 0 and y < MAP_H

func get_biome(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Biome.WATER
	return biome[idx(x, y)]

func is_land(x: int, y: int) -> bool:
	var b := get_biome(x, y)
	return b != Biome.WATER

func generate(s: int) -> void:
	RNGService.reseed(s)
	biome.resize(MAP_W * MAP_H)
	height.resize(MAP_W * MAP_H)
	moisture.resize(MAP_W * MAP_H)
	resources.clear()

	_pass_height(s)
	_pass_moisture(s)
	_pass_biome()
	_pass_rivers(s)
	_pass_smooth()
	_pass_scatter()
	_pick_start()
	map_generated.emit()

# 패스1: 고도맵 (FBM)
func _pass_height(s: int) -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.02
	n.seed = s
	for y in MAP_H:
		for x in MAP_W:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			# 가장자리를 낮춰 섬 형태 유도
			var cx := float(x) / MAP_W - 0.5
			var cy := float(y) / MAP_H - 0.5
			var edge := 1.0 - clampf((cx * cx + cy * cy) * 3.2, 0.0, 1.0)
			height[idx(x, y)] = clampf(v * 0.6 + edge * 0.4, 0.0, 1.0)

# 패스2: 습도맵
func _pass_moisture(s: int) -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.05
	n.seed = s + 1
	for y in MAP_H:
		for x in MAP_W:
			moisture[idx(x, y)] = n.get_noise_2d(x, y) * 0.5 + 0.5

# 패스3: 바이옴 판정
func _pass_biome() -> void:
	for y in MAP_H:
		for x in MAP_W:
			var i := idx(x, y)
			var h := height[i]
			var m := moisture[i]
			var b: int
			if h < 0.30:
				b = Biome.WATER
			elif h < 0.34:
				b = Biome.SAND
			elif h > 0.68 and m < 0.4:
				b = Biome.ROCK
			elif m > 0.55 and h > 0.36 and h < 0.66:
				b = Biome.FOREST
			else:
				b = Biome.GRASS
			biome[i] = b

# 패스4: 강 생성 (최급강하 + 랜덤 워크)
func _pass_rivers(_s: int) -> void:
	var sources: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for y in range(2, MAP_H - 2):
		for x in range(2, MAP_W - 2):
			if height[idx(x, y)] > 0.72:
				candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var n_rivers := RNGService.randi_range(2, 4)
	for k in mini(n_rivers, candidates.size()):
		sources.append(candidates[k])

	for src in sources:
		var cur := src
		var guard := 0
		while guard < MAP_W * 2:
			guard += 1
			if get_biome(cur.x, cur.y) == Biome.WATER:
				break
			biome[idx(cur.x, cur.y)] = Biome.WATER
			# 최급강하 이웃 탐색
			var best := cur
			var best_h := height[idx(cur.x, cur.y)]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := cur.x + dx
					var ny := cur.y + dy
					if in_bounds(nx, ny) and height[idx(nx, ny)] < best_h:
						best_h = height[idx(nx, ny)]
						best = Vector2i(nx, ny)
			# 15% 랜덤 워크
			if RNGService.chance(0.15) or best == cur:
				var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
				best = cur + dirs[RNGService.randi_range(0, 3)]
			if not in_bounds(best.x, best.y):
				break
			cur = best

# 패스5: 셀룰러 오토마타 스무딩 2패스
func _pass_smooth() -> void:
	for _pass in 2:
		var snapshot := biome.duplicate()
		for y in range(1, MAP_H - 1):
			for x in range(1, MAP_W - 1):
				var counts := {}
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var b: int = snapshot[idx(x + dx, y + dy)]
						counts[b] = counts.get(b, 0) + 1
				for b in counts:
					if counts[b] >= 5:
						biome[idx(x, y)] = b
						break

# 패스7: 개체 배치 (포아송 근사 + 광맥 클러스터)
func _pass_scatter() -> void:
	# 나무 — 숲 바이옴에 간격 두고 배치
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if get_biome(x, y) == Biome.FOREST and RNGService.chance(0.28):
				if not _has_neighbor_resource(x, y):
					resources[Vector2i(x, y)] = {"type": Res.TREE, "amount": 4}
	# 광맥 — 바위지대 클러스터 (철:석탄:돌 ≈ 2:1:6)
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if get_biome(x, y) == Biome.ROCK and RNGService.chance(0.25):
				if _has_neighbor_resource(x, y):
					continue
				var r := RNGService.randf()
				var cell := Vector2i(x, y)
				if r < 0.22:
					resources[cell] = {"type": Res.IRON, "amount": 80}
				elif r < 0.33:
					resources[cell] = {"type": Res.COAL, "amount": 60}
				else:
					resources[cell] = {"type": Res.STONE, "amount": 200}
	# 야생동물 — 초원 스폰
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if get_biome(x, y) == Biome.GRASS and RNGService.chance(0.015):
				if not _has_neighbor_resource(x, y):
					resources[Vector2i(x, y)] = {"type": Res.ANIMAL, "amount": 1}

func _has_neighbor_resource(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if resources.has(Vector2i(x + dx, y + dy)):
				return true
	return false

# 시작지 선정 — 평지·강·숲·바위 근접 점수 (§3.2, 간이판)
func _pick_start() -> void:
	var best_score := -1.0
	var best := Vector2i(MAP_W / 2, MAP_H / 2)
	var win := 12
	for y in range(win, MAP_H - win, 3):
		for x in range(win, MAP_W - win, 3):
			if not is_land(x, y):
				continue
			var flat := 0
			var near_water := 0
			var samples := 0
			for dy in range(-6, 7, 2):
				for dx in range(-6, 7, 2):
					samples += 1
					var b := get_biome(x + dx, y + dy)
					if b == Biome.GRASS or b == Biome.SAND:
						flat += 1
					elif b == Biome.WATER:
						near_water += 1
			var flat_ratio := float(flat) / samples
			if flat_ratio < 0.55:
				continue
			var score := flat_ratio * 0.6 + (0.4 if near_water > 0 else 0.0)
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	start_cell = best
	# 시작지 주변을 확실히 초원으로 정리하고 자원 제거
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := Vector2i(best.x + dx, best.y + dy)
			if in_bounds(c.x, c.y):
				if get_biome(c.x, c.y) == Biome.WATER:
					continue
				biome[idx(c.x, c.y)] = Biome.GRASS
				resources.erase(c)

# 자원 채취 처리 — 채취 시 amount 감소, 0이면 노드 제거하고 위치 반환
func harvest(cell: Vector2i, amount: int) -> int:
	if not resources.has(cell):
		return 0
	var node: Dictionary = resources[cell]
	var got: int = mini(amount, node["amount"])
	node["amount"] -= got
	if node["amount"] <= 0:
		resources.erase(cell)
	return got

# 특정 타입의 가장 가까운 자원 노드 검색
func nearest_resource(from: Vector2i, res_type: int, max_r: int = 60) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := max_r * max_r + 1
	for cell in resources:
		if resources[cell]["type"] != res_type:
			continue
		var d: int = (cell.x - from.x) * (cell.x - from.x) + (cell.y - from.y) * (cell.y - from.y)
		if d < best_d:
			best_d = d
			best = cell
	return best
