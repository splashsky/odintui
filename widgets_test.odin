package odintui

import "core:testing"

@(private)
widget_test_cell :: proc(t: ^testing.T, grid: ^Grid, x, y: int, expected: Cell) {
	cell, ok := get_cell(grid, x, y)
	testing.expect(t, ok && cell == expected)
}

@(test)
test_widget_label_clipping :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{fg = rgb(1, 2, 3)}

	draw_label(&grid, Rect{-1, 1, 3, 2}, "aé界z", style)
	widget_test_cell(t, &grid, 0, 1, {'é', style})
	widget_test_cell(t, &grid, 1, 1, {'界', style})
	widget_test_cell(t, &grid, 2, 1, BLANK_CELL)
	widget_test_cell(t, &grid, 0, 2, BLANK_CELL)
	draw_label(&grid, Rect{2, 0, 3, 1}, "A\nBC", style)
	widget_test_cell(t, &grid, 2, 0, {'A', style})
	widget_test_cell(t, &grid, 3, 0, BLANK_CELL)
	draw_label(&grid, Rect{4, 2, 10, 1}, "XYZ", style)
	widget_test_cell(t, &grid, 4, 2, {'X', style})
	draw_label(&grid, Rect{0, 0, 4, 1}, "Q\rZ", style)
	widget_test_cell(t, &grid, 0, 0, {'Q', style})
	widget_test_cell(t, &grid, 1, 0, BLANK_CELL)
	draw_label(&grid, Rect{min(int), 0, max(int), 1}, "ignored", style)
	draw_label(&grid, Rect{max(int), 0, max(int), 1}, "ignored", style)
	draw_label(&grid, Rect{0, min(int), 1, max(int)}, "ignored", style)
	draw_label(&grid, Rect{0, 0, 0, 1}, "ignored", style)
	draw_label(&grid, Rect{0, 0, 3, -1}, "ignored", style)
	widget_test_cell(t, &grid, 0, 0, {'Q', style})
}

@(test)
test_widget_border_shapes :: proc(t: ^testing.T) {
	grid, err := grid_init(7, 6)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{bg = rgb(4, 5, 6)}
	draw_border(&grid, Rect{1, 1, 5, 4}, style)
	for y in 1..<5 {
		for x in 1..<6 {
			glyph := ' '
			if y == 1 || y == 4 {
				glyph = '-'
			}
			if x == 1 || x == 5 {
				glyph = '|'
			}
			if (x == 1 || x == 5) && (y == 1 || y == 4) {
				glyph = '+'
			}
			if glyph == ' ' {
				widget_test_cell(t, &grid, x, y, BLANK_CELL)
			} else {
				widget_test_cell(t, &grid, x, y, {glyph, style})
			}
		}
	}
	draw_border(&grid, Rect{0, 0, 1, 3}, style)
	widget_test_cell(t, &grid, 0, 0, {'+', style})
	widget_test_cell(t, &grid, 0, 1, {'|', style})
	widget_test_cell(t, &grid, 0, 2, {'+', style})
	draw_border(&grid, Rect{2, 5, 4, 1}, style)
	widget_test_cell(t, &grid, 2, 5, {'+', style})
	widget_test_cell(t, &grid, 3, 5, {'-', style})
	widget_test_cell(t, &grid, 5, 5, {'+', style})
	draw_border(&grid, Rect{6, 0, 1, 1}, style)
	widget_test_cell(t, &grid, 6, 0, {'+', style})
	draw_border(&grid, Rect{0, 0, -1, 2}, style)
	draw_border(&grid, Rect{0, 0, 2, 0}, style)
	widget_test_cell(t, &grid, 0, 0, {'+', style})
}

@(test)
test_widget_border_preserves_offscreen_geometry :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{fg = rgb(1, 1, 1)}
	draw_border(&grid, Rect{-2, -1, 5, 4}, style)
	widget_test_cell(t, &grid, 0, 0, BLANK_CELL)
	widget_test_cell(t, &grid, 2, 0, {'|', style})
	widget_test_cell(t, &grid, 0, 2, {'-', style})
	widget_test_cell(t, &grid, 2, 2, {'+', style})

	fill(&grid, 0, 0, 5, 3, BLANK_CELL)
	draw_border(&grid, Rect{1, 0, max(int), max(int)}, style)
	widget_test_cell(t, &grid, 1, 0, {'+', style})
	widget_test_cell(t, &grid, 4, 0, {'-', style})
	widget_test_cell(t, &grid, 1, 2, {'|', style})
	widget_test_cell(t, &grid, 4, 2, BLANK_CELL)
	draw_border(&grid, Rect{min(int), min(int), max(int), max(int)}, style)
	draw_border(&grid, Rect{max(int), max(int), max(int), max(int)}, style)
	widget_test_cell(t, &grid, 4, 2, BLANK_CELL)

	fill(&grid, 0, 0, 5, 3, BLANK_CELL)
	draw_border(&grid, Rect{-2, 0, 5, 1}, style)
	widget_test_cell(t, &grid, 0, 0, {'-', style})
	widget_test_cell(t, &grid, 2, 0, {'+', style})
	draw_border(&grid, Rect{4, -1, 1, 3}, style)
	widget_test_cell(t, &grid, 4, 0, {'|', style})
	widget_test_cell(t, &grid, 4, 1, {'+', style})
}

