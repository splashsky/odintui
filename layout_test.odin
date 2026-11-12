package odintui

import "core:testing"

@(test)
test_layout_row_chunks :: proc(t: ^testing.T) {
	layout := layout_init(Rect{2, 3, 12, 4}, .Row, 2)
	testing.expect(t, layout_take(&layout, 3) == Rect{2, 3, 3, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_take(&layout, 0) == Rect{7, 3, 0, 4})
	testing.expect(t, layout_take(&layout, -1) == Rect{7, 3, 0, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_take(&layout, 100) == Rect{7, 3, 7, 4})
	testing.expect(t, layout_remaining(&layout) == Rect{14, 3, 0, 4})
	testing.expect(t, layout_take(&layout, 1) == Rect{14, 3, 0, 4})
}

@(test)
test_layout_column_and_empty :: proc(t: ^testing.T) {
	layout := layout_init(Rect{-3, 5, 6, 8}, .Column, 1)
	testing.expect(t, layout_take(&layout, 2) == Rect{-3, 5, 6, 2})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 8, 6, 5})
	testing.expect(t, layout_take(&layout, 3) == Rect{-3, 8, 6, 3})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 12, 6, 1})
	testing.expect(t, layout_take(&layout, 4) == Rect{-3, 12, 6, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{-3, 13, 6, 0})

	empty := layout_init(Rect{1, 2, -4, 8}, .Column, -1)
	testing.expect(t, layout_remaining(&empty) == Rect{1, 2, 0, 8})
	testing.expect(t, layout_take(&empty, 2) == Rect{1, 2, 0, 0})
	testing.expect(t, layout_remaining(&empty) == Rect{1, 2, 0, 8})
	no_gap := layout_init(Rect{0, 0, 3, 1}, .Row, -8)
	testing.expect(t, layout_take(&no_gap, 1) == Rect{0, 0, 1, 1})
	testing.expect(t, layout_remaining(&no_gap) == Rect{1, 0, 2, 1})
}

@(test)
test_layout_extreme_coordinates :: proc(t: ^testing.T) {
	layout := layout_init(Rect{max(int)-2, 0, 5, 1}, .Row, 0)
	testing.expect(t, layout_take(&layout, 2) == Rect{max(int)-2, 0, 2, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{max(int), 0, 3, 1})
	testing.expect(t, layout_take(&layout, 1) == Rect{max(int), 0, 1, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{max(int), 0, 0, 1})

	layout = layout_init(Rect{min(int), min(int), max(int), max(int)}, .Column, max(int))
	testing.expect(t, layout_take(&layout, 1) == Rect{min(int), min(int), max(int), 1})
	testing.expect(t, layout_remaining(&layout) == Rect{min(int), -1, max(int), 0})

	layout = layout_init(Rect{0, max(int)-1, 1, max(int)}, .Column, max(int))
	testing.expect(t, layout_take(&layout, 1) == Rect{0, max(int)-1, 1, 1})
	testing.expect(t, layout_remaining(&layout) == Rect{0, max(int), 1, 0})
}
