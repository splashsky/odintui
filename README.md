# odintui

A small, backend-agnostic, immediate-mode TUI library written in Odin, using
only Odin's standard `base` and `core` libraries. There are no third-party
dependencies. Each frame, the application draws into a `Grid`; `render` diffs
it against the previous frame and sends only changed runs to a backend.

It includes constraint layouts, clipping, styled and wrapped text, boxes,
scrollbars, sliders, lists, tabs, tables, a text field, a streaming input
parser and an ANSI terminal backend. Widgets are plain procedures over
caller-owned state, and drawing, rendering and input handling do not allocate.

## Run

Install the Odin compiler and run these commands from the repository root:

```sh
odin check . -no-entry-point
odin test . -out:/tmp/odintui-test
odin run examples/demo
odin run examples/showcase
```

The demo draws a border, labels and a progress bar using a column layout. It
renders an initial frame, an update, and an unchanged frame, reporting the
backend's draw-run, cell and flush counts. Its application-owned backend stores
a plain-text snapshot and prints it without terminal control sequences; it
works with redirected output. It substitutes `?` for every glyph outside
printable ASCII and intentionally ignores styles. The `Input: ??` in its
output demonstrates replacement of an escape character and a wide rune.

The showcase is an interactive Linux/macOS terminal application built on the
ANSI backend and input parser. It has two pages selected with a tab bar (or
F1/F2): a
"Widgets" page with scrollable styled text, a form with text fields, a
slider, progress bar and palette, and an event log; and a "Data" page with a
custom-row list and a scrolling table. It reflows on resize and supports
keyboard and mouse input. `examples/showcase/terminal.odin` is a small,
copyable POSIX host: raw mode, alternate screen, signal-safe restoration,
`poll`-based input with an escape timeout, and terminal size queries.

## Using the library

Import the root package from your application (the examples use `import tui
"../.."`). `grid_init(width, height)` returns a `Grid` and a `Grid_Error`;
check for `.None` and call `grid_destroy(&grid)` when finished. An optional
allocator can be passed to `grid_init`; it must outlive the grid. A grid owns
its buffers: do not copy it or mutate its fields directly. Use `grid_bounds`,
`get_cell`, `set_cell`, `fill`, `draw_text` and `grid_resize` instead.
Resize preserves the overlap, blanks newly exposed cells and leaves the grid
unchanged on error.

Each decoded rune occupies one **logical** cell: no grapheme segmentation or
terminal Unicode-width calculation is performed. `draw_label` and `draw_text`
clip; `draw_spans` wraps.

### Styles and clipping

`Style` contains foreground/background colors and an `attributes` bit set
(`Bold`, `Italic`, `Underline`, `Reverse`, `Dim`, `Blink`, `Hidden`,
`Strikethrough`). A zero `Color` means the backend's default color;
`rgb(0, 0, 0)` is explicit black, and `hex("#61dafb")` or `hex("fff")` parses
hex colors. A space with a style is still a styled cell and is not equivalent
to `BLANK_CELL`.

All drawing respects the grid's clip stack. `push_clip` intersects a
rectangle with the current clip (up to `MAX_CLIP_DEPTH` levels) and `pop_clip`
restores it; `if clip_scope(&grid, rect) { ... }` pops automatically at the end
of the enclosing scope. `rect.odin` provides `rect_intersect`,
`rect_contains`, `rect_inset` (uniform or `Insets`), `rect_align` and
`rect_center`; all are overflow-safe.

### Layout

`layout_split(bounds, axis, constraints, out, gap)` divides a rectangle along
`.Row` or `.Column`. `layout_fixed(n)` and `layout_percent(p)` are reserved
first; `layout_fill(weight, min_size, max_size)` shares the remainder by
weight, and a zero `Constraint` is a fill of weight 1. `layout_split_n`
returns a fixed array, so no output slice is needed:

```odin
rows := tui.layout_split_n(screen, .Column, [3]tui.Constraint{
	tui.layout_fixed(1), tui.layout_fill(), tui.layout_fixed(1),
})
columns := tui.layout_split_n(rows[1], .Row, [2]tui.Constraint{
	tui.layout_percent(30), tui.layout_fill(),
}, 1)
```

Use fill spacers on both sides to center. For sequential layouts,
`layout_init` creates a cursor; `layout_take` and `layout_take_end` cut from
the start or end and `layout_take_rest` takes what remains. `layout_cell`
returns one cell of a uniform grid with gaps.

### Text

`draw_spans(grid, bounds, spans, options)` draws borrowed, individually styled
`Span`s; `draw_paragraph` is the single-style form. `Text_Options` selects
`wrap` (`None`, `Char`, or `Word`, which breaks on spaces), per-line `align`,
an `ellipsis` on truncated text, and `scroll`, the number of leading visual
lines to skip. LF and CRLF are hard breaks. `measure_spans` and
`measure_text` return the line count and widest line for a width, which with
`scroll_clamp` is all a scrolling text view needs.

### Widgets

Widgets draw into a `Grid` and keep no state of their own; zero-value options
give a sensible default look.

- **Boxes**: `draw_box(grid, bounds, options)` draws a border (`BORDER_SINGLE`
  by default; also `BORDER_ASCII`, `BORDER_DOUBLE`, `BORDER_ROUNDED`,
  `BORDER_HEAVY` or a custom `Border_Set`), optional fill, aligned title and
  footer, hidden sides and padding. It returns the content rectangle;
  `box_content` computes it without drawing.
