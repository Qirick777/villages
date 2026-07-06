extends CanvasLayer
## UI/디버그 오버레이 (계획서 §12): 시계·배속, 자원 패널, 직업 압력 막대그래프,
## 요청 큐 요약, 시드 입력/재생성.

signal regenerate_requested(seed_value: int)

var _time_label: Label
var _stock_label: Label
var _pressure_box: VBoxContainer
var _request_label: Label
var _seed_edit: LineEdit
var _speed_label: Label

func _ready() -> void:
	_build()
	GameClock.minute_changed.connect(_on_minute)
	Village.stock_changed.connect(_refresh_stock)
	PressureBoard.pressure_updated.connect(_refresh_pressure)

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(240, 0)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 16)
	vb.add_child(_time_label)

	# 배속 버튼
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for spec in [["⏸", GameClock.Speed.PAUSE], ["×1", GameClock.Speed.X1],
			["×2", GameClock.Speed.X2], ["×4", GameClock.Speed.X4], ["×8", GameClock.Speed.X8]]:
		var btn := Button.new()
		btn.text = spec[0]
		var sp: int = spec[1]
		btn.pressed.connect(func(): GameClock.set_speed(sp))
		hb.add_child(btn)
	_speed_label = Label.new()
	vb.add_child(_speed_label)

	_stock_label = Label.new()
	vb.add_child(_stock_label)

	var pl := Label.new()
	pl.text = "── 직업 압력 (P) ──"
	vb.add_child(pl)
	_pressure_box = VBoxContainer.new()
	vb.add_child(_pressure_box)

	_request_label = Label.new()
	vb.add_child(_request_label)

	# 시드 입력
	var sb := HBoxContainer.new()
	vb.add_child(sb)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(RNGService.seed_value)
	_seed_edit.custom_minimum_size = Vector2(90, 0)
	sb.add_child(_seed_edit)
	var regen := Button.new()
	regen.text = "재생성"
	regen.pressed.connect(func():
		regenerate_requested.emit(_seed_edit.text.to_int()))
	sb.add_child(regen)

	_refresh_stock()

func _on_minute(_day: int, _minute: int) -> void:
	_time_label.text = GameClock.time_string() + "  (인구 %d)" % Village.population()
	_speed_label.text = "배속: ×%s  요청:%d" % [
		["0","1","2","4","8"][GameClock.speed], RequestBroker.total_open()]

func _refresh_stock() -> void:
	if not _stock_label:
		return
	_stock_label.text = "🍖식량 %d/%d  🪵%d 🪨%d ⛏철%d 🔥%d" % [
		int(Village.food_fu), int(Village.food_cap()),
		Village.res.get(&"나무", 0), Village.res.get(&"돌", 0),
		Village.res.get(&"철", 0), Village.res.get(&"석탄", 0)]

func _refresh_pressure(P: Dictionary) -> void:
	for c in _pressure_box.get_children():
		c.queue_free()
	var maxp := 1.0
	for j in P:
		maxp = maxf(maxp, P[j])
	var counts := Village.job_counts()
	for j in Defs.JOBS:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 11)
		var bars := int((P[j] / maxp) * 16.0)
		row.text = "%s(%d) %s %d" % [j, counts.get(j, 0), "█".repeat(bars), int(P[j])]
		row.add_theme_color_override("font_color", Defs.JOB_COLORS.get(j, Color.WHITE))
		_pressure_box.add_child(row)
