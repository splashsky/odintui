package odintui

// Tabs_Options controls tab appearance. Zero selected_style inherits style
// with Reverse. tab_width <= 0 fits labels; padding zero means one cell on
// each side, while negative padding means none. A zero separator draws none.
// Underline adds a second row with a heavy line under the selected tab.
Tabs_Options :: struct {
	style, selected_style: Style,
	tab_width, padding:    int,
	separator:             rune,
	underline:             bool,
}

@(private)
Tabs_Layout :: struct {
	bounds:         Rect,
	labels:         []string,
	options:        Tabs_Options,
	offset, cursor: int,
	index:          int,
}

@(private)
Tabs_Item :: struct {
	area, separator:  Rect,
	start, width:     int,
	label_length:     int,
	index:            int,
}

@(private)
tabs_add :: proc(a, b: int) -> int {
	return a + min(b, max(int)-a)
}

@(private)
tabs_label_length :: proc(label: string) -> int {
	count := 0
	for glyph in label {
		if glyph == '\n' || glyph == '\r' {
			break
		}
		count += 1
	}
	return count
}

@(private)
tabs_padding :: proc(options: Tabs_Options) -> int {
	if options.padding == 0 {
		return 1
	}
	return max(options.padding, 0)
}

@(private)
tabs_width :: proc(label_length: int, options: Tabs_Options) -> int {
	if options.tab_width > 0 {
		return options.tab_width
	}
	padding := tabs_padding(options)
	return tabs_add(label_length, tabs_add(padding, padding))
}

// tabs_layout and tabs_next provide the same geometry to drawing and hit tests.
@(private)
tabs_layout :: proc(bounds: Rect, labels: []string, selected: int, options: Tabs_Options) -> Tabs_Layout {
	bounds := bounds
	bounds.width = max(bounds.width, 0)
	height := 1
	if options.underline {
		height = 2
	}
	bounds.height = min(max(bounds.height, 0), height)
	layout := Tabs_Layout{bounds = bounds, labels = labels, options = options}
	if len(labels) == 0 {
		return layout
	}
	chosen := clamp(selected, 0, len(labels)-1)
	position := 0
	for label, index in labels {
		width := tabs_width(tabs_label_length(label), options)
		if index == chosen {
			if width > bounds.width {
				layout.offset = position
			} else {
				layout.offset = max(0, tabs_add(position, width)-bounds.width)
			}
			break
		}
		position = tabs_add(position, width)
		if options.separator != 0 {
			position = tabs_add(position, 1)
		}
	}
	return layout
}

@(private)
tabs_screen_rect :: proc(layout: ^Tabs_Layout, start, width: int) -> Rect {
	visible := rect_intersect(
		{start, 0, width, 1},
		{layout.offset, 0, layout.bounds.width, 1},
	)
	if rect_is_empty(visible) || layout.bounds.height <= 0 {
		return {}
	}
	screen := rect_inset(layout.bounds, Insets{left = visible.x-layout.offset})
	screen.width = min(screen.width, visible.width)
	return screen
}

@(private)
tabs_next :: proc(layout: ^Tabs_Layout) -> (item: Tabs_Item, ok: bool) {
	if layout.index >= len(layout.labels) || rect_is_empty(layout.bounds) ||
	   (layout.cursor >= layout.offset && layout.cursor-layout.offset >= layout.bounds.width) {
		return {}, false
	}
	index := layout.index
	length := tabs_label_length(layout.labels[index])
	width := tabs_width(length, layout.options)
	start := layout.cursor
	layout.cursor = tabs_add(start, width)
	item = {
		area = tabs_screen_rect(layout, start, width),
		start = start, width = width, label_length = length, index = index,
	}
	if layout.options.separator != 0 && index+1 < len(layout.labels) {
		item.separator = tabs_screen_rect(layout, layout.cursor, 1)
		layout.cursor = tabs_add(layout.cursor, 1)
	}
	layout.index += 1
	return item, true
}