- **Scrollbars and sliders**: `draw_scrollbar` draws a proportional thumb for
  a content size, viewport and offset; `scrollbar_offset_at` maps a click or
  drag on the track back to an offset. `draw_slider` and `slider_value_at` do
  the same for a value in [0, 1]. `scroll_clamp` and `scroll_into_view` keep
  offsets valid and items visible.
- **Lists**: `List_State{selected, offset}` is caller-owned. `draw_list` draws
  string items with a highlighted selection and optional scrollbar; for custom
  rows, iterate the visible items yourself:

  ```odin
  view := tui.list_begin(&state, len(files), area)
  for row, index in tui.list_next(&view) {
  	style := selected if index == state.selected else normal
  	tui.fill(&grid, row.x, row.y, row.width, row.height, {' ', style})
  	tui.draw_paragraph(&grid, row, files[index].name, style)
  }
  ```

  `list_handle` processes arrows, Page Up/Down, Home/End, Enter, the wheel,
  clicks and scrollbar drags; `list_move` and `list_index_at` are available
  for custom handling.
- **Tabs**: `draw_tabs(grid, bounds, labels, selected, options)` draws a tab
  bar that scrolls horizontally to keep the selected tab visible, with an
  optional underline row. `tabs_handle` and `tabs_index_at` handle keys and
  mouse.
- **Tables**: `draw_table(grid, bounds, columns, rows, &state, options)` lays
  out `Table_Column`s with the same constraints as `layout_split`, aligns
  cells, truncates with an ellipsis, joins border junctions and optionally
  separates rows. Pass a `List_State` for selection and scrolling;
  `table_handle` mirrors `list_handle` using the same geometry as
  `draw_table`, and `table_row_at` maps a point to a row. Up to
  `MAX_TABLE_COLUMNS` columns are shown.
- **Text field**: `text_field_init(buffer[:])` creates a single-line
  `Text_Field` that edits a caller-owned buffer without allocating.
  `text_field_handle` applies editing keys (including Ctrl/Alt word and line
  bindings) and pastes, reporting `changed`, `submitted` and `cancelled`.
  `draw_text_field` scrolls to the cursor and supports a placeholder, a
  password mask and focus, returning the cursor position for
  `ansi_set_cursor`. Invalid UTF-8 and control characters are discarded.
- **Labels and progress**: `draw_label`, `draw_border` and
  `draw_progress_bar`.

### Input

`input_parse(&parser, bytes, final)` decodes one event from raw terminal bytes
and returns how many it consumed; zero means more bytes are needed. Iterate a
buffer with `for event in tui.input_next(&parser, &pending, final)` and keep
unconsumed bytes for the next read. An `Input_Event` is a `Key_Event` (keys,
runes and modifiers, including CSI, SS3 and kitty encodings), `Mouse_Event`
(SGR mouse, 0-based), `Paste_Event` (bracketed paste chunks that borrow the
input and never split a UTF-8 sequence) or `Focus_Event`. A lone Escape is
ambiguous: after a short timeout with no further input, parse again with
`final = true`.

### ANSI backend

`Ansi_Backend` writes to any `io.Writer` through a fixed 4 KiB buffer,
emitting cursor moves and SGR changes only when needed in truecolor,
256-color or 16-color mode. Glyphs that are not single-column printable are
replaced. `ansi_backend(&state)` returns the `Backend` for `render`.
`ansi_enter` and `ansi_leave` switch the alternate screen, cursor visibility,
mouse reporting, bracketed paste, focus events and kitty keyboard mode;
`ansi_clear` and `ansi_set_cursor` act immediately. Raw mode and terminal size
queries remain the host's job; see the showcase.

### Writing your own widget

Follow the same shape as the built-in widgets so they compose:

- Draw with `draw_<widget>(grid: ^Grid, bounds: Rect, state: ^<Widget>_State,
  options: <Widget>_Options = {}) -> result`, and keep input handling in a
  separate `<widget>_handle(state, bounds, event, options)` that returns what
  changed.
- Let caller-owned state hold only what must persist (selection, scroll
  offset, buffers). Recompute geometry from `bounds` each frame, sharing one
  private layout routine between drawing and hit testing so they agree.
- Make the zero value of options a sensible default.
- Compose: draw a `draw_box` and work inside the content rectangle it
  returns, split it with `layout_split_n`, and use `clip_scope` when drawing
  may overflow.
- Do not allocate while drawing. Borrow strings and use fixed buffers.

## Backends and application lifecycle

The host owns the input, event loop, backend and any terminal setup and
cleanup. The library does not open a terminal, read input or handle resize
events. On resize, update the backend and call `grid_resize`; the backend must
also clear any old viewport left outside a smaller grid.

Provide a `Backend` with `draw_run` and `flush` callbacks, as in the demo.
`draw_run` receives a borrowed slice of adjacent cells for one row; callbacks
must not retain or modify it, mutate the grid, or assume they will not be
retried. Give rendering exclusive access to the grid and backend. A real
terminal backend must sanitize control and invalid runes and map glyphs to
single-column printable output; the grid does not do this for it.

`render` sends changed runs and commits the presented state only after a
successful flush. Check its boolean result: a failed callback may already have
applied part of a frame, so repair the backend and retry; the next render
redraws the whole nonempty grid. Unchanged or empty grids do not call the
backend. Call `invalidate(&grid)` before rendering to a different backend or
after out-of-band screen changes or loss of backend contents.
