package odintui

import "core:unicode/utf8"

// Span is a borrowed text fragment with a single cell style.
Span :: struct {
	text:  string,
	style: Style,
}

// Text_Wrap selects no wrapping, character wrapping, or space-based word wrapping.
Text_Wrap :: enum {
	None,
	Char,
	Word,
}

// Text_Options controls wrapping, per-line alignment, and truncation markers.
Text_Options :: struct {
	wrap:     Text_Wrap,
	align:    Align,
	ellipsis: bool,
}

@(private)
text_Cursor :: struct {
	span, offset: int,
}

@(private)
text_Iterator :: struct {
	cursor: text_Cursor,
	done:   bool,
}

@(private)
text_Line :: struct {
	start:  text_Cursor,
	length: int,
}

@(private)
text_next_rune :: proc(spans: []Span, cursor: ^text_Cursor) -> (rune, Style, bool) {
	for cursor.span < len(spans) {
		span := spans[cursor.span]
		if cursor.offset < len(span.text) {
			glyph, size := utf8.decode_rune_in_string(span.text[cursor.offset:])
			cursor.offset += size
			return glyph, span.style, true
		}
		cursor.span += 1
		cursor.offset = 0
	}
	return 0, {}, false
}

// text_break consumes a hard newline, including CRLF across span boundaries.
@(private)
text_break :: proc(spans: []Span, cursor: ^text_Cursor, glyph: rune) -> bool {
	if glyph == '\n' {
		return true
	}
	if glyph == '\r' {
		next := cursor^
		following, _, ok := text_next_rune(spans, &next)
		if ok && following == '\n' {
			cursor^ = next
			return true
		}
	}
	return false
}

@(private)
text_skip_break_spaces :: proc(spans: []Span, iter: ^text_Iterator) {
	for {
		before := iter.cursor
		glyph, _, ok := text_next_rune(spans, &iter.cursor)
		if !ok {
			iter.done = true
			return
		}
		if glyph != ' ' {
			if !text_break(spans, &iter.cursor, glyph) {
				iter.cursor = before
			}
			return
		}
	}
}

@(private)
text_next_line :: proc(spans: []Span, iter: ^text_Iterator, width: int, wrap: Text_Wrap) -> text_Line {
	line := text_Line{start = iter.cursor}
	break_at: text_Cursor
	break_length := 0
	has_break, in_space, has_word := false, false, false
	for {
		before := iter.cursor
		glyph, _, ok := text_next_rune(spans, &iter.cursor)
		if !ok {
			iter.done = true
			return line
		}
		if text_break(spans, &iter.cursor, glyph) {
			return line
		}
		if wrap != .None && line.length == width {
			iter.cursor = before
			if wrap == .Word {
				if glyph == ' ' && !in_space && has_word {
					break_at, break_length, has_break = before, line.length, true
				}
				if has_break {
					iter.cursor = break_at
					line.length = break_length
					text_skip_break_spaces(spans, iter)
				}
			}
			return line
		}
		if glyph == ' ' {
			if !in_space && has_word {
				break_at, break_length, has_break = before, line.length, true
			}
			in_space = true
		} else {
			in_space, has_word = false, true
		}
		if line.length < max(int) {
			line.length += 1
		}
	}
}

// measure_spans returns visual line count and widest line in logical cells.
// Empty text is one empty line; a trailing hard newline adds an empty line.
// For Char and Word, non-positive width returns zero lines; None ignores width.
// Word wrapping breaks on ASCII spaces, dropping spaces at soft breaks.
// LF and CRLF are hard breaks; a lone CR and other controls are ordinary cells.
measure_spans :: proc(spans: []Span, width: int, wrap: Text_Wrap) -> (lines, widest: int) {
	if wrap != .None && width <= 0 {
		return 0, 0
	}
	iter: text_Iterator
	for !iter.done {
		line := text_next_line(spans, &iter, width, wrap)
		if lines < max(int) {
			lines += 1
		}
		widest = max(widest, line.length)
	}
	return
}

// measure_text is the single-style-free string convenience for measure_spans.
measure_text :: proc(text: string, width: int, wrap: Text_Wrap) -> (lines, widest: int) {
	spans := [1]Span{{text = text}}
	return measure_spans(spans[:], width, wrap)
}

// draw_spans lays out borrowed styled spans within bounds and returns the
// number of visual lines in bounds, including empty lines and clipped lines.
// It writes only text cells, honors the grid clip, and allocates nothing.
// Ellipsis replaces the last text cell of a horizontally truncated line or
// the last bounded line when more lines follow; empty lines have no cell to replace.
// See measure_spans for line breaking and control-rune handling.
draw_spans :: proc(
	grid: ^Grid,
	bounds: Rect,
	spans: []Span,
	options: Text_Options = {},
) -> int {
	if bounds.width <= 0 || bounds.height <= 0 {
		return 0
	}
	iter: text_Iterator
	lines := 0
	clip := current_clip(grid)
	for !iter.done && lines < bounds.height {
		line := text_next_line(spans, &iter, bounds.width, options.wrap)
		y := i128(bounds.y) + i128(lines)
		if y >= i128(clip.y) && y < i128(clip.y)+i128(clip.height) {
			visible := min(line.length, bounds.width)
			offset := 0
			switch options.align {
			case .Start:
			case .Center:
				offset = (bounds.width-visible)/2
			case .End:
				offset = bounds.width-visible
			}
			x := i128(bounds.x) + i128(offset)
			truncated := options.ellipsis &&
			             (line.length > bounds.width || (lines == bounds.height-1 && !iter.done))
			cursor := line.start
			for column in 0..<visible {
				if x+i128(column) >= i128(clip.x)+i128(clip.width) {
					break
				}
				glyph, style, _ := text_next_rune(spans, &cursor)
				if truncated && column == visible-1 {
					glyph = '…'
				}
				if x+i128(column) >= i128(clip.x) {
					set_cell(grid, int(x+i128(column)), int(y), {glyph, style})
				}
			}
		}
		lines += 1
	}
	return lines
}

// draw_paragraph is the single-span convenience for draw_spans.
draw_paragraph :: proc(
	grid: ^Grid,
	bounds: Rect,
	text: string,
	style: Style = {},
	options: Text_Options = {},
) -> int {
	spans := [1]Span{{text, style}}
	return draw_spans(grid, bounds, spans[:], options)
}