@(test)
test_widget_empty_grid :: proc(t: ^testing.T) {
	grid, err := grid_init(0, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	draw_label(&grid, Rect{0, 0, 3, 1}, "abc")
	draw_border(&grid, Rect{-1, -1, max(int), max(int)})
	draw_progress_bar(&grid, Rect{0, 0, 3, 1}, 0.5, {}, {})
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 0, 3})
	testing.expect(t, grid_resize(&grid, 3, 0) == .None)
	draw_label(&grid, Rect{0, 0, 3, 1}, "abc")
	draw_border(&grid, Rect{-1, -1, max(int), max(int)})
	draw_progress_bar(&grid, Rect{0, 0, 3, 1}, 0.5, {}, {})
	testing.expect(t, grid_bounds(&grid) == Rect{0, 0, 3, 0})
}

@(test)
test_widget_progress :: proc(t: ^testing.T) {
	grid, err := grid_init(5, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	full := Style{fg = rgb(1, 2, 3)}
	empty := Style{bg = rgb(4, 5, 6)}
	bounds := Rect{0, 0, 5, 2}

	draw_progress_bar(&grid, bounds, 0.6, full, empty)
	for y in 0..<2 {
		for x in 0..<5 {
			expected := Cell{'-', empty}
			if x < 3 {
				expected = {'#', full}
			}
			widget_test_cell(t, &grid, x, y, expected)
		}
	}
	draw_progress_bar(&grid, bounds, 0.2, full, empty)
	widget_test_cell(t, &grid, 0, 0, {'#', full})
	widget_test_cell(t, &grid, 1, 0, {'-', empty})
	draw_progress_bar(&grid, bounds, 2, full, empty)
	widget_test_cell(t, &grid, 4, 1, {'#', full})
	draw_progress_bar(&grid, bounds, -1, full, empty)
	widget_test_cell(t, &grid, 0, 0, {'-', empty})
	draw_progress_bar(&grid, bounds, 1, full, empty)
	nan := transmute(f64)(u64(0x7ff8_0000_0000_0000))
	draw_progress_bar(&grid, bounds, nan, full, empty)
	widget_test_cell(t, &grid, 0, 0, {'-', empty})
	widget_test_cell(t, &grid, 4, 1, {'-', empty})
	infinity := transmute(f64)(u64(0x7ff0_0000_0000_0000))
	draw_progress_bar(&grid, bounds, infinity, full, empty)
	widget_test_cell(t, &grid, 4, 1, {'#', full})
	draw_progress_bar(&grid, bounds, -infinity, full, empty)
	widget_test_cell(t, &grid, 4, 1, {'-', empty})
	draw_progress_bar(&grid, Rect{-2, 0, 6, 1}, 0.5, full, empty)
	widget_test_cell(t, &grid, 0, 0, {'#', full})
	widget_test_cell(t, &grid, 1, 0, {'-', empty})
	widget_test_cell(t, &grid, 3, 0, {'-', empty})
	draw_progress_bar(&grid, Rect{0, 0, max(int), 1}, 0.9999999999999999, full, empty)
	widget_test_cell(t, &grid, 4, 0, {'#', full})
	when size_of(int) == 8 {
		draw_progress_bar(&grid, Rect{-max(int)/2, 0, max(int), 1}, 0.5, full, empty)
		widget_test_cell(t, &grid, 0, 0, {'-', empty})
	}
	draw_progress_bar(&grid, Rect{min(int), 0, max(int), 1}, 1, full, empty)
	draw_progress_bar(&grid, Rect{0, 0, 0, 1}, 0, full, empty)
	draw_progress_bar(&grid, Rect{0, 0, 1, -1}, 0, full, empty)
	when size_of(int) == 8 {
		widget_test_cell(t, &grid, 4, 0, {'-', empty})
	} else {
		widget_test_cell(t, &grid, 4, 0, {'#', full})
	}
}
