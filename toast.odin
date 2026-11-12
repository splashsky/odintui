package odintui

// Toast borrows its message; expires_at_ms is an absolute caller-supplied
// clock value, or 0 for no expiry. The clock need only be monotonic.
Toast :: struct {
	text: string,
	expires_at_ms: i64,
	style: Style,
}

// Toast_Stack borrows storage and all toast messages. Do not copy while in use.
Toast_Stack :: struct {
	items: []Toast,
	count: int,
}

toast_init :: proc(storage: []Toast) -> Toast_Stack { return {storage, 0} }

// toast_push drops the oldest toast when the caller's storage is full.
toast_push :: proc(stack: ^Toast_Stack, toast: Toast) -> bool {
	if stack == nil || len(stack.items) == 0 { return false }
	if stack.count == len(stack.items) {
		copy(stack.items, stack.items[1:])
		stack.count -= 1
	}
	stack.items[stack.count] = toast
	stack.count += 1
	return true
}

// toast_expire removes expired entries in place and returns the number removed.
toast_expire :: proc(stack: ^Toast_Stack, now_ms: i64) -> int {
	if stack == nil { return 0 }
	count := 0
	for item in stack.items[:stack.count] {
		if item.expires_at_ms != 0 && now_ms >= item.expires_at_ms { continue }
		stack.items[count] = item
		count += 1
	}
	removed := stack.count-count
	for i in count..<stack.count { stack.items[i] = {} }
	stack.count = count
	return removed
}

// Toast_Options padding defaults to one cell; negative padding means none.
Toast_Options :: struct {
	padding: int,
	style: Style,
}

// draw_toasts expires entries then draws newest at bottom-right. Text is
// single-line and ellipsized; it returns the number of visible toast rows.
draw_toasts :: proc(
	grid: ^Grid, bounds: Rect, stack: ^Toast_Stack, now_ms: i64, options: Toast_Options = {},
) -> int {
	if stack == nil { return 0 }
	toast_expire(stack, now_ms)
	if rect_is_empty(bounds) { return 0 }
	padding := options.padding
	if padding == 0 { padding = 1 }
	padding = max(padding, 0)
	count := min(stack.count, bounds.height)
	for i in 0..<count {
		item := stack.items[stack.count-1-i]
		width := min(bounds.width, tabs_add(tabs_label_length(item.text), tabs_add(padding, padding)))
		area := rect_align(bounds, width, 1, .End, .End)
		y := i128(area.y)-i128(i)
		if y < i128(min(int)) { break }
		area.y = int(y)
		style := item.style
		if style == (Style{}) { style = options.style }
		fill(grid, area.x, area.y, area.width, 1, {' ', style})
		content := rect_inset(area, Insets{left = padding, right = padding})
		_ = draw_paragraph(grid, content, item.text, style, {ellipsis = true})
	}
	return count
}
