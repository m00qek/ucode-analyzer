// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # Filesystem Access
 *
 * The `fs` module provides functions for interacting with the file system.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { readlink, popen } from 'fs';
 *
 *   let dest = readlink('/sys/class/net/eth0');
 *   let proc = popen('ps ww');
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as fs from 'fs';
 *
 *   let dest = fs.readlink('/sys/class/net/eth0');
 *   let proc = fs.popen('ps ww');
 *   ```
 *
 * Additionally, the filesystem module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lfs` switch.
 *
 * @module fs
 */

/**
 * Process handle returned by {@link module:fs#popen|popen()}.
 *
 * @typedef {{
 *   close: function(): ?int,
 *   read: function(int | string): ?string,
 *   write: function(*): ?int,
 *   flush: function(): ?boolean,
 *   fileno: function(): ?int
 * }} FsProc
 */

/**
 * File handle returned by {@link module:fs#open|open()},
 * {@link module:fs#fdopen|fdopen()}, {@link module:fs#mkstemp|mkstemp()},
 * and {@link module:fs#pipe|pipe()}.
 *
 * @typedef {{
 *   close: function(): ?boolean,
 *   read: function(int | string): ?string,
 *   write: function(*): ?int,
 *   seek: function(?int, ?int): ?boolean,
 *   truncate: function(?int): ?boolean,
 *   lock: function(?string): ?boolean,
 *   tell: function(): ?int,
 *   isatty: function(): ?boolean,
 *   flush: function(): ?boolean,
 *   fileno: function(): ?int,
 *   ioctl: function(int, int, int, *): *
 * }} FsFile
 */

/**
 * Directory handle returned by {@link module:fs#opendir|opendir()}.
 *
 * @typedef {{
 *   fileno: function(): ?int,
 *   read: function(): ?string,
 *   tell: function(): ?int,
 *   seek: function(int): ?boolean,
 *   close: function(): ?boolean
 * }} FsDir
 */

/**
 * File status information returned by {@link module:fs#stat|stat()} and
 * {@link module:fs#lstat|lstat()}.
 *
 * @typedef {{
 *   dev: int, ino: int, mode: int, nlink: int,
 *   uid: int, gid: int, rdev: int, size: int,
 *   blksize: int, blocks: int,
 *   atime: int, mtime: int, ctime: int,
 *   type: string
 * }} FileStatResult
 */

/**
 * Filesystem statistics returned by {@link module:fs#statvfs|statvfs()}.
 *
 * @typedef {{
 *   bsize: int, frsize: int, blocks: int, bfree: int, bavail: int,
 *   files: int, ffree: int, favail: int, fsid: int, flag: int, namemax: int,
 *   freesize: int, totalsize: int, type: ?int
 * }} StatVFSResult
 */

/**
 * Query error information.
 *
 * Returns a string containing a description of the last occurred error or
 * `null` if there is no error information.
 *
 * @function module:fs#error
 *
 *
 * @returns {?string}
 *
 * @example
 * // Trigger file system error
 * unlink('/path/does/not/exist');
 *
 * // Print error (should yield "No such file or directory")
 * print(error(), "\n");
 */
export function error() {};

/**
 * Closes the program handle and awaits program termination.
 *
 * Upon calling `close()` on the handle, the program's input or output stream
 * (depending on the open mode) is closed. Afterwards, the function awaits the
 * termination of the underlying program and returns its exit code.
 *
 * - When the program was terminated by a signal, the return value will be the
 *   negative signal number, e.g. `-9` for SIGKILL.
 *
 * - When the program terminated normally, the return value will be the positive
 *   exit code of the program.
 *
 * Returns a negative signal number if the program was terminated by a signal.
 *
 * Returns a positive exit code if the program terminated normally.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.proc#close
 *
 * @returns {?int}
 */

