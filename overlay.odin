package odintui

// Modal_Backdrop selects dimming, clearing, or leaving the underlying cells.
Modal_Backdrop :: enum { Dim, Clear, None }

// Modal_Options defaults to a dim backdrop and a filled, centered box up to
// 60x12. Positive width/height override the defaults; dimensions are clamped.
Modal_Options :: struct {
	width, height: int,
	backdrop: Modal_Backdrop,
	backdrop_style: Style,
	box: Box_Options,
}

// draw_modal paints the backdrop and box and returns the box content rectangle.
draw_modal :: proc(grid: ^Grid, bounds: Rect, options: Modal_Options = {}) -> Rect {
	area := rect_intersect(bounds, current_clip(grid))
	switch options.backdrop {
	case .Clear:
		fill(grid, area.x, area.y, area.width, area.height, {' ', options.backdrop_style})
	case .Dim:
		for y in area.y..<area.y+area.height {
			for x in area.x..<area.x+area.width {
				cell, _ := get_cell(grid, x, y)
				if cell.glyph == CONTINUATION {
					if x == area.x {
						cell.glyph = ' '
						cell.style.attributes += {.Dim}
						set_cell(grid, x, y, cell)
					}
					continue
				}
				cell.style.attributes += {.Dim}
				set_cell(grid, x, y, cell)
			}
		}
	case .None:
	}
	width, height := options.width, options.height
	if width <= 0 { width = 60 }
	if height <= 0 { height = 12 }
	box := options.box
	box.fill = true
	return draw_box(grid, rect_center(bounds, width, height), box)
}

// Modal_Result reports Escape or Enter without modifying caller-owned state.
Modal_Result :: struct { handled, cancelled, submitted: bool }

modal_handle :: proc(event: Input_Event) -> Modal_Result {
	key, ok := event.(Key_Event)
	if !ok || key.modifiers != {} { return {} }
	if key.key == .Escape { return {true, true, false} }
	if key.key == .Enter { return {true, false, true} }
	return {}
}

// Spinner_Options defaults to four ASCII frames and 80 ms per frame.
Spinner_Options :: struct {
	frames: []string,
	interval_ms: i64,
	style: Style,
}

// spinner_frame returns a borrowed frame, clamping negative elapsed time to 0.
spinner_frame :: proc(elapsed_ms: i64, options: Spinner_Options = {}) -> string {
	interval := options.interval_ms
	if interval <= 0 { interval = 80 }
	step := max(elapsed_ms, 0) / interval
	if len(options.frames) > 0 { return options.frames[int(step % i64(len(options.frames)))] }
	switch step % 4 {
	case 0: return "|"
	case 1: return "/"
	case 2: return "-"
	case: return "\\"
	}
}

draw_spinner :: proc(grid: ^Grid, bounds: Rect, elapsed_ms: i64, options: Spinner_Options = {}) {
	draw_label(grid, bounds, spinner_frame(elapsed_ms, options), options.style)
}
