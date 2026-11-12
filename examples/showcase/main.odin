package main

import tui "../.."
import "base:intrinsics"
import "core:fmt"
import "core:os"

App :: struct {
	quit: bool,
}

app_event :: proc(app: ^App, event: tui.Input_Event) {
	key, ok := event.(tui.Key_Event)
	if ok && ((key.key == .Rune && key.rune == 'q' && key.modifiers == {}) ||
	          (key.key == .Rune && key.rune == 'c' && .Ctrl in key.modifiers)) {
		app.quit = true
	}
}

app_draw :: proc(grid: ^tui.Grid, app: ^App) {
	_ = app
	bounds := tui.grid_bounds(grid)
	tui.fill(grid, bounds.x, bounds.y, bounds.width, bounds.height, tui.BLANK_CELL)
	tui.draw_label(grid, bounds, "odintui showcase - q to quit")
}

run :: proc() -> bool {
	term: Terminal
	defer terminal_close(&term)
	if !terminal_open(&term) {
		fmt.eprintln("showcase: requires a terminal on stdin and stdout; unable to enter raw mode")
		return false
	}
	width, height := terminal_size()
	grid, err := tui.grid_init(width, height)
	if err != .None {
		return false
	}
	defer tui.grid_destroy(&grid)
	app: App
	redraw := true
	for !app.quit && intrinsics.atomic_load(&terminal_signal) == 0 {
		width, height = terminal_size()
		if width != grid.width || height != grid.height {
			if tui.grid_resize(&grid, width, height) != .None || !tui.ansi_clear(&term.ansi) {
				return false
			}
			tui.invalidate(&grid)
			redraw = true
		}
		if redraw {
			app_draw(&grid, &app)
			if !tui.render(&grid, tui.ansi_backend(&term.ansi)) {
				return false
			}
			redraw = false
		}
		switch terminal_poll(&term, &app) {
		case .Input: redraw = true
		case .Closed: return true
		case .Error: return false
		case .Waiting:
		}
	}
	return intrinsics.atomic_load(&terminal_signal) == 0
}

main :: proc() {
	if !run() {
		fmt.eprintln("showcase: terminal or rendering failed")
		os.exit(1)
	}
}
