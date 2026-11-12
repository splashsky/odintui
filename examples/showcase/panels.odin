package main

import tui "../.."
import "core:fmt"

color :: proc(value: string) -> tui.Color {
	result, _ := tui.hex(value)
	return result
}

panel_box :: proc(grid: ^tui.Grid, bounds: tui.Rect, title: string, focused: bool) -> tui.Rect {
	border := tui.BORDER_SINGLE
	style := tui.Style{fg = color("#718096")}
	if focused {
		border = tui.BORDER_ROUNDED
		style = {fg = color("#61dafb"), attributes = {.Bold}}
	}
	return tui.draw_box(grid, bounds, {border = border, border_style = style, title = title})
}

Text_Panel_State :: struct {
	offset:   int,
	height:   int,
	viewport: tui.Rect,
	track:    tui.Rect,
	dragging: bool,
}

text_spans :: proc() -> [9]tui.Span {
	return {
		{"A small toolkit for ", {}},
		{"terminal interfaces", {fg = color("#61dafb"), attributes = {.Bold}}},
		{" can still express a lot. This paragraph combines ", {}},
		{"colour", {fg = color("#ffb86c")}},
		{", ", {}},
		{"italic", {fg = color("#bd93f9"), attributes = {.Italic}}},
		{", ", {}},
		{"underlined", {fg = color("#50fa7b"), attributes = {.Underline}}},
		{", and ", {}},
	}
}

// Separate spans retain styles across word wraps; all text is borrowed.
text_paragraph :: proc() -> [14]tui.Span {
	first := text_spans()
	result: [14]tui.Span
	copy(result[:], first[:])
	result[9] = {"struck-through", {fg = color("#ff79c6"), attributes = {.Strikethrough}}}
	result[10] = {".\n\n", {}}
	result[11] = {
		"Each frame describes the current screen. The grid compares it with the previous " +
		"frame and sends only the changed cells to the terminal. Resize the window and " +
		"the constraints divide the available space again.\n\n",
		{},
	}
	result[12] = {
		"Use the arrow keys, Page Up and Page Down, or the mouse wheel to explore this " +
		"paragraph. You can also click or drag the scrollbar. Widgets receive a grid, " +
		"bounds, and caller-owned state; they do not own the event loop.\n\n",
		{},
	}
	result[13] = {
		"Try the form and controls panels too. Tab moves between panels, and each panel " +
		"decides how to respond to input. Small building blocks can be composed into " +
		"applications without a retained widget tree.",
		{},
	}
	return result
}

text_layout :: proc(state: ^Text_Panel_State, content: tui.Rect) {
	state.viewport = content
	state.viewport.width = max(content.width-1, 0)
	state.track = {content.x+state.viewport.width, content.y, min(content.width, 1), content.height}
	spans := text_paragraph()
	state.height, _ = tui.measure_spans(spans[:], state.viewport.width, .Word)
	state.offset = tui.scroll_clamp(state.offset, state.height, state.viewport.height)
}

draw_text_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Text_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Text", focused)
	text_layout(state, content)
	spans := text_paragraph()
	_ = tui.draw_spans(grid, state.viewport, spans[:], {wrap = .Word, scroll = state.offset})
	tui.draw_scrollbar(
		grid, state.track, .Column, state.height, state.viewport.height, state.offset,
		{track_style = {fg = color("#465369")}, thumb_style = {fg = color("#61dafb")}, always_show = true},
	)
}

text_key :: proc(state: ^Text_Panel_State, key: tui.Key_Event) {
	step := max(state.viewport.height-1, 1)
	#partial switch key.key {
	case .Up:        state.offset -= 1
	case .Down:      state.offset += 1
	case .Page_Up:   state.offset -= step
	case .Page_Down: state.offset += step
	case .Home:      state.offset = 0
	case .End:       state.offset = state.height
	}
	state.offset = tui.scroll_clamp(state.offset, state.height, state.viewport.height)
}

text_mouse :: proc(state: ^Text_Panel_State, mouse: tui.Mouse_Event) {
	if mouse.button == .Wheel_Up && mouse.action == .Press {
		state.offset -= 3
	} else if mouse.button == .Wheel_Down && mouse.action == .Press {
		state.offset += 3
	} else if mouse.button == .Left && mouse.action == .Press &&
	          tui.rect_contains(state.track, mouse.x, mouse.y) {
		state.dragging = true
	}
	if state.dragging && mouse.button == .Left &&
	   (mouse.action == .Press || mouse.action == .Drag) && state.track.height > 0 {
		y := clamp(mouse.y, state.track.y, state.track.y+state.track.height-1)
		if offset, ok := tui.scrollbar_offset_at(
			state.track, .Column, state.height, state.viewport.height, state.track.x, y,
		); ok {
			state.offset = offset
		}
	}
	if mouse.action == .Release {
		state.dragging = false
	}
	state.offset = tui.scroll_clamp(state.offset, state.height, state.viewport.height)
}

