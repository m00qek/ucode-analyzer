/**
 * # Zlib bindings
 *
 * The `zlib` module provides single-call and stream-oriented functions for interacting with zlib data.
 *
 * @module zlib
 */

/**
 * Compresses data in Zlib or gzip format.
 *
 * If the input argument is a plain string, it is directly compressed.
 *
 * If an array, object or resource value is given, this function will attempt to
 * invoke a `read()` method on it to read chunks of input text to incrementally
 * compress. Reading will stop if the object's `read()` method returns
 * either `null` or an empty string.
 *
 * Throws an exception on errors.
 *
 * Returns the compressed data.
 *
 * @function module:zlib#deflate
 *
 * @param {string} str_or_resource
 * The string or resource object to be compressed.
 *
 * @param {?boolean} [gzip=false]
 * Add a gzip header if true (creates a gzip-compliant output, otherwise defaults to Zlib)
 *
 * @param {?int} [level=Z_DEFAULT_COMPRESSION]
 * The compression level (0-9).
 *
 * @returns {?string}
 *
 * @example
 * // deflate content using default compression
 * const deflated = deflate(content);
 *
 * // deflate content using fastest compression
 * const deflated = deflate(content, Z_BEST_SPEED);
 */
export function deflate(str_or_resource, gzip, level) {};

/**
 * Decompresses data in Zlib or gzip format.
 *
 * If the input argument is a plain string, it is directly decompressed.
 *
 * If an array, object or resource value is given, this function will attempt to
 * invoke a `read()` method on it to read chunks of input text to incrementally
 * decompress. Reading will stop if the object's `read()` method returns
 * either `null` or an empty string.
 *
 * Throws an exception on errors.
 *
 * Returns the decompressed data.
 *
 * @function module:zlib#inflate
 *
 * @param {string} str_or_resource
 * The string or resource object to be parsed as JSON.
 *
 * @returns {?string}
 */
export function inflate(str_or_resource) {};

/**
 * Initializes a deflate stream.
 *
 * Returns a stream handle on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib#deflater
 *
 * @param {?boolean} [gzip=false]
 * Add a gzip header if true (creates a gzip-compliant output, otherwise defaults to Zlib)
 *
 * @param {?int} [level=Z_DEFAULT_COMPRESSION]
 * The compression level (0-9).
 *
 * @returns {?module:zlib.deflate}
 *
 * @example
 * // initialize a Zlib deflate stream using default compression
 * const zstrmd = deflater();
 *
 * // initialize a gzip deflate stream using fastest compression
 * const zstrmd = deflater(true, Z_BEST_SPEED);
 */
export function deflater(gzip, level) {};

/**
 * Writes a chunk of data to the deflate stream.
 *
 * Input data must be a string, it is internally compressed by the zlib `deflate()` routine,
 * the end result is buffered according to the requested `flush` mode until read via
 * {@link module:zlib.zstrmd#read}.
 * Valid `flush`values are `Z_NO_FLUSH` (the default),
 * `Z_SYNC_FLUSH, Z_PARTIAL_FLUSH, Z_FULL_FLUSH, Z_FINISH`.
 * If `flush` is `Z_FINISH` then no more data can be written to the stream.
 * Refer to the {@link https://zlib.net/manual.html Zlib manual} for details
 * on each flush mode.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib.deflate#write
 *
 * @param {string} src
 * The string of data to deflate.
 *
 * @param {?int} [flush=Z_NO_FLUSH]
 * The zlib flush mode.
 *
 * @returns {?boolean}
 */
export function deflate(src, flush) {};

/**
 * Reads a chunk of compressed data from the deflate stream.
 *
 * Returns the current content of the deflate buffer, fed through
 * {@link module:zlib.deflate#write}.
 *
 * Returns compressed chunk on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib.deflate#read
 *
 * @returns {?string}
 */
export function deflate() {};

/**
 * Initializes an inflate stream. Can process either Zlib or gzip data.
 *
 * Returns a stream handle on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib#inflater
 *
 * @returns {?module:zlib.inflate}
 *
 * @example
 * // initialize an inflate stream
 * const zstrmi = inflater();
 */
export function inflater() {};

/**
 * Writes a chunk of data to the inflate stream.
 *
 * Input data must be a string, it is internally decompressed by the zlib `inflate()` routine,
 * the end result is buffered according to the requested `flush` mode until read via
 * {@link module:zlib.inflate#read}.
 * Valid `flush` values are `Z_NO_FLUSH` (the default), `Z_SYNC_FLUSH, Z_FINISH`.
 * If `flush` is `Z_FINISH` then no more data can be written to the stream.
 * Refer to the {@link https://zlib.net/manual.html Zlib manual} for details
 * on each flush mode.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib.inflate#write
 *
 * @param {string} src
 * The string of data to inflate.
 *
 * @param {?int} [flush=Z_NO_FLUSH]
 * The zlib flush mode.
 *
 * @returns {?boolean}
 */
export function inflate(src, flush) {};

/**
 * Reads a chunk of decompressed data from the inflate stream.
 *
 * Returns the current content of the inflate buffer, fed through
 * {@link module:zlib.inflate#write}.
 *
 * Returns decompressed chunk on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:zlib.inflate#read
 *
 * @returns {?string}
 */
export function inflate() {};

/**
 * Queries error information.
 *
 * Returns a string containing a description of the last occurred error or
 * `null` if there is no error information.
 *
 * @function module:zlib.deflate#error
 *
 *
 * @returns {?string}
 */
export function deflate() {};

