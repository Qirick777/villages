extends Node2D
## 지면 렌더러 — 바이옴 다이아몬드 타일을 직접 그린다 (Iso 헬퍼와 정렬 보장).
## TileMapLayer 대신 _draw로 처리해 오브젝트/주민 좌표계와 100% 일치시킨다.

var roads: Dictionary = {}    # Vector2i -> true

var BIOME_COLORS := {
	MapGen.Biome.WATER:  Color("#2f6fa8"),
	MapGen.Biome.SAND:   Color("#d9c48a"),
	MapGen.Biome.GRASS:  Color("#6d9e4f"),
	MapGen.Biome.FOREST: Color("#3f7038"),
	MapGen.Biome.ROCK:   Color("#8b8f96"),
}
var ROAD_COLOR := Color("#8a7a5c")

func _draw() -> void:
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	for y in MapGen.MAP_H:
		for x in MapGen.MAP_W:
			var b := MapGen.get_biome(x, y)
			var c: Color = BIOME_COLORS.get(b, Color.MAGENTA)
			if roads.has(Vector2i(x, y)):
				c = ROAD_COLOR
			var ctr := Iso.cell_to_world(Vector2i(x, y))
			var pts := PackedVector2Array([
				ctr + Vector2(0, -hh),
				ctr + Vector2(hw, 0),
				ctr + Vector2(0, hh),
				ctr + Vector2(-hw, 0),
			])
			draw_colored_polygon(pts, c)
			# 미세한 격자 음영 (입체감)
			draw_polyline(PackedVector2Array([
				ctr + Vector2(0, -hh), ctr + Vector2(hw, 0),
				ctr + Vector2(0, hh), ctr + Vector2(-hw, 0),
				ctr + Vector2(0, -hh)]), Color(0, 0, 0, 0.06), 1.0)

func add_road(cell: Vector2i) -> void:
	roads[cell] = true
	queue_redraw()
