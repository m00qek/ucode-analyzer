/**
 * # I/O Operations
 *
 * The `io` module provides object-oriented access to UNIX file descriptors.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { open, O_RDWR } from 'io';
 *
 *   let handle = open('/tmp/test.txt', O_RDWR);
 *   handle.write('Hello World\n');
 *   handle.close();
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as io from 'io';
 *
 *   let handle = io.open('/tmp/test.txt', io.O_RDWR);
 *   handle.write('Hello World\n');
 *   handle.close();
 *   ```
 *
 * Additionally, the io module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lio` switch.
 *
 * @module io
 */

/**
 * Query error information.
 *
 * Returns a string containing a description of the last occurred error or
 * `null` if there is no error information.
 *
 * @function module:io#error
 *
 * @returns {?string}
 *
 * @example
 * // Trigger an error
 * io.open('/path/does/not/exist');
 *
 * // Print error (should yield "No such file or directory")
 * print(io.error(), "\n");
 */
export function error() {};

/**
 * Gets the name of the pseudo-terminal slave.
 *
 * Returns the name of the pseudo-terminal slave device associated with
 * the master file descriptor.
 *
 * Returns a string containing the slave device name.
 *
 * Returns `null` if an error occurred or if the descriptor is not a
 * pseudo-terminal master.
 *
 * @function module:io.handle#ptsname
 *
 * @returns {?string}
 *
 * @example
 * const master = io.open('/dev/ptmx', O_RDWR);
 * const slave_name = master.ptsname();
 * print(slave_name, "\n");
 */
export function handle() {};

/**
 * Gets terminal attributes.
 *
 * Retrieves the terminal attributes for the file descriptor.
 *
 * Returns an object containing terminal attributes (iflag, oflag, cflag, lflag,
 * ispeed, ospeed, and cc array).
 *
 * Returns `null` if an error occurred or if the descriptor is not a terminal.
 *
 * @function module:io.handle#tcgetattr
 *
 * @returns {?object}
 *
 * @example
 * const handle = io.open('/dev/tty', O_RDWR);
 * const attrs = handle.tcgetattr();
 * if (attrs)
 *     print("Input flags: ", attrs.iflag, "\n");
 */
export function handle() {};

/**
 * Sets terminal attributes.
 *
 * Sets the terminal attributes for the file descriptor.
 *
 * The attrs parameter should be an object with properties:
 * - iflag: input flags
 * - oflag: output flags
 * - cflag: control flags
 * - lflag: local flags
 * - ispeed: input speed
 * - ospeed: output speed
 * - cc: array of control characters (optional)
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#tcsetattr
 *
 * @param {Object} attrs
 * The terminal attributes to set.
 *
 * @param {int} [when=0]
 * When to apply the changes (TCSANOW, TCSADRAIN, TCSAFLUSH).
 *
 * @returns {?boolean}
 *
 * @example
 * const handle = io.open('/dev/tty', O_RDWR);
 * const attrs = handle.tcgetattr();
 * attrs.lflag &= ~0x0000008; // Disable ECHO
 * handle.tcsetattr(attrs, TCSANOW);
 */
export function handle(attrs, when) {};

/**
 * Grants access to a pseudo-terminal slave device.
 *
 * Allows the owner of the pseudo-terminal master device to grant the
 * appropriate permissions on the corresponding slave device so that it
 * may be opened.
 *
 * This function is typically called before opening the slave device.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#grantpt
 *
 * @returns {?boolean}
 *
 * @example
 * const master = io.open('/dev/ptmx', O_RDWR);
 * if (master.grantpt()) {
 *     print("Granted access to slave device\n");
 * }
 */
export function handle() {};

/**
 * Unlocks a pseudo-terminal slave device.
 *
 * Unlocks the pseudo-terminal slave device associated with the master device
 * referred to by the file descriptor. This function is typically called after
 * grantpt() and before opening the slave device.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#unlockpt
 *
 * @returns {?boolean}
 *
 * @example
 * const master = io.open('/dev/ptmx', O_RDWR);
 * master.grantpt();
 * if (master.unlockpt()) {
 *     print("Unlocked slave device\n");
 * }
 */
export function handle() {};

/**
 * Reads data from the file descriptor.
 *
 * Reads up to the specified number of bytes from the file descriptor.
 *
 * Returns a string containing the read data.
 *
 * Returns an empty string on EOF.
 *
 * Returns `null` if a read error occurred.
 *
 * @function module:io.handle#read
 *
 * @param {int} length
 * The maximum number of bytes to read.
 *
 * @returns {?string}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * const data = handle.read(1024);
 */