/**
 * Reads a chunk of data from the program handle.
 *
 * The length argument may be either a positive number of bytes to read, in
 * which case the read call returns up to that many bytes, or a string to
 * specify a dynamic read size.
 *
 *  - If length is a number, the method will read the specified number of bytes
 *    from the handle. Reading stops after the given amount of bytes or after
 *    encountering EOF, whatever comes first.
 *
 *  - If length is the string "line", the method will read an entire line,
 *    terminated by "\n" (a newline), from the handle. Reading stops at the next
 *    newline or when encountering EOF. The returned data will contain the
 *    terminating newline character if one was read.
 *
 *  - If length is the string "all", the method will read from the handle until
 *    encountering EOF and return the complete contents.
 *
 *  - If length is a single character string, the method will read from the
 *    handle until encountering the specified character or upon encountering
 *    EOF. The returned data will contain the terminating character if one was
 *    read.
 *
 * Returns a string containing the read data.
 *
 * Returns an empty string on EOF.
 *
 * Returns `null` if a read error occurred.
 *
 * @function module:fs.proc#read
 *
 * @param {int|string} length
 * The length of data to read. Can be a number, the string "line", the string
 * "all", or a single character string.
 *
 * @returns {?string}
 *
 * @example
 * const fp = popen("command", "r");
 *
 * // Example 1: Read 10 bytes from the handle
 * const chunk = fp.read(10);
 *
 * // Example 2: Read the handle line by line
 * for (let line = fp.read("line"); length(line); line = fp.read("line"))
 *   print(line);
 *
 * // Example 3: Read the complete contents from the handle
 * const content = fp.read("all");
 *
 * // Example 4: Read until encountering the character ':'
 * const field = fp.read(":");
 */

/**
 * Writes a chunk of data to the program handle.
 *
 * In case the given data is not a string, it is converted to a string before
 * being written to the program's stdin. String values are written as-is,
 * integer and double values are written in decimal notation, boolean values are
 * written as `true` or `false` while arrays and objects are converted to their
 * JSON representation before being written. The `null` value is represented by
 * an empty string so `proc.write(null)` would be a no-op. Resource values are
 * written in the form `<type address>`, e.g. `<fs.file 0x7f60f0981760>`.
 *
 * If resource, array or object values contain a `tostring()` function in their
 * prototypes, then this function is invoked to obtain an alternative string
 * representation of the value.
 *
 * Returns the number of bytes written.
 *
 * Returns `null` if a write error occurred.
 *
 * @function module:fs.proc#write
 *
 * @param {*} data
 * The data to be written.
 *
 * @returns {?int}
 *
 * @example
 * const fp = popen("command", "w");
 *
 * fp.write("Hello world!\n");
 */

/**
 * Forces a write of all buffered data to the underlying handle.
 *
 * Returns `true` if the data was successfully flushed.
 *
 * Returns `null` on error.
 *
 * @function module:fs.proc#flush
 *
 * @returns {?boolean}
 *
 */

/**
 * Obtains the number of the handle's underlying file descriptor.
 *
 * Returns the descriptor number.
 *
 * Returns `null` on error.
 *
 * @function module:fs.proc#fileno
 *
 * @returns {?int}
 */

/**
 * Starts a process and returns a handle representing the executed process.
 *
 * The handle will be connected to the process stdin or stdout, depending on the
 * value of the mode argument.
 *
 * The mode argument may be either "r" to open the process for reading (connect
 * to its stdout) or "w" to open the process for writing (connect to its stdin).
 *
 * The mode character "r" or "w" may be optionally followed by "e" to apply the
 * FD_CLOEXEC flag onto the open descriptor.
 *
 * Returns a process handle referring to the executed process.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#popen
 *
 * @param {string} command
 * The command to be executed.
 *
 * @param {string} [mode="r"]
 * The open mode of the process handle.
 *
 * @returns {?FsProc}
 *
 * @example
 * // Open a process
 * const process = popen('command', 'r');
 */
export function popen(command, mode) {};

/**
 * Closes the file handle.
 *
 * Upon calling `close()` on the handle, buffered data is flushed and the
 * underlying file descriptor is closed.
 *
 * Returns `true` if the handle was properly closed.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.file#close
 *
 * @returns {?boolean}
 */

/**
 * Reads a chunk of data from the file handle.
 *
 * The length argument may be either a positive number of bytes to read, in
 * which case the read call returns up to that many bytes, or a string to
 * specify a dynamic read size.
 *
 *  - If length is a number, the method will read the specified number of bytes
 *    from the handle. Reading stops after the given amount of bytes or after
 *    encountering EOF, whatever comes first.
 *
 *  - If length is the string "line", the method will read an entire line,
 *    terminated by "\n" (a newline), from the handle. Reading stops at the next
 *    newline or when encountering EOF. The returned data will contain the
 *    terminating newline character if one was read.
 *
 *  - If length is the string "all", the method will read from the handle until
 *    encountering EOF and return the complete contents.
 *
 *  - If length is a single character string, the method will read from the
 *    handle until encountering the specified character or upon encountering
 *    EOF. The returned data will contain the terminating character if one was
 *    read.
 *
 * Returns a string containing the read data.
 *
 * Returns an empty string on EOF.
 *
 * Returns `null` if a read error occurred.
 *
 * @function module:fs.file#read
 *
 * @param {int|string} length
 * The length of data to read. Can be a number, the string "line", the string
 * "all", or a single character string.
 *
 * @returns {?string}
 *
 * @example
 * const fp = open("file.txt", "r");
 *
 * // Example 1: Read 10 bytes from the handle
 * const chunk = fp.read(10);
 *
 * // Example 2: Read the handle line by line
 * for (let line = fp.read("line"); length(line); line = fp.read("line"))
 *   print(line);
 *
 * // Example 3: Read the complete contents from the handle
 * const content = fp.read("all");
 *
 * // Example 4: Read until encountering the character ':'
 * const field = fp.read(":");
 */

