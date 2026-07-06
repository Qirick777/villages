extends Node
## 시간/배속/스케줄 신호 발행 싱글톤 (계획서 §2).
## 0.5초 고정 틱으로 갱신, 배속은 틱 간격만 축소 → 결정론 유지.

signal minute_changed(day: int, minute: int)
signal hour_changed(day: int, hour: int)
signal day_changed(day: int)            # 자정 (압력 갱신·부패 트리거)
signal phase_changed(phase: StringName) # WAKE / MEETING_AM / WORK_AM ...
signal tick(day: int, minute: int)      # 0.5s 시뮬레이션 틱

enum Speed { PAUSE, X1, X2, X4, X8 }

var day: int = 1
var minute: int = Defs.T_WAKE           # 06:00에서 시작
var speed: int = Speed.X1
var phase: StringName = &"WAKE"

var _accum: float = 0.0
var _prev_hour: int = -1
var _minute_frac: float = 0.0

# 배속별 시뮬 배수
const SPEED_MULT := {
	Speed.PAUSE: 0.0, Speed.X1: 1.0, Speed.X2: 2.0, Speed.X4: 4.0, Speed.X8: 8.0,
}

func _process(delta: float) -> void:
	var mult: float = SPEED_MULT[speed]
	if mult <= 0.0:
		return
	_accum += delta * mult
	while _accum >= Defs.TICK_SECONDS:
		_accum -= Defs.TICK_SECONDS
		_advance_tick()

func _advance_tick() -> void:
	# tick 신호는 매 0.5초마다 발행(이동·생산 구동). 게임 분은 소수부를 누적해
	# 하루 = 1200초를 정확히 유지한다(틱당 ≈0.6분).
	tick.emit(day, minute)

	_minute_frac += (Defs.TICK_SECONDS / Defs.DAY_SECONDS) * Defs.MINUTES_PER_DAY
	var whole := int(_minute_frac)
	if whole <= 0:
		return
	_minute_frac -= whole
	minute += whole

	var rolled_day := false
	while minute >= Defs.MINUTES_PER_DAY:
		minute -= Defs.MINUTES_PER_DAY
		day += 1
		rolled_day = true

	minute_changed.emit(day, minute)

	var h := minute / 60
	if h != _prev_hour:
		_prev_hour = h
		hour_changed.emit(day, h)

	_update_phase()

	if rolled_day:
		day_changed.emit(day)

func _update_phase() -> void:
	var new_phase: StringName
	if minute < Defs.T_WAKE:
		new_phase = &"SLEEP"
	elif minute < Defs.T_MEETING_AM_END:
		new_phase = &"MEETING_AM"
	elif minute < Defs.T_MEETING_NOON:
		new_phase = &"WORK_AM"
	elif minute < Defs.T_MEETING_NOON_END:
		new_phase = &"MEETING_NOON"
	elif minute < Defs.T_WORK_PM_END:
		new_phase = &"WORK_PM"
	elif minute < Defs.T_REST_END:
		new_phase = &"REST"
	else:
		new_phase = &"SLEEP"
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)

func set_speed(s: int) -> void:
	speed = clampi(s, 0, Speed.X8)

func time_string() -> String:
	return "Day %d  %02d:%02d" % [day, minute / 60, minute % 60]

## 현재 정규화된 하루 진행도 (0~1), 주야 연출용
func day_fraction() -> float:
	return float(minute) / float(Defs.MINUTES_PER_DAY)
