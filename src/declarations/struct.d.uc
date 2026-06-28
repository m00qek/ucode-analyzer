// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # Handle Packed Binary Data
 *
 * The `struct` module provides routines for interpreting byte strings as packed
 * binary data.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { pack, unpack } from 'struct';
 *
 *   let buffer = pack('bhl', -13, 1234, 444555666);
 *   let values = unpack('bhl', buffer);
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as struct from 'struct';
 *
 *   let buffer = struct.pack('bhl', -13, 1234, 444555666);
 *   let values = struct.unpack('bhl', buffer);
 *   ```
 *
 * Additionally, the struct module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lstruct` switch.
 *
 * ## Format Strings
 *
 * Format strings describe the data layout when packing and unpacking data.
 * They are built up from format-characters, which specify the type of data
 * being packed/unpacked. In addition, special characters control the byte
 * order, size and alignment.
 *
 * Each format string consists of an optional prefix character which describes
 * the overall properties of the data and one or more format characters which
 * describe the actual data values and padding.
 *
 * ### Byte Order, Size, and Alignment
 *
 * By default, C types are represented in the machine's native format and byte
 * order, and properly aligned by skipping pad bytes if necessary (according to
 * the rules used by the C compiler).
 *
 * This behavior is chosen so that the bytes of a packed struct correspond
 * exactly to the memory layout of the corresponding C struct.
 *
 * Whether to use native byte ordering and padding or standard formats depends
 * on the application.
 *
 * Alternatively, the first character of the format string can be used to indicate
 * the byte order, size and alignment of the packed data, according to the
 * following table:
 *
 * | Character | Byte order             | Size     | Alignment |
 * |-----------|------------------------|----------|-----------|
 * | `@`       | native                 | native   | native    |
 * | `=`       | native                 | standard | none      |
 * | `<`       | little-endian          | standard | none      |
 * | `>`       | big-endian             | standard | none      |
 * | `!`       | network (= big-endian) | standard | none      |
 *
 * If the first character is not one of these, `'@'` is assumed.
 *
 * Native byte order is big-endian or little-endian, depending on the
 * host system. For example, Intel x86, AMD64 (x86-64), and Apple M1 are
 * little-endian; IBM z and many legacy architectures are big-endian.
 *
 * Native size and alignment are determined using the C compiler's
 * `sizeof` expression. This is always combined with native byte order.
 *
 * Standard size depends only on the format character; see the table in
 * the `format-characters` section.
 *
 * Note the difference between `'@'` and `'='`: both use native byte order,
 * but the size and alignment of the latter is standardized.
 *
 * The form `'!'` represents the network byte order which is always big-endian
 * as defined in `IETF RFC 1700`.
 *
 * There is no way to indicate non-native byte order (force byte-swapping); use
 * the appropriate choice of `'<'` or `'>'`.
 *
 * Notes:
 *
 * (1) Padding is only automatically added between successive structure members.
 *     No padding is added at the beginning or the end of the encoded struct.
 *
 * (2) No padding is added when using non-native size and alignment, e.g.
 *     with '<', '>', '=', and '!'.
 *
 * (3) To align the end of a structure to the alignment requirement of a
 *     particular type, end the format with the code for that type with a repeat
 *     count of zero.
 *
 *
 * ### Format Characters
 *
 * Format characters have the following meaning; the conversion between C and
 * ucode values should be obvious given their types.  The 'Standard size' column
 * refers to the size of the packed value in bytes when using standard size;
 * that is, when the format string starts with one of `'<'`, `'>'`, `'!'` or
 * `'='`.  When using native size, the size of the packed value is platform
 * dependent.
 *
 * | Format | C Type               | Ucode type | Standard size  | Notes    |
 * |--------|----------------------|------------|----------------|----------|
 * | `x`    | *pad byte*           | *no value* |                | (7)      |
 * | `c`    | `char`               | string     | 1              |          |
 * | `b`    | `signed char`        | int        | 1              | (1), (2) |
 * | `B`    | `unsigned char`      | int        | 1              | (2)      |
 * | `?`    | `_Bool`              | bool       | 1              | (1)      |
 * | `h`    | `short`              | int        | 2              | (2)      |
 * | `H`    | `unsigned short`     | int        | 2              | (2)      |
 * | `i`    | `int`                | int        | 4              | (2)      |
 * | `I`    | `unsigned int`       | int        | 4              | (2)      |
 * | `l`    | `long`               | int        | 4              | (2)      |
 * | `L`    | `unsigned long`      | int        | 4              | (2)      |
 * | `q`    | `long long`          | int        | 8              | (2)      |
 * | `Q`    | `unsigned long long` | int        | 8              | (2)      |
 * | `n`    | `ssize_t`            | int        |                | (3)      |
 * | `N`    | `size_t`             | int        |                | (3)      |
 * | `e`    | (6)                  | double     | 2              | (4)      |
 * | `f`    | `float`              | double     | 4              | (4)      |
 * | `d`    | `double`             | double     | 8              | (4)      |
 * | `s`    | `char[]`             | double     |                | (9)      |
 * | `p`    | `char[]`             | double     |                | (8)      |
 * | `P`    | `void *`             | int        |                | (5)      |
 * | `*`    | `char[]`             | string     |                | (10)     |
 * | `X`    | `char[]`             | string     |                | (11)     |
 * | `Z`    | `char[]`             | string     |                | (12)     |
 *
 * Notes:
 *
 * - (1) The `'?'` conversion code corresponds to the `_Bool` type defined by
 *    C99. If this type is not available, it is simulated using a `char`. In
 *    standard mode, it is always represented by one byte.
 *
 * - (2) When attempting to pack a non-integer using any of the integer
 *    conversion codes, this module attempts to convert the given value into an
 *    integer. If the value is not convertible, a type error exception is thrown.
 *
 * - (3) The `'n'` and `'N'` conversion codes are only available for the native
 *    size (selected as the default or with the `'@'` byte order character).
 *    For the standard size, you can use whichever of the other integer formats
 *    fits your application.
 *
 * - (4) For the `'f'`, `'d'` and `'e'` conversion codes, the packed
 *    representation uses the IEEE 754 binary32, binary64 or binary16 format
 *    (for `'f'`, `'d'` or `'e'` respectively), regardless of the floating-point
 *    format used by the platform.
 *
 * - (5) The `'P'` format character is only available for the native byte
 *    ordering (selected as the default or with the `'@'` byte order character).
 *    The byte order character `'='` chooses to use little- or big-endian
 *    ordering based on the host system. The struct module does not interpret
 *    this as native ordering, so the `'P'` format is not available.
 *
 * - (6) The IEEE 754 binary16 "half precision" type was introduced in the 2008
 *    revision of the `IEEE 754` standard. It has a sign bit, a 5-bit exponent
 *    and 11-bit precision (with 10 bits explicitly stored), and can represent
 *    numbers between approximately `6.1e-05` and `6.5e+04` at full precision.
 *    This type is not widely supported by C compilers: on a typical machine, an
 *    unsigned short can be used for storage, but not for math operations. See
 *    the Wikipedia page on the `half-precision floating-point format` for more
 *    information.
 *
 * - (7) When packing, `'x'` inserts one NUL byte.
 *
 * - (8) The `'p'` format character encodes a "Pascal string", meaning a short
 *    variable-length string stored in a *fixed number of bytes*, given by the
 *    count. The first byte stored is the length of the string, or 255,
 *    whichever is smaller.  The bytes of the string follow.  If the string
 *    passed in to `pack()` is too long (longer than the count minus 1), only
 *    the leading `count-1` bytes of the string are stored.  If the string is
 *    shorter than `count-1`, it is padded with null bytes so that exactly count
 *    bytes in all are used.  Note that for `unpack()`, the `'p'` format
 *    character consumes `count` bytes, but that the string returned can never
 *    contain more than 255 bytes.
 *
 * - (9) For the `'s'` format character, the count is interpreted as the length
 *    of the bytes, not a repeat count like for the other format characters; for
 *    example, `'10s'` means a single 10-byte string mapping to or from a single
 *    ucode byte string, while `'10c'` means 10 separate one byte character
 *    elements (e.g., `cccccccccc`) mapping to or from ten different ucode byte
 *    strings. If a count is not given, it defaults to 1. For packing, the
 *    string is truncated or padded with null bytes as appropriate to make it
 *    fit. For unpacking, the resulting bytes object always has exactly the
 *    specified number of bytes.  As a special case, `'0s'` means a single,
 *    empty string (while `'0c'` means 0 characters).
 *
 * - (10) The `*` format character serves as wildcard. For `pack()` it will
 *    append the corresponding byte argument string as-is, not applying any
 *    padding or zero filling. When a repeat count is given, that many bytes of
 *    the input byte string argument will be appended at most on `pack()`,
 *    effectively truncating longer input strings. For `unpack()`, the wildcard
 *    format will yield a byte string containing the entire remaining input data
 *    bytes, or - when a repeat count is given - that many bytes of input data
 *    at most.
 *
 * - (11) The `X` format character handles hexadecimal encoding of binary data.
 *    On `pack()`, the argument is a hexadecimal string; with no repeat count the
 *    entire string is decoded into binary, while a repeat count limits the
 *    number of output bytes (truncating longer input). On `unpack()`, the input
 *    binary data is converted into a hexadecimal string, using all remaining
 *    bytes by default, or at most the specified number of bytes when a repeat
 *    count is given. Decoding accepts both upper- and lowercase hex digits, but
 *    encoding always produces lowercase output. The encoded text length is
 *    exactly twice the number of processed binary bytes.
 *
 * - (12) The `Z` format character behaves like `X`, but uses base64 encoding
 *    instead of hexadecimal. On `pack()`, the argument is a base64 string; by
 *    default the entire string is decoded into binary, or at most the specified
 *    number of bytes when a repeat count is given. On `unpack()`, the input
 *    binary data is converted into a base64 string, consuming all remaining
 *    bytes by default, or at most the repeat count if given. The encoded base64
 *    string is approximately 1.4 times the size of the processed binary data.
 *
 * A format character may be preceded by an integral repeat count.  For example,
 * the format string `'4h'` means exactly the same as `'hhhh'`.
 *
 * Whitespace characters between formats are ignored; a count and its format
 * must not contain whitespace though.
 *
 * When packing a value `x` using one of the integer formats (`'b'`,
 * `'B'`, `'h'`, `'H'`, `'i'`, `'I'`, `'l'`, `'L'`,
 * `'q'`, `'Q'`), if `x` is outside the valid range for that format, a type
 * error exception is raised.
 *
 * For the `'?'` format character, the return value is either `true` or `false`.
 * When packing, the truish result value of the argument is used. Either 0 or 1
 * in the native or standard bool representation will be packed, and any
 * non-zero value will be `true` when unpacking.
 *
 * ## Examples
 *
 * Note:
 *    Native byte order examples (designated by the `'@'` format prefix or
 *    lack of any prefix character) may not match what the reader's
 *    machine produces as
 *    that depends on the platform and compiler.
 *
 * Pack and unpack integers of three different sizes, using big endian
 * ordering:
 *
 * ```
 * import { pack, unpack } from 'struct';
 *
 * pack(">bhl", 1, 2, 3);  // "\x01\x00\x02\x00\x00\x00\x03"
 * unpack(">bhl", "\x01\x00\x02\x00\x00\x00\x03");  // [ 1, 2, 3 ]
 * ```
 *
 * Attempt to pack an integer which is too large for the defined field:
 *
 * ```bash
 * $ ucode -lstruct -p 'struct.pack(">h", 99999)'
 * Type error: Format 'h' requires numeric argument between -32768 and 32767
 * In [-p argument], line 1, byte 24:
 *
 *  `struct.pack(">h", 99999)`
 *   Near here -------------^
 * ```
 *
 * Demonstrate the difference between `'s'` and `'c'` format characters:
 *
 * ```
 * import { pack } from 'struct';
 *
 * pack("@ccc", "1", "2", "3");  // "123"
 * pack("@3s", "123");           // "123"
 * ```
 *
 * The ordering of format characters may have an impact on size in native
 * mode since padding is implicit. In standard mode, the user is
 * responsible for inserting any desired padding.
 *
 * Note in the first `pack()` call below that three NUL bytes were added after
 * the packed `'#'` to align the following integer on a four-byte boundary.
 * In this example, the output was produced on a little endian machine:
 *
 * ```
 * import { pack } from 'struct';
 *
 * pack("@ci", "#", 0x12131415);  // "#\x00\x00\x00\x15\x14\x13\x12"
 * pack("@ic", 0x12131415, "#");  // "\x15\x14\x13\x12#"
 * ```
 *
 * The following format `'ih0i'` results in two pad bytes being added at the
 * end, assuming the platform's ints are aligned on 4-byte boundaries:
 *
 * ```
 * import { pack } from 'struct';
 *
 * pack("ih0i", 0x01010101, 0x0202);  // "\x01\x01\x01\x01\x02\x02\x00\x00"
 * ```
 *
 * Use the wildcard format to extract the remainder of the input data:
 *
 * ```
 * import { unpack } from 'struct';
 *
 * unpack("ccc*", "foobarbaz");   // [ "f", "o", "o", "barbaz" ]
 * unpack("ccc3*", "foobarbaz");  // [ "f", "o", "o", "bar" ]
 * ```
 *
 * Use the wildcard format to pack binary stings as-is into the result data:
 *
 * ```
 * import { pack } from 'struct';
 *
 * pack("h*h", 0x0101, "\x02\x00\x03", 0x0404);  // "\x01\x01\x02\x00\x03\x04\x04"
 * pack("c3*c", "a", "foobar", "c");  // "afooc"
 * ```
 *
 * @module struct
 */

