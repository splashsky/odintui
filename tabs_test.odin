package odintui

import "base:runtime"
import "core:testing"

@(test)
tabs_test_drawing_and_hit_testing :: proc(t: ^testing.T) {
	grid, err := grid_init(9, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	labels := []string{"abcde", "界"}
	options := Tabs_Options{tab_width = 4, separator = '|', underline = true}
	draw_tabs(&grid, {0, 0, 9, 3}, labels, 1, options)
	text_expect_row(t, &grid, 0, " a… | 界  ")
	text_expect_row(t, &grid, 1, "─────━━━━")
	text_expect_row(t, &grid, 2, "         ")
	selected := Style{attributes = {.Reverse}}
	box_test_cell(t, &grid, 5, 0, {' ', selected})
	box_test_cell(t, &grid, 6, 0, {'界', selected})
	box_test_cell(t, &grid, 8, 1, {'━', selected})
	index, ok := tabs_index_at({0, 0, 9, 3}, labels, 1, 8, 1, options)
	testing.expect(t, ok && index == 1)
	_, ok = tabs_index_at({0, 0, 9, 3}, labels, 1, 4, 0, options)
	testing.expect(t, !ok)
	_, ok = tabs_index_at({0, 0, 9, 3}, labels, 1, 6, 2, options)
	testing.expect(t, !ok)
}

@(test)
tabs_test_horizontal_scroll_and_clipped_ellipsis :: proc(t: ^testing.T) {
	grid, err := grid_init(8, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	labels := []string{"A", "BB", "CCC"}
	options := Tabs_Options{separator = '|', underline = true}
	draw_tabs(&grid, {0, 0, 8, 2}, labels, 2, options)
	text_expect_row(t, &grid, 0, "B | CCC ")
	text_expect_row(t, &grid, 1, "───━━━━━")
	index, ok := tabs_index_at({0, 0, 8, 2}, labels, 2, 0, 0, options)
	testing.expect(t, ok && index == 1)
	_, ok = tabs_index_at({0, 0, 8, 2}, labels, 2, 2, 0, options)
	testing.expect(t, !ok)
	index, ok = tabs_index_at({0, 0, 8, 2}, labels, 2, 7, 1, options)
	testing.expect(t, ok && index == 2)
	draw_tabs(&grid, {0, 0, 8, 2}, labels, 0, options)
	text_expect_row(t, &grid, 0, " A | BB ")
	text_expect_row(t, &grid, 1, "━━━─────")

	fixed := []string{"abcdef", "xyz"}
	draw_tabs(&grid, {0, 0, 8, 1}, fixed, 1, {tab_width = 5})
	text_expect_row(t, &grid, 0, "b…  xyz ")
	draw_tabs(&grid, {0, 0, 4, 1}, fixed, 0, {tab_width = 8})
	text_expect_row(t, &grid, 0, " abcxyz ")
}

@(test)
tabs_test_handlers_and_empty :: proc(t: ^testing.T) {
	labels := []string{"one", "two", "three"}
	bounds := Rect{1, 1, 12, 2}
	options := Tabs_Options{underline = true, separator = '|'}
	selected := 0
	result := tabs_handle(&selected, labels, bounds, Key_Event{key = .Left}, options)
	testing.expect(t, result == Tabs_Result{true, false} && selected == 0)
	result = tabs_handle(&selected, labels, bounds, Key_Event{key = .Right}, options)
	testing.expect(t, result == Tabs_Result{true, true} && selected == 1)
	result = tabs_handle(&selected, labels, bounds, Key_Event{key = .End}, options)
	testing.expect(t, result.changed && selected == 2)
	result = tabs_handle(&selected, labels, bounds, Key_Event{key = .Home}, options)
	testing.expect(t, result.changed && selected == 0)
	result = tabs_handle(&selected, labels, bounds, Mouse_Event{2, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.changed && selected == 1)
	result = tabs_handle(&selected, labels, bounds, Mouse_Event{1, 2, .Left, .Press, {}}, options)
	testing.expect(t, result.changed && selected == 0)
	result = tabs_handle(&selected, labels, bounds, Mouse_Event{6, 1, .Left, .Press, {}}, options)
	testing.expect(t, result == Tabs_Result{} && selected == 0)
	result = tabs_handle(&selected, labels, bounds, Mouse_Event{1, 3, .Wheel_Up, .Press, {}}, options)
	testing.expect(t, result == Tabs_Result{})
	result = tabs_handle(&selected, labels, bounds, Key_Event{key = .Up}, options)
	testing.expect(t, result == Tabs_Result{})
	selected = 99
	result = tabs_handle(&selected, nil, bounds, Key_Event{key = .End}, options)
	testing.expect(t, result.changed && selected == 0)
	_, ok := tabs_index_at(bounds, nil, selected, 1, 1, options)
	testing.expect(t, !ok)
}

@(test)
tabs_test_clipping_and_no_allocations :: proc(t: ^testing.T) {
	allocator_state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &allocator_state}
	grid, err := grid_init(7, 2, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	labels := []string{"é界", "abcdef"}
	selected := 1
	options := Tabs_Options{tab_width = 4, underline = true}
	testing.expect(t, push_clip(&grid, {1, 0, 4, 2}))
	draw_tabs(&grid, {0, 0, 7, 2}, labels, selected, options)
	result := tabs_handle(&selected, labels, {0, 0, 7, 2}, Key_Event{key = .Left}, options)
	index, ok := tabs_index_at({0, 0, 7, 2}, labels, 1, 4, 0, options)
	testing.expect(t, result.changed && selected == 0 && ok && index == 1)
	testing.expect(t, allocator_state.remaining == 0)
	box_test_cell(t, &grid, 0, 0, BLANK_CELL)
	box_test_cell(t, &grid, 1, 0, {'界', {}})
	box_test_cell(t, &grid, 4, 0, {'a', {attributes = {.Reverse}}})
	box_test_cell(t, &grid, 5, 0, BLANK_CELL)
	pop_clip(&grid)
}

@(test)
tabs_test_defaults_and_line_breaks :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	labels := []string{"é\nignored", "界"}
	draw_tabs(&grid, {0, 0, 6, 2}, labels, 0)
	text_expect_row(t, &grid, 0, " é  界 ")
	index, ok := tabs_index_at({0, 0, 6, 2}, labels, 0, 3, 0)
	testing.expect(t, ok && index == 1)
	_, ok = tabs_index_at({0, 0, 6, 2}, labels, 0, 3, 1)
	testing.expect(t, !ok)
	fill(&grid, 0, 0, 6, 2, BLANK_CELL)
	highlight := Style{fg = rgb(7, 8, 9)}
	draw_tabs(&grid, {0, 0, 6, 2}, labels, 1, {
		padding = -1, selected_style = highlight, separator = '|',
	})
	text_expect_row(t, &grid, 0, "é|界   ")
	box_test_cell(t, &grid, 2, 0, {'界', highlight})
	_, ok = tabs_index_at({0, 0, -1, 2}, labels, 0, 0, 0)
	testing.expect(t, !ok)
}
