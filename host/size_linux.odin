package host
import "core:sys/linux"
import "core:sys/posix"
query_size :: proc() -> Terminal_Size {
	s: Terminal_Size
	_ = linux.ioctl(linux.Fd(posix.STDOUT_FILENO), linux.TIOCGWINSZ, uintptr(&s))
	return s
}
