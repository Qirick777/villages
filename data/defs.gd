class_name Defs
extends RefCounted
## 게임 전역 상수·정의 테이블 (계획서 §2, §4, §5, §6 수치화).
## 모든 밸런싱 상수를 한 곳에 모아 M6 밸런싱 단계에서 조정하기 쉽게 한다.

# ─────────────────────────────────────────────────────────────
# 시간 (§2)
# ─────────────────────────────────────────────────────────────
const DAY_SECONDS: float = 1200.0          # 현실 20분 = 게임 하루
const MINUTES_PER_DAY: int = 1440
const TICK_SECONDS: float = 0.5            # 고정 시뮬레이션 틱

# 일과 경계 (게임 분 단위)
const T_WAKE: int = 6 * 60
const T_MEETING_AM_END: int = 7 * 60 + 30
const T_MEETING_NOON: int = 12 * 60
const T_MEETING_NOON_END: int = 13 * 60
const T_WORK_PM_END: int = 18 * 60
const T_REST_END: int = 22 * 60

# ─────────────────────────────────────────────────────────────
# 직업 (§5)
# ─────────────────────────────────────────────────────────────
const JOB_FARMER := &"농부"
const JOB_HUNTER := &"사냥꾼"
const JOB_CARPENTER := &"목수"
const JOB_MINER := &"광부"
const JOB_ARTISAN := &"장인"
const JOB_BUILDER := &"건축가"
const JOB_MANAGER := &"관리자"
const JOB_GUARD := &"경비"

const JOBS: Array[StringName] = [
	JOB_FARMER, JOB_HUNTER, JOB_CARPENTER, JOB_MINER,
	JOB_ARTISAN, JOB_BUILDER, JOB_MANAGER, JOB_GUARD,
]

# 직업별 표시 색 (플레이스홀더 스프라이트 팔레트)
# Color("#hex")는 const 폴딩이 보장되지 않으므로 static var로 둔다.
static var JOB_COLORS: Dictionary = {
	JOB_FARMER: Color("#8ec06c"),
	JOB_HUNTER: Color("#b5732f"),
	JOB_CARPENTER: Color("#a0703c"),
	JOB_MINER: Color("#7f8896"),
	JOB_ARTISAN: Color("#c9a04a"),
	JOB_BUILDER: Color("#d0603c"),
	JOB_MANAGER: Color("#5c8adf"),
	JOB_GUARD: Color("#c33f3f"),
}

# 목표 구성비 (§6.6) — 임명 시 동률 판정용
const JOB_TARGET_RATIO: Dictionary = {
	JOB_FARMER: 0.25, JOB_HUNTER: 0.15, JOB_CARPENTER: 0.12, JOB_MINER: 0.12,
	JOB_ARTISAN: 0.10, JOB_BUILDER: 0.08, JOB_MANAGER: 0.10, JOB_GUARD: 0.10,
}

# ─────────────────────────────────────────────────────────────
# 식량 (§4.2)
# ─────────────────────────────────────────────────────────────
const ADULT_FU_PER_DAY: float = 3.0
const CHILD_FU_PER_DAY: float = 1.5
const START_FOOD_FU: float = 40.0
const STORE_DAYS: int = 5                   # 비축 상한 = 인구×3×5
const SPOILAGE_RATE: float = 0.10           # 자정 초과분 부패

# ─────────────────────────────────────────────────────────────
# 도구 (§4.3) — item -> {재료, 내구도, 사용직업}
# ─────────────────────────────────────────────────────────────
const TOOL_AXE := &"돌도끼"
const TOOL_STONE_PICK := &"돌곡괭이"
const TOOL_IRON_PICK := &"철곡괭이"
const TOOL_HOE := &"괭이"
const TOOL_BOW := &"활"
const TOOL_HAMMER := &"망치"
const TOOL_SPEAR := &"창"

