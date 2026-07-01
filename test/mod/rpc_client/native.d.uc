/**
 * # rpc_client.native
 *
 * Test-only native helper for driving a child process over pipes. Implemented
 * in `mod/rpc_client/native.c`, installed as
 * `/usr/lib/ucode/rpc_client/native.so`. Imported as
 * `import * as native from 'rpc_client.native'`.
 *
 * `spawn()` forks/execs a command and returns a process handle connected to the
 * child's stdin and stdout via pipes.
 */

/** @typedef {any} RpcProc - Opaque handle to a spawned child process. */

/**
 * Spawn `path` with the given argument vector and return a process handle wired
 * to the child's stdin (for {@link module:rpc_client.proc#write_raw|write_raw})
 * and stdout (for {@link module:rpc_client.proc#read_raw|read_raw}).
 *
 * @param {string} path - Executable to run (resolved via PATH).
 * @param {string[]} [args] - Argument vector (excluding argv[0]).
 * @returns {?RpcProc}
 */
export function spawn(path, args) {};

/**
 * Write a chunk of data to the child's stdin via a single `write(2)`.
 *
 * @function module:rpc_client.proc#write_raw
 * @param {string} data
 * @returns {int} The number of bytes written.
 */

/**
 * Read up to `n` bytes from the child's stdout via a single `read(2)`.
 *
 * @function module:rpc_client.proc#read_raw
 * @param {int} n - Maximum number of bytes to read.
 * @returns {string} The bytes read, or an empty string at end of file.
 */

/**
 * Close both pipe ends, wait for the child, and return its exit status.
 *
 * @function module:rpc_client.proc#close
 * @returns {int}
 * The child's exit code (>= 0), or the negative signal number if it was killed
 * by a signal.
 */
