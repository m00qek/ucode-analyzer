/**
 * # language_server.native
 *
 * Native helper backing the language server's non-blocking stdin read loop.
 * Implemented in `mod/language_server/native.c`, installed as
 * `/usr/lib/ucode/language_server/native.so`. Imported as
 * `import * as native from 'language_server.native'`.
 */

/**
 * Perform a single raw `read(2)` of up to `n` bytes from file descriptor `fd`.
 *
 * Unlike the stdio-buffered `fs` reads, this issues exactly one syscall and
 * never blocks to fill a buffer, so it composes with uloop's level-triggered
 * fd polling.
 *
 * @param {int} fd - File descriptor to read from.
 * @param {int} n - Maximum number of bytes to read.
 * @returns {?string}
 * A string of the bytes read (length 1..n) when data is available, `null` at
 * end of file (read returned 0), or an empty string when the fd is non-blocking
 * and no data is ready (EAGAIN / EWOULDBLOCK).
 */
export function read_raw(fd, n) {};
