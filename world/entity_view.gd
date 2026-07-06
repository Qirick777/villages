extends Node2D
## 자원 노드/건물의 아이소메트릭 시각 표현.
## 건물은 실제 점유 타일 크기에서 아이소 박스(명암 벽 + 지붕 + 창문 + 문)를 생성.

enum Kind { TREE, ORE, HALL, HOUSE, FARM }

var kind: int = Kind.TREE
var building = null            # Building (HALL/HOUSE/FARM일 때)
var _windows: Array = []       # 밤에 점등되는 창문 Polygon2D
var _roof_seed: int = 0

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
	var cl: Vector2i = b.cell
	_roof_seed = abs(cl.x * 73856093 ^ cl.y * 19349663)
	match b.category:
		&"HALL", &"HALL_EXT": kind = Kind.HALL
		&"FARM": kind = Kind.FARM
		_: kind = Kind.HOUSE
	if kind != Kind.FARM and not GameClock.hour_changed.is_connected(_update_windows):
		GameClock.hour_changed.connect(_update_windows)
	refresh()

# ────────────────────────────────────────────────────────────
# 자연물
# ────────────────────────────────────────────────────────────
func _make_tree() -> void:
	_ellipse_shadow(11, 5, 0.25)
	var trunk := Polygon2D.new()
	trunk.polygon = PackedVector2Array([Vector2(-2.5,0), Vector2(2.5,0), Vector2(2,-15), Vector2(-2,-15)])
	trunk.color = Color("#5a3d24")
	add_child(trunk)
	# 3단 잎 (풍성하게)
	for spec in [[-13.0, 13.0, -34.0, "#3a6b32"], [-11.0, 11.0, -44.0, "#43793a"], [-8.0, 8.0, -52.0, "#4f8a44"]]:
		var leaf := Polygon2D.new()
		leaf.polygon = PackedVector2Array([
			Vector2(spec[0], spec[2] + 16.0), Vector2(spec[1], spec[2] + 16.0), Vector2(0, spec[2])])
		leaf.color = Color(spec[3])
		add_child(leaf)

func _make_ore(res_type: int) -> void:
	_ellipse_shadow(12, 5, 0.22)
	var base := Color("#9a9ea6")
	var gem := Color("#c8ccd4")
	if res_type == MapGen.Res.IRON:
		base = Color("#8a6b52"); gem = Color("#c99a78")
	elif res_type == MapGen.Res.COAL:
		base = Color("#33333a"); gem = Color("#55555f")
	var rock := Polygon2D.new()
	rock.polygon = PackedVector2Array([Vector2(-12,0), Vector2(-6,-9), Vector2(4,-13), Vector2(12,-4), Vector2(9,4), Vector2(-4,5)])
	rock.color = base
	add_child(rock)
	var vein := Polygon2D.new()
	vein.polygon = PackedVector2Array([Vector2(-2,-6), Vector2(3,-8), Vector2(5,-3), Vector2(0,-1)])
	vein.color = gem
	add_child(vein)

func _make_animal() -> void:
	_ellipse_shadow(8, 4, 0.22)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-8,-6), Vector2(6,-7), Vector2(8,-2), Vector2(-8,-1)])
	body.color = Color("#d8c4a0")
	add_child(body)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(6,-9), Vector2(11,-8), Vector2(10,-3), Vector2(6,-3)])
	head.color = Color("#c8b090")
	add_child(head)

func _ellipse_shadow(rx: float, ry: float, a: float) -> void:
	var s := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 12:
		var t := TAU * i / 12.0
		pts.append(Vector2(cos(t) * rx, sin(t) * ry))
	s.polygon = pts
	s.color = Color(0, 0, 0, a)
	add_child(s)

