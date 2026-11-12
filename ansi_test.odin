package odintui

import "base:runtime"
import "core:io"
import "core:testing"

@(private)
ansi_Test_Writer :: struct {
	bytes:  [16384]byte,
	len:    int,
	writes: int,
	limit:  int,
	short:  bool,
	fail:   bool,
}

@(private)
ansi_test_writer_proc :: proc(
	data: rawptr,
	mode: io.Stream_Mode,
	p: []byte,
	offset: i64,
	whence: io.Seek_From,
) -> (i64, io.Error) {
	writer := (^ansi_Test_Writer)(data)
	if mode != .Write {
		return 0, .Unsupported
	}
	n := min(len(p), len(writer.bytes)-writer.len)
	if writer.limit > 0 {
		n = min(n, writer.limit)
	}
	if writer.short && n > 0 {
		n -= 1
	}
	copy(writer.bytes[writer.len:], p[:n])
	writer.len += n
	writer.writes += 1
	if writer.fail {
		return i64(n), .Unknown
	}
	return i64(n), nil
}

@(private)
ansi_test_text :: proc(writer: ^ansi_Test_Writer) -> string {
	return string(writer.bytes[:writer.len])
}

@(test)
ansi_test_frame_and_buffering :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	bold := Style{attributes = {.Bold}}
	first := []Cell{{'a', bold}, {'b', bold}}
	second := []Cell{{'c', bold}, {'d', {}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, first))
	testing.expect(t, backend.draw_run(backend.user_data, 2, 0, second))
	testing.expect(t, writer.writes == 0)
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect(t, writer.writes == 1)
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0;1mabc\x1b[0md\x1b[0m")
}

@(test)
ansi_test_failure_resynchronizes :: proc(t: ^testing.T) {
	writer := ansi_Test_Writer{limit = 4}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	cells := []Cell{{'a', {attributes = {.Bold}}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, !backend.flush(backend.user_data))
	writer.limit, writer.len = 0, 0
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x18\x1b[1;1H\x1b[0;1ma\x1b[0m")
}

@(test)
ansi_test_colors_and_attributes :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	all := bit_set[Attribute; u8]{
		.Bold, .Dim, .Italic, .Underline, .Blink, .Reverse, .Hidden, .Strikethrough,
	}
	cells := []Cell{{'a', {rgb(255, 0, 0), rgb(128, 128, 128), all}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(
		t, ansi_test_text(&writer),
		"\x1b[1;1H\x1b[0;1;2;3;4;5;7;8;9;38;2;255;0;0;48;2;128;128;128ma\x1b[0m",
	)
	writer.len = 0
	state.color_mode = .Color_256
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(
		t, ansi_test_text(&writer),
		"\x1b[1;1H\x1b[0;1;2;3;4;5;7;8;9;38;5;196;48;5;244ma\x1b[0m",
	)
	writer.len = 0
	state.color_mode = .Color_16
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(
		t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0;1;2;3;4;5;7;8;9;91;100ma\x1b[0m",
	)
}

@(test)
ansi_test_color_changes_within_run :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, color_mode = .Color_256}
	backend := ansi_backend(&state)
	style := Style{fg = rgb(0, 95, 255), bg = rgb(8, 8, 8)}
	cells := []Cell{{'a', style}, {'b', style}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells[:1]))
	state.color_mode = .Color_16
	testing.expect(t, backend.draw_run(backend.user_data, 1, 0, cells[1:]))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(
		t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0;38;5;27;48;5;232ma\x1b[0;94;40mb\x1b[0m",
	)
}

@(test)
ansi_test_sanitizes_cells_and_replacement :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, replacement = '·'}
	backend := ansi_backend(&state)
	cells := []Cell{
		{'A', {}}, {'é', {}}, {'\x1b', {}}, {rune(0x7f), {}}, {rune(0x9b), {}},
		{'界', {}}, {rune(0xd800), {}}, {rune(0x110000), {}}, {rune(-1), {}},
		{'\u0301', {}}, {'\u200d', {}}, {'\u1161', {}},
	}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0mAé··········\x1b[0m")
	writer.len = 0
	state.replacement = '\x1b'
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells[2:3]))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m?\x1b[0m")
}

@(test)
ansi_test_single_column_spaces :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	cells := []Cell{{'\u00a0', {}}, {'\u2002', {}}, {'\u0301', {}}, {'\u093e', {}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m\u00a0\u2002??\x1b[0m")
}

@(test)
ansi_test_render_does_not_allocate :: proc(t: ^testing.T) {
	failing := Failing_Allocator{backing = context.allocator, remaining = 3}
	allocator := runtime.Allocator{procedure = failing_allocator_proc, data = &failing}
	grid, err := grid_init(70, 70, allocator)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}, color_mode = .Color_256}
	backend := ansi_backend(&state)
	fill(&grid, 0, 0, 70, 70, {'界', {fg = rgb(100, 100, 100)}})
	context.allocator = allocator
	testing.expect(t, render(&grid, backend))
	testing.expect(t, writer.writes > 1)
	set_cell(&grid, 0, 0, {'é', {}})
	testing.expect(t, render(&grid, backend))
}

@(test)
ansi_test_terminal_modes_and_cursor :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	modes := Ansi_Terminal_Modes{
		.Alt_Screen, .Hide_Cursor, .Mouse, .Bracketed_Paste, .Focus, .Kitty_Keyboard,
	}
	testing.expect(t, ansi_enter(&state, modes))
	testing.expect_value(
		t, ansi_test_text(&writer),
		"\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[?1004h\x1b[>1u",
	)
	writer.len = 0
	testing.expect(t, ansi_set_cursor(&state, 9, 2, true))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[3;10H\x1b[?25h")
	writer.len = 0
	testing.expect(t, ansi_set_cursor(&state, 0, 0, false))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[?25l")
	writer.len = 0
	testing.expect(t, ansi_clear(&state))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[0m\x1b[2J\x1b[H")
	writer.len = 0
	testing.expect(t, ansi_leave(&state, modes))
	testing.expect_value(
		t, ansi_test_text(&writer),
		"\x1b[<u\x1b[?1004l\x1b[?2004l\x1b[?1006l\x1b[?1002l\x1b[?25h\x1b[?1049l\x1b[0m\x1b[?25h",
	)
}

@(test)
ansi_test_mode_changes_invalidate_terminal_state :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	cells := []Cell{{'a', {attributes = {.Bold}}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect(t, ansi_enter(&state, {.Alt_Screen}))
	writer.len = 0
	testing.expect(t, backend.draw_run(backend.user_data, 1, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;2H\x1b[0;1ma\x1b[0m")
}

@(test)
ansi_test_render_retry_after_partial_writes :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer := ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	set_cell(&grid, 1, 0, {'x', {attributes = {.Bold}}})
	testing.expect(t, !render(&grid, backend))
	writer.short, writer.len = false, 0
	set_cell(&grid, 0, 0, {'z', {}})
	testing.expect(t, render(&grid, backend))
	testing.expect_value(t, ansi_test_text(&writer), "\x18\x1b[1;1H\x1b[0mz\x1b[0;1mx\x1b[0m")
}

@(test)
ansi_test_stream_failure_during_draw :: proc(t: ^testing.T) {
	grid, err := grid_init(5000, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer := ansi_Test_Writer{fail = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	testing.expect(t, !render(&grid, backend))
	testing.expect(t, writer.writes == 1)
	writer.fail, writer.len = false, 0
	testing.expect(t, render(&grid, backend))
	text := ansi_test_text(&writer)
	testing.expect(t, len(text) > 5000 && text[:11] == "\x18\x1b[1;1H\x1b[0m")
}

@(test)
ansi_test_invalidation_after_external_changes :: proc(t: ^testing.T) {
	grid, err := grid_init(2, 1)
	testing.expect(t, err == .None)
	defer grid_destroy(&grid)
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	testing.expect(t, render(&grid, backend))
	testing.expect(t, ansi_set_cursor(&state, 0, 0, true))
	// The host may have changed cursor or SGR outside this backend.
	writer.len = 0
	invalidate(&grid)
	testing.expect(t, render(&grid, backend))
	testing.expect_value(t, ansi_test_text(&writer), "\x1b[1;1H\x1b[0m  \x1b[0m")
}

@(test)
ansi_test_invalid_arguments_and_writer :: proc(t: ^testing.T) {
	writer: ansi_Test_Writer
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	cells := []Cell{{'a', {}}}
	testing.expect(t, !backend.draw_run(backend.user_data, -1, 0, cells))
	testing.expect(t, !backend.draw_run(backend.user_data, max(int), 0, cells))
	testing.expect(t, !backend.draw_run(backend.user_data, max(int)-1, max(int), cells))
	testing.expect(t, !ansi_set_cursor(&state, 0, max(int), true))
	testing.expect(t, !ansi_clear(nil))
	testing.expect(t, !ansi_enter(nil, {}))
	testing.expect(t, !ansi_leave(nil, {}))
	testing.expect(t, !ansi_set_cursor(nil, 0, 0, true))
	testing.expect(t, !ansi_backend(nil).draw_run(nil, 0, 0, cells))
	testing.expect(t, !ansi_backend(nil).flush(nil))
	missing_writer: Ansi_Backend
	testing.expect(t, !ansi_clear(&missing_writer))
	testing.expect(t, ansi_set_cursor(&state, max(int)-1, max(int)-1, true))
}
