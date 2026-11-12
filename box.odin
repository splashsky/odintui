package odintui

// Border_Set contains perimeter and junction glyphs, each occupying one cell.
Border_Set :: struct {
	top_left, top_right, bottom_left, bottom_right: rune,
	horizontal, vertical:                           rune,
	top_tee, bottom_tee, left_tee, right_tee, cross: rune,
}

// BORDER_ASCII is the ASCII border used by draw_border.
BORDER_ASCII :: Border_Set{'+', '+', '+', '+', '-', '|', '+', '+', '+', '+', '+'}
// BORDER_SINGLE uses single-line box drawing characters.
BORDER_SINGLE :: Border_Set{'┌', '┐', '└', '┘', '─', '│', '┬', '┴', '├', '┤', '┼'}
// BORDER_DOUBLE uses double-line box drawing characters.
BORDER_DOUBLE :: Border_Set{'╔', '╗', '╚', '╝', '═', '║', '╦', '╩', '╠', '╣', '╬'}
// BORDER_ROUNDED uses single lines with rounded corners.
BORDER_ROUNDED :: Border_Set{'╭', '╮', '╰', '╯', '─', '│', '┬', '┴', '├', '┤', '┼'}
// BORDER_HEAVY uses heavy box drawing characters.
BORDER_HEAVY :: Border_Set{'┏', '┓', '┗', '┛', '━', '┃', '┳', '┻', '┣', '┫', '╋'}

// Border_Side identifies a side that can be hidden.
Border_Side :: enum {
	Top,
	Right,
	Bottom,
	Left,
}

// Box_Options defaults to a single border on all sides and no fill or padding.
// Hidden sides consume no space. A zero border set selects BORDER_SINGLE.
// A zero title/footer style inherits border_style. Titles are single-line.
Box_Options :: struct {
	border:        Border_Set,
	hidden_sides:  bit_set[Border_Side; u8],
	border_style:  Style,
	fill:          bool,
	fill_style:    Style,
	title:         string,
	title_align:   Align,
	title_style:   Style,
	footer:        string,
	footer_align:  Align,
	footer_style:  Style,
	padding:       Insets,
}

// box_content returns the bounds inside the visible sides and then padding.
// Negative extents and padding are treated as zero.
box_content :: proc(bounds: Rect, options: Box_Options = {}) -> Rect {
	return rect_inset(box_inner(bounds, options), options.padding)
}

@(private)
box_inner :: proc(bounds: Rect, options: Box_Options) -> Rect {
	insets: Insets
	if .Top not_in options.hidden_sides {
		insets.top = 1
	}
	if .Right not_in options.hidden_sides {
		insets.right = 1
	}
	if .Bottom not_in options.hidden_sides {
		insets.bottom = 1
	}
	if .Left not_in options.hidden_sides {
		insets.left = 1
	}
	return rect_inset(bounds, insets)
}

// draw_box draws a clipped perimeter, optional interior fill and titles, then
// returns box_content. An unjoined side extends to the end of its edge; corners
// appear only where two visible sides meet. On coincident corners, later
// corners in top-left, top-right, bottom-left, bottom-right order win.
draw_box :: proc(grid: ^Grid, bounds: Rect, options: Box_Options = {}) -> Rect {
	content := box_content(bounds, options)
	if rect_is_empty(bounds) {
		return content
	}
	border := options.border
	if border == (Border_Set{}) {
		border = BORDER_SINGLE
	}
	top := .Top not_in options.hidden_sides
	right_side := .Right not_in options.hidden_sides
	bottom_side := .Bottom not_in options.hidden_sides
	left := .Left not_in options.hidden_sides
	right, right_ok := widget_last_coordinate(bounds.x, bounds.width)
	bottom, bottom_ok := widget_last_coordinate(bounds.y, bounds.height)

	if options.fill {
		inner := box_inner(bounds, options)
		fill(grid, inner.x, inner.y, inner.width, inner.height, {' ', options.fill_style})
	}
	if top {
		fill(grid, bounds.x, bounds.y, bounds.width, 1, {border.horizontal, options.border_style})
	}
	if bottom_side && bottom_ok {
		fill(grid, bounds.x, bottom, bounds.width, 1, {border.horizontal, options.border_style})
	}
	if left {
		fill(grid, bounds.x, bounds.y, 1, bounds.height, {border.vertical, options.border_style})
	}
	if right_side && right_ok {
		fill(grid, right, bounds.y, 1, bounds.height, {border.vertical, options.border_style})
	}
	if top && left {
		set_cell(grid, bounds.x, bounds.y, {border.top_left, options.border_style})
	}
	if top && right_side && right_ok {
		set_cell(grid, right, bounds.y, {border.top_right, options.border_style})
	}
	if bottom_side && left && bottom_ok {
		set_cell(grid, bounds.x, bottom, {border.bottom_left, options.border_style})
	}
	if bottom_side && right_side && bottom_ok && right_ok {
		set_cell(grid, right, bottom, {border.bottom_right, options.border_style})
	}
	if top {
		box_title(grid, bounds, bounds.y, left, right_side, options.title,
		          options.title_align, options.title_style, options.border_style)
	}
	if bottom_side && bottom_ok {
		box_title(grid, bounds, bottom, left, right_side, options.footer,
		          options.footer_align, options.footer_style, options.border_style)
	}
	return content
}

@(private)
box_title :: proc(
	grid: ^Grid, bounds: Rect, y: int, left, right: bool, text: string,
	align: Align, style, border_style: Style,
) {
	if len(text) == 0 {
		return
	}
	span := bounds.width
	start: i128 = i128(bounds.x)
	if left && span > 0 {
		start += 1
		span -= 1
	}
	if right && span > 0 {
		span -= 1
	}
	if span <= 0 {
		return
	}
	count := 0
	for glyph in text {
		if glyph == '\n' || glyph == '\r' || count == span {
			break
		}
		count += 1
	}
	if count == 0 {
		return
	}
	padding := 0
	if span-count >= 2 {
		padding = 1
	}
	used := count + 2*padding
	switch align {
	case .Start:
	case .Center:
		start += i128((span-used)/2)
	case .End:
		start += i128(span-used)
	}
	style := style
	if style == (Style{}) {
		style = border_style
	}
	if padding > 0 && start <= i128(max(int)) {
		set_cell(grid, int(start), y, {' ', style})
	}
	start += i128(padding)
	if start <= i128(max(int)) {
		draw_label(grid, {int(start), y, count, 1}, text, style)
	}
	start += i128(count)
	if padding > 0 && start <= i128(max(int)) {
		set_cell(grid, int(start), y, {' ', style})
	}
}