/**
 * Precompiled struct format instance returned by {@link module:struct#new|new()}.
 *
 * @typedef {{ pack: function(*): string, unpack: function(string, ?int): *[] }} StructInstance
 */

/**
 * Incremental struct buffer returned by {@link module:struct#buffer|buffer()}.
 *
 * @typedef {{
 *   pos: function(?int): *,
 *   length: function(?int): *,
 *   start: function(): StructBuffer,
 *   end: function(): StructBuffer,
 *   put: function(string, *): StructBuffer,
 *   get: function(string | int): *,
 *   read: function(string): *[],
 *   slice: function(?int, ?int): string,
 *   set: function(*, ?int, ?int): StructBuffer,
 *   pull: function(): string
 * }} StructBuffer
 */

/**
 * Pack given values according to specified format.
 *
 * The `pack()` function creates a byte string containing the argument values
 * packed according to the given format string.
 *
 * Returns the packed string.
 *
 * Raises a runtime exception if a given argument value does not match the
 * required type of the corresponding format string directive or if and invalid
 * format string is provided.
 *
 * @function module:struct#pack
 *
 * @param {string} format
 * The format string.
 *
 * @param {...*} values
 * Variable number of values to pack.
 *
 * @returns {string}
 *
 * @example
 * // Pack the values 1, 2, 3 as three consecutive unsigned int values
 * // in network byte order.
 * const data = pack('!III', 1, 2, 3);
 */