/**
 * Writes a chunk of data to the file handle.
 *
 * In case the given data is not a string, it is converted to a string before
 * being written into the file. String values are written as-is, integer and
 * double values are written in decimal notation, boolean values are written as
 * `true` or `false` while arrays and objects are converted to their JSON
 * representation before being written. The `null` value is represented by an
 * empty string so `file.write(null)` would be a no-op. Resource values are
 * written in the form `<type address>`, e.g. `<fs.file 0x7f60f0981760>`.
 *
 * If resource, array or object values contain a `tostring()` function in their
 * prototypes, then this function is invoked to obtain an alternative string
 * representation of the value.
 *
 * Returns the number of bytes written.
 *
 * Returns `null` if a write error occurred.
 *
 * @function module:fs.file#write
 *
 * @param {*} data
 * The data to be written.
 *
 * @returns {?int}
 *
 * @example
 * const fp = open("file.txt", "w");
 *
 * fp.write("Hello world!\n");
 */

/**
 * Set file read position.
 *
 * Set the read position of the open file handle to the given offset and
 * position.
 *
 * Returns `true` if the read position was set.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.file#seek
 *
 * @param {int} [offset=0]
 * The offset in bytes.
 *
 * @param {int} [position=0]
 * The position of the offset.
 *
 * | Position | Description                                                                                  |
 * |----------|----------------------------------------------------------------------------------------------|
 * | `0`      | The given offset is relative to the start of the file. This is the default value if omitted. |
 * | `1`      | The given offset is relative to the current read position.                                   |
 * | `2`      | The given offset is relative to the end of the file.                                         |
 *
 * @returns {?boolean}
 *
 * @example
 * const fp = open("file.txt", "r");
 *
 * print(fp.read(100), "\n");  // read 100 bytes...
 * fp.seek(0, 0);              // ... and reset position to start of file
 * print(fp.read(100), "\n");  // ... read same 100 bytes again
 *
 * fp.seek(10, 1);  // skip 10 bytes forward, relative to current offset ...
 * fp.tell();       // ... position is at 110 now
 *
 * fp.seek(-10, 2);            // set position to ten bytes before EOF ...
 * print(fp.read(100), "\n");  // ... reads 10 bytes at most
 */

/**
 * Truncate file to a given size
 *
 * Returns `true` if the file was successfully truncated.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.file#truncate
 *
 * @param {int} [offset=0]
 * The offset in bytes.
 *
 * @returns {?boolean}
 */

/**
 * Locks or unlocks a file.
 *
 * The mode argument specifies lock/unlock operation flags.
 *
 * | Flag    | Description                  |
 * |---------|------------------------------|
 * | "s"     | shared lock                  |
 * | "x"     | exclusive lock               |
 * | "n"     | don't block when locking     |
 * | "u"     | unlock                       |
 *
 * Returns `true` if the file was successfully locked/unlocked.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.file#lock
 *
 * @param {string} [op]
 * The lock operation flags
 *
 * @returns {?boolean}
 */

/**
 * Obtain current read position.
 *
 * Obtains the current, absolute read position of the open file.
 *
 * Returns an integer containing the current read offset in bytes.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.file#tell
 *
 * @returns {?int}
 */

/**
 * Check for TTY.
 *
 * Checks whether the open file handle refers to a TTY (terminal) device.
 *
 * Returns `true` if the handle refers to a terminal.
 *
 * Returns `false` if the handle refers to another kind of file.
 *
 * Returns `null` on error.
 *
 * @function module:fs.file#isatty
 *
 * @returns {?boolean}
 *
 */

/**
 * Forces a write of all buffered data to the underlying handle.
 *
 * Returns `true` if the data was successfully flushed.
 *
 * Returns `null` on error.
 *
 * @function module:fs.file#flush
 *
 * @returns {?boolean}
 *
 */

