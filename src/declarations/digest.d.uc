// Source: https://github.com/jow-/ucode @ fecacb8188c6a4f38d97434160b979d73e898b24
/**
 * # Digest Functions
 *
 * The `digest` module bundles various digest functions.
 *
 * @module digest
 */

/**
 * Calculates the MD5 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#md5
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * md5("This is a test");  // Returns "ce114e4501d2f4e2dcea3e17b546f339"
 * md5(123);               // Returns null
 */
export function md5(str) {};

/**
 * Calculates the SHA1 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#sha1
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * sha1("This is a test");  // Returns "a54d88e06612d820bc3be72877c74f257b561b19"
 * sha1(123);               // Returns null
 */
export function sha1(str) {};

/**
 * Calculates the SHA256 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#sha256
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * sha256("This is a test");  // Returns "c7be1ed902fb8dd4d48997c6452f5d7e509fbcdbe2808b16bcf4edce4c07d14e"
 * sha256(123);               // Returns null
 */
export function sha256(str) {};

/**
 * Calculates the 64-bit FNV-1a non-cryptographic hash of string and returns
 * that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#fnv1a64
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * fnv1a64("This is a test");  // Returns "25f0b040ca8b4ce0"
 * fnv1a64(123);               // Returns null
 */
export function fnv1a64(str) {};

/**
 * Calculates the 64-bit FNV-1a non-cryptographic hash of a given file and
 * returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#fnv1a64_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function fnv1a64_file(path) {};

/**
 * Calculates the MD2 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#md2
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * md2("This is a test");  // Returns "dc378580fd0722e56b82666a6994c718"
 * md2(123);               // Returns null
 */
export function md2(str) {};

/**
 * Calculates the MD4 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#md4
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * md4("This is a test");  // Returns "3b487cf6856af7e330bc4b1b7d977ef8"
 * md4(123);               // Returns null
 */
export function md4(str) {};

/**
 * Calculates the SHA384 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#sha384
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * sha384("This is a test");  // Returns "a27c7667e58200d4c0688ea136968404a0da366b1a9fc19bb38a0c7a609a1eef2bcc82837f4f4d92031a66051494b38c"
 * sha384(123);               // Returns null
 */
export function sha384(str) {};

/**
 * Calculates the SHA512 hash of string and returns that hash.
 *
 * Returns `null` if a non-string argument is given.
 *
 * @function module:digest#sha512
 *
 * @param {string} str
 * The string to hash.
 *
 * @returns {?string}
 *
 * @example
 * sha512("This is a test");  // Returns "a028d4f74b602ba45eb0a93c9a4677240dcf281a1a9322f183bd32f0bed82ec72de9c3957b2f4c9a1ccf7ed14f85d73498df38017e703d47ebb9f0b3bf116f69"
 * sha512(123);               // Returns null
 */
export function sha512(str) {};

/**
 * Calculates the MD5 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#md5_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function md5_file(path) {};

/**
 * Calculates the SHA1 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#sha1_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function sha1_file(path) {};

/**
 * Calculates the SHA256 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#sha256_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function sha256_file(path) {};

/**
 * Calculates the MD2 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#md2_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function md2_file(path) {};

/**
 * Calculates the MD4 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#md4_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function md4_file(path) {};

/**
 * Calculates the SHA384 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#sha384_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function sha384_file(path) {};

/**
 * Calculates the SHA512 hash of a given file and returns that hash.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:digest#sha512_file
 *
 * @param {string} path
 * The path to the file.
 *
 * @returns {?string}
 */
export function sha512_file(path) {};

