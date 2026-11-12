package odintui

// scroll_clamp clamps offset to the valid range for content and viewport.
// Negative content, viewport, and offset are treated as zero.
scroll_clamp :: proc(offset, content, viewport: int) -> int {
	total := max(content, 0)
	view := max(viewport, 0)
	return clamp(offset, 0, max(total-view, 0))
}

// scroll_into_view moves offset minimally to expose [start, start+size).
// Negative arguments are zero; an empty item leaves the offset unchanged.
// An item larger than the viewport, including a zero viewport, aligns its
// start. Results exceeding max(int) saturate there.
scroll_into_view :: proc(offset, start, size, viewport: int) -> int {
	current := max(offset, 0)
	first := max(start, 0)
	length := max(size, 0)
	view := max(viewport, 0)
	if length == 0 {
		return current
	}
	if length > view || first < current {
		return first
	}
	end := i128(first) + i128(length)
	if end > i128(current)+i128(view) {
		return int(min(end-i128(view), i128(max(int))))
	}
	return current
}