# ────────────────────────────────────────────────────────────
# 건물
# ────────────────────────────────────────────────────────────
func refresh() -> void:
	for c in get_children():
		c.queue_free()
	_windows.clear()
	if building == null:
		return

	var sz: Vector2i = building.size
	var built: bool = building.built
	var prog: float = building.progress()

	var tw := float(Iso.TILE_W)
	var th := float(Iso.TILE_H)
	var ex := Vector2(tw * 0.5, th * 0.5)
	var ey := Vector2(-tw * 0.5, th * 0.5)
	var hx := sz.x * 0.5
	var hy := sz.y * 0.5

	# 지면 다이아몬드 네 꼭짓점 (중심 기준)
	var p_top := -ex * hx - ey * hy
	var p_right := ex * hx - ey * hy
	var p_bottom := ex * hx + ey * hy
	var p_left := -ex * hx + ey * hy

	if kind == Kind.FARM:
		_draw_farm(p_top, p_right, p_bottom, p_left, built, prog)
		_add_label()
		return

	# 벽 높이 (건물 종류·크기별)
	var wall_h := 30.0 + (sz.x + sz.y) * 1.5
	if kind == Kind.HALL:
		wall_h = 52.0
	if not built:
		wall_h *= (0.25 + 0.75 * prog)   # 골조가 자라나는 연출
	var up := Vector2(0, -wall_h)

	var base_col: Color = building.color
	if not built:
		base_col = base_col.darkened(0.3)

	# 그림자 (지면에 드리움)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		p_top, p_right + Vector2(6, 3), p_bottom + Vector2(6, 3), p_left])
	shadow.color = Color(0, 0, 0, 0.18)
	add_child(shadow)

	# 지면 기초(석재)
	_poly([p_top, p_right, p_bottom, p_left], Color("#6b6157"))

	# 벽: 왼쪽(그늘) / 오른쪽(햇빛) 두 면으로 볼륨
	var wall_light := base_col
	var wall_shade := base_col.darkened(0.28)
	_poly([p_left, p_bottom, p_bottom + up, p_left + up], wall_shade)   # 좌면(그늘)
	_poly([p_bottom, p_right, p_right + up, p_bottom + up], wall_light) # 우면(빛)
	# 벽 모서리 하이라이트
	_line([p_bottom + up, p_bottom], Color(1, 1, 1, 0.12), 2.0)

	# 창문 + 문 (완공 시)
	if built:
		_add_openings(p_left, p_bottom, p_right, up, wall_h)

	# 지붕
	var t2 := p_top + up
	var r2 := p_right + up
	var b2 := p_bottom + up
	var l2 := p_left + up
	var roof_h := wall_h * 0.5 + 8.0
	var apex := (t2 + r2 + b2 + l2) * 0.25 + Vector2(0, -roof_h)
	var roof := _roof_color()
	# 뒤 → 앞 순서로 그려 겹침 정렬
	_poly([t2, l2, apex], roof.darkened(0.32))    # 뒤좌
	_poly([t2, r2, apex], roof.darkened(0.18))    # 뒤우
	_poly([l2, b2, apex], roof.darkened(0.10))    # 앞좌
	_poly([b2, r2, apex], roof.lightened(0.10))   # 앞우(빛)
	# 지붕 능선 하이라이트
	_line([l2, apex], roof.lightened(0.25), 1.5)
	_line([r2, apex], roof.lightened(0.25), 1.5)

	_add_label()
	_update_windows(0, 0)

func _add_openings(p_left: Vector2, p_bottom: Vector2, p_right: Vector2, up: Vector2, wall_h: float) -> void:
	# 문 (앞 하단, 바텀 꼭짓점 부근)
	var door_base := p_bottom
	var dw := Vector2(7, 3)
	var door := Polygon2D.new()
	door.polygon = PackedVector2Array([
		door_base - dw, door_base + dw,
		door_base + dw + Vector2(0, -wall_h * 0.55),
		door_base - dw + Vector2(0, -wall_h * 0.55)])
	door.color = Color("#2f2016")
	add_child(door)

	# 창문 2개 (좌면·우면 각 1개), 밤에 점등
	var wl := _mid(p_left, p_bottom) + Vector2(0, -wall_h * 0.6)
	var wr := _mid(p_bottom, p_right) + Vector2(0, -wall_h * 0.6)
	for wp in [wl, wr]:
		var win := Polygon2D.new()
		win.polygon = PackedVector2Array([
			wp + Vector2(-4, 3), wp + Vector2(4, 3), wp + Vector2(4, -5), wp + Vector2(-4, -5)])
		win.color = Color("#3a4a63")
		add_child(win)
		_windows.append(win)

