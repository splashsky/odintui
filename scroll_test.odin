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

@(test)
scroll_test_slider :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 5)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	draw_slider(&grid, {0, 0, 5, 2}, .Row, 0.5)
	scroll_test_cell(t, &grid, 1, 0, {'─', {}})
	scroll_test_cell(t, &grid, 2, 0, {'●', {}})
	scroll_test_cell(t, &grid, 3, 0, {'─', {}})
	scroll_test_cell(t, &grid, 2, 1, BLANK_CELL)
	draw_slider(&grid, {0, 0, 5, 1}, .Row, 2)
	scroll_test_cell(t, &grid, 4, 0, {'●', {}})
	draw_slider(&grid, {0, 0, 5, 1}, .Row, -1)
	scroll_test_cell(t, &grid, 0, 0, {'●', {}})
	draw_slider(&grid, {0, 0, 6, 1}, .Row, 0.5)
	scroll_test_cell(t, &grid, 2, 0, {'─', {}})
	scroll_test_cell(t, &grid, 3, 0, {'●', {}})
	draw_slider(&grid, {0, 0, 5, 1}, .Row, transmute(f64)(u64(0x7ff8_0000_0000_0000)))
	scroll_test_cell(t, &grid, 0, 0, {'●', {}})
	style := Style{bg = rgb(4, 5, 6)}
	testing.expect(t, push_clip(&grid, {5, 2, 1, 2}))
	draw_slider(&grid, {5, 1, 1, 4}, .Column, 0.7, {
		track = '.', thumb = '#', track_style = style, thumb_style = style,
	})
	pop_clip(&grid)
	scroll_test_cell(t, &grid, 5, 1, BLANK_CELL)
	scroll_test_cell(t, &grid, 5, 2, {'.', style})
	scroll_test_cell(t, &grid, 5, 3, {'#', style})
	scroll_test_cell(t, &grid, 5, 4, BLANK_CELL)
	draw_slider(&grid, {0, 4, 1, 1}, .Column, 1)
	scroll_test_cell(t, &grid, 0, 4, {'●', {}})
	draw_slider(&grid, {max(int), 0, max(int), 1}, .Row, 1)
	draw_slider(&grid, {0, min(int), 1, max(int)}, .Column, 1)
	draw_slider(&grid, {0, 0, -1, 1}, .Row, 0.5)
	when size_of(int) == 8 {
		draw_slider(&grid, {-max(int)/2, 4, max(int), 1}, .Row, 0.5)
		scroll_test_cell(t, &grid, 0, 4, {'●', {}})
		scroll_test_cell(t, &grid, 1, 4, {'─', {}})
	}
}

@(test)
scroll_test_slider_hit_round_trip :: proc(t: ^testing.T) {
	grid, err := grid_init(260, 260)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	lengths := []int{1, 2, 3, 6, 49, 50, 51, 98, 99, 100, 257}
	axes := []Layout_Axis{.Row, .Column}
	for axis in axes {
		for length in lengths {
			bounds := Rect{1, 1, length, 2}
			if axis == .Column {
				bounds = {1, 1, 2, length}
			}
			for i in 0..<length {
				x, y := bounds.x, bounds.y
				if axis == .Column {
					y += i
				} else {
					x += i
				}
				value, ok := slider_value_at(bounds, axis, x, y)
				testing.expect(t, ok && value >= 0 && value <= 1)
				if length == 1 {
					testing.expect(t, value == 0)
				}
				draw_slider(&grid, bounds, axis, value)
				scroll_test_cell(t, &grid, x, y, {'●', {}})
			}
		}
	}
	_, ok := slider_value_at({2, 3, 10, 2}, .Row, 2, 4)
	testing.expect(t, !ok)
	_, ok = slider_value_at({2, 3, 2, 10}, .Column, 3, 3)
	testing.expect(t, !ok)
	_, ok = slider_value_at({2, 3, 0, 2}, .Row, 2, 3)
	testing.expect(t, !ok)
	_, ok = slider_value_at({2, 3, 10, 2}, .Row, 12, 3)
	testing.expect(t, !ok)
	value, hit := slider_value_at({min(int), 0, max(int), 1}, .Row, -2, 0)
	testing.expect(t, hit && value >= 0 && value <= 1)
	value, hit = slider_value_at({max(int), 0, max(int), 1}, .Row, max(int), 0)
	testing.expect(t, hit && value == 0)
	when size_of(int) == 8 {
		travel := int(1 << 53)
		indices := []int{1, travel/2+1, travel-1, travel}
		for i in indices {
			bounds := Rect{-i, 0, travel+1, 1}
			value, hit = slider_value_at(bounds, .Row, 0, 0)
			testing.expect(t, hit)
			draw_slider(&grid, bounds, .Row, value)
			scroll_test_cell(t, &grid, 0, 0, {'●', {}})
		}
		draw_slider(
			&grid, {-max(int)/2, 0, max(int), 1}, .Row,
			transmute(f64)(u64(0x3fef_ffff_ffff_ffff)),
		)
	}
}

@(test)
scroll_test_slider_does_not_allocate :: proc(t: ^testing.T) {
	state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &state}
	grid, err := grid_init(5, 2, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	draw_slider(&grid, {0, 0, 5, 1}, .Row, 0.5)
	draw_slider(&grid, {4, 0, 1, 2}, .Column, 1)
	scroll_test_cell(t, &grid, 4, 1, {'●', {}})
	value, hit := slider_value_at({0, 0, 5, 1}, .Row, 3, 0)
	draw_slider(&grid, {0, 1, 5, 1}, .Row, value)
	testing.expect(t, hit)
	scroll_test_cell(t, &grid, 2, 0, {'●', {}})
	scroll_test_cell(t, &grid, 3, 1, {'●', {}})
	testing.expect(t, state.remaining == 0)
}