Form_Panel_State :: struct {
	name_buffer, password_buffer: [128]byte,
	name, password:               tui.Text_Field,
	fields:                       [2]tui.Rect,
	selected:                     int,
	editing:                      bool,
}

form_init :: proc(state: ^Form_Panel_State) {
	state.name = tui.text_field_init(state.name_buffer[:])
	state.password = tui.text_field_init(state.password_buffer[:])
}

form_current :: proc(state: ^Form_Panel_State) -> ^tui.Text_Field {
	return &state.name if state.selected == 0 else &state.password
}

form_layout :: proc(state: ^Form_Panel_State, content: tui.Rect) -> [2]tui.Rect {
	layout := tui.layout_init(content, .Column)
	labels: [2]tui.Rect
	labels[0] = tui.layout_take(&layout, 1)
	state.fields[0] = tui.layout_take(&layout, 1)
	_ = tui.layout_take(&layout, 1)
	labels[1] = tui.layout_take(&layout, 1)
	state.fields[1] = tui.layout_take(&layout, 1)
	return labels
}

draw_form_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Form_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Form", focused)
	labels := form_layout(state, content)
	label_style := tui.Style{fg = color("#b3c5d7")}
	field_style := tui.Style{bg = color("#263448")}
	tui.draw_label(grid, labels[0], "Name", label_style)
	_, _, _ = tui.draw_text_field(
		grid, state.fields[0], &state.name,
		{style = field_style, placeholder = "your name", placeholder_style = {fg = color("#718096")},
		 focused = focused && state.editing && state.selected == 0},
	)
	tui.draw_label(grid, labels[1], "Password", label_style)
	_, _, _ = tui.draw_text_field(
		grid, state.fields[1], &state.password,
		{style = field_style, placeholder = "secret", placeholder_style = {fg = color("#718096")},
		 mask = '*', focused = focused && state.editing && state.selected == 1},
	)
}

// Returns true for a submission; the caller decides how to present it.
form_event :: proc(state: ^Form_Panel_State, event: tui.Input_Event) -> bool {
	if key, ok := event.(tui.Key_Event); ok {
		if key.modifiers == {} {
			#partial switch key.key {
			case .Up:   state.selected = 0; state.editing = true; return false
			case .Down: state.selected = 1; state.editing = true; return false
			case .Escape: state.editing = false; return false
			case .Enter:
				if !state.editing {
					state.editing = true
					return false
				}
			}
		}
	}
	if state.editing {
		return tui.text_field_handle(form_current(state), event).submitted
	}
	return false
}

form_mouse :: proc(state: ^Form_Panel_State, mouse: tui.Mouse_Event) {
	if mouse.button == .Left && mouse.action == .Press {
		for bounds, i in state.fields {
			if tui.rect_contains(bounds, mouse.x, mouse.y) {
				state.selected = i
				state.editing = true
			}
		}
	}
}

Controls_Panel_State :: struct {
	value:    f64,
	slider:   tui.Rect,
	dragging: bool,
}

controls_slider_bounds :: proc(content: tui.Rect) -> tui.Rect {
	layout := tui.layout_init(content, .Column)
	_ = tui.layout_take(&layout, 1)
	return tui.layout_take(&layout, 1)
}

draw_controls_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Controls_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Controls", focused)
	layout := tui.layout_init(content, .Column)
	buf: [48]byte
	label := fmt.bprintf(buf[:], "Slider: %d%%", int(state.value*100+0.5))
	tui.draw_label(grid, tui.layout_take(&layout, 1), label)
	state.slider = controls_slider_bounds(content)
	_ = tui.layout_take(&layout, 1)
	tui.draw_slider(grid, state.slider, .Row, state.value, {
		track_style = {fg = color("#718096")}, thumb_style = {fg = color("#ffb86c")},
	})
	_ = tui.layout_take(&layout, 1)
	tui.draw_label(grid, tui.layout_take(&layout, 1), "Progress")
	tui.draw_progress_bar(
		grid, tui.layout_take(&layout, 1), state.value,
		{fg = color("#50fa7b")}, {fg = color("#465369")},
	)
	_ = tui.layout_take(&layout, 1)
	tui.draw_label(grid, tui.layout_take(&layout, 1), "Palette")
	swatches := tui.layout_take(&layout, 3)
	colors := [6]string{"#ff5555", "#ffb86c", "#f1fa8c", "#50fa7b", "#61dafb", "#bd93f9"}
	for value, i in colors {
		cell := tui.layout_cell(swatches, 3, 2, i%3, i/3, 1, 1)
		tui.fill(grid, cell.x, cell.y, cell.width, cell.height, {' ', {bg = color(value)}})
	}
}

