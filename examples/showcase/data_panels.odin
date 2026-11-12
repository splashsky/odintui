package main

import tui "../.."

// Each row is ID, name, kind, size. Strings are borrowed literals.
DATA_ROWS :: [40][4]string{
	{"01", "README.md",         "text", "3 KB"},
	{"02", "main.odin",         "odin", "8 KB"},
	{"03", "terminal.odin",     "odin", "7 KB"},
	{"04", "panels.odin",       "odin", "14 KB"},
	{"05", "assets",            "dir",  "--"},
	{"06", "palette.txt",       "text", "1 KB"},
	{"07", "notes.md",          "text", "4 KB"},
	{"08", "layout.odin",       "odin", "12 KB"},
	{"09", "grid.odin",         "odin", "11 KB"},
	{"10", "render.odin",       "odin", "3 KB"},
	{"11", "input.odin",        "odin", "16 KB"},
	{"12", "scroll.odin",       "odin", "6 KB"},
	{"13", "text.odin",         "odin", "9 KB"},
	{"14", "box.odin",          "odin", "7 KB"},
	{"15", "widgets.odin",      "odin", "4 KB"},
	{"16", "text_field.odin",   "odin", "15 KB"},
	{"17", "list.odin",         "odin", "9 KB"},
	{"18", "tabs.odin",         "odin", "10 KB"},
	{"19", "table.odin",        "odin", "10 KB"},
	{"20", "examples",          "dir",  "--"},
	{"21", "demo",              "dir",  "--"},
	{"22", "showcase",          "dir",  "--"},
	{"23", "tests",             "dir",  "--"},
	{"24", "grid_test.odin",    "odin", "18 KB"},
	{"25", "input_test.odin",   "odin", "20 KB"},
	{"26", "layout_test.odin",  "odin", "15 KB"},
	{"27", "text_test.odin",    "odin", "8 KB"},
	{"28", "table_test.odin",   "odin", "11 KB"},
	{"29", "tabs_test.odin",    "odin", "7 KB"},
	{"30", "list_test.odin",    "odin", "10 KB"},
	{"31", "LICENSE",           "text", "1 KB"},
	{"32", "CHANGELOG.md",      "text", "6 KB"},
	{"33", "CONTRIBUTING.md",   "text", "2 KB"},
	{"34", "theme.odin",        "odin", "5 KB"},
	{"35", "theme_test.odin",   "odin", "4 KB"},
	{"36", "screenshots",       "dir",  "--"},
	{"37", "build.sh",          "text", "1 KB"},
	{"38", "docs",              "dir",  "--"},
	{"39", "guide.md",          "text", "5 KB"},
	{"40", "reference.md",      "text", "9 KB"},
}
FILE_COUNT :: 30

data_list_options :: proc() -> tui.List_Options {
	return {
		scrollbar = true,
		scrollbar_options = {
			track_style = {fg = color("#465369")}, thumb_style = {fg = color("#61dafb")},
		},
	}
}

Files_Panel_State :: struct {
	list: tui.List_State,
}

draw_files_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Files_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Files", focused)
	options := data_list_options()
	view := tui.list_begin(&state.list, FILE_COUNT, content, options)
	tui.fill(grid, content.x, content.y, content.width, content.height, tui.BLANK_CELL)
	rows := DATA_ROWS
	iter := view
	for row, index in tui.list_next(&iter) {
		style := tui.Style{}
		if index == state.list.selected {
			style = {bg = color("#314b65"), fg = color("#ffffff")}
		}
		tui.fill(grid, row.x, row.y, row.width, row.height, {' ', style})
		columns := tui.layout_split_n(row, .Row, [3]tui.Constraint{
			tui.layout_fixed(5), tui.layout_fill(), tui.layout_fixed(6),
		})
		kind_style := style
		kind_style.fg = color("#61dafb")
		if rows[index][2] == "dir" {
			kind_style.fg = color("#ffb86c")
		}
		_ = tui.draw_paragraph(grid, columns[0], rows[index][2], kind_style, {ellipsis = true})
		_ = tui.draw_paragraph(grid, columns[1], rows[index][1], style, {ellipsis = true})
		_ = tui.draw_paragraph(grid, columns[2], rows[index][3], style, {
			align = .End, ellipsis = true,
		})
	}
	if !tui.rect_is_empty(view.scrollbar) {
		tui.draw_scrollbar(
			grid, view.scrollbar, .Column, FILE_COUNT, view.viewport, state.list.offset,
			options.scrollbar_options,
		)
	}
}

files_event :: proc(state: ^Files_Panel_State, bounds: tui.Rect, event: tui.Input_Event) -> bool {
	result := tui.list_handle(
		&state.list, FILE_COUNT, tui.box_content(bounds), event, data_list_options(),
	)
	return result.submitted
}

Table_Panel_State :: struct {
	list: tui.List_State,
	body: tui.Rect,
}

table_columns :: proc() -> [4]tui.Table_Column {
	return {
		{"ID", tui.layout_fixed(4), .End},
		{"Name", tui.layout_percent(46), .Start},
		{"Kind", tui.layout_fill(), .Start},
		{"Size", tui.layout_fixed(8), .End},
	}
}

table_options :: proc() -> tui.Table_Options {
	return {
		borderless = true,
		scrollbar = true,
		// In a borderless table the scrollbar overlays the last body column.
		padding = 1,
		header_style = {fg = color("#61dafb"), attributes = {.Bold}},
		border_style = {fg = color("#718096")},
		selected_style = {bg = color("#314b65"), fg = color("#ffffff")},
		scrollbar_options = data_list_options().scrollbar_options,
	}
}

draw_table_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Table_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Table", focused)
	columns := table_columns()
	data := DATA_ROWS
	rows: [len(DATA_ROWS)][]string
	for &row, i in rows {
		row = data[i][:]
	}
	state.body = tui.draw_table(grid, content, columns[:], rows[:], &state.list, table_options())
}

table_event :: proc(state: ^Table_Panel_State, bounds: tui.Rect, event: tui.Input_Event) {
	content := tui.box_content(bounds)
	// With the borderless, headed table above, the body starts after two header rows.
	body := tui.rect_inset(content, tui.Insets{top = 2})
	options := data_list_options()
	if mouse, ok := event.(tui.Mouse_Event); ok && mouse.button == .Left && mouse.action == .Press {
		copy := state.list
		view := tui.list_begin(&copy, len(DATA_ROWS), body, options)
		if !tui.rect_contains(view.scrollbar, mouse.x, mouse.y) {
			columns := table_columns()
			if row, hit := tui.table_row_at(
				content, columns[:], len(DATA_ROWS), &state.list, mouse.x, mouse.y, table_options(),
			); hit {
				state.list.selected = row
				_ = tui.list_begin(&state.list, len(DATA_ROWS), body, options)
			}
			return
		}
	}
	_ = tui.list_handle(&state.list, len(DATA_ROWS), body, event, options)
}
