package main

import tui "../.."
import "base:runtime"
import "core:strings"
import "core:sys/posix"
import "core:testing"

@(test)
test_raw_attributes :: proc(t: ^testing.T) {
	saved := posix.termios{
		c_iflag = {.IXON, .ICRNL},
		c_oflag = {.OPOST},
		c_cflag = {.PARENB},
		c_lflag = {.ICANON, .ECHO, .ISIG, .IEXTEN},
	}
	raw := terminal_raw_attributes(saved)
	control := transmute(posix.tcflag_t)raw.c_cflag
	testing.expect(t, control & posix.tcflag_t(posix._CSIZE) == posix.tcflag_t(posix.CS8))
	testing.expect(t, .PARENB not_in raw.c_cflag)
	testing.expect(t, raw.c_iflag == {} && raw.c_oflag == {} && raw.c_lflag == {})
	testing.expect(t, raw.c_cc[.VMIN] == 1 && raw.c_cc[.VTIME] == 0)
}

@(test)
test_focus_form_and_password_log :: proc(t: ^testing.T) {
	app: App
	app_init(&app)
	app_event(&app, tui.Key_Event{key = .Tab})
	testing.expect(t, app.focused == .Form && app.form.editing)
	app_event(&app, tui.Key_Event{key = .Rune, rune = 'q'})
	testing.expect(t, !app.quit && tui.text_field_text(&app.form.name) == "q")
	app_event(&app, tui.Key_Event{key = .Enter})
	testing.expect(t, string(app.status[:app.status_n]) == "Submitted: q")
	app_event(&app, tui.Key_Event{key = .Down})
	app_event(&app, tui.Key_Event{key = .Rune, rune = 'x'})
	index := (app.log.next+LOG_LINES-1)%LOG_LINES
	testing.expect(t, strings.contains(string(app.log.lines[index][:app.log.sizes[index]]), "hidden"))
	testing.expect(t, tui.text_field_text(&app.form.password) == "x")
	app_event(&app, tui.Key_Event{key = .Escape})
	app_event(&app, tui.Key_Event{key = .Rune, rune = 'q'})
	testing.expect(t, app.quit)

	app.quit = false
	app.form.editing = true
	app_event(&app, tui.Key_Event{key = .Rune, rune = 'c', modifiers = {.Ctrl}})
	testing.expect(t, app.quit)
}

@(test)
test_scrolling_and_slider_mouse :: proc(t: ^testing.T) {
	grid, err := tui.grid_init(100, 30)
	testing.expect(t, err == .None)
	defer tui.grid_destroy(&grid)
	app: App
	app_init(&app)
	app_draw(&grid, &app)
	testing.expect(t, app.text.height > app.text.viewport.height)
	track := app.text.track
	app_event(&app, tui.Mouse_Event{
		x = track.x, y = track.y+track.height-1, button = .Left, action = .Press,
	})
	testing.expect(t, app.text.offset == app.text.height-app.text.viewport.height)
	app_event(&app, tui.Mouse_Event{
		x = track.x, y = track.y, button = .Left, action = .Drag,
	})
	testing.expect(t, app.text.offset == 0)
	app_event(&app, tui.Mouse_Event{button = .Left, action = .Release})
	testing.expect(t, !app.text.dragging)
	testing.expect(t, tui.current_clip(&grid) == tui.grid_bounds(&grid))

	slider := app.controls.slider
	app_event(&app, tui.Mouse_Event{
		x = slider.x+slider.width-1, y = slider.y, button = .Left, action = .Press,
	})
	testing.expect(t, app.focused == .Controls && app.controls.value == 1)
	app_event(&app, tui.Mouse_Event{
		x = slider.x-5, y = slider.y, button = .Left, action = .Drag,
	})
	testing.expect(t, app.controls.value == 0)
}

