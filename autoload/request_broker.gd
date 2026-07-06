extends Node
## 수요 시스템의 심장 — 요청 게시판 (계획서 §6.2).
## 주민이 필요를 POST하고, 공급자가 우선순위 힙에서 pull하며, 재료 부족 시 하위 요청을 재귀 생성한다.

signal request_posted(req)
signal request_fulfilled(req)

var _next_id: int = 1
# 전체 요청 (id -> Request)
var requests: Dictionary = {}
# provider_job -> Array[Request id]  (미완 요청만)
var by_job: Dictionary = {}

func _ready() -> void:
	for j in Defs.JOBS:
		by_job[j] = []

func clear() -> void:
	_next_id = 1
	requests.clear()
	for j in Defs.JOBS:
		by_job[j] = []

## 요청 등록. 동일 chain 내 (item, provider) 중복은 병합(§6.2-4).
func post(item: StringName, qty: int, requester: int, provider: StringName,
		base_pri: int, chain: int = 0, payload: Dictionary = {}):
	# 순환 병합: 같은 chain의 미완 (item, provider) 요청이 있으면 수량 합산
	if chain != 0:
		for rid in by_job.get(provider, []):
			var r: Request = requests[rid]
			if r.chain_id == chain and r.item == item and r.state == Request.State.POSTED:
				r.qty += qty
				return r
	var req := Request.new(_next_id, item, qty, requester, provider, base_pri,
		chain, GameClock.day)
	req.payload = payload
	_next_id += 1
	requests[req.id] = req
	if not by_job.has(provider):
		by_job[provider] = []
	by_job[provider].append(req.id)
	request_posted.emit(req)
	return req

## 공급자가 자기 직업 대상 최고 우선순위 미청구 요청을 하나 pull.
func pull_for(job: StringName, worker_id: int):
	var ids: Array = by_job.get(job, [])
	var best_id := -1
	var best_pri := -1
	for rid in ids:
		var r: Request = requests[rid]
		if r.state != Request.State.POSTED:
			continue
		var pri := r.effective_priority(GameClock.day)
		if pri > best_pri:
			best_pri = pri
			best_id = rid
	if best_id < 0:
		return null
	var req: Request = requests[best_id]
	req.state = Request.State.CLAIMED
	req.claimed_by = worker_id
	return req

## 요청 충족 처리. 상위 체인 요청은 자연히 재개(공급자가 재확인).
func fulfill(req: Request) -> void:
	req.state = Request.State.FULFILLED
	by_job[req.provider_job].erase(req.id)
	requests.erase(req.id)
	request_fulfilled.emit(req)

## 청구했으나 처리 실패 시 다시 게시 상태로 (사망·시간종료 등)
func release(req: Request) -> void:
	if req.state == Request.State.CLAIMED:
		req.state = Request.State.POSTED
		req.claimed_by = -1

## 특정 직업의 미완 요청 목록 (압력 계산·UI용)
func open_for(job: StringName) -> Array:
	var out := []
	for rid in by_job.get(job, []):
		var r: Request = requests[rid]
		if r.state == Request.State.POSTED or r.state == Request.State.CLAIMED:
			out.append(r)
	return out

func total_open() -> int:
	var c := 0
	for r in requests.values():
		if r.state == Request.State.POSTED or r.state == Request.State.CLAIMED:
			c += 1
	return c

# ── 도구/자재 조달 체인 헬퍼 ────────────────────────────────
## 도구 제작에 필요한 재료가 창고에 없으면 하위 요청을 파생한다(§6.2-3).
func request_tool_materials(tool: StringName, requester: int, chain: int) -> void:
	var cost: Dictionary = Defs.TOOLS[tool]["cost"]
	for mat in cost:
		var need: int = cost[mat]
		if not Village.has_res(mat, need):
			var provider := _material_provider(mat)
			post(mat, need, requester, provider, Defs.PRI_BUILD_MATERIAL, chain)

func _material_provider(mat: StringName) -> StringName:
	match mat:
		&"나무": return Defs.JOB_CARPENTER
		&"돌", &"철", &"석탄": return Defs.JOB_MINER
		_: return Defs.JOB_CARPENTER
