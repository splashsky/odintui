package odintui

import "base:runtime"
import "core:testing"

@(private)
box_test_cell :: proc(t: ^testing.T, grid: ^Grid, x, y: int, expected: Cell) {
	cell, ok := get_cell(grid, x, y)
	testing.expect(t, ok && cell == expected)
}

@(test)
box_test_default_and_sides :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 5)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	testing.expect(t, draw_box(&grid, {0, 0, 8, 5}) == Rect{1, 1, 6, 3})
	box_test_cell(t, &grid, 0, 0, {'┌', {}})
	box_test_cell(t, &grid, 7, 0, {'┐', {}})
	box_test_cell(t, &grid, 0, 4, {'└', {}})
	box_test_cell(t, &grid, 7, 4, {'┘', {}})
	box_test_cell(t, &grid, 1, 0, {'─', {}})
	box_test_cell(t, &grid, 0, 1, {'│', {}})

	fill(&grid, 0, 0, 8, 5, BLANK_CELL)
	options := Box_Options{border = BORDER_HEAVY, hidden_sides = {.Top, .Right}}
	testing.expect(t, draw_box(&grid, {1, 1, 5, 3}, options) == Rect{2, 1, 4, 2})
	box_test_cell(t, &grid, 1, 1, {'┃', {}})
	box_test_cell(t, &grid, 5, 1, BLANK_CELL)
	box_test_cell(t, &grid, 1, 3, {'┗', {}})
	box_test_cell(t, &grid, 5, 3, {'━', {}})
	options.hidden_sides = {.Top, .Right, .Bottom, .Left}
	options.fill, options.fill_style = true, {bg = rgb(1, 2, 3)}
	options.padding = {1, 1, 0, 2}
	testing.expect(t, draw_box(&grid, {1, 1, 5, 3}, options) == Rect{3, 2, 2, 2})
	box_test_cell(t, &grid, 1, 1, {' ', options.fill_style})
	box_test_cell(t, &grid, 5, 3, {' ', options.fill_style})
}

@(test)
box_test_titles_and_clips :: proc(t: ^testing.T) {
	grid, err := grid_init(10, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{fg = rgb(1, 2, 3)}
	title_style := Style{attributes = {.Bold}}
	options := Box_Options{
		border = BORDER_ROUNDED, border_style = style, title = "é界",
		title_align = .Center, title_style = title_style,
		footer = "ABCDE", footer_align = .End, fill = true, fill_style = {bg = rgb(4, 5, 6)},
		padding = {1, 2, 0, 1},
	}
	testing.expect(t, draw_box(&grid, {0, 0, 10, 4}, options) == Rect{2, 2, 5, 1})
	box_test_cell(t, &grid, 0, 0, {'╭', style})
	box_test_cell(t, &grid, 2, 0, {'─', style})
	box_test_cell(t, &grid, 3, 0, {' ', title_style})
	box_test_cell(t, &grid, 4, 0, {'é', title_style})
	box_test_cell(t, &grid, 5, 0, {'界', title_style})
	box_test_cell(t, &grid, 6, 0, {' ', title_style})
	box_test_cell(t, &grid, 2, 3, {' ', style})
	box_test_cell(t, &grid, 3, 3, {'A', style})
	box_test_cell(t, &grid, 8, 3, {' ', style})
	box_test_cell(t, &grid, 9, 3, {'╯', style})
	box_test_cell(t, &grid, 1, 1, {' ', options.fill_style})

	fill(&grid, 0, 0, 10, 4, BLANK_CELL)
	testing.expect(t, push_clip(&grid, {2, 0, 3, 4}))
	options.title = "123456789"
	draw_box(&grid, {-1, 0, 8, 4}, options)
	pop_clip(&grid)
	box_test_cell(t, &grid, 1, 0, BLANK_CELL)
	box_test_cell(t, &grid, 2, 0, {'3', title_style})
	box_test_cell(t, &grid, 4, 0, {'5', title_style})
	box_test_cell(t, &grid, 5, 0, BLANK_CELL)
}

@(test)
box_test_small_and_extreme :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	draw_box(&grid, {0, 0, 1, 1}, {title = "abc"})
	box_test_cell(t, &grid, 0, 0, {'┘', {}})
	draw_box(&grid, {0, 1, 4, 1}, {title = "long", footer = "xyz"})
	box_test_cell(t, &grid, 0, 1, {'└', {}})
	box_test_cell(t, &grid, 1, 1, {'x', {}})
	box_test_cell(t, &grid, 2, 1, {'y', {}})
	box_test_cell(t, &grid, 3, 1, {'┘', {}})
	testing.expect(t, box_content({max(int), min(int), 10, -1}, {}) == Rect{max(int), min(int), 0, 0})
	draw_box(&grid, {1, 0, max(int), max(int)}, {title = "x", title_align = .End})
	box_test_cell(t, &grid, 1, 0, {'┌', {}})
	box_test_cell(t, &grid, 3, 0, {'─', {}})
	draw_box(&grid, {min(int), min(int), max(int), max(int)}, {fill = true, title = "x"})
	draw_box(&grid, {max(int), 0, max(int), 1}, {title = "x"})
}

@(test)
box_test_drawing_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(8, 3, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	content := draw_box(&grid, {0, 0, 8, 3}, {
		fill = true, title = "é界", footer = "end", padding = {0, 1, 0, 1},
	})
	testing.expect(t, state.remaining == 0 && content == Rect{2, 1, 4, 1})
	box_test_cell(t, &grid, 2, 0, {'é', {}})
}
