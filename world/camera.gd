extends Camera2D
## 마우스 엣지/드래그 이동 + 휠 줌 (계획서 §1.1).

var _drag := false
var _drag_start := Vector2.ZERO
var _cam_start := Vector2.ZERO

func _ready() -> void:
	zoom = Vector2(1, 1)
	make_current()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_by(1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_by(1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_drag = e.pressed
			_drag_start = e.position
			_cam_start = position
	elif e is InputEventMouseMotion and _drag:
		position = _cam_start + (_drag_start - e.position) / zoom.x

func _zoom_by(f: float) -> void:
	var z := clampf(zoom.x * f, 0.5, 2.0)
	zoom = Vector2(z, z)

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("cam_pan_left"): dir.x -= 1
	if Input.is_action_pressed("cam_pan_right"): dir.x += 1
	if Input.is_action_pressed("cam_pan_up"): dir.y -= 1
	if Input.is_action_pressed("cam_pan_down"): dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * 500.0 * delta / zoom.x