export function pack(format, values) {};

/**
 * Unpack given byte string according to specified format.
 *
 * The `unpack()` function interpretes a byte string according to the given
 * format string and returns the resulting values. If the optional offset
 * argument is given, unpacking starts from this byte position within the input.
 * If not specified, the start offset defaults to `0`, the start of the given
 * input string.
 *
 * Returns an array of unpacked values.
 *
 * Raises a runtime exception if the format string is invalid or if an invalid
 * input string or offset value is given.
 *
 * @function module:struct#unpack
 *
 * @param {string} format
 * The format string.
 *
 * @param {string} input
 * The input string to unpack.
 *
 * @param {int} [offset=0]
 * The offset within the input string to start unpacking from.
 *
 * @returns {*[]}
 *
 * @example
 * // Unpack three consecutive unsigned int values in network byte order.
 * const numbers =
 *   unpack('!III', '\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03');
 * print(numbers, "\n"); // [ 1, 2, 3 ]
 */
export function unpack(format, input, offset) {};

/**
 * Precompile format string.
 *
 * The `new()` function precompiles the given format string argument and returns
 * a `struct` object instance useful for packing and unpacking multiple items
 * without having to recompute the internal format each time.
 *
 * Returns an precompiled struct format instance.
 *
 * Raises a runtime exception if the format string is invalid.
 *
 * @function module:struct#new
 *
 * @param {string} format
 * The format string.
 *
 * @returns {StructInstance}
 *
 * @example
 * // Create a format of three consecutive unsigned int values in network byte order.
 * const fmt = struct.new('!III');
 * const buf = fmt.pack(1, 2, 3);  // "\x00\x00\x00\x01…"
 * print(fmt.unpack(buf), "\n");   // [ 1, 2, 3 ]
 */
