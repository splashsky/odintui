package odintui

// List_State is caller-owned selection and scroll state shared by lists and
// tables: selected is the selected item and offset the first visible item.
List_State :: struct {
	selected: int,
	offset:   int,
}
