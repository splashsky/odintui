package odintui

// Badge_Options padding defaults to one cell; negative padding means none.
Badge_Options :: struct {
	style: Style,
	padding: int,
}

// draw_badge fills a single-row pill-sized rectangle and returns its bounds.
draw_badge :: proc(grid: ^Grid, bounds: Rect, text: string, options: Badge_Options = {}) -> Rect {
	padding := options.padding
	if padding == 0 { padding = 1 }
	padding = max(padding, 0)
	width := tabs_add(tabs_label_length(text), tabs_add(padding, padding))
	area := rect_align(bounds, width, 1, .Start, .Start)
	fill(grid, area.x, area.y, area.width, area.height, {' ', options.style})
	content := rect_inset(area, Insets{left = padding, right = padding})
	_ = draw_paragraph(grid, content, text, options.style, {ellipsis = true})
	return area
}

// Big_Text_Options optionally reveals a fraction of the block from left to
// right. The zero value shows the entire block; reveal_fraction is clamped.
Big_Text_Options :: struct {
	align: Align,
	reveal: bool,
	reveal_fraction: f64,
}

draw_big_text :: proc(
	grid: ^Grid, bounds: Rect, text: string, style: Style = {}, options: Big_Text_Options = {},
) -> int {
	if rect_is_empty(bounds) { return 0 }
	clip := bounds
	if options.reveal {
		fraction := options.reveal_fraction
		_, widest := measure_text(text, 0, .None)
		clip = rect_align(bounds, widest, bounds.height, options.align, .Start)
		width := clip.width
		clip.width = 0
		if fraction >= 1 { clip.width = width
		} else if fraction > 0 { clip.width = widget_progress_width(width, fraction) }
	}
	if clip_scope(grid, clip) {
		return draw_paragraph(grid, bounds, text, style, {align = options.align})
	}
	return 0
}

// Definition borrows a label and a potentially multiline value.
Definition :: struct { label, value: string }

// Definition_Options defaults to a label width fitted to the widest label,
// two columns of gap, and word-wrapped values. Negative gap means no gap.
Definition_Options :: struct {
	label_width, gap: int,
	label_style, value_style: Style,
}

// draw_definition_list draws aligned labels and word-wrapped values, returning
// the number of complete or partially visible definitions.
draw_definition_list :: proc(
	grid: ^Grid, bounds: Rect, items: []Definition, options: Definition_Options = {},
) -> int {
	if rect_is_empty(bounds) { return 0 }
	label_width := options.label_width
	if label_width <= 0 {
		for item in items { label_width = max(label_width, tabs_label_length(item.label)) }
	}
	label_width = min(label_width, bounds.width)
	gap := options.gap
	if gap == 0 { gap = 2 }
	gap = min(max(gap, 0), bounds.width-label_width)
	value_width := bounds.width-label_width-gap
	label_style := options.label_style
	if label_style == (Style{}) { label_style.attributes += {.Dim} }
	rows := layout_init(bounds, .Column)
	count := 0
	for item in items {
		if rect_is_empty(layout_remaining(&rows)) { break }
		lines := 1
		if value_width > 0 { lines, _ = measure_text(item.value, value_width, .Word) }
		row := layout_take(&rows, max(lines, 1))
		cols := layout_init(row, .Row)
		draw_label(grid, layout_take(&cols, label_width), item.label, label_style)
		_ = layout_take(&cols, gap)
		_ = draw_paragraph(grid, layout_take_rest(&cols), item.value, options.value_style, {wrap = .Word})
		count += 1
	}
	return count
}