func _draw_farm(p_top: Vector2, p_right: Vector2, p_bottom: Vector2, p_left: Vector2, built: bool, prog: float) -> void:
	# 갈아엎은 흙
	var soil := Color("#6b4a2f") if built else Color("#5a4636")
	_poly([p_top, p_right, p_bottom, p_left], soil)
	# 이랑(furrow) 라인
	for i in range(1, 5):
		var t := i / 5.0
		var a := p_top.lerp(p_left, t)
		var bpt := p_right.lerp(p_bottom, t)
		_line([a, bpt], Color(0, 0, 0, 0.15), 1.5)
	# 작물 (완공 시 초록 점)
	if built:
		for i in range(1, 5):
			for j in range(1, 4):
				var u := p_top.lerp(p_right, i / 5.0)
				var v := p_left.lerp(p_bottom, i / 5.0)
				var cpt := u.lerp(v, j / 4.0)
				var crop := Polygon2D.new()
				crop.polygon = PackedVector2Array([
					cpt + Vector2(0, -6), cpt + Vector2(3, 0), cpt + Vector2(-3, 0)])
				crop.color = Color("#5ea23f")
				add_child(crop)
	# 울타리 말뚝 (네 꼭짓점 + 변 중앙)
	for corner in [p_top, p_right, p_bottom, p_left,
			_mid(p_top, p_right), _mid(p_right, p_bottom),
			_mid(p_bottom, p_left), _mid(p_left, p_top)]:
		var post := Polygon2D.new()
		post.polygon = PackedVector2Array([
			corner + Vector2(-1.5, 0), corner + Vector2(1.5, 0),
			corner + Vector2(1.5, -9), corner + Vector2(-1.5, -9)])
		post.color = Color("#7a5a3a")
		add_child(post)
	if not built:
		# 미완공: 진행률 흐리게
		modulate = Color(1, 1, 1, 0.55 + 0.45 * prog)
	else:
		modulate = Color(1, 1, 1, 1)

# 밤에 창문 점등
func _update_windows(_day: int, _hour: int) -> void:
	if _windows.is_empty():
		return
	var f := GameClock.day_fraction()
	var lit := f < 0.28 or f > 0.74     # 새벽 전 / 해질녘 이후
	var col := Color("#ffd98a") if lit else Color("#3a4a63")
	for w in _windows:
		if is_instance_valid(w):
			w.color = col

# ── 헬퍼 ──
func _poly(pts: Array, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array(pts)
	p.color = col
	add_child(p)

func _line(pts: Array, col: Color, w: float) -> void:
	var l := Line2D.new()
	l.points = PackedVector2Array(pts)
	l.width = w
	l.default_color = col
	add_child(l)

func _mid(a: Vector2, b: Vector2) -> Vector2:
	return (a + b) * 0.5

func _roof_color() -> Color:
	var palette: Array[Color] = [
		Color("#b5533f"), Color("#a5654a"), Color("#6f7d8c"), Color("#8a6d4a")]
	return palette[_roof_seed % palette.size()]

func _add_label() -> void:
	var label := Label.new()
	label.text = _building_name()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.position = Vector2(-26, -1)
	# 라벨은 건물 위로: 대략 지붕 높이만큼 올림
	var lift := 64.0 if kind == Kind.HALL else 46.0
	if kind == Kind.FARM:
		lift = 20.0
	label.position = Vector2(-26, -lift)
	add_child(label)

func _building_name() -> String:
	var b = building
	if kind == Kind.HALL:
		return "🏛 회관"
	if kind == Kind.FARM:
		return "🌾 밭" if b.built else "🚧 밭 %d%%" % int(b.progress() * 100)
	return "🏠 집" if b.built else "🚧 집 %d%%" % int(b.progress() * 100)
