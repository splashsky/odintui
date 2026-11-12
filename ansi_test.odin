package odintui

import "core:io"
import "core:testing"

@(private)
Ansi_Test_Writer :: struct {
	bytes:  [16384]byte,
	len:    int,
	writes: int,
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
	writer := (^Ansi_Test_Writer)(data)
	if mode != .Write {
		return 0, .Unsupported
	}
	n := min(len(p), len(writer.bytes)-writer.len)
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
ansi_test_text :: proc(writer: ^Ansi_Test_Writer) -> string {
	return string(writer.bytes[:writer.len])
}

@(test)
ansi_test_frame_and_buffering :: proc(t: ^testing.T) {
	writer: Ansi_Test_Writer
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
	writer := Ansi_Test_Writer{short = true}
	state := Ansi_Backend{writer = {ansi_test_writer_proc, &writer}}
	backend := ansi_backend(&state)
	cells := []Cell{{'a', {attributes = {.Bold}}}}
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, !backend.flush(backend.user_data))
	writer.short, writer.len = false, 0
	testing.expect(t, backend.draw_run(backend.user_data, 0, 0, cells))
	testing.expect(t, backend.flush(backend.user_data))
	testing.expect_value(t, ansi_test_text(&writer), "\x18\x1b[1;1H\x1b[0;1ma\x1b[0m")
}
