import * as uloop from 'uloop';
import * as native from 'language_server.native';

// Watch a file handle for readability under the uloop event loop, delivering
// raw byte chunks to onData(chunk) as they arrive and calling onEof() at end of
// stream.
//
// Reads go through native.read_raw (a raw read() syscall) rather than the fs
// module: fs reads are stdio-buffered, which blocks and defeats uloop's
// level-triggered polling. Because uloop is level-triggered, a single read per
// event is sufficient -- any bytes left in the kernel buffer raise another
// event -- so no non-blocking mode or drain loop is required.
export function onReadable(handle, onData, onEof) {
	let fd = handle.fileno();

	uloop.handle(handle, function() {
		let chunk = native.read_raw(fd, 65536);

		if (chunk === null) {
			onEof();
			return;
		}

		if (length(chunk) > 0)
			onData(chunk);
	}, uloop.ULOOP_READ);
};