/**
 * Obtains the number of the handle's underlying file descriptor.
 *
 * Returns the descriptor number.
 *
 * Returns `null` on error.
 *
 * @function module:fs.file#fileno
 *
 * @returns {?int}
 */

/**
 * Performs an ioctl operation on the file.
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
 * In case of an error, null is returned and error details are available via
 * {@link module:fs#error|error()}.
 *
 * @function module:fs.file#ioctl
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
 */

/**
 * Opens a file.
 *
 * The mode argument specifies the way the file is opened, it may
 * start with one of the following values:
 *
 * | Mode    | Description                                                                                                   |
 * |---------|---------------------------------------------------------------------------------------------------------------|
 * | "r"     | Opens a file for reading. The file must exist.                                                                 |
 * | "w"     | Opens a file for writing. If the file exists, it is truncated. If the file does not exist, it is created.     |
 * | "a"     | Opens a file for appending. Data is written at the end of the file. If the file does not exist, it is created. |
 * | "r+"    | Opens a file for both reading and writing. The file must exist.                                              |
 * | "w+"    | Opens a file for both reading and writing. If the file exists, it is truncated. If the file does not exist, it is created. |
 * | "a+"    | Opens a file for both reading and appending. Data can be read and written at the end of the file. If the file does not exist, it is created. |
 *
 * Additionally, the following flag characters may be appended to
 * the mode value:
 *
 * | Flag    | Description                                                                                                   |
 * |---------|---------------------------------------------------------------------------------------------------------------|
 * | "x"     | Opens a file for exclusive creation. If the file exists, the `open` call fails.                             |
 * | "e"     | Opens a file with the `O_CLOEXEC` flag set, ensuring that the file descriptor is closed on `exec` calls.      |
 *
 * If the mode is one of `"w…"` or `"a…"`, the permission argument
 * controls the filesystem permissions bits used when creating
 * the file.
 *
 * Returns a file handle object associated with the opened file.
 *
 * @function module:fs#open
 *
 * @param {string} path
 * The path to the file.
 *
 * @param {string} [mode="r"]
 * The file opening mode.
 *
 * @param {int} [perm=0o666]
 * The file creation permissions (for modes `w…` and `a…`)
 *
 * @returns {?FsFile}
 *
 * @example
 * // Open a file in read-only mode
 * const fileHandle = open('file.txt', 'r');
 */
export function open(path, mode, perm) {};

/**
 * Associates a file descriptor number with a file handle object.
 *
 * The mode argument controls how the file handle object is opened
 * and must match the open mode of the underlying descriptor.
 *
 * It may be set to one of the following values:
 *
 * | Mode    | Description                                                                                                  |
 * |---------|--------------------------------------------------------------------------------------------------------------|
 * | "r"     | Opens a file stream for reading. The file descriptor must be valid and opened in read mode.                  |
 * | "w"     | Opens a file stream for writing. The file descriptor must be valid and opened in write mode.                 |
 * | "a"     | Opens a file stream for appending. The file descriptor must be valid and opened in write mode.               |
 * | "r+"    | Opens a file stream for both reading and writing. The file descriptor must be valid and opened in read/write mode. |
 * | "w+"    | Opens a file stream for both reading and writing. The file descriptor must be valid and opened in read/write mode. |
 * | "a+"    | Opens a file stream for both reading and appending. The file descriptor must be valid and opened in read/write mode. |
 *
 * Returns the file handle object associated with the file descriptor.
 *
 * @function module:fs#fdopen
 *
 * @param {int} fd
 * The file descriptor.
 *
 * @param {string} [mode="r"]
 * The open mode.
 *
 * @returns {?FsFile}
 *
 * @example
 * // Associate file descriptors of stdin and stdout with handles
 * const stdinHandle = fdopen(0, 'r');
 * const stdoutHandle = fdopen(1, 'w');
 */
export function fdopen(fd, mode) {};

/**
 * Duplicates a file descriptor.
 *
 * This function duplicates the file descriptor `oldfd` to `newfd`. If `newfd`
 * was previously open, it is silently closed before being reused.
 *
 * Returns `true` on success.
 * Returns `null` on error.
 *
 * @function module:fs#dup2
 * @since 2026.01.16~85922056
 *
 * @param {int} oldfd
 * The file descriptor to duplicate.
 *
 * @param {int} newfd
 * The file descriptor number to duplicate to.
 *
 * @returns {?boolean}
 *
 * @example
 * // Redirect stderr to a log file
 * const logfile = open('/tmp/error.log', 'w');
 * dup2(logfile.fileno(), 2);
 * logfile.close();
 */
