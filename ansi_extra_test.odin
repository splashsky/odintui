package odintui

import "core:testing"

@(test)
ansi_test_extras_and_sanitization :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	testing.expect(t, ansi_set_title(&state, "hi\x1b]2;evil\x07\u009b!\xff"))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b]2;hi]2;evil!\x1b\\")
	writer.len = 0
	testing.expect(t, ansi_set_cursor_shape(&state, .Steady_Bar))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[6 q")
	writer.len = 0
	testing.expect(t, ansi_set_clipboard(&state, []byte{0, 0x1b, 0xff, 'a'}))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b]52;c;ABv/YQ==\x1b\\")
	writer.len = 0
	large: [ANSI_CLIPBOARD_MAX+1]byte
	testing.expect(t, !ansi_set_clipboard(&state, large[:]) && writer.len == 0)
	testing.expect(t, !ansi_set_title(nil, "x") && !ansi_set_clipboard(nil, nil))
	testing.expect(t, !ansi_set_cursor_shape(nil, .Default))
}

@(test)
ansi_test_links_and_synchronized_frames :: proc(t: ^testing.T) {
	grid, err := grid_init(4, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [4]u32
	urls := []string{"https://a/\x1b]evil\x07\u009b", "https://b"}
	testing.expect(t, !grid_enable_links(&grid, current[:], current[:], urls))
	testing.expect(t, grid_enable_links(&grid, current[:], presented[:], urls))
	draw_text(&grid, 0, 0, "界ab")
	testing.expect(t, grid_link_rect(&grid, {1, 0, 2, 1}, 1))
	testing.expect(t, current == [4]u32{1, 1, 1, 0})
	testing.expect(t, !grid_link_rect(&grid, grid_bounds(&grid), 3))
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, synchronized_output = true}
	ansi_bind_links(&state, &grid)
	testing.expect(t, render(&grid, ansi_backend(&state)))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x1b[?2026h\x1b[1;1H\x1b]8;;https://a/]evil\x1b\\\x1b[0m界a\x1b]8;;\x1b\\b\x1b[0m\x1b[?2026l")
	writer.len = 0
	testing.expect(t, grid_link_rect(&grid, {0, 0, 1, 1}, 2))
	testing.expect(t, render(&grid, ansi_backend(&state)))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x1b[?2026h\x1b[1;1H\x1b]8;;https://b\x1b\\\x1b[0m界\x1b]8;;\x1b\\\x1b[0m\x1b[?2026l")
	writer.len = 0
	testing.expect(t, render(&grid, ansi_backend(&state)) && writer.len == 0)
	grid_disable_links(&grid)
	testing.expect(t, !grid_link_rect(&grid, grid_bounds(&grid), 1))
}

@(test)
ansi_test_synchronized_failure_recovery :: proc(t: ^testing.T) {
	grid, err := grid_init(1, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [1]u32
	urls := []string{"https://example.test"}
	testing.expect(t, grid_enable_links(&grid, current[:], presented[:], urls))
	testing.expect(t, grid_link_rect(&grid, {0, 0, 1, 1}, 1))
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, synchronized_output = true}
	ansi_bind_links(&state, &grid)
	testing.expect(t, !render(&grid, ansi_backend(&state)))
	writer.short, writer.len = false, 0
	testing.expect(t, render(&grid, ansi_backend(&state)))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x18\x1b]8;;\x1b\\\x1b[?2026l\x1b[?2026h\x1b[1;1H\x1b]8;;https://example.test\x1b\\\x1b[0m \x1b]8;;\x1b\\\x1b[0m\x1b[?2026l")
}
