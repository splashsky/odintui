package odintui

import "base:runtime"
import "core:testing"

@(test)
list_test_iterator_and_drawing :: proc(t: ^testing.T) {
	grid, err := grid_init(6, 5)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	items := []string{"zero", "é界long", "two", "three", "four"}
	style := Style{fg = rgb(1, 2, 3)}
	selected := style
	selected.attributes += {.Reverse}
	state := List_State{selected = 2}
	options := List_Options{style = style, item_height = 2, scrollbar = true}
	view := draw_list(&grid, {0, 0, 6, 5}, &state, items, options)
	testing.expect(t, state == List_State{2, 0})
	row_count := 0
	for row, index in list_next(&view) {
		testing.expect(t, index == row_count)
		expected_height := 2
		if index == 2 {
			expected_height = 1
		}
		testing.expect(t, row == Rect{0, index*2, 5, expected_height})
		row_count += 1
	}
	testing.expect(t, row_count == 3)
	text_expect_row(t, &grid, 0, "zero █")
	text_expect_row(t, &grid, 2, "é界lo…█")
	text_expect_row(t, &grid, 4, "two  │")
	box_test_cell(t, &grid, 4, 4, {' ', selected})
	box_test_cell(t, &grid, 4, 1, {' ', style})

	// A caller can use the iterator to paint arbitrary multiline content.
	state.selected = 4
	view = list_begin(&state, len(items), {1, 0, 4, 3}, {item_height = 2})
	testing.expect(t, state.offset == 3)
	for row, index in list_next(&view) {
		fill(&grid, row.x, row.y, row.width, row.height, {rune('0')+rune(index), {}})
	}
	text_expect_row(t, &grid, 0, "z3333█")
	text_expect_row(t, &grid, 2, "é4444█")
}

@(test)
list_test_navigation_and_hit_testing :: proc(t: ^testing.T) {
	state := List_State{selected = -9, offset = 99}
	bounds := Rect{2, 3, 5, 5}
	options := List_Options{item_height = 2, scrollbar = true}
	view := list_begin(&state, 8, bounds, options)
	testing.expect(t, state == List_State{0, 0})
	row, index, ok := list_next(&view)
	testing.expect(t, ok && row == Rect{2, 3, 4, 2} && index == 0)
	index, ok = list_index_at(&state, 8, bounds, 5, 7, options)
	testing.expect(t, ok && index == 2)
	_, ok = list_index_at(&state, 8, bounds, 6, 7, options)
	testing.expect(t, !ok)
	_, ok = list_index_at(&state, 8, bounds, 5, 8, options)
	testing.expect(t, !ok)

	list_move(&state, 8, -1, true)
	testing.expect(t, state.selected == 7)
	list_move(&state, 8, 10, true)
	testing.expect(t, state.selected == 1)
	list_move(&state, 8, min(int))
	testing.expect(t, state.selected == 0)
	list_move(&state, 8, max(int))
	testing.expect(t, state.selected == 7)
	list_first(&state)
	list_last(&state, -1)
	testing.expect(t, state.selected == 0)
	state = {4, 3}
	view = list_begin(&state, -4, bounds, options)
	_, _, ok = list_next(&view)
	testing.expect(t, !ok && state == List_State{})
}

@(test)
list_test_handlers :: proc(t: ^testing.T) {
	bounds := Rect{0, 0, 4, 3}
	options := List_Options{scrollbar = true}
	state := List_State{}
	result := list_handle(&state, 6, bounds, Key_Event{key = .Page_Down}, options)
	testing.expect(t, result == List_Result{true, true, false} && state == List_State{3, 1})
	result = list_handle(&state, 6, bounds, Key_Event{key = .Enter}, options)
	testing.expect(t, result == List_Result{true, false, true})
	result = list_handle(&state, 6, bounds, Key_Event{key = .End}, options)
	testing.expect(t, result.changed && state == List_State{5, 3})
	result = list_handle(&state, 6, bounds, Key_Event{key = .Down}, {wrap = true})
	testing.expect(t, result.changed && state == List_State{0, 0})
	result = list_handle(&state, 6, bounds, Key_Event{key = .Left}, options)
	testing.expect(t, result == List_Result{} && state == List_State{0, 0})

	state = {2, 0}
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{2, 1})
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{2, 2})
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{3, 3})
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.handled && !result.changed && state == List_State{3, 3})
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Up, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{3, 2})

	state = {}
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 1, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{1, 1})

	state = {2, 2}
	result = list_handle(&state, 6, bounds, Mouse_Event{1, 2, .Left, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{4, 2})
	result = list_handle(&state, 6, bounds, Mouse_Event{3, 2, .Left, .Drag, {}}, options)
	testing.expect(t, result.changed && state == List_State{4, 3})
	result = list_handle(&state, 6, bounds, Mouse_Event{3, 0, .Left, .Press, {}}, options)
	testing.expect(t, result.changed && state == List_State{2, 0})
	result = list_handle(&state, 6, bounds, Mouse_Event{8, 0, .Wheel_Down, .Press, {}}, options)
	testing.expect(t, result == List_Result{} && state == List_State{2, 0})
	result = list_handle(&state, 0, bounds, Key_Event{key = .Enter}, options)
	testing.expect(t, result.handled && !result.submitted && state == List_State{})
}

@(test)
list_test_clipping_and_no_allocations :: proc(t: ^testing.T) {
	allocator_state := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &allocator_state}
	grid, err := grid_init(4, 3, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	context.allocator = allocator
	items := []string{"abcde", "second", "third", "fourth"}
	state := List_State{}
	testing.expect(t, push_clip(&grid, {1, 0, 2, 3}))
	draw_list(&grid, {0, 0, 4, 3}, &state, items, {scrollbar = true})
	result := list_handle(&state, len(items), {0, 0, 4, 3}, Key_Event{key = .Down})
	testing.expect(t, result.changed && state.selected == 1)
	index, ok := list_index_at(&state, len(items), {0, 0, 4, 3}, 1, 1)
	testing.expect(t, ok && index == 1 && allocator_state.remaining == 0)
	box_test_cell(t, &grid, 0, 0, BLANK_CELL)
	box_test_cell(t, &grid, 1, 0, {'b', {attributes = {.Reverse}}})
	box_test_cell(t, &grid, 2, 0, {'…', {attributes = {.Reverse}}})
	pop_clip(&grid)
}

@(test)
list_test_defaults_and_empty_geometry :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 3)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	items := []string{"abc", "z"}
	highlight := Style{bg = rgb(4, 5, 6)}
	state := List_State{selected = 99, offset = 99}
	options := List_Options{selected_style = highlight, scrollbar = true, item_height = -1}
	index, ok := list_index_at(&state, len(items), {0, 0, 4, 3}, 3, 1, options)
	testing.expect(t, ok && index == 1 && state == List_State{99, 99})
	draw_list(&grid, {0, 0, 4, 3}, &state, items, options)
	testing.expect(t, state == List_State{1, 0})
	box_test_cell(t, &grid, 3, 1, {' ', highlight})
	box_test_cell(t, &grid, 3, 0, BLANK_CELL)
	view := list_begin(&state, len(items), {0, 0, -1, 3})
	_, _, ok = list_next(&view)
	testing.expect(t, !ok)
	_, ok = list_index_at(&state, len(items), {0, 0, 4, 0}, 0, 0)
	testing.expect(t, !ok)
	list_move(&state, 3, min(int), true)
	testing.expect(t, state.selected == 2)
}