export function handle(length) {};

/**
 * Writes data to the file descriptor.
 *
 * Writes the given data to the file descriptor. Non-string values are
 * converted to strings before being written.
 *
 * Returns the number of bytes written.
 *
 * Returns `null` if a write error occurred.
 *
 * @function module:io.handle#write
 *
 * @param {*} data
 * The data to write.
 *
 * @returns {?int}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_WRONLY | O_CREAT);
 * handle.write('Hello World\n');
 */
export function handle(data) {};

/**
 * Sets the file descriptor position.
 *
 * Sets the file position of the descriptor to the given offset and whence.
 *
 * Returns `true` if the position was successfully set.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#seek
 *
 * @param {int} [offset=0]
 * The offset in bytes.
 *
 * @param {int} [whence=0]
 * The position reference.
 *
 * | Whence | Description                                                        |
 * |--------|--------------------------------------------------------------------|
 * | `0`    | The offset is relative to the start of the file (SEEK_SET).       |
 * | `1`    | The offset is relative to the current position (SEEK_CUR).        |
 * | `2`    | The offset is relative to the end of the file (SEEK_END).         |
 *
 * @returns {?boolean}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * handle.seek(100, 0);  // Seek to byte 100 from start
 */
export function handle(offset, whence) {};

/**
 * Gets the current file descriptor position.
 *
 * Returns the current file position as an integer.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#tell
 *
 * @returns {?int}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * const pos = handle.tell();
 */
export function handle() {};

/**
 * Duplicates the file descriptor.
 *
 * Creates a duplicate of the file descriptor using dup(2).
 *
 * Returns a new io.handle for the duplicated descriptor.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#dup
 *
 * @returns {?module:io.handle}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * const dup_handle = handle.dup();
 */
export function handle() {};

/**
 * Duplicates the file descriptor to a specific descriptor number.
 *
 * Creates a duplicate of the file descriptor to the specified descriptor
 * number using dup2(2). If newfd was previously open, it is silently closed.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#dup2
 *
 * @param {int} newfd
 * The target file descriptor number.
 *
 * @returns {?boolean}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_WRONLY);
 * handle.dup2(2);  // Redirect stderr to the file
 */
export function handle(newfd) {};

/**
 * Gets the file descriptor number.
 *
 * Returns the underlying file descriptor number.
 *
 * Returns `null` if the handle is closed.
 *
 * @function module:io.handle#fileno
 *
 * @returns {?int}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * print(handle.fileno(), "\n");
 */
export function handle() {};

/**
 * Performs fcntl() operations on the file descriptor.
 *
 * Performs the specified fcntl() command on the file descriptor with an
 * optional argument.
 *
 * Returns the result of the fcntl() call. For F_DUPFD and F_DUPFD_CLOEXEC,
 * returns a new io.handle wrapping the duplicated descriptor. For other
 * commands, returns a number (interpretation depends on cmd).
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#fcntl
 *
 * @param {int} cmd
 * The fcntl command (e.g., F_GETFL, F_SETFL, F_GETFD, F_SETFD, F_DUPFD).
 *
 * @param {int} [arg]
 * Optional argument for the command.
 *
 * @returns {?(int|module:io.handle)}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * const flags = handle.fcntl(F_GETFL);
 * handle.fcntl(F_SETFL, flags | O_NONBLOCK);
 * const dup_handle = handle.fcntl(F_DUPFD, 10);  // Returns io.handle
 */
export function handle(cmd, arg) {};

