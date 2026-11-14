package main

import tui "../.."
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:time"

Panel :: enum {Text, Form, Controls, Log, Files, Table}
PANEL_COUNT :: 6
WIDGETS_PAGE :: 0
DATA_PAGE :: 1
PAGE_LABELS :: [2]string{"Widgets", "Data"}

App :: struct {
	quit:     bool,
	page:     int,
	focused:  Panel,
	page_focus: [2]Panel,
	screen:   tui.Rect,
	tabs:     tui.Rect,
	bounds:   [PANEL_COUNT]tui.Rect,
	text:     Text_Panel_State,
	form:     Form_Panel_State,
	controls: Controls_Panel_State,
	log:      Log_Panel_State,
	files:    Files_Panel_State,
	table:    Table_Panel_State,
	status:   [192]byte,
	status_n: int,
	modal_open: bool,
	now_ms: i64,
	toast_storage: [4]tui.Toast,
	toasts: tui.Toast_Stack,
	links: ^tui.Link_Grid,
}

app_init :: proc(app: ^App) {
	form_init(&app.form)
	app.toasts = tui.toast_init(app.toast_storage[:])
	app.controls.value = 0.4
	app.page_focus[DATA_PAGE] = .Files
}

app_tab_options :: proc() -> tui.Tabs_Options {
	return {
		style = {fg = color("#b3c5d7"), bg = color("#263448")},
		selected_style = {fg = color("#263448"), bg = color("#61dafb"), attributes = {.Bold}},
		separator = '│',
	}
}

app_focus :: proc(app: ^App, panel: Panel) {
	if app.focused != panel {
		app.text.dragging = false
		app.controls.dragging = false
		app.focused = panel
		app.page_focus[app.page] = panel
		if panel == .Form {
			app.form.editing = true
		}
	}
}

app_select_page :: proc(app: ^App, page: int) {
	chosen := clamp(page, WIDGETS_PAGE, DATA_PAGE)
	if app.page == chosen {
		return
	}
	app.page_focus[app.page] = app.focused
	app.text.dragging = false
	app.controls.dragging = false
	app.page = chosen
	app.focused = app.page_focus[chosen]
	// Input can contain a page switch and another event in the same read.
	_, _ = app_layout(app, app.screen)
	if app.page == WIDGETS_PAGE {
		text_layout(&app.text, tui.box_content(app.bounds[int(Panel.Text)]))
		_ = form_layout(&app.form, tui.box_content(app.bounds[int(Panel.Form)]))
		app.controls.slider = controls_slider_bounds(tui.box_content(app.bounds[int(Panel.Controls)]))
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
		if app.modal_open {
			result := tui.modal_handle(event)
			if result.cancelled || result.submitted || (key.key == .F3 && key.modifiers == {}) {
				app.modal_open = false
			}
			return
		}
		if key.key == .F3 && key.modifiers == {} {
			app.modal_open = true
			return
		}
		if key.key == .F4 && key.modifiers == {} {
			_ = tui.toast_push(&app.toasts, {text = "✓ A toast notification", expires_at_ms = app.now_ms+3000})
			return
		}
		if key.modifiers == {} && (key.key == .F1 || key.key == .F2) {
			app_select_page(app, WIDGETS_PAGE if key.key == .F1 else DATA_PAGE)
			return
		}
		if key.key == .Tab && (key.modifiers == {} || key.modifiers == {.Shift}) {
			direction := 1
			if .Shift in key.modifiers {
				direction = -1
			}
			first, count := 0, 4
			if app.page == DATA_PAGE {
				first, count = int(Panel.Files), 2
			}
			app_focus(app, Panel(first+(int(app.focused)-first+direction+count)%count))
			return
		}
		if key.key == .Rune && key.rune == 'q' && key.modifiers == {} &&
		   !(app.focused == .Form && app.form.editing) {
			app.quit = true
			return
		}
	}
	if app.modal_open { return }
	if mouse, ok := event.(tui.Mouse_Event); ok {
		labels := PAGE_LABELS
		page := app.page
		if tui.tabs_handle(&page, labels[:], app.tabs, event, app_tab_options()).handled {
			app_select_page(app, page)
			return
		}
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
		case .Files:
			_ = files_event(&app.files, app.bounds[int(Panel.Files)], event)
		case .Table:
			table_event(&app.table, app.bounds[int(Panel.Table)], event)
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
			_ = tui.toast_push(&app.toasts, {text = string(app.status[:app.status_n]), expires_at_ms = app.now_ms+3000})
		}
	case .Controls:
		if key, ok := event.(tui.Key_Event); ok {
			controls_key(&app.controls, key)
		}
	case .Log:
	case .Files:
		if files_event(&app.files, app.bounds[int(Panel.Files)], event) {
			rows := DATA_ROWS
			message := fmt.bprintf(app.status[:], "Selected file: %s", rows[app.files.list.selected][1])
			app.status_n = len(message)
			_ = tui.toast_push(&app.toasts, {text = string(app.status[:app.status_n]), expires_at_ms = app.now_ms+3000})
		}
	case .Table:
		table_event(&app.table, app.bounds[int(Panel.Table)], event)
	}
}

