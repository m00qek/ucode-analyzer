import * as uloop from 'uloop';
import * as io from 'io';

// Watch a file handle for readability under the uloop event loop, delivering
// raw byte chunks to onData(chunk) as they arrive and calling onEof() at end of
// stream.
//
// Reads go through the io module (ucode-mod-io), whose read() is a single raw
// read() syscall, rather than the fs module: fs reads are stdio-buffered, which
// blocks and defeats uloop's level-triggered polling. Because uloop is
// level-triggered, a single read per event is normally sufficient -- any bytes
// left in the kernel buffer raise another event -- so no non-blocking mode is
// required.
//
// The exception is hangup. On EPOLLHUP/EPOLLERR libubox unregisters the fd
// before running the callback (flagged by `error`) and never calls it again,
// even when that same event also carried data -- as happens when a writer
// sends its last message and closes before we get to read it. The writer is
// gone, so reads can no longer block: drain to end of stream right away.
export function onReadable(handle, onData, onEof) {
	// Wraps the fd without owning it: the caller's handle still closes it.
	let fd = io.new(handle.fileno());
	if (!fd) die(sprintf('cannot watch fd %d: %s', handle.fileno(), io.error()));

	let watch;
	watch = uloop.handle(fd, function(events, eof, error) {
		while (true) {
			let chunk = fd.read(65536);

			// A read error on the fd cannot be recovered from: report it and treat
			// it as end of stream, so the caller shuts down instead of spinning on
			// a level-triggered event that will keep failing.
			if (chunk === null)
				warn(sprintf('read failed: %s\n', io.error()));

			if (chunk === null || chunk === '') {
				watch.delete();
				onEof();
				return;
			}

			onData(chunk);

			if (!eof && !error)
				return;
		}
	}, uloop.ULOOP_READ);
};
