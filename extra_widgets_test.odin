package odintui

import "base:runtime"
import "core:testing"

@(test)
modal_test_backdrops_and_input :: proc(t: ^testing.T) {
	grid, err := grid_init(12, 7)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	fill(&grid, 0, 0, 12, 7, {'x', {}})
	content := draw_modal(&grid, grid_bounds(&grid), {width = 6, height = 5, box = {title = "ok"}})
	testing.expect(t, content == Rect{4, 2, 4, 3})
	box_test_cell(t, &grid, 0, 0, {'x', {attributes = {.Dim}}})
	box_test_cell(t, &grid, 3, 1, {'┌', {}})
	box_test_cell(t, &grid, 4, 2, BLANK_CELL)
	result := modal_handle(Key_Event{key = .Escape})
	testing.expect(t, result.handled && result.cancelled && !result.submitted)
	result = modal_handle(Key_Event{key = .Enter})
	testing.expect(t, result.handled && result.submitted && !result.cancelled)
	testing.expect(t, !modal_handle(Key_Event{key = .Escape, modifiers = {.Ctrl}}).handled)
	testing.expect(t, !modal_handle(Mouse_Event{}).handled)
	clear_style := Style{bg = rgb(1, 2, 3)}
	_ = draw_modal(&grid, grid_bounds(&grid), {width = 4, height = 3, backdrop = .Clear, backdrop_style = clear_style})
	box_test_cell(t, &grid, 0, 0, {' ', clear_style})
}

@(test)
spinner_test_frames :: proc(t: ^testing.T) {
	frames := []string{"◐", "界", "!"}
	opts := Spinner_Options{frames = frames, interval_ms = 25}
	testing.expect(t, spinner_frame(-1, opts) == "◐")
	testing.expect(t, spinner_frame(25, opts) == "界")
	testing.expect(t, spinner_frame(75, opts) == "◐")
	testing.expect(t, spinner_frame(80) == "/")
	grid, err := grid_init(3, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	draw_spinner(&grid, grid_bounds(&grid), 25, opts)
	box_test_cell(t, &grid, 0, 0, {'界', {}})
	box_test_cell(t, &grid, 1, 0, {CONTINUATION, {}})
}

@(test)
key_hints_test_priority_and_styles :: proc(t: ^testing.T) {
	grid, err := grid_init(24, 2)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	hints := []Key_Hint{
		{key = "a", label = "one", priority = 5},
		{key = "b", label = "two", priority = 1},
		{key = "?", label = "help", always_keep = true},
	}
	key_style := Style{attributes = {.Bold}}
	label_style := Style{attributes = {.Dim}}
	fill(&grid, 0, 0, 24, 1, {'.', {}})
	count := draw_key_hints(&grid, {0, 0, 14, 1}, hints, {key_style = key_style, label_style = label_style})
	testing.expect(t, count == 2)
	text_expect_row(t, &grid, 0, "a one   ? help..........")
	box_test_cell(t, &grid, 0, 0, {'a', key_style})
	box_test_cell(t, &grid, 1, 0, {' ', label_style})
	box_test_cell(t, &grid, 2, 0, {'o', label_style})
	fill(&grid, 0, 1, 24, 1, {'.', {}})
	count = draw_key_hints(&grid, {0, 1, 3, 1}, hints)
	testing.expect(t, count == 1)
	text_expect_row(t, &grid, 1, "? h.....................")
}

@(test)
toast_test_queue_expiry_and_drawing :: proc(t: ^testing.T) {
	grid, err := grid_init(12, 4)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	storage: [2]Toast
	stack := toast_init(storage[:])
	testing.expect(t, toast_push(&stack, {text = "old", expires_at_ms = 5}))
	testing.expect(t, toast_push(&stack, {text = "界", expires_at_ms = 10}))
	testing.expect(t, toast_push(&stack, {text = "new"}))
	testing.expect(t, stack.count == 2 && stack.items[0].text == "界")
	style := Style{bg = rgb(3, 4, 5)}
	testing.expect(t, draw_toasts(&grid, grid_bounds(&grid), &stack, 9, {style = style}) == 2)
	box_test_cell(t, &grid, 8, 2, {' ', style})
	box_test_cell(t, &grid, 9, 2, {'界', style})
	box_test_cell(t, &grid, 10, 2, {CONTINUATION, style})
	box_test_cell(t, &grid, 8, 3, {'n', style})
	testing.expect(t, toast_expire(&stack, 10) == 1 && stack.count == 1)
	testing.expect(t, stack.items[0].text == "new")
	no_storage := toast_init(nil)
	testing.expect(t, !toast_push(&no_storage, {text = "x"}))
}

@(test)
badge_big_text_and_definitions :: proc(t: ^testing.T) {
	grid, err := grid_init(12, 8)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	style := Style{bg = rgb(1, 2, 3)}
	area := draw_badge(&grid, {0, 0, 12, 1}, "界", {style = style})
	testing.expect(t, area == Rect{0, 0, 4, 1})
	box_test_cell(t, &grid, 1, 0, {'界', style})
	box_test_cell(t, &grid, 2, 0, {CONTINUATION, style})
	_ = draw_big_text(&grid, {0, 1, 12, 2}, "ABCD\nEFGH", {}, {
		align = .Center, reveal = true, reveal_fraction = 0.5,
	})
	text_expect_row(t, &grid, 1, "    AB      ")
	text_expect_row(t, &grid, 2, "    EF      ")
	items := []Definition{{"name", "hello world"}, {"id", "界"}}
	count := draw_definition_list(&grid, {0, 3, 12, 5}, items)
	testing.expect(t, count == 2)
	text_expect_row(t, &grid, 3, "name  hello ")
	text_expect_row(t, &grid, 4, "      world ")
	text_expect_row(t, &grid, 5, "id    界    ")
	cell, _ := get_cell(&grid, 0, 3)
	testing.expect(t, .Dim in cell.style.attributes)
}

@(test)
extra_widgets_no_allocation :: proc(t: ^testing.T) {
	failing := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &failing}
	grid, err := grid_init(20, 6, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [120]u32
	urls := []string{"https://example.test"}
	storage: [2]Toast
	stack := toast_init(storage[:])
	hints := []Key_Hint{{key = "?", label = "help", always_keep = true}}
	defs := []Definition{{"a", "wide 界 text"}}
	context.allocator = allocator
	_ = grid_enable_links(&grid, current[:], presented[:], urls)
	_ = grid_link_rect(&grid, {0, 0, 2, 1}, 1)
	_ = draw_modal(&grid, grid_bounds(&grid), {width = 8, height = 4})
	draw_spinner(&grid, {0, 0, 2, 1}, 100)
	_ = draw_key_hints(&grid, {0, 5, 20, 1}, hints)
	_ = toast_push(&stack, {text = "message", expires_at_ms = 100})
	_ = draw_toasts(&grid, grid_bounds(&grid), &stack, 1)
	_ = draw_badge(&grid, {0, 0, 10, 1}, "ok")
	_ = draw_big_text(&grid, {0, 0, 10, 2}, "AB\nCD")
	_ = draw_definition_list(&grid, grid_bounds(&grid), defs)
	writer: ansi_Test_Writer
	ansi := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, synchronized_output = true}
	ansi_bind_links(&ansi, &grid)
	testing.expect(t, render(&grid, ansi_backend(&ansi)))
	testing.expect(t, ansi_set_title(&ansi, "title") && ansi_set_clipboard(&ansi, []byte{1, 2, 3}))
	testing.expect(t, failing.remaining == 0)
}