app_layout :: proc(app: ^App, bounds: tui.Rect) -> (title, status: tui.Rect) {
	rows := tui.layout_split_n(bounds, .Column, [4]tui.Constraint{
		tui.layout_fixed(1), tui.layout_fixed(1), tui.layout_fill(), tui.layout_fixed(1),
	})
	title, status = rows[0], rows[3]
	app.screen, app.tabs = bounds, rows[1]
	app.bounds = {}
	body := rows[2]
	if app.page == DATA_PAGE {
		axis := tui.Layout_Axis.Row
		if body.width < 70 {
			axis = .Column
		}
		panels := tui.layout_split_n(body, axis, [2]tui.Constraint{
			tui.layout_percent(40), tui.layout_fill(),
		}, 1)
		app.bounds[int(Panel.Files)] = panels[0]
		app.bounds[int(Panel.Table)] = panels[1]
	} else if body.width < 70 {
		panels := tui.layout_split_n(body, .Column, [4]tui.Constraint{
			tui.layout_percent(35), tui.layout_fixed(7), tui.layout_fill(), tui.layout_fill(),
		})
		copy(app.bounds[:], panels[:])
	} else {
		columns := tui.layout_split_n(body, .Row, [3]tui.Constraint{
			tui.layout_percent(40), tui.layout_fixed(26), tui.layout_fill(),
		}, 1)
		middle := tui.layout_split_n(columns[1], .Column, [2]tui.Constraint{
			tui.layout_fixed(8), tui.layout_fill(),
		})
		app.bounds[0], app.bounds[1] = columns[0], middle[0]
		app.bounds[2], app.bounds[3] = middle[1], columns[2]
	}
	return title, status
}

app_draw :: proc(grid: ^tui.Grid, app: ^App) {
	bounds := tui.grid_bounds(grid)
	_ = tui.link_grid_set(app.links, bounds, 0)
	tui.fill(grid, bounds.x, bounds.y, bounds.width, bounds.height, tui.BLANK_CELL)
	title, status := app_layout(app, bounds)
	tui.fill(grid, title.x, title.y, title.width, title.height, {' ', {bg = color("#263448")}})
	tui.draw_label(grid, title, " odintui | Interactive showcase", {
		fg = color("#61dafb"), bg = color("#263448"), attributes = {.Bold},
	})
	if title.width >= 55 {
		spinner := tui.rect_inset(title, tui.Insets{left = 33})
		tui.draw_spinner(grid, spinner, app.now_ms, {style = {fg = color("#50fa7b")}})
		tag := tui.rect_align(title, 11, 1, .End, .Start)
		tui.draw_label(grid, tag, "界 🙂  docs", {fg = color("#61dafb"), bg = color("#263448")})
		link := tui.rect_inset(tag, tui.Insets{left = 7})
		_ = tui.link_grid_set(app.links, link, 1)
	}
	labels := PAGE_LABELS
	tui.draw_tabs(grid, app.tabs, labels[:], app.page, app_tab_options())
	if app.page == WIDGETS_PAGE {
		draw_text_panel(grid, app.bounds[0], &app.text, app.focused == .Text)
		draw_form_panel(grid, app.bounds[1], &app.form, app.focused == .Form)
		draw_controls_panel(grid, app.bounds[2], &app.controls, app.focused == .Controls)
		draw_log_panel(grid, app.bounds[3], &app.log, app.focused == .Log)
	} else {
		draw_files_panel(grid, app.bounds[4], &app.files, app.focused == .Files)
		draw_table_panel(grid, app.bounds[5], &app.table, app.focused == .Table)
	}
	tui.fill(grid, status.x, status.y, status.width, status.height, {' ', {bg = color("#263448")}})
	hints := []tui.Key_Hint{
		{key = "F1/F2", label = "page", priority = 2},
		{key = "Tab", label = "panel", priority = 3},
		{key = "F3", label = "modal", priority = 1},
		{key = "F4", label = "toast", priority = 1},
		{key = "Ctrl+C", label = "quit", always_keep = true},
	}
	_ = tui.draw_key_hints(grid, status, hints, {
		key_style = {fg = color("#ffffff"), bg = color("#263448"), attributes = {.Bold}},
		label_style = {fg = color("#c7d8e8"), bg = color("#263448")},
		separator_style = {bg = color("#263448")},
	})
	toast_area := tui.rect_inset(bounds, tui.Insets{bottom = 1})
	_ = tui.draw_toasts(grid, toast_area, &app.toasts, app.now_ms, {style = {bg = color("#314b65")}})
	if app.modal_open {
		_ = tui.link_grid_set(app.links, bounds, 0)
		content := tui.draw_modal(grid, bounds, {
			width = 38, height = 8,
			box = {title = "Modal", border_style = {fg = color("#61dafb")}, fill_style = {bg = color("#263448")}},
		})
		_ = tui.draw_paragraph(grid, content, "Wide: 界 🙂\n\nEnter or Escape closes this modal.",
			{bg = color("#263448")}, {wrap = .Word})
	}
}