export function dup2(oldfd, newfd) {};

/**
 * Obtains the number of the handle's underlying file descriptor.
 *
 * Returns the descriptor number.
 *
 * Returns `null` on error.
 *
 * @function module:fs.dir#fileno
 *
 * @returns {?int}
 */

/**
 * Read the next entry from the open directory.
 *
 * Returns a string containing the entry name.
 *
 * Returns `null` if there are no more entries to read.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.dir#read
 *
 * @returns {?string}
 */

/**
 * Obtain current read position.
 *
 * Returns the current read position in the open directory handle which can be
 * passed back to the `seek()` function to return to this position. This is
 * mainly useful to read an open directory handle (or specific items) multiple
 * times.
 *
 * Returns an integer referring to the current position.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.dir#tell
 *
 * @returns {?int}
 */

/**
 * Set read position.
 *
 * Sets the read position within the open directory handle to the given offset
 * value. The offset value should be obtained by a previous call to `tell()` as
 * the specific integer values are implementation defined.
 *
 * Returns `true` if the read position was set.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.dir#seek
 *
 * @param {int} offset
 * Position value obtained by `tell()`.
 *
 * @returns {?boolean}
 *
 * @example
 *
 * const handle = opendir("/tmp");
 * const begin = handle.tell();
 *
 * print(handle.read(), "\n");
 *
 * handle.seek(begin);
 *
 * print(handle.read(), "\n");  // prints the first entry again
 */

/**
 * Closes the directory handle.
 *
 * Closes the underlying file descriptor referring to the opened directory.
 *
 * Returns `true` if the handle was properly closed.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs.dir#close
 *
 * @returns {?boolean}
 */

/**
 * Opens a directory and returns a directory handle associated with the open
 * directory descriptor.
 *
 * Returns a director handle referring to the open directory.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#opendir
 *
 * @param {string} path
 * The path to the directory.
 *
 * @returns {?FsDir}
 *
 * @example
 * // Open a directory
 * const directory = opendir('path/to/directory');
 */
export function opendir(path) {};

/**
 * Reads the target path of a symbolic link.
 *
 * Returns a string containing the target path.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#readlink
 *
 * @param {string} path
 * The path to the symbolic link.
 *
 * @returns {?string}
 *
 * @example
 * // Read the value of a symbolic link
 * const targetPath = readlink('symbolicLink');
 */
export function readlink(path) {};

/**
 * Retrieves information about a file or directory.
 *
 * Returns an object containing information about the file or directory.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions.
 *
 * @function module:fs#stat
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @returns {?FileStatResult}
 *
 * @example
 * // Get information about a file
 * const fileInfo = stat('path/to/file');
 */
export function stat(path) {};

/**
 * Retrieves information about a file or directory, without following symbolic
 * links.
 *
 * Returns an object containing information about the file or directory.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions.
 *
 * @function module:fs#lstat
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @returns {?FileStatResult}
 *
 * @example
 * // Get information about a directory
 * const dirInfo = lstat('path/to/directory');
 */
export function lstat(path) {};

/**
 * Creates a new directory.
 *
 * Returns `true` if the directory was successfully created.
 *
 * Returns `null` if an error occurred, e.g. due to non-existent path.
 *
 * @function module:fs#mkdir
 *
 * @param {string} path
 * The path to the new directory.
 *
 * @returns {?boolean}
 *
 * @example
 * // Create a directory
 * mkdir('path/to/new-directory');
 */
export function mkdir(path) {};

/**
 * Removes the specified directory.
 *
 * Returns `true` if the directory was successfully removed.
 *
 * Returns `null` if an error occurred, e.g. due to non-existent path.
 *
 * @function module:fs#rmdir
 *
 * @param {string} path
 * The path to the directory to be removed.
 *
 * @returns {?boolean}
 *
 * @example
 * // Remove a directory
 * rmdir('path/to/directory');
 */
export function rmdir(path) {};

/**
 * Creates a new symbolic link.
 *
 * Returns `true` if the symlink was successfully created.
 *
 * Returns `null` if an error occurred, e.g. due to non-existent path.
 *
 * @function module:fs#symlink
 *
 * @param {string} target
 * The target of the symbolic link.
 *
 * @param {string} path
 * The path of the symbolic link.
 *
 * @returns {?boolean}
 *
 * @example
 * // Create a symbolic link
 * symlink('target', 'path/to/symlink');
 */