export function new(format) {};

/**
 * Pack given values.
 *
 * The `pack()` function creates a byte string containing the argument values
 * packed according to the given format instance.
 *
 * Returns the packed string.
 *
 * Raises a runtime exception if a given argument value does not match the
 * required type of the corresponding format string directive.
 *
 * @function module:struct.instance#pack
 *
 * @param {...*} values
 * Variable number of values to pack.
 *
 * @returns {string}
 *
 * @example
 * const fmt = struct.new(…);
 * const data = fmt.pack(…);
 */

/**
 * Unpack given byte string.
 *
 * The `unpack()` function interpretes a byte string according to the given
 * format instance and returns the resulting values. If the optional offset
 * argument is given, unpacking starts from this byte position within the input.
 * If not specified, the start offset defaults to `0`, the start of the given
 * input string.
 *
 * Returns an array of unpacked values.
 *
 * Raises a runtime exception if an invalid input string or offset value is
 * given.
 *
 * @function module:struct.instance#unpack
 *
 * @param {string} input
 * The input string to unpack.
 *
 * @param {int} [offset=0]
 * The offset within the input string to start unpacking from.
 *
 * @returns {*[]}
 *
 * @example
 * const fmt = struct.new(…);
 * const values = fmt.unpack(…);
 */

/**
 * Creates a new struct buffer instance.
 *
 * The `buffer()` function creates a new struct buffer object that can be used
 * for incremental packing and unpacking of binary data. If an initial data
 * string is provided, the buffer is initialized with this content.
 *
 * Note that even when initial data is provided, the buffer position is always
 * set to zero. This design assumes that the primary intent when initializing
 * a buffer with data is to read (unpack) from the beginning. If you want to
 * append data to a pre-initialized buffer, you need to explicitly move the
 * position to the end, either by calling `end()` or by setting the position
 * manually with `pos()`.
 *
 * Returns a new struct buffer instance.
 *
 * @function module:struct#buffer
 *
 * @param {string} [initialData]
 * Optional initial data to populate the buffer with.
 *
 * @returns {StructBuffer}
 *
 * @example
 * // Create an empty buffer
 * const emptyBuf = struct.buffer();
 *
 * // Create a buffer with initial data
 * const dataBuf = struct.buffer("\x01\x02\x03\x04");
 *
 * // Read from the beginning of the initialized buffer
 * const value = dataBuf.get('I');
 *
 * // Append data to the initialized buffer
 * dataBuf.end().put('I', 5678);
 *
 * // Alternative chained syntax for initializing and appending
 * const buf = struct.buffer("\x01\x02\x03\x04").end().put('I', 5678);
 */
