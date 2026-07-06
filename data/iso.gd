class_name Iso
extends RefCounted
## 아이소메트릭 좌표 변환 (계획서 §1.1, 64×32 다이아몬드 타일).

const TILE_W: int = 64
const TILE_H: int = 32

## 격자 셀 -> 월드 픽셀 (타일 중심)
static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * (TILE_W / 2.0),
		(cell.x + cell.y) * (TILE_H / 2.0)
	)

static func cell_to_world_f(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * (TILE_W / 2.0),
		(x + y) * (TILE_H / 2.0)
	)

## 월드 픽셀 -> 격자 셀
static func world_to_cell(w: Vector2) -> Vector2i:
	var fx := w.x / (TILE_W / 2.0)
	var fy := w.y / (TILE_H / 2.0)
	return Vector2i(
		int(round((fx + fy) / 2.0)),
		int(round((fy - fx) / 2.0))
	)

## Y-sort 정렬 기준값
static func depth(cell: Vector2i) -> float:
	return (cell.x + cell.y) * (TILE_H / 2.0)
