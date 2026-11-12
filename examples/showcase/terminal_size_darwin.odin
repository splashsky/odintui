package main

import "core:sys/darwin"

terminal_query_size :: proc() -> Terminal_Size {
	size: Terminal_Size
	_ = darwin.syscall_ioctl(1, darwin.TIOCGWINSZ, &size)
	return size
}
