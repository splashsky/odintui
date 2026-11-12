package odintui

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
