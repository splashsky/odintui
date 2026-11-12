package odintui

// MAX_KEY_HINTS bounds scratch storage used for priority selection.
MAX_KEY_HINTS :: 64

// Key_Hint is a borrowed key/label pair. Higher priorities are kept first;
// ties favor earlier items. always_keep items take precedence over all others.
Key_Hint :: struct {
	key, label: string,
	priority: int,
	always_keep: bool,
}

// Key_Hint_Options controls styles and the separator (default: three spaces).
Key_Hint_Options :: struct {
	key_style, label_style, separator_style: Style,
	separator: string,
}

@(private)
key_hint_width :: proc(hint: Key_Hint) -> int {
	width := tabs_label_length(hint.key)
	if len(hint.key) > 0 && len(hint.label) > 0 { width = tabs_add(width, 1) }
	return tabs_add(width, tabs_label_length(hint.label))
}

// draw_key_hints renders as many complete pairs as fit, in original order.
// Highest priority wins; equal priority drops from the right. The first
// always_keep item is truncated if it alone exceeds the available width.
// At most MAX_KEY_HINTS are considered. Returns the number displayed.
draw_key_hints :: proc(
	grid: ^Grid, bounds: Rect, hints: []Key_Hint, options: Key_Hint_Options = {},
) -> int {
	if rect_is_empty(bounds) { return 0 }
	separator := options.separator
	if len(separator) == 0 { separator = "   " }
	sep_width := tabs_label_length(separator)
	count := min(len(hints), MAX_KEY_HINTS)
	processed, selected: [MAX_KEY_HINTS]bool
	remaining, chosen := bounds.width, 0
	for _ in 0..<count {
		best := -1
		for i in 0..<count {
			if processed[i] { continue }
			if best < 0 || (hints[i].always_keep && !hints[best].always_keep) ||
			   (hints[i].always_keep == hints[best].always_keep && hints[i].priority > hints[best].priority) {
				best = i
			}
		}
		processed[best] = true
		width := key_hint_width(hints[best])
		if chosen > 0 { width = tabs_add(width, sep_width) }
		if width <= remaining || (chosen == 0 && hints[best].always_keep && remaining > 0) {
			selected[best] = true
			chosen += 1
			remaining -= min(width, remaining)
		}
	}
	cursor := layout_init(bounds, .Row)
	drawn := 0
	for i in 0..<count {
		if !selected[i] { continue }
		if drawn > 0 {
			draw_label(grid, layout_take(&cursor, sep_width), separator, options.separator_style)
		}
		hint := hints[i]
		draw_label(grid, layout_take(&cursor, tabs_label_length(hint.key)), hint.key, options.key_style)
		if len(hint.key) > 0 && len(hint.label) > 0 {
			gap := layout_take(&cursor, 1)
			fill(grid, gap.x, gap.y, gap.width, gap.height, {' ', options.label_style})
		}
		draw_label(grid, layout_take(&cursor, tabs_label_length(hint.label)), hint.label, options.label_style)
		drawn += 1
	}
	return drawn
}