/**
 * Performs an ioctl operation on the file descriptor.
 *
 * The direction parameter specifies who is reading and writing,
 * from the user's point of view. It can be one of the following values:
 *
 * | Direction      | Description                                                                       |
 * |----------------|-----------------------------------------------------------------------------------|
 * | IOC_DIR_NONE   | neither userspace nor kernel is writing, ioctl is executed without passing data.  |
 * | IOC_DIR_WRITE  | userspace is writing and kernel is reading.                                       |
 * | IOC_DIR_READ   | kernel is writing and userspace is reading.                                       |
 * | IOC_DIR_RW     | userspace is writing and kernel is writing back into the data structure.          |
 *
 * Returns the result of the ioctl operation; for `IOC_DIR_READ` and
 * `IOC_DIR_RW` this is a string containing the data, otherwise a number as
 * return code.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#ioctl
 *
 * @param {int} direction
 * The direction of the ioctl operation. Use constants IOC_DIR_*.
 *
 * @param {int} type
 * The ioctl type (see https://www.kernel.org/doc/html/latest/userspace-api/ioctl/ioctl-number.html)
 *
 * @param {int} num
 * The ioctl sequence number.
 *
 * @param {int|string} [value]
 * The value to pass to the ioctl system call. For `IOC_DIR_NONE`, this argument
 * is ignored. With `IOC_DIR_READ`, the value should be a positive integer
 * specifying the number of bytes to expect from the kernel. For the other
 * directions, `IOC_DIR_WRITE` and `IOC_DIR_RW`, that value parameter must be a
 * string, serving as buffer for the data to send.
 *
 * @returns {?int|?string}
 *
 * @example
 * const handle = io.open('/dev/tty', O_RDWR);
 * const size = handle.ioctl(IOC_DIR_READ, 0x54, 0x13, 8);  // TIOCGWINSZ
 */
export function handle(direction, type, num, value) {};

/**
 * Checks if the file descriptor refers to a terminal.
 *
 * Returns `true` if the descriptor refers to a terminal device.
 *
 * Returns `false` otherwise.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#isatty
 *
 * @returns {?boolean}
 *
 * @example
 * const handle = io.new(0);  // stdin
 * if (handle.isatty())
 *     print("Running in a terminal\n");
 */
export function handle() {};

/**
 * Closes the file descriptor.
 *
 * Closes the underlying file descriptor. Further operations on this handle
 * will fail.
 *
 * Returns `true` if the descriptor was successfully closed.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io.handle#close
 *
 * @returns {?boolean}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDONLY);
 * handle.close();
 */
export function handle() {};

/**
 * Creates an io.handle from a file descriptor number.
 *
 * Wraps the given file descriptor number in an io.handle object.
 *
 * Returns an io.handle object.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io#new
 *
 * @param {int} fd
 * The file descriptor number.
 *
 * @returns {?module:io.handle}
 *
 * @example
 * // Wrap stdin
 * const stdin = io.new(0);
 * const data = stdin.read(100);
 */
export function new(fd) {};

/**
 * Opens a file and returns an io.handle.
 *
 * Opens the specified file with the given flags and mode, returning an
 * io.handle wrapping the resulting file descriptor.
 *
 * Returns an io.handle object.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io#open
 *
 * @param {string} path
 * The path to the file.
 *
 * @param {int} [flags=O_RDONLY]
 * The open flags (O_RDONLY, O_WRONLY, O_RDWR, etc.).
 *
 * @param {int} [mode=0o666]
 * The file creation mode (used with O_CREAT).
 *
 * @returns {?module:io.handle}
 *
 * @example
 * const handle = io.open('/tmp/test.txt', O_RDWR | O_CREAT, 0o644);
 * handle.write('Hello World\n');
 * handle.close();
 */
export function open(path, flags, mode) {};

/**
 * Creates a pipe.
 *
 * Creates a unidirectional data channel (pipe) that can be used for
 * inter-process communication. Returns an array containing two io.handle
 * objects: the first is the read end of the pipe, the second is the write end.
 *
 * Data written to the write end can be read from the read end.
 *
 * Returns an array `[read_handle, write_handle]` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:io#pipe
 *
 * @returns {?Array<module:io.handle>}
 *
 * @example
 * const [reader, writer] = io.pipe();
 * writer.write('Hello from pipe!');
 * const data = reader.read(100);
 * print(data, "\n");  // Prints: Hello from pipe!
 */
export function pipe() {};

/**
 * Creates an io.handle from various value types.
 *
 * Creates an io.handle by extracting the file descriptor from the given value.
 * The value can be:
 * - An integer file descriptor number
 * - An fs.file, fs.proc, or socket resource
 * - Any object/array/resource with a fileno() method
 *
 * Returns an io.handle object.
 *
 * Returns `null` if an error occurred or the value cannot be converted.
 *
 * @function module:io#from
 *
 * @param {*} value
 * The value to convert.
 *
 * @returns {?module:io.handle}
 *
 * @example
 * import { open as fsopen } from 'fs';
 * const fp = fsopen('/tmp/test.txt', 'r');
 * const handle = io.from(fp);
 * const data = handle.read(100);
 */
export function from(value) {};

