class_name NameGen
extends RefCounted
## 시드 기반 이름 생성 (계획서 §8.3). 성 12 × 이름 40 풀.

const FAMILIES := [
	"바람", "돌", "강", "숲", "언덕", "샘", "들", "이슬",
	"별", "노을", "바위", "달",
]

const GIVEN := [
	"아라", "노아", "리안", "세나", "카이", "미르", "여울", "하루",
	"소리", "다온", "루아", "가온", "은솔", "지오", "라온", "새힘",
	"보라", "한별", "누리", "재이", "슬기", "온유", "예린", "도담",
	"하람", "가랑", "무늬", "빛나", "초아", "라움", "단이", "여름",
	"바다", "구름", "나래", "이든", "서리", "고운", "다랑", "포도",
]

static func family() -> String:
	return FAMILIES[RNGService.randi_range(0, FAMILIES.size() - 1)]

static func given() -> String:
	return GIVEN[RNGService.randi_range(0, GIVEN.size() - 1)]