export function symlink(target, path) {};

/**
 * Removes the specified file or symbolic link.
 *
 * Returns `true` if the unlink operation was successful.
 *
 * Returns `null` if an error occurred, e.g. due to non-existent path.
 *
 * @function module:fs#unlink
 *
 * @param {string} path
 * The path to the file or symbolic link.
 *
 * @returns {?boolean}
 *
 * @example
 * // Remove a file
 * unlink('path/to/file');
 */
export function unlink(path) {};

/**
 * Retrieves the current working directory.
 *
 * Returns a string containing the current working directory path.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#getcwd
 *
 * @returns {?string}
 *
 * @example
 * // Get the current working directory
 * const cwd = getcwd();
 */
export function getcwd() {};

/**
 * Changes the current working directory to the specified path.
 *
 * Returns `true` if the permission change was successful.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions or
 * invalid arguments.
 *
 * @function module:fs#chdir
 *
 * @param {string} path
 * The path to the new working directory.
 *
 * @returns {?boolean}
 *
 * @example
 * // Change the current working directory
 * chdir('new-directory');
 */
export function chdir(path) {};

/**
 * Changes the permission mode bits of a file or directory.
 *
 * Returns `true` if the permission change was successful.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions or
 * invalid arguments.
 *
 * @function module:fs#chmod
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @param {int} mode
 * The new mode (permissions).
 *
 * @returns {?boolean}
 *
 * @example
 * // Change the mode of a file
 * chmod('path/to/file', 0o644);
 */
export function chmod(path, mode) {};

/**
 * Changes the owner and group of a file or directory.
 *
 * The user and group may be specified either as uid or gid number respectively,
 * or as a string containing the user or group name, in which case it is
 * resolved to the proper uid/gid first.
 *
 * If either the user or group parameter is omitted or given as `-1`,
 * it is not changed.
 *
 * Returns `true` if the ownership change was successful.
 *
 * Returns `null` if an error occurred or if a user/group name cannot be
 * resolved to a uid/gid value.
 *
 * @function module:fs#chown
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @param {int|string} [uid=-1]
 * The new owner's user ID. When given as number, it is used as-is, when given
 * as string, the user name is resolved to the corresponding uid first.
 *
 * @param {int|string} [gid=-1]
 * The new group's ID. When given as number, it is used as-is, when given as
 * string, the group name is resolved to the corresponding gid first.
 *
 * @returns {?boolean}
 *
 * @example
 * // Change the owner of a file
 * chown('path/to/file', 1000);
 *
 * // Change the group of a directory
 * chown('/htdocs/', null, 'www-data');
 */
export function chown(path, uid, gid) {};

/**
 * Renames or moves a file or directory.
 *
 * Returns `true` if the rename operation was successful.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#rename
 *
 * @param {string} oldPath
 * The current path of the file or directory.
 *
 * @param {string} newPath
 * The new path of the file or directory.
 *
 * @returns {?boolean}
 *
 * @example
 * // Rename a file
 * rename('old-name.txt', 'new-name.txt');
 */
export function rename(oldPath, newPath) {};

/**
 * Takes an arbitrary number of glob patterns and
 * resolves matching files for each one. In case of multiple patterns,
 * no efforts are made to remove duplicates or to globally sort the combined
 * match list. The list of matches for each individual pattern is sorted.
 * Returns an array containing all matched file paths.
 *
 * @function module:fs#glob
 *
 * @param {...string} pattern
 *
 * @returns {?string[]}
 *
 * @example
 *
 * import { chdir, glob } from 'fs';
 * chdir('/etc/ssl/certs/');
 * for (let cert in glob('*.crt', '*.pem')) {
 * 	if (cert != null)
 * 		print(cert, '\n');
 * }
 * // ACCVRAIZ1.crt
 * // AC_RAIZ_FNMT-RCM.crt
 * // AC_RAIZ_FNMT-RCM_SERVIDORES_SEGUROS.crt
 * // ...
 */
export function glob(pattern) {};

/**
 * Retrieves the directory name of a path.
 *
 * Returns the directory name component of the specified path.
 *
 * Returns `null` if the path argument is not a string.
 *
 * @function module:fs#dirname
 *
 * @param {string} path
 * The path to extract the directory name from.
 *
 * @returns {?string}
 *
 * @example
 * // Get the directory name of a path
 * const directoryName = dirname('/path/to/file.txt');
 */
export function dirname(path) {};