const TOOLS: Dictionary = {
	TOOL_AXE:        {"cost": {&"나무": 2, &"돌": 2}, "durability": 60,  "user": JOB_CARPENTER},
	TOOL_STONE_PICK: {"cost": {&"나무": 2, &"돌": 3}, "durability": 50,  "user": JOB_MINER},
	TOOL_IRON_PICK:  {"cost": {&"나무": 2, &"철": 2}, "durability": 150, "user": JOB_MINER},
	TOOL_HOE:        {"cost": {&"나무": 2, &"돌": 1}, "durability": 80,  "user": JOB_FARMER},
	TOOL_BOW:        {"cost": {&"나무": 3},          "durability": 80,  "user": JOB_HUNTER},
	TOOL_HAMMER:     {"cost": {&"나무": 1, &"철": 1}, "durability": 120, "user": JOB_BUILDER},
	TOOL_SPEAR:      {"cost": {&"나무": 2, &"철": 1}, "durability": 100, "user": JOB_GUARD},
}

# 직업 -> 주 사용 도구
const JOB_PRIMARY_TOOL: Dictionary = {
	JOB_FARMER: TOOL_HOE,
	JOB_HUNTER: TOOL_BOW,
	JOB_CARPENTER: TOOL_AXE,
	JOB_MINER: TOOL_STONE_PICK,
	JOB_BUILDER: TOOL_HAMMER,
	JOB_GUARD: TOOL_SPEAR,
}

# ─────────────────────────────────────────────────────────────
# 요청 우선순위 (§6.3)
# ─────────────────────────────────────────────────────────────
const PRI_FOOD: int = 100
const PRI_TOOL_BROKEN: int = 80
const PRI_TOOL_PREVENTIVE: int = 60
const PRI_WEAPON: int = 55
const PRI_BUILD_MATERIAL: int = 50
const PRI_BUILD_HOUSE: int = 45
const PRI_ROAD: int = 40
const PRI_CLEAN: int = 20

const AGING_RATE: float = 0.25
const PRI_CAP: int = 200

# ─────────────────────────────────────────────────────────────
# 압력 이벤트 보너스 (§6.4)
# ─────────────────────────────────────────────────────────────
const P_DECAY: float = 0.5
const BONUS_HUNGRY: int = 120
const BONUS_MANAGER_OVERFLOW: int = 100
const BONUS_ROAD_WAIT: int = 60
const BONUS_COUPLE_NOHOUSE: int = 50
const BONUS_ARTISAN_CARRYOVER: int = 40
const BONUS_WOLF_ATTACK: int = 100
const BONUS_DEBRIS: int = 30
const BONUS_FARMER_NOFIELD: int = 40
const BONUS_FIELD_UNWORKED: int = 15
const BONUS_JOB_VACANCY: int = 80

# ─────────────────────────────────────────────────────────────
# 생애주기 (§8.2) — 나이(일) 경계
# ─────────────────────────────────────────────────────────────
const AGE_CHILD: int = 2
const AGE_TEEN: int = 4
const AGE_ADULT: int = 6
const AGE_ELDER: int = 60
const AGE_DEATH_MIN: int = 66
const AGE_DEATH_MAX: int = 72

const SPRITE_SCALE: Dictionary = {
	&"infant": 0.5, &"child": 0.7, &"teen": 0.85, &"adult": 1.0, &"elder": 1.0,
}

# 번식 (§8.1)
const COUPLE_GAUGE_PER_DAY: float = 34.0
const PREGNANCY_DAYS: int = 2
const REPRODUCE_COOLDOWN_DAYS: int = 5

# 맨손 효율 (§0 원칙1)
const BAREHAND_EFF: float = 0.25

# 하드 제약 (§6.5)
static func guard_quota(pop: int) -> int:
	return int(ceil(0.10 * pop))

static func manager_quota(pop: int) -> int:
	return int(ceil(pop / 10.0))

static func food_quota(pop: int) -> int:
	return int(ceil(0.35 * pop))

static func life_stage(age_days: int) -> StringName:
	if age_days < AGE_CHILD: return &"infant"
	elif age_days < AGE_TEEN: return &"child"
	elif age_days < AGE_ADULT: return &"teen"
	elif age_days < AGE_ELDER: return &"adult"
	else: return &"elder"

static func fu_consumption(age_days: int) -> float:
	var st := life_stage(age_days)
	match st:
		&"infant": return 1.0
		&"child": return CHILD_FU_PER_DAY
		&"teen": return 2.0
		_: return ADULT_FU_PER_DAY