controls_key :: proc(state: ^Controls_Panel_State, key: tui.Key_Event) {
	#partial switch key.key {
	case .Left:  state.value -= 0.05
	case .Right: state.value += 0.05
	case .Home:  state.value = 0
	case .End:   state.value = 1
	}
	state.value = clamp(state.value, 0, 1)
}

controls_mouse :: proc(state: ^Controls_Panel_State, mouse: tui.Mouse_Event) {
	if mouse.button == .Left && mouse.action == .Press &&
	   tui.rect_contains(state.slider, mouse.x, mouse.y) {
		state.dragging = true
	}
	if state.dragging && mouse.button == .Left &&
	   (mouse.action == .Press || mouse.action == .Drag) && !tui.rect_is_empty(state.slider) {
		x := clamp(mouse.x, state.slider.x, state.slider.x+state.slider.width-1)
		if value, ok := tui.slider_value_at(state.slider, .Row, x, state.slider.y); ok {
			state.value = value
		}
	}
	if mouse.action == .Release {
		state.dragging = false
	}
}

LOG_LINES :: 32
Log_Panel_State :: struct {
	lines: [LOG_LINES][128]byte,
	sizes: [LOG_LINES]int,
	next:  int,
	count: int,
}

// Writes modifiers as a "Ctrl+Alt+Shift+Super+" prefix.
modifier_prefix :: proc(buffer: []byte, modifiers: tui.Modifiers) -> string {
	ORDER :: [4]tui.Modifier{.Ctrl, .Alt, .Shift, .Super}
	NAMES :: [tui.Modifier]string{.Shift = "Shift+", .Alt = "Alt+", .Ctrl = "Ctrl+", .Super = "Super+"}
	names := NAMES
	n := 0
	for modifier in ORDER {
		if modifier in modifiers {
			n += copy(buffer[n:], names[modifier])
		}
	}
	return string(buffer[:n])
}

log_event :: proc(state: ^Log_Panel_State, event: tui.Input_Event, secret: bool) {
	buffer := state.lines[state.next][:]
	prefix_buffer: [32]byte
	text := ""
	switch value in event {
	case tui.Key_Event:
		prefix := modifier_prefix(prefix_buffer[:], value.modifiers)
		if secret && value.key == .Rune {
			text = fmt.bprintf(buffer, "Key %s(hidden)", prefix)
		} else if value.key == .Rune {
			text = fmt.bprintf(buffer, "Key %s%q", prefix, value.rune)
		} else {
			text = fmt.bprintf(buffer, "Key %s%v", prefix, value.key)
		}
	case tui.Mouse_Event:
		prefix := modifier_prefix(prefix_buffer[:], value.modifiers)
		text = fmt.bprintf(buffer, "Mouse %s%v %v %d,%d", prefix, value.button, value.action, value.x, value.y)
	case tui.Paste_Event:
		text = fmt.bprintf(buffer, "Paste %v (%d bytes)", value.kind, len(value.text))
	case tui.Focus_Event:
		text = fmt.bprintf(buffer, "Focus %s", "gained" if value.focused else "lost")
	case nil:
		text = fmt.bprintf(buffer, "Unknown event")
	}
	state.sizes[state.next] = len(text)
	state.next = (state.next+1)%LOG_LINES
	state.count = min(state.count+1, LOG_LINES)
}

draw_log_panel :: proc(grid: ^tui.Grid, bounds: tui.Rect, state: ^Log_Panel_State, focused: bool) {
	content := panel_box(grid, bounds, "Event log", focused)
	count := min(state.count, content.height)
	for i in 0..<count {
		index := (state.next-count+i+LOG_LINES)%LOG_LINES
		line := tui.Rect{content.x, content.y+i, content.width, 1}
		tui.draw_label(grid, line, string(state.lines[index][:state.sizes[index]]))
	}
}