/**
 * Retrieves the base name of a path.
 *
 * Returns the base name component of the specified path.
 *
 * Returns `null` if the path argument is not a string.
 *
 * @function module:fs#basename
 *
 * @param {string} path
 * The path to extract the base name from.
 *
 * @returns {?string}
 *
 * @example
 * // Get the base name of a path
 * const baseName = basename('/path/to/file.txt');
 */
export function basename(path) {};

/**
 * Lists the content of a directory.
 *
 * Returns a sorted array of the names of files and directories in the specified
 * directory.
 *
 * Returns `null` if an error occurred, e.g. if the specified directory cannot
 * be opened.
 *
 * @function module:fs#lsdir
 *
 * @param {string} path
 * The path to the directory.
 *
 * @returns {?string[]}
 *
 * @example
 * // List the content of a directory
 * const fileList = lsdir('/path/to/directory');
 */
export function lsdir(path) {};

/**
 * Creates a unique, ephemeral temporary file.
 *
 * Creates a new temporary file, opens it in read and write mode, unlinks it and
 * returns a file handle object referring to the yet open but deleted file.
 *
 * Upon closing the handle, the associated file will automatically vanish from
 * the system.
 *
 * The optional path template argument may be used to override the path and name
 * chosen for the temporary file. If the path template contains no path element,
 * `/tmp/` is prepended, if it does not end with `XXXXXX`, then  * `.XXXXXX` is
 * appended to it. The `XXXXXX` sequence is replaced with a random value
 * ensuring uniqueness of the temporary file name.
 *
 * Returns a file handle object referring to the ephemeral file on success.
 *
 * Returns `null` if an error occurred, e.g. on insufficient permissions or
 * inaccessible directory.
 *
 * @function module:fs#mkstemp
 *
 * @param {string} [template="/tmp/XXXXXX"]
 * The path template to use when forming the temporary file name.
 *
 * @returns {?FsFile}
 *
 * @example
 * // Create a unique temporary file in the current working directory
 * const tempFile = mkstemp('./data-XXXXXX');
 */
export function mkstemp(template) {};

/**
 * Creates a unique temporary directory based on the given template.
 *
 * If the template argument is given and contains a relative path, the created
 * directory will be placed relative to the current working directory.
 *
 * If the template argument is given and contains an absolute path, the created
 * directory will be placed relative to the given directory.
 *
 * If the template argument is given but does not contain a directory separator,
 * the directory will be placed in `/tmp/`.
 *
 * If no template argument is given, the default `/tmp/XXXXXX` is used.
 *
 * The template argument must end with six consecutive X characters (`XXXXXX`),
 * which will be replaced with a random string to create the unique directory name.
 * If the template does not end with `XXXXXX`, it will be automatically appended.
 *
 * Returns a string containing the path of the created directory on success.
 *
 * Returns `null` if an error occurred, e.g. on insufficient permissions or
 * inaccessible directory.
 *
 * @function module:fs#mkdtemp
 * @since 2026.01.16~85922056
 *
 * @param {string} [template="/tmp/XXXXXX"]
 * The path template to use when forming the temporary directory name.
 *
 * @returns {?string}
 *
 * @example
 * // Create a unique temporary directory in the current working directory
 * const tempDir = mkdtemp('./data-XXXXXX');
 */
export function mkdtemp(template) {};

/**
 * Checks the accessibility of a file or directory.
 *
 * The optional modes argument specifies the access modes which should be
 * checked. A file is only considered accessible if all access modes specified
 * in the modes argument are possible.
 *
 * The following modes are recognized:
 *
 * | Mode | Description                           |
 * |------|---------------------------------------|
 * | "r"  | Tests whether the file is readable.   |
 * | "w"  | Tests whether the file is writable.   |
 * | "x"  | Tests whether the file is executable. |
 * | "f"  | Tests whether the file exists.        |
 *
 * Returns `true` if the given path is accessible or `false` when it is not.
 *
 * Returns `null` if an error occurred, e.g. due to inaccessible intermediate
 * path components, invalid path arguments etc.
 *
 * @function module:fs#access
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @param {string} [mode="f"]
 * Optional access mode.
 *
 * @returns {?boolean}
 *
 * @example
 * // Check file read and write accessibility
 * const isAccessible = access('path/to/file', 'rw');
 *
 * // Check execute permissions
 * const mayExecute = access('/usr/bin/example', 'x');
 */
export function access(path, mode) {};