// Link planes are allocated only on initialization/resize, never during draw.
showcase_links :: proc(grid: ^tui.Grid, urls: []string) -> (tui.Link_Grid, []u32, []u32, bool) {
	current, err := make([]u32, len(grid.cells))
	if err != nil { return {}, nil, nil, false }
	presented, err2 := make([]u32, len(grid.cells))
	if err2 != nil { delete(current); return {}, nil, nil, false }
	links, ok := tui.link_grid_init(grid, current, presented, urls)
	if !ok {
		delete(current)
		delete(presented)
		return {}, nil, nil, false
	}
	return links, current, presented, true
}

run :: proc() -> string {
	term: Terminal
	defer terminal_close(&term)
	if !terminal_open(&term) {
		return "showcase: requires a terminal on stdin and stdout; unable to enter raw mode"
	}
	width, height := terminal_size()
	grid, err := tui.grid_init(width, height)
	if err != .None {
		return "showcase: unable to allocate the grid"
	}
	defer tui.grid_destroy(&grid)
	urls := [1]string{"https://github.com/splashsky/odintui"}
	links, current, presented, links_ok := showcase_links(&grid, urls[:])
	if !links_ok { return "showcase: unable to allocate hyperlink planes" }
	defer {
		delete(current)
		delete(presented)
	}
	defer tui.link_grid_destroy(&links)
	ext := tui.Ansi_Extended_Backend{ansi = &term.ansi, links = &links, synchronized_output = true}
	defer _ = tui.ansi_extended_recover(&ext)
	app: App
	app_init(&app)
	app.links = &links
	start := time.tick_now()
	redraw := true
	for !app.quit && intrinsics.atomic_load(&terminal_signal) == 0 {
		app.now_ms = i64(time.tick_since(start)/time.Millisecond)
		width, height = terminal_size()
		if width != grid.width || height != grid.height {
			if tui.grid_resize(&grid, width, height) != .None || !tui.ansi_clear(&term.ansi) {
				return "showcase: resize or terminal clear failed"
			}
			new_links, new_current, new_presented, ok := showcase_links(&grid, urls[:])
			if !ok { return "showcase: unable to resize hyperlink planes" }
			delete(current)
			delete(presented)
			current, presented = new_current, new_presented
			links = new_links
			tui.invalidate(&grid)
			redraw = true
		}
		if redraw {
			app_draw(&grid, &app)
			if !tui.render_linked(&grid, tui.ansi_extended_backend(&ext), &links) {
				return "showcase: terminal render failed"
			}
			redraw = false
		}
		switch terminal_poll(&term, &app) {
		case .Input: redraw = true
		case .Closed: return ""
		case .Error: return "showcase: terminal input failed"
		case .Waiting: redraw = true
		}
	}
	if intrinsics.atomic_load(&terminal_signal) != 0 {
		return "showcase: terminated by signal"
	}
	return ""
}

main :: proc() {
	if message := run(); len(message) > 0 {
		fmt.eprintln(message)
		os.exit(1)
	}
}
