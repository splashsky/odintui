package odintui

import "core:unicode"
import "core:unicode/utf8"

// Text_Field borrows buffer for its lifetime. Only max_runes may be modified
// directly; a non-positive limit means no limit other than buffer capacity.
// The cursor is a byte offset and scroll is the first visible rune index.
Text_Field :: struct {
	buffer:    []byte,
	length:    int,
	cursor:    int,
	scroll:    int,
	max_runes: int,
}

// text_field_init copies as much initial text as fits, without splitting a
// rune. Initial text must not overlap buffer. Invalid UTF-8 and C0/C1 controls
// are discarded, as they are for all insertion operations.
text_field_init :: proc(buffer: []byte, initial := "") -> Text_Field {
	field := Text_Field{buffer = buffer}
	for i := 0; i < len(initial); {
		r, n := utf8.decode_rune(initial[i:])
		i += n
		if !text_field_printable(r) || (r == utf8.RUNE_ERROR && n == 1) {
			continue
		}
		if n > len(buffer)-field.length {
			break
		}
		copy(buffer[field.length:], transmute([]byte)initial[i-n:i])
		field.length += n
	}
	field.cursor = field.length
	return field
}

// text_field_text returns a borrowed view invalidated by the next edit.
text_field_text :: proc(field: ^Text_Field) -> string {
	return string(field.buffer[:field.length])
}

@(private)
text_field_printable :: proc(r: rune) -> bool {
	return utf8.valid_rune(r) && r >= 0x20 && !(r >= 0x7f && r <= 0x9f)
}

@(private)
text_field_overlaps :: proc(field: ^Text_Field, text: string) -> bool {
	if len(field.buffer) == 0 || len(text) == 0 {
		return false
	}
	a, b := uintptr(raw_data(field.buffer)), uintptr(raw_data(text))
	if a <= b {
		return b-a < uintptr(len(field.buffer))
	}
	return a-b < uintptr(len(text))
}

@(private)
text_field_measure :: proc(text: string) -> (bytes, runes: int) {
	for i := 0; i < len(text); {
		r, n := utf8.decode_rune(text[i:])
		i += n
		if text_field_printable(r) && (r != utf8.RUNE_ERROR || n != 1) {
			bytes += n
			runes += 1
		}
	}
	return
}

@(private)
text_field_copy :: proc(buffer: []byte, text: string) {
	offset := 0
	for i := 0; i < len(text); {
		r, n := utf8.decode_rune(text[i:])
		i += n
		if text_field_printable(r) && (r != utf8.RUNE_ERROR || n != 1) {
			copy(buffer[offset:], transmute([]byte)text[i-n:i])
			offset += n
		}
	}
}

// text_field_insert_string inserts all accepted runes atomically; it returns
// false if they do not fit or text overlaps the field's buffer. Invalid UTF-8
// bytes and C0/C1 controls are discarded. An empty insertion succeeds.
text_field_insert_string :: proc(field: ^Text_Field, text: string) -> bool {
	bytes, runes := text_field_measure(text)
	if bytes > len(field.buffer)-field.length || text_field_overlaps(field, text) {
		return false
	}
	if field.max_runes > 0 {
		existing := utf8.rune_count(text_field_text(field))
		if existing > field.max_runes || runes > field.max_runes-existing {
			return false
		}
	}
	copy(field.buffer[field.cursor+bytes:field.length+bytes],
	     field.buffer[field.cursor:field.length])
	text_field_copy(field.buffer[field.cursor:field.cursor+bytes], text)
	field.length += bytes
	field.cursor += bytes
	return true
}

// text_field_insert_rune inserts a printable scalar atomically; controls and
// invalid scalars are ignored and count as a successful empty insertion.
text_field_insert_rune :: proc(field: ^Text_Field, r: rune) -> bool {
	if !text_field_printable(r) {
		return true
	}
	bytes, count := utf8.encode_rune(r)
	return text_field_insert_string(field, string(bytes[:count]))
}

// text_field_set_text atomically replaces the text and moves the cursor to
// the end; it has the same filtering and non-overlap rule as insertion.
text_field_set_text :: proc(field: ^Text_Field, text: string) -> bool {
	bytes, runes := text_field_measure(text)
	if bytes > len(field.buffer) || (field.max_runes > 0 && runes > field.max_runes) ||
	   text_field_overlaps(field, text) {
		return false
	}
	text_field_copy(field.buffer[:bytes], text)
	field.length, field.cursor, field.scroll = bytes, bytes, 0
	return true
}

// text_field_clear removes all text and resets the cursor and scroll.
text_field_clear :: proc(field: ^Text_Field) {
	field.length, field.cursor, field.scroll = 0, 0, 0
}