export function buffer(initialData) {};

/**
 * Get or set the current position in the buffer.
 *
 * If called without arguments, returns the current position.
 * If called with a position argument, sets the current position to that value.
 *
 * @function module:struct.buffer#pos
 *
 * @param {int} [position]
 * The position to set. If omitted, the current position is returned.
 *
 * @returns {int|StructBuffer}
 * If called without arguments, returns the current position.
 * If called with a position argument, returns the buffer instance for chaining.
 *
 * @example
 * const currentPos = buf.pos();
 * buf.pos(10);  // Set position to 10
 */

/**
 * Get or set the current buffer length.
 *
 * If called without arguments, returns the current length of the buffer.
 * If called with a length argument, sets the buffer length to that value,
 * padding the data with trailing zero bytes or truncating it depending on
 * whether the updated length is larger or smaller than the current length
 * respectively.
 *
 * In case the updated length is smaller than the current buffer offset, the
 * position is updated accordingly, so that it points to the new end of the
 * truncated buffer data.
 *
 * @function module:struct.buffer#length
 *
 * @param {int} [length]
 * The length to set. If omitted, the current length is returned.
 *
 * @returns {int|StructBuffer}
 * If called without arguments, returns the current length.
 * If called with a length argument, returns the buffer instance for chaining.
 *
 * @example
 * const buf = struct.buffer("abc"); // Initialize buffer with three bytes
 * const currentLen = buf.length();  // Returns 3
 *
 * buf.length(6);                    // Extend to 6 bytes
 * buf.slice();                      // Trailing null bytes: "abc\x00\x00\x00"
 *
 * buf.length(2);                    // Truncate to 2 bytes
 * buf.slice();                      // Truncated data: "ab"
 */

/**
 * Set the buffer position to the start (0).
 *
 * @function module:struct.buffer#start
 *
 * @returns {StructBuffer}
 * The buffer instance.
 *
 * @example
 * buf.start();
 */

/**
 * Set the buffer position to the end.
 *
 * @function module:struct.buffer#end
 *
 * @returns {StructBuffer}
 * The buffer instance.
 *
 * @example
 * buf.end();
 */