@(test)
test_partial_input_and_escape_timeout :: proc(t: ^testing.T) {
	app: App
	app_init(&app)
	term: Terminal
	term.pending[0], term.pending[1] = 0x1b, '['
	term.count = 2
	testing.expect(t, !terminal_parse(&term, &app, false) && term.count == 2)
	term.pending[2] = 'B'
	term.count = 3
	testing.expect(t, terminal_parse(&term, &app, false) && term.count == 0)
	testing.expect(t, app.log.count == 1)

	app_focus(&app, .Form)
	term.pending[0] = 0x1b
	term.count = 1
	testing.expect(t, !terminal_parse(&term, &app, false))
	testing.expect(t, terminal_parse(&term, &app, true))
	testing.expect(t, !app.form.editing && term.count == 0)
}

@(test)
test_paste_split_utf8 :: proc(t: ^testing.T) {
	form: Form_Panel_State
	form_init(&form)
	form.editing = true
	_ = form_event(&form, tui.Paste_Event{kind = .Start})
	first := [2]byte{'A', 0xe2}
	second := [1]byte{0x82}
	third := [2]byte{0xac, 'B'}
	_ = form_event(&form, tui.Paste_Event{kind = .Chunk, text = first[:]})
	_ = form_event(&form, tui.Paste_Event{kind = .Chunk, text = second[:]})
	_ = form_event(&form, tui.Paste_Event{kind = .Chunk, text = third[:]})
	_ = form_event(&form, tui.Paste_Event{kind = .End})
	testing.expect(t, tui.text_field_text(&form.name) == "A€B")
	testing.expect(t, form.paste_n == 0)
}

Frame_Test_Backend :: struct {
	runs, flushes: int,
}

frame_test_draw :: proc(data: rawptr, x, y: int, cells: []tui.Cell) -> bool {
	_ = x
	_ = y
	_ = cells
	(^Frame_Test_Backend)(data).runs += 1
	return true
}

frame_test_flush :: proc(data: rawptr) -> bool {
	(^Frame_Test_Backend)(data).flushes += 1
	return true
}

frame_test_allocator :: proc(
	data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int,
	old_memory: rawptr, old_size: int, location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	_ = size
	_ = alignment
	_ = old_memory
	_ = old_size
	_ = location
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize {
		(^int)(data)^ += 1
	}
	return nil, .Out_Of_Memory
}

@(test)
test_frames_do_not_allocate_and_diff_unchanged :: proc(t: ^testing.T) {
	grid, err := tui.grid_init(100, 30)
	testing.expect(t, err == .None)
	defer tui.grid_destroy(&grid)
	app: App
	app_init(&app)
	mock: Frame_Test_Backend
	backend := tui.Backend{&mock, frame_test_draw, frame_test_flush}
	attempts := 0
	allocator := runtime.Allocator{procedure = frame_test_allocator, data = &attempts}
	saved_allocator, saved_temp := context.allocator, context.temp_allocator
	context.allocator, context.temp_allocator = allocator, allocator
	app_draw(&grid, &app)
	first_ok := tui.render(&grid, backend)
	runs := mock.runs
	app_draw(&grid, &app)
	second_ok := tui.render(&grid, backend)
	same_runs := mock.runs == runs
	app_event(&app, tui.Key_Event{key = .Tab})
	app_event(&app, tui.Key_Event{key = .Rune, rune = 'A'})
	paste := [2]byte{'B', 'C'}
	app_event(&app, tui.Paste_Event{kind = .Start})
	app_event(&app, tui.Paste_Event{kind = .Chunk, text = paste[:]})
	app_event(&app, tui.Paste_Event{kind = .End})
	app_event(&app, tui.Key_Event{key = .Enter})
	app_event(&app, tui.Focus_Event{focused = true})
	app_event(&app, tui.Mouse_Event{x = 1, y = 2, button = .Wheel_Down, action = .Press})
	app_draw(&grid, &app)
	third_ok := tui.render(&grid, backend)
	context.allocator, context.temp_allocator = saved_allocator, saved_temp
	testing.expect(t, attempts == 0)
	testing.expect(t, first_ok && second_ok && third_ok && same_runs && mock.flushes == 2)
}