/**
 * Reads the content of a file, optionally limited to the given amount of bytes.
 *
 * Returns a string containing the file contents.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions.
 *
 * @function module:fs#readfile
 *
 * @param {string} path
 * The path to the file.
 *
 * @param {int} [limit]
 * Number of bytes to limit the result to. When omitted, the entire content is
 * returned.
 *
 * @returns {?string}
 *
 * @example
 * // Read first 100 bytes of content
 * const content = readfile('path/to/file', 100);
 *
 * // Read entire file content
 * const content = readfile('path/to/file');
 */
export function readfile(path, limit) {};

/**
 * Writes the given data to a file, optionally truncated to the given amount
 * of bytes.
 *
 * In case the given data is not a string, it is converted to a string before
 * being written into the file. String values are written as-is, integer and
 * double values are written in decimal notation, boolean values are written as
 * `true` or `false` while arrays and objects are converted to their JSON
 * representation before being written into the file. The `null` value is
 * represented by an empty string so `writefile(…, null)` would write an empty
 * file. Resource values are written in the form `<type address>`, e.g.
 * `<fs.file 0x7f60f0981760>`.
 *
 * If resource, array or object values contain a `tostring()` function in their
 * prototypes, then this function is invoked to obtain an alternative string
 * representation of the value.
 *
 * If a file already exists at the given path, it is truncated. If no file
 * exists, it is created with default permissions 0o666 masked by the currently
 * effective umask.
 *
 * Returns the number of bytes written.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions.
 *
 * @function module:fs#writefile
 *
 * @param {string} path
 * The path to the file.
 *
 * @param {*} data
 * The data to be written.
 *
 * @param {int} [limit]
 * Truncates the amount of data to be written to the specified amount of bytes.
 * When omitted, the entire content is written.
 *
 * @returns {?int}
 *
 * @example
 * // Write string to a file
 * const bytesWritten = writefile('path/to/file', 'Hello, World!');
 *
 * // Write object as JSON to a file and limit to 1024 bytes at most
 * const obj = { foo: "Hello world", bar: true, baz: 123 };
 * const bytesWritten = writefile('debug.txt', obj, 1024);
 */
export function writefile(path, data, limit) {};

/**
 * Resolves the absolute path of a file or directory.
 *
 * Returns a string containing the resolved path.
 *
 * Returns `null` if an error occurred, e.g. due to insufficient permissions.
 *
 * @function module:fs#realpath
 *
 * @param {string} path
 * The path to the file or directory.
 *
 * @returns {?string}
 *
 * @example
 * // Resolve the absolute path of a file
 * const absolutePath = realpath('path/to/file');
 */
export function realpath(path) {};

/**
 * Creates a pipe and returns file handle objects associated with the read- and
 * write end of the pipe respectively.
 *
 * Returns a two element array containing both a file handle object open in read
 * mode referring to the read end of the pipe and a file handle object open in
 * write mode referring to the write end of the pipe.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:fs#pipe
 *
 * @returns {?FsFile[]}
 *
 * @example
 * // Create a pipe
 * const pipeHandles = pipe();
 * pipeHandles[1].write("Hello world\n");
 * print(pipeHandles[0].read("line"));
 */
export function pipe() {};

/**
 * Pre-opened file handle for standard input (file descriptor 0).
 *
 * @name module:fs.stdin
 * @returns {FsFile}
 */
export let stdin;

/**
 * Pre-opened file handle for standard output (file descriptor 1).
 *
 * @name module:fs.stdout
 * @returns {FsFile}
 */
export let stdout;

/**
 * Pre-opened file handle for standard error (file descriptor 2).
 *
 * @name module:fs.stderr
 * @returns {FsFile}
 */
export let stderr;

/**
 * Ioctl direction constant: no data is transferred between userspace and kernel.
 *
 * @name module:fs.IOC_DIR_NONE
 * @returns {int}
 */
export let IOC_DIR_NONE = 0;

/**
 * Ioctl direction constant: kernel writes data into userspace buffer.
 *
 * @name module:fs.IOC_DIR_READ
 * @returns {int}
 */
export let IOC_DIR_READ = 1;

/**
 * Ioctl direction constant: userspace writes data into kernel buffer.
 *
 * @name module:fs.IOC_DIR_WRITE
 * @returns {int}
 */
export let IOC_DIR_WRITE = 2;

/**
 * Ioctl direction constant: bidirectional data transfer between userspace and kernel.
 *
 * @name module:fs.IOC_DIR_RW
 * @returns {int}
 */
export let IOC_DIR_RW = 3;

