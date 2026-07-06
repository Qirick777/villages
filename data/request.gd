class_name Request
extends RefCounted
## 수요 시스템의 기본 단위 (계획서 §6.1).
## 주민이 필요를 느끼면 RequestBroker에 POST하고, 공급자가 pull하여 처리한다.

enum State { POSTED, CLAIMED, FULFILLED, MERGED }

var id: int = 0
var item: StringName = &""          # "곡괭이", "나무", "FOOD", "건축", "도로" ...
var qty: int = 1
var requester_id: int = -1
var provider_job: StringName = &""  # 이 요청을 처리할 직업
var base_priority: int = 0
var chain_id: int = 0               # 파생 요청 추적용 (루트 요청 id)
var created_day: int = 0
var state: int = State.POSTED
var claimed_by: int = -1
var payload: Dictionary = {}        # 부가 정보 (건축 대상 위치 등)

func _init(p_id: int, p_item: StringName, p_qty: int, p_requester: int,
		p_provider: StringName, p_pri: int, p_chain: int, p_day: int) -> void:
	id = p_id
	item = p_item
	qty = p_qty
	requester_id = p_requester
	provider_job = p_provider
	base_priority = p_pri
	chain_id = p_chain if p_chain != 0 else p_id
	created_day = p_day

## 에이징 반영 유효 우선순위 (§6.3)
func effective_priority(current_day: int) -> int:
	var age := maxi(0, current_day - created_day)
	var eff := int(base_priority * (1.0 + Defs.AGING_RATE * age))
	return mini(eff, Defs.PRI_CAP)

func _to_string() -> String:
	return "Request#%d[%s x%d -> %s pri=%d state=%d]" % [
		id, item, qty, provider_job, base_priority, state]
