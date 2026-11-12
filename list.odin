package odintui

// List_State is caller-owned selection and scroll state shared by lists and
// tables: selected is the selected item and offset the first visible item.
List_State :: struct {
	selected: int,
	offset:   int,
}

// List_Options controls row appearance, height, navigation, and the scrollbar.
// A zero selected_style inherits style with Reverse; item_height <= 0 means 1.
List_Options :: struct {
	style, selected_style: Style,
	item_height:           int,
	wrap:                  bool,
	scrollbar:             bool,
	scrollbar_options:     Scrollbar_Options,
}

// List_View is a non-owning iterator over the visible items of a list.
List_View :: struct {
	remaining:   Layout,
	index, count: int,
	item_height: int,
	scrollbar:   Rect,
	viewport:    int,
}

// list_begin normalizes state and returns visible rows, reserving the last
// column for the scrollbar only when enabled and items overflow. A partially
// visible final item counts as visible.
list_begin :: proc(
	state: ^List_State,
	count: int,
	bounds: Rect,
	options: List_Options = {},
) -> List_View {
	total := max(count, 0)
	height := max(options.item_height, 1)
	bounds := bounds
	bounds.width = max(bounds.width, 0)
	bounds.height = max(bounds.height, 0)
	viewport := bounds.height / height
	if bounds.height % height != 0 {
		viewport += 1
	}
	state.selected = clamp(state.selected, 0, max(total-1, 0))
	state.offset = scroll_clamp(state.offset, total, viewport)
	if total > 0 {
		state.offset = scroll_into_view(state.offset, state.selected, 1, viewport)
		state.offset = scroll_clamp(state.offset, total, viewport)
	}

	content := layout_init(bounds, .Row)
	bar: Rect
	if options.scrollbar && total > viewport && bounds.width > 0 && bounds.height > 0 {
		bar = layout_take_end(&content, 1)
	}
	return {
		remaining = layout_init(layout_remaining(&content), .Column),
		index = state.offset,
		count = total,
		item_height = height,
		scrollbar = bar,
		viewport = viewport,
	}
}

// list_next returns the next visible item and its clipped row rectangle.
list_next :: proc(view: ^List_View) -> (row: Rect, index: int, ok: bool) {
	if view.index >= view.count || rect_is_empty(layout_remaining(&view.remaining)) {
		return {}, 0, false
	}
	row = layout_take(&view.remaining, view.item_height)
	index = view.index
	view.index += 1
	return row, index, true
}

// draw_list paints rows and optional scrollbar, returning a fresh row iterator.
// Text is ellipsized on each item's first line; remaining lines are filled.
draw_list :: proc(
	grid: ^Grid,
	bounds: Rect,
	state: ^List_State,
	items: []string,
	options: List_Options = {},
) -> List_View {
	view := list_begin(state, len(items), bounds, options)
	iter := view
	fill(grid, bounds.x, bounds.y, bounds.width, bounds.height, {' ', options.style})
	selected_style := options.selected_style
	if selected_style == (Style{}) {
		selected_style = options.style
		selected_style.attributes += {.Reverse}
	}
	for row, index in list_next(&iter) {
		style := options.style
		if index == state.selected {
			style = selected_style
		}
		fill(grid, row.x, row.y, row.width, row.height, {' ', style})
		draw_paragraph(grid, {row.x, row.y, row.width, 1}, items[index], style, {ellipsis = true})
	}
	if !rect_is_empty(view.scrollbar) {
		draw_scrollbar(grid, view.scrollbar, .Column, len(items), view.viewport,
		               state.offset, options.scrollbar_options)
	}
	return view
}

// list_move moves the selection by delta, clamping or wrapping at the ends.
// A negative count is empty; offset is not modified.
list_move :: proc(state: ^List_State, count, delta: int, wrap := false) {
	total := max(count, 0)
	if total == 0 {
		state.selected = 0
		return
	}
	selected := clamp(state.selected, 0, total-1)
	if wrap {
		step := delta % total
		if step > 0 && step >= total-selected {
			selected = step - (total-selected)
		} else if step < 0 && step < -selected {
			selected = total - (-step-selected)
		} else {
			selected += step
		}
	} else if delta > 0 {
		selected += min(delta, total-1-selected)
	} else if delta < 0 {
		if delta < -selected {
			selected = 0
		} else {
			selected += delta
		}
	}
	state.selected = selected
}