@(private)
text_field_remove :: proc(field: ^Text_Field, start, end: int) {
	copy(field.buffer[start:], field.buffer[end:field.length])
	field.length -= end-start
	field.cursor = start
}

// text_field_backspace deletes the rune before the cursor, if any.
text_field_backspace :: proc(field: ^Text_Field) -> bool {
	if field.cursor == 0 {
		return false
	}
	start := field.cursor-1
	for start > 0 && field.buffer[start] & 0xc0 == 0x80 {
		start -= 1
	}
	text_field_remove(field, start, field.cursor)
	return true
}

// text_field_delete deletes the rune at the cursor, if any.
text_field_delete :: proc(field: ^Text_Field) -> bool {
	if field.cursor == field.length {
		return false
	}
	_, size := utf8.decode_rune(field.buffer[field.cursor:field.length])
	text_field_remove(field, field.cursor, field.cursor+size)
	return true
}

@(private)
text_field_prev :: proc(field: ^Text_Field, offset: int) -> int {
	prev := offset-1
	for prev > 0 && field.buffer[prev] & 0xc0 == 0x80 {
		prev -= 1
	}
	return prev
}

@(private)
text_field_space_at :: proc(field: ^Text_Field, offset: int) -> bool {
	r, _ := utf8.decode_rune(field.buffer[offset:field.length])
	return unicode.is_space(r)
}

// text_field_left moves one rune to the left.
text_field_left :: proc(field: ^Text_Field) {
	if field.cursor > 0 {
		field.cursor = text_field_prev(field, field.cursor)
	}
}

// text_field_right moves one rune to the right.
text_field_right :: proc(field: ^Text_Field) {
	if field.cursor < field.length {
		_, size := utf8.decode_rune(field.buffer[field.cursor:field.length])
		field.cursor += size
	}
}

// text_field_home moves the cursor to the beginning.
text_field_home :: proc(field: ^Text_Field) {
	field.cursor = 0
}

// text_field_end moves the cursor to the end.
text_field_end :: proc(field: ^Text_Field) {
	field.cursor = field.length
}

// text_field_word_left skips whitespace and then the preceding non-whitespace
// run. Words are delimited by Unicode whitespace, not punctuation.
text_field_word_left :: proc(field: ^Text_Field) {
	for field.cursor > 0 {
		prev := text_field_prev(field, field.cursor)
		if !text_field_space_at(field, prev) {
			break
		}
		field.cursor = prev
	}
	for field.cursor > 0 {
		prev := text_field_prev(field, field.cursor)
		if text_field_space_at(field, prev) {
			break
		}
		field.cursor = prev
	}
}

// text_field_word_right skips whitespace and then the next non-whitespace run.
text_field_word_right :: proc(field: ^Text_Field) {
	for field.cursor < field.length && text_field_space_at(field, field.cursor) {
		text_field_right(field)
	}
	for field.cursor < field.length && !text_field_space_at(field, field.cursor) {
		text_field_right(field)
	}
}

// text_field_delete_word_backward removes the preceding word and whitespace.
text_field_delete_word_backward :: proc(field: ^Text_Field) -> bool {
	end := field.cursor
	text_field_word_left(field)
	if end == field.cursor {
		return false
	}
	text_field_remove(field, field.cursor, end)
	return true
}

// text_field_delete_to_start removes all text preceding the cursor.
text_field_delete_to_start :: proc(field: ^Text_Field) -> bool {
	if field.cursor == 0 {
		return false
	}
	text_field_remove(field, 0, field.cursor)
	return true
}

// text_field_delete_to_end removes all text from the cursor onwards.
text_field_delete_to_end :: proc(field: ^Text_Field) -> bool {
	if field.cursor == field.length {
		return false
	}
	field.length = field.cursor
	return true
}

// Text_Field_Result describes a consumed event, its text change, or a request
// to submit/cancel. Cursor movement is handled but not a text change.
Text_Field_Result :: struct {
	handled:   bool,
	changed:   bool,
	submitted: bool,
	cancelled: bool,
}

