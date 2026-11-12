package main

import tui "../.."
import "base:intrinsics"
import "core:fmt"
import "core:os"

Panel :: enum {Text, Form, Controls, Log}
PANEL_COUNT :: 4

App :: struct {
	quit:     bool,
	focused:  Panel,
	bounds:   [PANEL_COUNT]tui.Rect,
	text:     Text_Panel_State,
	form:     Form_Panel_State,
	controls: Controls_Panel_State,
	log:      Log_Panel_State,
	status:   [192]byte,
	status_n: int,
}

app_init :: proc(app: ^App) {
	form_init(&app.form)
	app.controls.value = 0.4
}

app_focus :: proc(app: ^App, panel: Panel) {
	if app.focused != panel {
		app.text.dragging = false
		app.controls.dragging = false
		app.focused = panel
		if panel == .Form {
			app.form.editing = true
		}
	}
}

app_event :: proc(app: ^App, event: tui.Input_Event) {
	secret := app.focused == .Form && app.form.editing && app.form.selected == 1
	log_event(&app.log, event, secret)
	if key, ok := event.(tui.Key_Event); ok {
		if key.key == .Rune && key.rune == 'c' && .Ctrl in key.modifiers {
			app.quit = true
			return
		}
		if key.key == .Tab && (key.modifiers == {} || key.modifiers == {.Shift}) {
			direction := 1
			if .Shift in key.modifiers {
				direction = -1
			}
			app_focus(app, Panel((int(app.focused)+direction+PANEL_COUNT)%PANEL_COUNT))
			return
		}
		if key.key == .Rune && key.rune == 'q' && key.modifiers == {} &&
		   !(app.focused == .Form && app.form.editing) {
			app.quit = true
			return
		}
	}
	if mouse, ok := event.(tui.Mouse_Event); ok {
		if mouse.button == .Left && mouse.action == .Press {
			for bounds, i in app.bounds {
				if tui.rect_contains(bounds, mouse.x, mouse.y) {
					app_focus(app, Panel(i))
					break
				}
			}
		}
		switch app.focused {
		case .Text: text_mouse(&app.text, mouse)
		case .Form: form_mouse(&app.form, mouse)
		case .Controls: controls_mouse(&app.controls, mouse)
		case .Log:
		}
		return
	}
	switch app.focused {
	case .Text:
		if key, ok := event.(tui.Key_Event); ok {
			text_key(&app.text, key)
		}
	case .Form:
		if form_event(&app.form, event) {
			message := fmt.bprintf(app.status[:], "Submitted: %s", tui.text_field_text(&app.form.name))
			app.status_n = len(message)
		}
	case .Controls:
		if key, ok := event.(tui.Key_Event); ok {
			controls_key(&app.controls, key)
		}
	case .Log:
	}
}

app_layout :: proc(app: ^App, bounds: tui.Rect) -> (title, status: tui.Rect) {
	rows := tui.layout_split_n(bounds, .Column, [3]tui.Constraint{
		tui.layout_fixed(1), tui.layout_fill(), tui.layout_fixed(1),
	})
	title, status = rows[0], rows[2]
	body := rows[1]
	if body.width < 70 {
		panels := tui.layout_split_n(body, .Column, [4]tui.Constraint{
			tui.layout_percent(35), tui.layout_fixed(7), tui.layout_fill(), tui.layout_fill(),
		})
		app.bounds = panels
	} else {
		columns := tui.layout_split_n(body, .Row, [3]tui.Constraint{
			tui.layout_percent(40), tui.layout_fixed(26), tui.layout_fill(),
		}, 1)
		middle := tui.layout_split_n(columns[1], .Column, [2]tui.Constraint{
			tui.layout_fixed(8), tui.layout_fill(),
		})
		app.bounds = {columns[0], middle[0], middle[1], columns[2]}
	}
	return title, status
}

app_draw :: proc(grid: ^tui.Grid, app: ^App) {
	bounds := tui.grid_bounds(grid)
	tui.fill(grid, bounds.x, bounds.y, bounds.width, bounds.height, tui.BLANK_CELL)
	title, status := app_layout(app, bounds)
	tui.fill(grid, title.x, title.y, title.width, title.height, {' ', {bg = color("#263448")}})
	tui.draw_label(grid, title, " odintui | Interactive showcase", {
		fg = color("#61dafb"), bg = color("#263448"), attributes = {.Bold},
	})
	draw_text_panel(grid, app.bounds[0], &app.text, app.focused == .Text)
	draw_form_panel(grid, app.bounds[1], &app.form, app.focused == .Form)
	draw_controls_panel(grid, app.bounds[2], &app.controls, app.focused == .Controls)
	draw_log_panel(grid, app.bounds[3], &app.log, app.focused == .Log)
	tui.fill(grid, status.x, status.y, status.width, status.height, {' ', {bg = color("#263448")}})
	hints := "Tab/Shift-Tab: panel  q: quit  Ctrl+C: quit"
	if app.focused == .Text {
		hints = "Arrows/PgUp/PgDn/wheel: scroll  Tab: panel  q: quit"
	} else if app.focused == .Form && app.form.editing {
		hints = "Up/Down: field  Enter: submit  Esc: leave field  Tab: panel  Ctrl+C: quit"
	} else if app.focused == .Form {
		hints = "Enter: edit  Tab: panel  q: quit"
	} else if app.focused == .Controls {
		hints = "Left/Right or mouse: slider  Tab: panel  q: quit"
	}
	text := hints
	buffer: [320]byte
	if app.status_n > 0 {
		text = fmt.bprintf(buffer[:], "%s | %s", string(app.status[:app.status_n]), hints)
	}
	tui.draw_label(grid, status, text, {fg = color("#c7d8e8"), bg = color("#263448")})
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
	app_init(&app)
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