// list_first selects the first item, or zero for an empty list.
list_first :: proc(state: ^List_State) {
	state.selected = 0
}

// list_last selects the last item, or zero for an empty list.
list_last :: proc(state: ^List_State, count: int) {
	state.selected = max(max(count, 0)-1, 0)
}

// list_index_at returns the item at a point, excluding the scrollbar column.
// It uses the normalized state without modifying the caller's state.
list_index_at :: proc(
	state: ^List_State,
	count: int,
	bounds: Rect,
	x, y: int,
	options: List_Options = {},
) -> (index: int, ok: bool) {
	copy := state^
	view := list_begin(&copy, count, bounds, options)
	area := layout_remaining(&view.remaining)
	if !rect_contains(area, x, y) {
		return 0, false
	}
	row := (y-area.y) / view.item_height
	if row >= view.count-view.index {
		return 0, false
	}
	return view.index+row, true
}

@(private)
list_scroll_to :: proc(state: ^List_State, count, viewport, offset: int) {
	state.offset = scroll_clamp(offset, count, viewport)
	if viewport > 0 && count > 0 {
		state.selected = clamp(state.selected, state.offset, min(count-1, state.offset+viewport-1))
	}
}

// List_Result reports whether an event was handled, changed state, or submitted.
List_Result :: struct {
	handled, changed, submitted: bool,
}

// list_handle processes navigation, Enter, and mouse input inside bounds.
// Wheel presses scroll one item; scrollbar presses and drags jump. Scrolling
// moves the selection only as far as needed to keep it within the viewport.
list_handle :: proc(
	state: ^List_State,
	count: int,
	bounds: Rect,
	event: Input_Event,
	options: List_Options = {},
) -> List_Result {
	before := state^
	total := max(count, 0)
	#partial switch e in event {
	case Key_Event:
		#partial switch e.key {
		case .Up, .Down, .Page_Up, .Page_Down, .Home, .End, .Enter:
		case:
			return {}
		}
		view := list_begin(state, total, bounds, options)
		#partial switch e.key {
		case .Up:        list_move(state, total, -1, options.wrap)
		case .Down:      list_move(state, total, 1, options.wrap)
		case .Page_Up:   list_move(state, total, -max(view.viewport, 1), options.wrap)
		case .Page_Down: list_move(state, total, max(view.viewport, 1), options.wrap)
		case .Home:      list_first(state)
		case .End:       list_last(state, total)
		case .Enter:
		case:
		}
		list_begin(state, total, bounds, options)
		return {true, state^ != before, e.key == .Enter && total > 0}
	case Mouse_Event:
		if !rect_contains(bounds, e.x, e.y) {
			return {}
		}
		copy := state^
		view := list_begin(&copy, total, bounds, options)
		if e.action == .Press && (e.button == .Wheel_Up || e.button == .Wheel_Down) {
			delta := 1
			if e.button == .Wheel_Up {
				delta = -1
			}
			list_scroll_to(&copy, total, view.viewport, copy.offset+delta)
		} else if e.button == .Left && (e.action == .Press || e.action == .Drag) &&
		          rect_contains(view.scrollbar, e.x, e.y) {
			offset, ok := scrollbar_offset_at(view.scrollbar, .Column, total, view.viewport, e.x, e.y)
			if !ok {
				return {}
			}
			list_scroll_to(&copy, total, view.viewport, offset)
		} else if e.button == .Left && e.action == .Press {
			index, ok := list_index_at(&copy, total, bounds, e.x, e.y, options)
			if !ok {
				return {}
			}
			copy.selected = index
		} else {
			return {}
		}
		state^ = copy
		return {handled = true, changed = state^ != before}
	case:
		return {}
	}
}
