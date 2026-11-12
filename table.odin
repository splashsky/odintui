package odintui

// MAX_TABLE_COLUMNS limits table layout to the first 32 columns.
MAX_TABLE_COLUMNS :: 32

// Table_Column describes a header, its constrained width, and text alignment.
Table_Column :: struct {
	title: string,
	width: Constraint,
	align: Align,
}

// Table_Options controls borders, spacing, styles, and the optional scrollbar.
// Zero options draw a single border, header separator, and column lines.
// Padding is the number of cells on each side of the text; negatives are zero.
// Zero header and selection styles inherit style with Bold and Reverse added.
Table_Options :: struct {
	border:            Border_Set,
	borderless:        bool,
	no_column_lines:   bool,
	row_lines:         bool,
	no_header:         bool,
	padding:           int,
	style:             Style,
	header_style:      Style,
	border_style:      Style,
	selected_style:    Style,
	scrollbar:         bool,
	scrollbar_options: Scrollbar_Options,
}

@(private)
Table_Geometry :: struct {
	inner, header, header_line, body: Rect,
	columns, separators:              [MAX_TABLE_COLUMNS]Rect,
	count, viewport, selected, offset: int,
}

@(private)
table_geometry :: proc(
	bounds: Rect, columns: []Table_Column, row_count: int,
	state: ^List_State, options: Table_Options,
) -> Table_Geometry {
	result: Table_Geometry
	bounds := bounds
	bounds.width = max(bounds.width, 0)
	bounds.height = max(bounds.height, 0)
	result.inner = bounds
	if !options.borderless {
		result.inner = rect_inset(bounds, 1)
	}
	result.body = result.inner
	if !options.no_header {
		result.header = result.body
		result.header.height = min(result.header.height, 1)
		result.body = rect_inset(result.body, Insets{top = result.header.height})
		result.header_line = result.body
		result.header_line.height = min(result.header_line.height, 1)
		result.body = rect_inset(result.body, Insets{top = result.header_line.height})
	}

	result.count = min(len(columns), MAX_TABLE_COLUMNS)
	constraints: [MAX_TABLE_COLUMNS]Constraint
	for i in 0..<result.count {
		constraints[i] = columns[i].width
	}
	gap := 0
	if !options.no_column_lines {
		gap = 1
	}
	layout_split(result.inner, .Row, constraints[:result.count], result.columns[:result.count], gap)
	for i in 0..<result.count {
		column := result.columns[i]
		if gap != 0 && i+1 < result.count && column.x <= max(int)-column.width {
			x := column.x + column.width
			if rect_contains(result.inner, x, result.inner.y) {
				result.separators[i] = {x, result.inner.y, 1, result.inner.height}
			}
		}
		result.columns[i] = rect_inset(column, Insets{
			left = max(options.padding, 0), right = max(options.padding, 0),
		})
	}

	result.viewport = result.body.height
	if options.row_lines {
		result.viewport = result.body.height/2 + result.body.height%2
	}
	total := max(row_count, 0)
	if state != nil && total > 0 {
		result.selected = clamp(state.selected, 0, total-1)
		result.offset = scroll_clamp(state.offset, total, result.viewport)
		result.offset = scroll_into_view(result.offset, result.selected, 1, result.viewport)
		result.offset = scroll_clamp(result.offset, total, result.viewport)
	}
	return result
}

@(private)
table_horizontal :: proc(
	grid: ^Grid, bounds, line: Rect, geometry: ^Table_Geometry,
	border: Border_Set, options: Table_Options,
) {
	if rect_is_empty(line) {
		return
	}
	style := options.border_style
	fill(grid, line.x, line.y, line.width, 1, {border.horizontal, style})
	for separator in geometry.separators[:geometry.count] {
		if separator.width > 0 {
			set_cell(grid, separator.x, line.y, {border.cross, style})
		}
	}
	if !options.borderless {
		set_cell(grid, bounds.x, line.y, {border.left_tee, style})
		right, ok := widget_last_coordinate(bounds.x, bounds.width)
		if ok {
			set_cell(grid, right, line.y, {border.right_tee, style})
		}
	}
}

