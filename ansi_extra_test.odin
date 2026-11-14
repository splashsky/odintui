package odintui

import "core:testing"
import "core:strings"

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
	_, invalid := link_grid_init(&grid, current[:], current[:], urls)
	testing.expect(t, !invalid)
	links, valid := link_grid_init(&grid, current[:], presented[:], urls)
	testing.expect(t, valid)
	draw_text(&grid, 0, 0, "界ab")
	testing.expect(t, link_grid_set(&links, {1, 0, 2, 1}, 1))
	testing.expect(t, current == [4]u32{1, 1, 1, 0})
	testing.expect(t, !link_grid_set(&links, grid_bounds(&grid), 3))
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, links = &links, synchronized_output = true}
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x1b[?2026h\x1b[1;1H\x1b]8;;https://a/]evil\x1b\\\x1b[0m界a\x1b]8;;\x1b\\b\x1b[0m\x1b[?2026l")
	writer.len = 0
	testing.expect(t, link_grid_set(&links, {0, 0, 1, 1}, 2))
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x1b[?2026h\x1b[1;1H\x1b]8;;https://b\x1b\\\x1b[0m界\x1b]8;;\x1b\\\x1b[0m\x1b[?2026l")
	writer.len = 0
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links) && writer.len == 0)
	link_grid_destroy(&links)
	testing.expect(t, !link_grid_set(&links, grid_bounds(&grid), 1))
}

@(test)
ansi_test_synchronized_failure_recovery :: proc(t: ^testing.T) {
	grid, err := grid_init(1, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [1]u32
	urls := []string{"https://example.test"}
	links, valid := link_grid_init(&grid, current[:], presented[:], urls)
	testing.expect(t, valid)
	testing.expect(t, link_grid_set(&links, {0, 0, 1, 1}, 1))
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, links = &links, synchronized_output = true}
	testing.expect(t, !render_linked(&grid, ansi_extended_backend(&ext), &links))
	writer.short, writer.len = false, 0
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect_value(t, ansi_test_text(&writer),
		"\x18\x1b]8;;\x1b\\\x1b[?2026l\x1b[?2026h\x1b[1;1H\x1b]8;;https://example.test\x1b\\\x1b[0m \x1b]8;;\x1b\\\x1b[0m\x1b[?2026l")
}

@(test)
ansi_test_recovery_after_buffered_link_close :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [2]u32
	urls := []string{"https://example.test"}
	links, _ := link_grid_init(&grid, current[:], presented[:], urls)
	_ = link_grid_set(&links, {0, 0, 1, 1}, 1)
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, links = &links}
	testing.expect(t, !render_linked(&grid, ansi_extended_backend(&ext), &links))
	// The close was queued but the short write may not have reached it.
	writer.short, writer.len = false, 0
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect(t, strings.has_prefix(ansi_test_text(&writer), "\x18\x1b]8;;\x1b\\"))
}

@(test)
ansi_test_extended_recover_before_leave :: proc(t: ^testing.T) {
	grid, err := grid_init(1, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, synchronized_output = true}
	testing.expect(t, !render(&grid, ansi_extended_backend(&ext)))
	writer.short, writer.len = false, 0
	testing.expect(t, ansi_extended_recover(&ext))
	testing.expect_value(t, ansi_test_text(&writer), "\x18\x1b[?2026l")
	testing.expect(t, ansi_extended_recover(&ext))
}

@(test)
ansi_test_link_plane_normalization_and_resize :: proc(t: ^testing.T) {
	grid, err := grid_init(3, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [3]u32
	urls := []string{"a", "b"}
	links, ok := link_grid_init(&grid, current[:], presented[:], urls)
	testing.expect(t, ok)
	_ = link_grid_set(&links, {0, 0, 1, 1}, 1)
	_ = link_grid_set(&links, {1, 0, 1, 1}, 2)
	set_cell(&grid, 0, 0, {'界', {}})
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, links = &links}
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect(t, current[0] == 1 && current[1] == 1)
	testing.expect(t, grid_resize(&grid, 2, 1) == .None)
	testing.expect(t, !render_linked(&grid, ansi_extended_backend(&ext), &links))
	link_grid_destroy(&links)
}

@(test)
ansi_test_existing_positional_literals :: proc(t: ^testing.T) {
	cell := Cell{' ', {}}
	style := Style{Color{}, Color{}, {}}
	span := Span{"x", style}
	grid := Grid{0, 0, {}, nil, nil, nil, 0, 0, false, {}, 0, {}}
	state := Ansi_Backend{{}, .Truecolor, 0, {}, 0, 0, 0, false, {}, false, .Truecolor, false}
	testing.expect(t, cell == BLANK_CELL && span.text == "x" && grid.width == 0 && !state.cancel)
}

@(test)
ansi_test_wide_replacement_is_rejected :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, replacement = '🇦'}
	backend := ansi_backend(&state)
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, []Cell{{'\x1b', {}}}))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m?\x1b[0m")
}

@(test)
ansi_test_long_link_and_repeated_recovery :: proc(t: ^testing.T) {
	grid, err := grid_init(1, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [1]u32
	long_url: [5000]byte
	for &b in long_url { b = 'a' }
	urls := []string{string(long_url[:])}
	links, ok := link_grid_init(&grid, current[:], presented[:], urls)
	testing.expect(t, ok && link_grid_set(&links, grid_bounds(&grid), 1))
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	ext := Ansi_Extended_Backend{ansi = &state, links = &links, synchronized_output = true}
	testing.expect(t, !render_linked(&grid, ansi_extended_backend(&ext), &links))
	// Failing again while sending recovery must not forget the pending resets.
	writer.len = 0
	testing.expect(t, !ansi_extended_recover(&ext))
	writer.short, writer.len = false, 0
	testing.expect(t, ansi_extended_recover(&ext))
	testing.expect_value(t, ansi_test_text(&writer), "\x18\x1b]8;;\x1b\\\x1b[?2026l")
	writer.len = 0
	testing.expect(t, render_linked(&grid, ansi_extended_backend(&ext), &links))
	testing.expect(t, strings.contains(ansi_test_text(&writer), "\x1b]8;;aaaa"))
	testing.expect(t, strings.has_suffix(ansi_test_text(&writer), "\x1b]8;;\x1b\\\x1b[0m\x1b[?2026l"))
}

@(test)
ansi_test_continuation_metadata_diff_includes_lead :: proc(t: ^testing.T) {
	grid, err := grid_init(3, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	current, presented: [3]u32
	urls := []string{"a", "b"}
	links, ok := link_grid_init(&grid, current[:], presented[:], urls)
	testing.expect(t, ok)
	set_cell(&grid, 0, 0, {'界', {}})
	_ = link_grid_set(&links, {0, 0, 2, 1}, 1)
	mock: Mock_Backend
	testing.expect(t, render_linked(&grid, mock_backend(&mock), &links))
	// Simulate a stale presented plane and a narrow dirty interval.
	links.presented[1] = 2
	grid_mark_dirty(&grid, 0, 1, 2)
	testing.expect(t, render_linked(&grid, mock_backend(&mock), &links))
	testing.expect(t, mock.calls[1] == Call{0, 0, 2})
}