@(private)
tabs_draw_label :: proc(grid: ^Grid, layout: ^Tabs_Layout, item: Tabs_Item, style: Style) {
	padding := tabs_padding(layout.options)
	left := min(padding, item.width)
	right := min(padding, item.width-left)
	width := item.width-left-right
	start := tabs_add(item.start, left)
	area := tabs_screen_rect(layout, start, width)
	if rect_is_empty(area) {
		return
	}
	skip := max(layout.offset, start)-start
	label := layout.labels[item.index]
	byte_start, runes := 0, 0
	for glyph, byte_index in label {
		if glyph == '\n' || glyph == '\r' || runes == skip {
			byte_start = byte_index
			break
		}
		runes += 1
		byte_start = len(label)
	}
	area.height = 1
	draw_label(grid, area, label[byte_start:], style)
	if item.label_length > width && width > 0 {
		marker := tabs_screen_rect(layout, tabs_add(start, width-1), 1)
		if !rect_is_empty(marker) {
			set_cell(grid, marker.x, marker.y, {'…', style})
		}
	}
}

// draw_tabs draws a horizontally scrolled tab bar and optional underline.
// The selected tab is fully exposed when it fits; a wider tab aligns left.
draw_tabs :: proc(
	grid: ^Grid,
	bounds: Rect,
	labels: []string,
	selected: int,
	options: Tabs_Options = {},
) {
	layout := tabs_layout(bounds, labels, selected, options)
	fill(grid, layout.bounds.x, layout.bounds.y, layout.bounds.width, layout.bounds.height,
	     {' ', options.style})
	if options.underline && bounds.height >= 2 {
		underline := rect_inset(bounds, Insets{top = 1})
		underline.height = 1
		fill(grid, underline.x, underline.y, underline.width, 1, {'─', options.style})
	}
	style := options.selected_style
	if style == (Style{}) {
		style = options.style
		style.attributes += {.Reverse}
	}
	chosen := clamp(selected, 0, max(len(labels)-1, 0))
	for item in tabs_next(&layout) {
		tab_style := options.style
		if item.index == chosen {
			tab_style = style
		}
		fill(grid, item.area.x, item.area.y, item.area.width, 1, {' ', tab_style})
		tabs_draw_label(grid, &layout, item, tab_style)
		if options.underline && bounds.height >= 2 && item.index == chosen {
			line := rect_inset(item.area, Insets{top = 1})
			fill(grid, line.x, line.y, line.width, line.height, {'━', tab_style})
		}
		if !rect_is_empty(item.separator) {
			set_cell(grid, item.separator.x, item.separator.y, {options.separator, options.style})
		}
	}
}

// tabs_index_at returns the tab at a point in either displayed row;
// separators and empty space are not tabs.
tabs_index_at :: proc(
	bounds: Rect,
	labels: []string,
	selected, x, y: int,
	options: Tabs_Options = {},
) -> (index: int, ok: bool) {
	layout := tabs_layout(bounds, labels, selected, options)
	for item in tabs_next(&layout) {
		if rect_contains(item.area, x, y) {
			return item.index, true
		}
	}
	return 0, false
}

// Tabs_Result reports whether an event was handled or changed selection.
Tabs_Result :: struct {
	handled, changed: bool,
}

// tabs_handle handles Left/Right, Home/End, wheel presses and left clicks.
// Movement clamps at the ends. Mouse input must be inside the displayed rows.
tabs_handle :: proc(
	selected: ^int,
	labels: []string,
	bounds: Rect,
	event: Input_Event,
	options: Tabs_Options = {},
) -> Tabs_Result {
	before := selected^
	count := len(labels)
	value := clamp(selected^, 0, max(count-1, 0))
	#partial switch e in event {
	case Key_Event:
		#partial switch e.key {
		case .Left:  value = max(value-1, 0)
		case .Right: value = min(value+1, max(count-1, 0))
		case .Home:  value = 0
		case .End:   value = max(count-1, 0)
		case:        return {}
		}
	case Mouse_Event:
		layout := tabs_layout(bounds, labels, selected^, options)
		if !rect_contains(layout.bounds, e.x, e.y) || e.action != .Press {
			return {}
		}
		#partial switch e.button {
		case .Wheel_Up:   value = max(value-1, 0)
		case .Wheel_Down: value = min(value+1, max(count-1, 0))
		case .Left:
			index, ok := tabs_index_at(bounds, labels, selected^, e.x, e.y, options)
			if !ok {
				return {}
			}
			value = index
		case:
			return {}
		}
	case:
		return {}
	}
	selected^ = value
	return {true, value != before}
}
