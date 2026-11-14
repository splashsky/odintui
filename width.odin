package odintui

import "core:unicode"
import "core:unicode/utf8"

// CONTINUATION marks the second column of a wide glyph. It is not a Unicode
// scalar and must not be passed to set_cell by callers.
CONTINUATION :: rune(-2)

// rune_width reports terminal columns for a scalar. Ambiguous characters are
// narrow. Combining/format runes are dropped; controls and invalid scalars
// reserve one cell and are sanitized by terminal backends.
rune_width :: proc(r: rune) -> int {
	if r >= ' ' && r <= '~' {
		return 1
	}
	if !utf8.valid_rune(r) || unicode.is_control(r) {
		return 1
	}
	if unicode.is_combining(r) || unicode.is_nonspacing_mark(r) ||
	   unicode.is_spacing_mark(r) || unicode.is_enclosing_mark(r) ||
	   unicode.is_gcb_extend_class(r) || (r >= 0x1160 && r <= 0x11ff) ||
	   (r >= 0xd7b0 && r <= 0xd7ff) {
		return 0
	}
	w := unicode.normalized_east_asian_width(r)
	if w == 0 {
		return 0
	}
	lo, hi := 0, len(emoji_presentation_ranges)
	for lo < hi {
		mid := lo + (hi-lo)/2
		if r < emoji_presentation_ranges[mid][0] {
			hi = mid
		} else if r > emoji_presentation_ranges[mid][1] {
			lo = mid+1
		} else {
			return 2
		}
	}
	return w
}

// text_width returns the columns in text, including controls as one column;
// it does not interpret line breaks. The result saturates at max(int).
text_width :: proc(text: string) -> int {
	width := 0
	for glyph in text {
		width += min(rune_width(glyph), max(int)-width)
	}
	return width
}
