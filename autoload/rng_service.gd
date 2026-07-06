extends Node
## 시드 관리 싱글톤 (계획서 §1.4). 모든 랜덤은 여기서만 뽑아 결정론을 보장한다.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0

func _ready() -> void:
	# 기본 시드 (UI에서 재설정 가능)
	reseed(12345)

func reseed(s: int) -> void:
	seed_value = s
	_rng.seed = s
	_rng.state = s

func randi() -> int:
	return _rng.randi()

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func chance(p: float) -> bool:
	return _rng.randf() < p

## 별도 시드로 파생 RNG (맵 노이즈 습도맵 등 seed+1 용)
func derived_seed(offset: int) -> int:
	return seed_value + offset
