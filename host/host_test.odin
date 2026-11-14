package host
import "core:testing"
import "core:sys/posix"

@(test)
raw_settings :: proc(t: ^testing.T) {
	s: posix.termios
	s.c_lflag = {.ECHO, .ICANON, .ISIG, .IEXTEN}
	s.c_iflag = {.ICRNL, .IXON}
	s.c_oflag = {.OPOST}
	r := raw_attributes(s)
	testing.expect(t, .ECHO not_in r.c_lflag && .ICANON not_in r.c_lflag && .ISIG not_in r.c_lflag)
	testing.expect(t, .ICRNL not_in r.c_iflag && .OPOST not_in r.c_oflag)
	testing.expect_value(t, r.c_cc[.VMIN], 1)
	testing.expect_value(t, r.c_cc[.VTIME], 0)
}

@(test)
poll_rejects_unopened :: proc(t: ^testing.T) {
	h: Host
	testing.expect(t, poll(&h, nil, 0).error)
	close(&h)
}

@(test)
poll_caller_descriptor :: proc(t: ^testing.T) {
	h: Host
	testing.expect(t,posix.pipe(&h.pipe) == .OK); h.pipe_open = true; defer close(&h)
	p: [2]posix.FD
	testing.expect(t,posix.pipe(&p) == .OK); defer posix.close(p[0]); defer posix.close(p[1])
	b := byte(42); testing.expect(t,posix.write(p[1],&b,1) == 1)
	fds := [1]posix.pollfd{{fd=p[0],events={.IN}}}
	r := poll(&h,fds[:],100)
	testing.expect(t,!r.error && .IN in fds[0].revents)
}
