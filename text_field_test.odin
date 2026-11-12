package odintui

import "core:testing"

@(test)
text_field_test_editing :: proc(t: ^testing.T) {
	buffer: [12]byte
	field := text_field_init(buffer[:], "aé界🙂xyz")
	testing.expect(t, text_field_text(&field) == "aé界🙂xy")
	testing.expect(t, field.cursor == 12)
	testing.expect(t, !text_field_insert_rune(&field, 'z'))
	testing.expect(t, text_field_backspace(&field))
	testing.expect(t, text_field_backspace(&field))
	testing.expect(t, text_field_backspace(&field))
	testing.expect(t, text_field_text(&field) == "aé界")
	field.cursor = 1
	testing.expect(t, text_field_delete(&field))
	testing.expect(t, text_field_text(&field) == "a界")
	testing.expect(t, text_field_insert_string(&field, "🙂\t\xff!"))
	testing.expect(t, text_field_text(&field) == "a🙂!界")
	field.max_runes = 4
	testing.expect(t, !text_field_insert_string(&field, "ab"))
	testing.expect(t, text_field_text(&field) == "a🙂!界")
	testing.expect(t, !text_field_set_text(&field, "12345"))
	testing.expect(t, text_field_text(&field) == "a🙂!界")
	testing.expect(t, text_field_set_text(&field, "é\t界"))
	testing.expect(t, text_field_text(&field) == "é界" && field.cursor == 5)
	testing.expect(t, !text_field_insert_string(&field, text_field_text(&field)))
	text_field_clear(&field)
	testing.expect(t, !text_field_backspace(&field) && !text_field_delete(&field))
	testing.expect(t, text_field_text(&field) == "" && field.scroll == 0)
}

@(test)
text_field_test_capacity_and_invalid :: proc(t: ^testing.T) {
	buffer: [4]byte
	field := text_field_init(buffer[:], "é界a")
	testing.expect(t, text_field_text(&field) == "é")
	testing.expect(t, !text_field_insert_string(&field, "a界"))
	testing.expect(t, text_field_text(&field) == "é")
	testing.expect(t, text_field_insert_string(&field, "\xc3\x80\xff\x00"))
	testing.expect(t, text_field_text(&field) == "éÀ")
	testing.expect(t, text_field_insert_rune(&field, rune(0xd800)))
	testing.expect(t, text_field_text(&field) == "éÀ")
	empty := text_field_init(nil, "a")
	testing.expect(t, text_field_text(&empty) == "")
	testing.expect(t, !text_field_insert_rune(&empty, 'a'))
}

@(test)
text_field_test_movement_and_word_deletion :: proc(t: ^testing.T) {
	buffer: [64]byte
	field := text_field_init(buffer[:], "α,β\u00a0  界🙂 end  ")
	text_field_word_left(&field)
	testing.expect(t, text_field_text(&field)[field.cursor:] == "end  ")
	text_field_word_left(&field)
	testing.expect(t, text_field_text(&field)[field.cursor:] == "界🙂 end  ")
	text_field_left(&field)
	testing.expect(t, text_field_text(&field)[field.cursor:] == " 界🙂 end  ")
	text_field_right(&field)
	testing.expect(t, text_field_text(&field)[field.cursor:] == "界🙂 end  ")
	text_field_word_right(&field)
	testing.expect(t, text_field_text(&field)[field.cursor:] == " end  ")
	testing.expect(t, text_field_delete_word_backward(&field))
	testing.expect(t, text_field_text(&field) == "α,β\u00a0   end  ")
	testing.expect(t, text_field_delete_to_start(&field))
	testing.expect(t, text_field_text(&field) == " end  " && field.cursor == 0)
	testing.expect(t, !text_field_delete_to_start(&field))
	text_field_word_right(&field)
	testing.expect(t, text_field_text(&field)[:field.cursor] == " end")
	testing.expect(t, text_field_delete_to_end(&field))
	testing.expect(t, text_field_text(&field) == " end")
	testing.expect(t, !text_field_delete_to_end(&field))
	text_field_home(&field)
	text_field_left(&field)
	testing.expect(t, field.cursor == 0 && !text_field_delete_word_backward(&field))
	text_field_end(&field)
	text_field_right(&field)
	testing.expect(t, field.cursor == field.length)
}
