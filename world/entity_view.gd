extends Node2D
## 자원 노드/건물 등 정적 엔티티의 간단한 아이소메트릭 시각 표현.

enum Kind { TREE, ORE, HALL, HOUSE, FARM }

var kind: int = Kind.TREE
var building = null           # Building (HALL/HOUSE/FARM일 때)

func setup_resource(res_type: int, cell: Vector2i) -> void:
	position = Iso.cell_to_world(cell)
	# 오토로드 enum(MapGen.Res.*)은 match 상수 패턴으로 못 쓰므로 if/elif로 분기.
	if res_type == MapGen.Res.TREE:
		kind = Kind.TREE
		_make_tree()
	elif res_type == MapGen.Res.ANIMAL:
		_make_animal()
	else:
		kind = Kind.ORE
		_make_ore(res_type)

func setup_building(b) -> void:
	building = b
	position = Iso.cell_to_world(b.center())
	match b.category:
		&"HALL", &"HALL_EXT": kind = Kind.HALL
		&"FARM": kind = Kind.FARM
		_: kind = Kind.HOUSE
	refresh()

func _make_tree() -> void:
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-10,0), Vector2(0,5), Vector2(10,0), Vector2(0,-5)])
	shadow.color = Color(0,0,0,0.25)
	add_child(shadow)
	var trunk := Polygon2D.new()
	trunk.polygon = PackedVector2Array([Vector2(-2,0), Vector2(2,0), Vector2(2,-14), Vector2(-2,-14)])
	trunk.color = Color("#5a3d24")
	add_child(trunk)
	var crown := Polygon2D.new()
	crown.polygon = PackedVector2Array([Vector2(0,-38), Vector2(11,-14), Vector2(-11,-14)])
	crown.color = Color("#2f5e2a")
	add_child(crown)

func _make_ore(res_type: int) -> void:
	var rock := Polygon2D.new()
	rock.polygon = PackedVector2Array([Vector2(-11,0), Vector2(0,6), Vector2(11,0), Vector2(6,-12), Vector2(-6,-12)])
	if res_type == MapGen.Res.IRON:
		rock.color = Color("#a6785a")
	elif res_type == MapGen.Res.COAL:
		rock.color = Color("#3a3a40")
	else:
		rock.color = Color("#9a9ea6")
	add_child(rock)

func _make_animal() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-7,-6), Vector2(7,-6), Vector2(7,-1), Vector2(-7,-1)])
	body.color = Color("#c8b090")
	add_child(body)

func refresh() -> void:
	for c in get_children():
		c.queue_free()
	if building == null:
		return
	var b = building
	var footprint: float = (b.size.x + b.size.y) * (Iso.TILE_W / 4.0)
	# 그림자
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-footprint*0.5,0), Vector2(0,footprint*0.25),
		Vector2(footprint*0.5,0), Vector2(0,-footprint*0.25)])
	shadow.color = Color(0,0,0,0.22)
	add_child(shadow)

	var col: Color = b.color
	var h := 26.0
	if kind == Kind.HALL:
		col = Color("#b08a4a"); h = 40.0
	elif kind == Kind.FARM:
		col = Color("#7a9e4a"); h = 6.0
	if not b.built:
		col = col.darkened(0.35)
		h *= (0.3 + 0.7 * b.progress())

	# 벽 (하단 어둡게, 상단 밝게 — 볼륨감)
	var wall := Polygon2D.new()
	wall.polygon = PackedVector2Array([
		Vector2(-footprint*0.5,0), Vector2(0,footprint*0.25),
		Vector2(footprint*0.5,0), Vector2(footprint*0.5,-h),
		Vector2(0,footprint*0.25-h), Vector2(-footprint*0.5,-h)])
	wall.color = col
	add_child(wall)

	if kind != Kind.FARM and b.built:
		var roof := Polygon2D.new()
		roof.polygon = PackedVector2Array([
			Vector2(-footprint*0.5,-h), Vector2(0,footprint*0.25-h),
			Vector2(footprint*0.5,-h), Vector2(0,-h-18)])
		roof.color = col.lightened(0.25)
		add_child(roof)
		# 문 (정면)
		var door := Polygon2D.new()
		door.polygon = PackedVector2Array([
			Vector2(-4, 0), Vector2(4, 2), Vector2(4, -12), Vector2(-4, -14)])
		door.color = Color("#3a2a1a")
		add_child(door)

	# 이름표
	var label := Label.new()
	label.text = _building_name(b)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-footprint * 0.4, -h - 34)
	add_child(label)

func _building_name(b) -> String:
	if kind == Kind.HALL:
		return "🏛 회관"
	if kind == Kind.FARM:
		var crop := "🌾 밭"
		if not b.built:
			crop = "🚧 밭 %d%%" % int(b.progress() * 100)
		return crop
	if not b.built:
		return "🚧 집 %d%%" % int(b.progress() * 100)
	return "🏠 집"
