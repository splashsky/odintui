package odintui

import "base:runtime"
import "core:testing"

@(private)
scroll_test_cell :: proc(t: ^testing.T, grid: ^Grid, x, y: int, expected: Cell) {
	cell, ok := get_cell(grid, x, y)
	testing.expect(t, ok && cell == expected)
}

@(test)
scroll_test_clamp :: proc(t: ^testing.T) {
	testing.expect(t, scroll_clamp(-5, 100, 10) == 0)
	testing.expect(t, scroll_clamp(99, 100, 10) == 90)
	testing.expect(t, scroll_clamp(10, 4, 8) == 0)
	testing.expect(t, scroll_clamp(4, -1, -2) == 0)
	testing.expect(t, scroll_clamp(max(int), max(int), 0) == max(int))
	testing.expect(t, scroll_clamp(max(int), max(int), max(int)-1) == 1)
}

@(test)
scroll_test_into_view :: proc(t: ^testing.T) {
	testing.expect(t, scroll_into_view(10, 12, 3, 10) == 10)
	testing.expect(t, scroll_into_view(10, 7, 2, 10) == 7)
	testing.expect(t, scroll_into_view(10, 18, 5, 10) == 13)
	testing.expect(t, scroll_into_view(10, 12, 11, 10) == 12)
	testing.expect(t, scroll_into_view(10, 12, 2, 0) == 12)
	testing.expect(t, scroll_into_view(10, 0, 0, 3) == 10)
	testing.expect(t, scroll_into_view(-1, -9, 2, 3) == 0)
	testing.expect(t, scroll_into_view(max(int)-5, max(int)-1, 4, 5) == max(int)-2)
	testing.expect(t, scroll_into_view(max(int), max(int), max(int), max(int)-1) == max(int))
}

@(test)
scroll_test_scrollbar_draw :: proc(t: ^testing.T) {
	grid, err := grid_init(10, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	draw_scrollbar(&grid, {0, 0, 10, 2}, .Row, 100, 20, 0)
	scroll_test_cell(t, &grid, 0, 0, {'█', {}})
	scroll_test_cell(t, &grid, 1, 0, {'█', {}})
	scroll_test_cell(t, &grid, 2, 0, {'─', {}})
	scroll_test_cell(t, &grid, 0, 1, BLANK_CELL)
	draw_scrollbar(&grid, {0, 0, 10, 1}, .Row, 100, 20, 40)
	scroll_test_cell(t, &grid, 0, 0, {'─', {}})
	scroll_test_cell(t, &grid, 4, 0, {'█', {}})
	scroll_test_cell(t, &grid, 5, 0, {'█', {}})
	draw_scrollbar(&grid, {0, 0, 10, 1}, .Row, 100, 20, 80)
	scroll_test_cell(t, &grid, 7, 0, {'─', {}})
	scroll_test_cell(t, &grid, 8, 0, {'█', {}})
	scroll_test_cell(t, &grid, 9, 0, {'█', {}})

	style := Style{fg = rgb(1, 2, 3)}
	testing.expect(t, push_clip(&grid, {2, 1, 1, 2}))
	draw_scrollbar(&grid, {2, 0, 3, 4}, .Column, 8, 2, 6, {
		track = '.', thumb = '#', track_style = style, thumb_style = style,
	})
	pop_clip(&grid)
	scroll_test_cell(t, &grid, 2, 1, {'.', style})
	scroll_test_cell(t, &grid, 2, 2, {'.', style})
	scroll_test_cell(t, &grid, 2, 3, BLANK_CELL)
	scroll_test_cell(t, &grid, 3, 1, BLANK_CELL)
	draw_scrollbar(&grid, {0, 3, 10, 1}, .Row, 10, 10, 0)
	scroll_test_cell(t, &grid, 0, 3, BLANK_CELL)
	draw_scrollbar(&grid, {0, 3, 10, 1}, .Row, 10, 10, 0, {always_show = true})
	scroll_test_cell(t, &grid, 0, 3, {'█', {}})
	scroll_test_cell(t, &grid, 9, 3, {'█', {}})
}

@(test)
scroll_test_scrollbar_hit :: proc(t: ^testing.T) {
	bounds := Rect{2, 3, 10, 2}
	offset, ok := scrollbar_offset_at(bounds, .Row, 100, 20, 2, 3)
	testing.expect(t, ok && offset == 0)
	offset, ok = scrollbar_offset_at(bounds, .Row, 100, 20, 7, 3)
	testing.expect(t, ok && offset == 40)
	offset, ok = scrollbar_offset_at(bounds, .Row, 100, 20, 11, 3)
	testing.expect(t, ok && offset == 80)
	_, ok = scrollbar_offset_at(bounds, .Row, 100, 20, 2, 4)
	testing.expect(t, !ok)
	_, ok = scrollbar_offset_at(bounds, .Row, 20, 20, 2, 3)
	testing.expect(t, !ok)
	offset, ok = scrollbar_offset_at({2, 3, 2, 10}, .Column, 100, 20, 2, 12)
	testing.expect(t, ok && offset == 80)
	offset, ok = scrollbar_offset_at({0, 0, 1, 1}, .Column, 100, 1, 0, 0)
	testing.expect(t, ok && offset == 0)
	offset, ok = scrollbar_offset_at({min(int), 0, max(int), 1}, .Row, max(int), 0, -2, 0)
	testing.expect(t, ok && offset == max(int))
	_, ok = scrollbar_offset_at({max(int), 0, max(int), 1}, .Row, 3, 1, max(int), 0)
	testing.expect(t, ok)
}

@(test)
scroll_test_scrollbar_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(5, 3, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	draw_scrollbar(&grid, {0, 0, 5, 1}, .Row, 10, 2, 8)
	draw_scrollbar(&grid, {0, 0, 1, 3}, .Column, 10, 2, 0)
	scroll_test_cell(t, &grid, 0, 0, {'█', {}})
	scroll_test_cell(t, &grid, 4, 0, {'█', {}})
	testing.expect(t, state.remaining == 0)
}