/**
 * Pack data into the buffer at the current position.
 *
 * The `put()` function packs the given values into the buffer according to
 * the specified format string, starting at the current buffer position.
 * The format string follows the same syntax as used in `struct.pack()`.
 *
 * For a detailed explanation of the format string syntax, refer to the
 * ["Format Strings" section]{@link module:struct} in the module
 * documentation.
 *
 * @function module:struct.buffer#put
 *
 * @param {string} format
 * The format string specifying how to pack the data.
 *
 * @param {...*} values
 * The values to pack into the buffer.
 *
 * @returns {StructBuffer}
 * The buffer instance.
 *
 * @see {@link module:struct#pack|struct.pack()}
 *
 * @example
 * buf.put('II', 1234, 5678);
 */

/**
 * Unpack a single value from the buffer at the current position.
 *
 * The `get()` function unpacks a single value from the buffer according to the
 * specified format string, starting at the current buffer position.
 * The format string follows the same syntax as used in `struct.unpack()`.
 *
 * For a detailed explanation of the format string syntax, refer to the
 * ["Format Strings" section]{@link module:struct} in the module documentation.
 *
 * Alternatively, `get()` accepts a postive or negative integer as format, which
 * specifies the length of a string to unpack before or after the current
 * position. Negative values extract that many bytes before the current offset
 * while postive ones extracts that many bytes after.
 *
 * @function module:struct.buffer#get
 *
 * @param {string|int} format
 * The format string specifying how to unpack the data.
 *
 * @returns {*}
 * The unpacked value.
 *
 * @see {@link module:struct#unpack|struct.unpack()}
 *
 * @example
 * const val = buf.get('I');
 * const str = buf.get(5);    // equivalent to buf.get('5s')
 * const str = buf.get(-3);   // equivalent to buf.pos(buf.pos() - 3).get('3s')
 */

/**
 * Unpack multiple values from the buffer at the current position.
 *
 * The `read()` function unpacks multiple values from the buffer according to
 * the specified format string, starting at the current buffer position.
 * The format string follows the same syntax as used in `struct.unpack()`.
 *
 * For a detailed explanation of the format string syntax, refer to the
 * ["Format Strings" section]{@link module:struct} in the module documentation.
 *
 * @function module:struct.buffer#read
 *
 * @param {string} format
 * The format string specifying how to unpack the data.
 *
 * @returns {*[]}
 * An array containing the unpacked values.
 *
 * @see {@link module:struct#unpack|struct.unpack()}
 *
 * @example
 * const values = buf.read('II');
 */

/**
 * Extract a slice of the buffer content.
 *
 * The `slice()` function returns a substring of the buffer content
 * between the specified start and end positions.
 *
 * Both the start and end position values may be negative, in which case they're
 * relative to the end of the buffer, e.g. `slice(-3)` will extract the last
 * three bytes of data.
 *
 * @function module:struct.buffer#slice
 *
 * @param {int} [start=0]
 * The starting position of the slice.
 *
 * @param {int} [end=buffer.length()]
 * The ending position of the slice (exclusive).
 *
 * @returns {string}
 * A string containing the specified slice of the buffer content.
 *
 * @example
 * const slice = buf.slice(4, 8);
 */

/**
 * Set a slice of the buffer content to given byte value.
 *
 * The `set()` function overwrites a substring of the buffer content with the
 * given byte value, similar to the C `memset()` function, between the specified
 * start and end positions.
 *
 * Both the start and end position values may be negative, in which case they're
 * relative to the end of the buffer, e.g. `set(0, -2)` will overwrite the last
 * two bytes of data with `\x00`.
 *
 * When the start or end positions are beyond the current buffer length, the
 * buffer is grown accordingly.
 *
 * @function module:struct.buffer#set
 *
 * @param {int|string} [value=0]
 * The byte value to use when overwriting buffer contents. When a string is
 * given, the first character is used as value.
 *
 * @param {int} [start=0]
 * The position to start overwriting from.
 *
 * @param {int} [end=buffer.length()]
 * The position to end overwriting (exclusive).
 *
 * @returns {StructBuffer}
 * The buffer instance.
 *
 * @example
 * const buf = struct.buffer("abcde");
 * buf.set("X", 2, 4).slice();  // Buffer content is now "abXXe"
 * buf.set().slice();           // Buffer content is now "\x00\x00\x00\x00\x00"
 */

/**
 * Extract and remove all content from the buffer.
 *
 * The `pull()` function returns all content of the buffer as a string
 * and resets the buffer to an empty state.
 *
 * @function module:struct.buffer#pull
 *
 * @returns {string}
 * A string containing all the buffer content.
 *
 * @example
 * const allData = buf.pull();
 */