// draw_table draws up to MAX_TABLE_COLUMNS columns, clearing its interior.
// Widths include padding; column lines occupy one extra cell between columns.
// Missing cells are empty and extra cells are ignored. A nil state disables
// selection and scrolling; otherwise selection and row offset are clamped and
// kept visible. The returned body rectangle includes any row separator lines.
// A scrollbar overlays the right border, or the last body column if borderless.
draw_table :: proc(
	grid: ^Grid, bounds: Rect, columns: []Table_Column, rows: [][]string,
	state: ^List_State = nil, options: Table_Options = {},
) -> Rect {
	geometry := table_geometry(bounds, columns, len(rows), state, options)
	if state != nil {
		state.selected, state.offset = geometry.selected, geometry.offset
	}
	border := options.border
	if border == (Border_Set{}) {
		border = BORDER_SINGLE
	}
	header_style := options.header_style
	if header_style == (Style{}) {
		header_style = options.style
		header_style.attributes += {.Bold}
	}
	selected_style := options.selected_style
	if selected_style == (Style{}) {
		selected_style = options.style
		selected_style.attributes += {.Reverse}
	}

	inner := geometry.inner
	fill(grid, inner.x, inner.y, inner.width, inner.height, {' ', options.style})
	if !options.borderless {
		draw_box(grid, bounds, {border = border, border_style = options.border_style})
	}
	header := geometry.header
	fill(grid, header.x, header.y, header.width, header.height, {' ', header_style})
	for separator in geometry.separators[:geometry.count] {
		if separator.width == 0 {
			continue
		}
		fill(grid, separator.x, separator.y, 1, separator.height, {border.vertical, options.border_style})
		if !options.borderless {
			set_cell(grid, separator.x, bounds.y, {border.top_tee, options.border_style})
			bottom, ok := widget_last_coordinate(bounds.y, bounds.height)
			if ok {
				set_cell(grid, separator.x, bottom, {border.bottom_tee, options.border_style})
			}
		}
	}
	for column, i in geometry.columns[:geometry.count] {
		column := column
		column.y, column.height = header.y, header.height
		draw_paragraph(grid, column, columns[i].title, header_style, {
			align = columns[i].align, ellipsis = true,
		})
	}
	table_horizontal(grid, bounds, geometry.header_line, &geometry, border, options)

	visible := rect_intersect(geometry.body, current_clip(grid))
	stride := 1
	if options.row_lines {
		stride = 2
	}
	for y in visible.y..<visible.y+visible.height {
		distance := y - geometry.body.y
		index := distance / stride
		if index >= len(rows)-geometry.offset {
			break
		}
		if distance%stride != 0 {
			if index < len(rows)-geometry.offset-1 {
				table_horizontal(grid, bounds, {geometry.body.x, y, geometry.body.width, 1},
				                 &geometry, border, options)
			}
			continue
		}
		row := geometry.offset + index
		style := options.style
		if state != nil && row == geometry.selected {
			style = selected_style
			fill(grid, geometry.body.x, y, geometry.body.width, 1, {' ', style})
			for separator in geometry.separators[:geometry.count] {
				if separator.width > 0 {
					set_cell(grid, separator.x, y, {border.vertical, options.border_style})
				}
			}
		}
		for column, i in geometry.columns[:geometry.count] {
			if i < len(rows[row]) {
				column := column
				column.y, column.height = y, 1
				draw_paragraph(grid, column, rows[row][i], style, {
					align = columns[i].align, ellipsis = true,
				})
			}
		}
	}
	if options.scrollbar && !rect_is_empty(geometry.body) {
		track := geometry.body
		x, ok := widget_last_coordinate(track.x, track.width)
		if !options.borderless {
			x, ok = widget_last_coordinate(bounds.x, bounds.width)
		}
		if ok {
			track.x = x
		} else {
			track.width = 0
		}
		draw_scrollbar(grid, track, .Column, len(rows), geometry.viewport, geometry.offset,
		               options.scrollbar_options)
	}
	return geometry.body
}

// table_row_at maps a point on a body row to its index without changing state.
// Header, row separator, empty, and outside cells return false. Column lines
// and a borderless scrollbar still count as part of the row.
table_row_at :: proc(
	bounds: Rect, columns: []Table_Column, row_count: int, state: ^List_State,
	x, y: int, options: Table_Options = {},
) -> (row: int, ok: bool) {
	geometry := table_geometry(bounds, columns, row_count, state, options)
	if !rect_contains(geometry.body, x, y) {
		return 0, false
	}
	distance := y-geometry.body.y
	if options.row_lines && distance%2 != 0 {
		return 0, false
	}
	if options.row_lines {
		distance /= 2
	}
	if distance >= max(row_count, 0)-geometry.offset {
		return 0, false
	}
	return geometry.offset+distance, true
}