// text_field_handle applies supported key bindings and paste events. Paste
// chunks are atomic and independently decoded: invalid bytes, including bytes
// of UTF-8 split between chunks, and controls are discarded. Paste boundaries
// are consumed. Unsupported events and modifier combinations are unhandled;
// recognized events remain handled even if an edit is blocked by capacity.
text_field_handle :: proc(field: ^Text_Field, event: Input_Event) -> Text_Field_Result {
	paste, is_paste := event.(Paste_Event)
	if is_paste {
		result := Text_Field_Result{handled = true}
		if paste.kind == .Chunk {
			old_length := field.length
			_ = text_field_insert_string(field, string(paste.text))
			result.changed = field.length != old_length
		}
		return result
	}

	key, ok := event.(Key_Event)
	if !ok {
		return {}
	}
	result := Text_Field_Result{handled = true}
	if key.modifiers == {.Ctrl} {
		#partial switch key.key {
		case .Left:
			text_field_word_left(field)
		case .Right:
			text_field_word_right(field)
		case .Rune:
			switch key.rune {
			case 'a': text_field_home(field)
			case 'e': text_field_end(field)
			case 'w': result.changed = text_field_delete_word_backward(field)
			case 'u': result.changed = text_field_delete_to_start(field)
			case 'k': result.changed = text_field_delete_to_end(field)
			case 'd': result.changed = text_field_delete(field)
			case: return {}
			}
		case:
			return {}
		}
		return result
	}
	if key.modifiers == {.Alt} {
		#partial switch key.key {
		case .Backspace:
			result.changed = text_field_delete_word_backward(field)
		case .Rune:
			switch key.rune {
			case 'b': text_field_word_left(field)
			case 'f': text_field_word_right(field)
			case: return {}
			}
		case:
			return {}
		}
		return result
	}
	if key.key == .Rune && (key.modifiers == {} || key.modifiers == {.Shift}) {
		if !text_field_printable(key.rune) {
			return {}
		}
		old_length := field.length
		_ = text_field_insert_rune(field, key.rune)
		result.changed = field.length != old_length
		return result
	}
	if key.modifiers != {} {
		return {}
	}
	#partial switch key.key {
	case .Enter: result.submitted = true
	case .Escape: result.cancelled = true
	case .Backspace: result.changed = text_field_backspace(field)
	case .Delete: result.changed = text_field_delete(field)
	case .Left: text_field_left(field)
	case .Right: text_field_right(field)
	case .Home: text_field_home(field)
	case .End: text_field_end(field)
	case: return {}
	}
	return result
}

// Text_Field_Options configures the field, placeholder, mask and cursor.
// A zero or non-printable mask disables masking.
Text_Field_Options :: struct {
	style:             Style,
	placeholder:       string,
	placeholder_style: Style,
	mask:              rune,
	focused:           bool,
}

// draw_text_field paints the first row and keeps the cursor within its width.
// The returned position is in grid coordinates; visible is true only when
// focused and the cursor is inside the current clip and grid. The cursor
// cell retains its glyph/style and gains the Reverse attribute. Placeholder
// controls and invalid UTF-8 bytes are discarded like inserted text.
draw_text_field :: proc(
	grid: ^Grid,
	bounds: Rect,
	field: ^Text_Field,
	options: Text_Field_Options = {},
) -> (cursor_x, cursor_y: int, cursor_visible: bool) {
	if bounds.width <= 0 || bounds.height <= 0 {
		return 0, 0, false
	}
	cursor_index := utf8.rune_count(string(field.buffer[:field.cursor]))
	field.scroll = clamp(field.scroll, 0, cursor_index)
	if cursor_index-field.scroll >= bounds.width {
		field.scroll = cursor_index-(bounds.width-1)
	}
	fill(grid, bounds.x, bounds.y, bounds.width, 1, {' ', options.style})
	text, style := text_field_text(field), options.style
	placeholder := field.length == 0
	if placeholder {
		text, style = options.placeholder, options.placeholder_style
	}
	mask := !placeholder && text_field_printable(options.mask)
	index, byte_index := 0, 0
	for byte_index < len(text) {
		r, n := utf8.decode_rune(text[byte_index:])
		byte_index += n
		if !text_field_printable(r) || (r == utf8.RUNE_ERROR && n == 1) {
			continue
		}
		if index >= field.scroll {
			column := index-field.scroll
			if column >= bounds.width {
				break
			}
			x := i128(bounds.x)+i128(column)
			if x >= i128(min(int)) && x <= i128(max(int)) {
				if mask {
					r = options.mask
				}
				set_cell(grid, int(x), bounds.y, {r, style})
			}
		}
		index += 1
	}
	x := i128(bounds.x) + i128(cursor_index-field.scroll)
	if x < i128(min(int)) || x > i128(max(int)) {
		return 0, bounds.y, false
	}
	cursor_x, cursor_y = int(x), bounds.y
	cursor_visible = options.focused && rect_contains(current_clip(grid), cursor_x, cursor_y)
	if cursor_visible {
		cell, _ := get_cell(grid, cursor_x, cursor_y)
		cell.style.attributes += {.Reverse}
		set_cell(grid, cursor_x, cursor_y, cell)
	}
	return
}
