/**
 * # Builtin functions
 *
 * The core namespace is not an actual module but refers to the set of
 * builtin functions and properties available to `ucode` scripts.
 *
 * @module core
 */

/**
 * Print any of the given values to stdout.
 *
 * The `print()` function writes a string representation of each given argument
 * to stdout and returns the amount of bytes written.
 *
 * String values are printed as-is, integer and double values are printed in
 * decimal notation, boolean values are printed as `true` or `false` while
 * arrays and objects are converted to their JSON representation before being
 * written to the standard output. The `null` value is represented by an empty
 * string so `print(null)` would print nothing. Resource values are printed in
 * the form `<type address>`, e.g. `<fs.file 0x7f60f0981760>`.
 *
 * If resource, array or object values contain a `tostring()` function in their
 * prototypes, then this function is invoked to obtain an alternative string
 * representation of the value.
 *
 * Examples:
 *
 * ```javascript
 * print(1 != 2);                       // Will print 'true'
 * print(0xff);                         // Will print '255'
 * print(2e3);                          // Will print '2000'
 * print(null);                         // Will print nothing
 * print({ hello: true, world: 123 });  // Will print '{ "hello": true, "world": 123 }'
 * print([1,2,3]);                      // Will print '[ 1, 2, 3 ]'
 *
 * print(proto({ foo: "bar" },          // Will print 'MyObj'
 *   { tostring: () => "MyObj" }));     // instead of '{ "foo": "bar" }'
 *
 * ```
 *
 * Returns the amount of bytes printed.
 *
 * @function module:core#print
 *
 * @param {*} values
 * Arbitrary values to print
 *
 * @returns {int}
 */
export function print(values) {};

/**
 * Determine the length of the given object, array or string.
 *
 * Returns the length of the given value.
 *
 *  - For strings, the length is the amount of bytes within the string
 *  - For arrays, the length is the amount of array elements
 *  - For objects, the length is defined as the amount of keys
 *
 * Returns `null` if the given argument is not an object, array or string.
 *
 * @function module:core#length
 *
 * @param {*} x - The input object, array, or string.
 *
 * @returns {?int} - The length of the input.
 *
 * @example
 * length("test")                             // 4
 * length([true, false, null, 123, "test"])   // 5
 * length({foo: true, bar: 123, baz: "test"}) // 3
 * length({})                                 // 0
 * length(true)                               // null
 * length(10.0)                               // null
 */
export function length(x) {};

/**
 * Finds the given value passed as the second argument within the array or
 * string specified in the first argument.
 *
 * Returns the first matching array index or first matching string offset or
 * `-1` if the value was not found.
 *
 * Returns `null` if the first argument was neither an array nor a string.
 *
 * @function module:core#index
 *
 * @param {*} arr_or_str
 * The array or string to search for the value.
 *
 * @param {*} needle
 * The value to find within the array or string.
 *
 * @returns {?int}
 *
 * @example
 * index("Hello hello hello", "ll")          // 2
 * index([ 1, 2, 3, 1, 2, 3, 1, 2, 3 ], 2)   // 1
 * index("foo", "bar")                       // -1
 * index(["Red", "Blue", "Green"], "Brown")  // -1
 * index(123, 2)                             // null
 */
export function index(arr_or_str, needle) {};

/**
 * Finds the given value passed as the second argument within the array or
 * string specified in the first argument.
 *
 * Returns the last matching array index or last matching string offset or
 * `-1` if the value was not found.
 *
 * Returns `null` if the first argument was neither an array nor a string.
 *
 * @function module:core#rindex
 *
 * @param {*} arr_or_str
 * The array or string to search for the value.
 *
 * @param {*} needle
 * The value to find within the array or string.
 *
 * @returns {?int}
 *
 * @example
 * rindex("Hello hello hello", "ll")          // 14
 * rindex([ 1, 2, 3, 1, 2, 3, 1, 2, 3 ], 2)   //  7
 * rindex("foo", "bar")                       // -1
 * rindex(["Red", "Blue", "Green"], "Brown")  // -1
 * rindex(123, 2)                             // null
 */
export function rindex(arr_or_str, needle) {};

/**
 * Pushes the given argument(s) to the given array.
 *
 * Returns the last pushed value.
 *
 * @function module:core#push
 *
 * @param {*} arr
 * The array to push values to.
 *
 * @param {*} [values]
 * The values to push.
 *
 * @returns {*}
 *
 * @example
 * let x = [ 1, 2, 3 ];
 * push(x, 4, 5, 6);    // 6
 * print(x, "\n");      // [ 1, 2, 3, 4, 5, 6 ]
 */
export function push(arr, values) {};

/**
 * Pops the last item from the given array and returns it.
 *
 * Returns `null` if the array was empty or if a non-array argument was passed.
 *
 * @function module:core#pop
 *
 * @param {*} arr
 * The input array.
 *
 * @returns {*}
 *
 * @example
 * let x = [ 1, 2, 3 ];
 * pop(x);          // 3
 * print(x, "\n");  // [ 1, 2 ]
 */
export function pop(arr) {};

/**
 * Pops the first item from the given array and returns it.
 *
 * Returns `null` if the array was empty or if a non-array argument was passed.
 *
 * @function module:core#shift
 *
 * @param {*} arr
 * The array from which to pop the first item.
 *
 * @returns {*}
 *
 * @example
 * let x = [ 1, 2, 3 ];
 * shift(x);        // 1
 * print(x, "\n");  // [ 2, 3 ]
 */
export function shift(arr) {};

/**
 * Add the given values to the beginning of the array passed via first argument.
 *
 * Returns the last value added to the array.
 *
 * @function module:core#unshift
 *
 * @param {*} arr
 * The array to which the values will be added.
 *
 * @param {*}
 * Values to add.
 *
 * @returns {*}
 *
 * @example
 * let x = [ 3, 4, 5 ];
 * unshift(x, 1, 2);  // 2
 * print(x, "\n");    // [ 1, 2, 3, 4, 5 ]
 */
export function unshift(arr) {};

/**
 * Converts each given numeric value to a byte and return the resulting string.
 * Invalid numeric values or values < 0 result in `\0` bytes, values larger than
 * 255 are truncated to 255.
 *
 * Returns a new strings consisting of the given byte values.
 *
 * @function module:core#chr
 *
 * @param {*} n1
 * The numeric values.
 *
 * @returns {string}
 *
 * @example
 * chr(65, 98, 99);  // "Abc"
 * chr(-1, 300);     // string consisting of an `0x0` and a `0xff` byte
 */
export function chr(n1) {};

/**
 * Raise an exception with the given message and abort execution.
 *
 * @function module:core#die
 *
 * @param {string} msg
 * The error message.
 *
 * @throws {Error}
 * The error with the given message.
 *
 * @example
 * die(msg);
 */
export function die(msg) {};

/**
 * Check whether the given key exists within the given object value.
 *
 * Returns `true` if the given key is present within the object passed as the
 * first argument, otherwise `false`.
 *
 * @function module:core#exists
 *
 * @param {*} obj
 * The input object.
 *
 * @param {string} key
 * The key to check for existence.
 *
 * @returns {boolean}
 *
 * @example
 * let x = { foo: true, bar: false, qrx: null };
 * exists(x, 'foo');  // true
 * exists(x, 'qrx');  // true
 * exists(x, 'baz');  // false
 */
export function exists(obj, key) {};

/**
 * Terminate the interpreter with the given exit code.
 *
 * This function does not return.
 *
 * @function module:core#exit
 *
 * @param {int} n
 * The exit code.
 *
 * @example
 * exit();
 * exit(5);
 */
export function exit(n) {};

/**
 * Query an environment variable or then entire environment.
 *
 * Returns the value of the given environment variable, or - if omitted - a
 * dictionary containing all environment variables.
 *
 * @function module:core#getenv
 *
 * @param {string} [name]
 * The name of the environment variable.
 *
 * @returns {*}
 */
export function getenv(name) {};

/**
 * Filter the array passed as the first argument by invoking the function
 * specified in the second argument for each array item.
 *
 * If the invoked function returns a truthy result, the item is retained,
 * otherwise, it is dropped. The filter function is invoked with three
 * arguments:
 *
 * 1. The array value
 * 2. The current index
 * 3. The array being filtered
 *
 * (Note that the `map` function behaves similarly to `filter` with respect
 * to its `fn` parameters.)
 *
 * Returns a new array containing only retained items, in the same order as
 * the input array.
 *
 * @function module:core#filter
 *
 * @param {*} arr
 * The input array.
 *
 * @param {*} fn
 * The filter function.
 *
 * @returns {*}
 *
 * @example
 * // filter out any empty string:
 * a = filter(["foo", "", "bar", "", "baz"], length)
 * // a = ["foo", "bar", "baz"]
 *
 * // filter out any non-number type:
 * a = filter(["foo", 1, true, null, 2.2], function(v) {
 *     return (type(v) == "int" || type(v) == "double");
 * });
 * // a = [1, 2.2]
 */
export function filter(arr, fn) {};

/**
 * Converts the given hexadecimal string into a number.
 *
 * Returns the resulting integer value or `NaN` if the input value cannot be
 * interpreted as hexadecimal number.
 *
 * @function module:core#hex
 *
 * @param {*} x
 * The hexadecimal string to be converted.
 *
 * @returns {int}
 */
export function hex(x) {};

/**
 * Converts the given value to an integer, using an optional base.
 *
 * Returns `NaN` if the value is not convertible.
 *
 * @function module:core#int
 *
 * @param {*} x
 * The value to be converted to an integer.
 *
 * @param {int} [base]
 * The base into which the value is to be converted, the default is 10.
 * Note that the base parameter is ignored if the `x` value is already numeric.
 *
 * @returns {int}
 *
 * @example
 * int("123")         // Returns 123
 * int("123", 10)     // 123
 * int("10 or more")  // 10
 * int("12.3")        // 12
 * int("123", 7)      // 66
 * int("abc", 16)     // 2748
 * int("xyz", 36)     // 44027
 * int(10.10, "2")    // 10, the invalid base is ignored
 * int("xyz", 16)     // NaN, bad value
 * int("1010", "2")   // NaN, bad base
 */
export function int(x, base) {};

/**
 * Joins the array passed as the second argument into a string, using the
 * separator passed in the first argument as glue.
 *
 * Returns `null` if the second argument is not an array.
 *
 * @function module:core#join
 *
 * @param {string} sep
 * The separator to be used in joining the array elements.
 *
 * @param {*} arr
 * The array to be joined into a string.
 *
 * @returns {?string}
 */
export function join(sep, arr) {};

/**
 * Enumerates all object key names.
 *
 * Returns an array of all key names present in the passed object.
 * Returns `null` if the given argument is not an object.
 *
 * @function module:core#keys
 *
 * @param {*} obj
 * The object from which to retrieve the key names.
 *
 * @returns {*}
 */
export function keys(obj) {};

/**
 * Convert the given string to lowercase and return the resulting string.
 *
 * Returns `null` if the given argument could not be converted to a string.
 *
 * @function module:core#lc
 *
 * @param {string} s
 * The input string.
 *
 * @returns {?string}
 * The lowercase string.
 *
 * @example
 * lc("HeLLo WoRLd!");  // "hello world!"
 */
export function lc(s) {};

/**
 * Transform the array passed as the first argument by invoking the function
 * specified in the second argument for each array item.
 *
 * The mapping function is invoked with three arguments (see examples, below,
 * for some possibly counterintuitive usage):
 *
 * 1. The array value
 * 2. The current index
 * 3. The array being filtered
 *
 * (Note that the `filter` function behaves similarly to `map` with respect
 * to its `fn` parameters.)
 *
 * Returns a new array of the same length as the input array containing the
 * transformed values.
 *
 * @function module:core#map
 *
 * @param {*} arr
 * The input array.
 *
 * @param {*} fn
 * The mapping function.
 *
 * @returns {*}
 *
 * @example
 * // turn into an array of string lengths:
 * a = map(["Apple", "Banana", "Bean"], length);
 * // a = [5, 6, 4]
 *
 * // map to type names:
 * a = map(["foo", 1, true, null, 2.2], type);
 * // a = ["string", "int", "bool", null, "double"]
 *
 * // attempt to naively use built-in 'int' to map an array:
 * a = map(["x", "2", "11", "7"], int)
 * // a = [NaN, NaN, 3, NaN]
 * //
 * // This is a direct result of 'int' being provided the second, index parameter
 * // for its base value in the conversion.
 * //
 * // The resulting calls to 'int' are as follows:
 * //  int("x",  0, [...]) - convert "x"  to base 0, 'int' ignores the third value
 * //  int("2",  1, [...]) - convert "2"  to base 1, digit out of range, so NaN
 * //  int("11", 2, [...]) - convert "11" to base 2, produced unexpected 3
 * //  int("7",  3, [...]) - convert "7"  to base 3, digit out of range, NaN again
 *
 * // remedy this by using an arrow function to ensure the proper base value
 * // (in this case, the default of 10) is passed to 'int':
 * a = map(["x", "2", "1", "7"], (x) => int(x))
 * // a = [NaN, 2, 1, 7]
 *
 * // convert base-2 values:
 * a = map(["22", "1010", "0001", "0101"], (x) => int(x, 2))
 * // a = [NaN, 10, 1, 5]
 */
export function map(arr, fn) {};

/**
 * Without further arguments, this function returns the byte value of the first
 * character in the given string.
 *
 * If an offset argument is supplied, the byte value of the character at this
 * position is returned. If an invalid index is supplied, the function will
 * return `null`. Negative index entries are counted towards the end of the
 * string, e.g. `-2` will return the value of the second last character.
 *
 * Returns the byte value of the character.
 * Returns `null` if the offset is invalid or if the input is not a string.
 *
 * @function module:core#ord
 *
 * @param {string} s
 * The input string.
 *
 * @param {int} [offset]
 * The offset of the character.
 *
 * @returns {?int}
 *
 * @example
 * ord("Abc");         // 65
 * ord("Abc", 0);      // 65
 * ord("Abc", 1);      // 98
 * ord("Abc", 2);      // 99
 * ord("Abc", 10);     // null
 * ord("Abc", -10);    // null
 * ord("Abc", "nan");  // null
 */
export function ord(s, offset) {};

/**
 * Query the type of the given value.
 *
 * Returns the type of the given value as a string which might be one of
 * `"function"`, `"object"`, `"array"`, `"double"`, `"int"`, or `"bool"`.
 *
 * Returns `null` when no value or `null` is passed.
 *
 * @function module:core#type
 *
 * @param {*} x
 * The value to determine the type of.
 *
 * @returns {?string}
 */
export function type(x) {};

/**
 * Reverse the order of the given input array or string.
 *
 * If an array is passed, returns the array in reverse order.
 * If a string is passed, returns the string with the sequence of the characters
 * reversed.
 *
 * Returns the reversed array or string.
 * Returns `null` if neither an array nor a string were passed.
 *
 * @function module:core#reverse
 *
 * @param {*} arr_or_str
 * The input array or string.
 *
 * @returns {*}
 *
 * @example
 * reverse([1, 2, 3]);   // [ 3, 2, 1 ]
 * reverse("Abc");       // "cbA"
 */
export function reverse(arr_or_str) {};

/**
 * Sort the given array according to the given sort function.
 * If no sort function is provided, a default ascending sort order is applied.
 *
 * The input array is sorted in-place, no copy is made.
 *
 * The custom sort function is repeatedly called until the entire array is
 * sorted. It will receive two values as arguments and should return a value
 * lower than, larger than or equal to zero depending on whether the first
 * argument is smaller, larger or equal to the second argument respectively.
 *
 * Returns the sorted input array.
 *
 * @function module:core#sort
 *
 * @param {*} arr
 * The input array to be sorted.
 *
 * @param {*} [fn]
 * The sort function.
 *
 * @returns {*}
 *
 * @example
 * sort([8, 1, 5, 9]) // [1, 5, 8, 9]
 * sort(["Bean", "Orange", "Apple"], function(a, b) {
 *    return length(a) - length(b);
 * }) // ["Bean", "Apple", "Orange"]
 */
export function sort(arr, fn) {};

/**
 * Removes the elements designated by `off` and `len` from the given array,
 * and replaces them with the additional arguments passed, if any.
 *
 * The array grows or shrinks as necessary.
 *
 * Returns the modified input array.
 *
 * @function module:core#splice
 *
 * @param {*} arr
 * The input array to be modified.
 *
 * @param {int} off
 * The index to start removing elements.
 *
 * @param {int} [len]
 * The number of elements to remove.
 *
 * @param {*} [elements]
 * The elements to insert.
 *
 * @returns {*}
 *
 * @example
 * let x = [ 1, 2, 3, 4 ];
 * splice(x, 1, 2, "a", "b", "c");  // [ 1, "a", "b", "c", 4 ]
 * print(x, "\n");                  // [ 1, "a", "b", "c", 4 ]
 */
export function splice(arr, off, len, elements) {};

/**
 * Performs a shallow copy of a portion of the source array, as specified by
 * the start and end offsets. The original array is not modified.
 *
 * Returns a new array containing the copied elements, if any.
 * Returns `null` if the given source argument is not an array value.
 *
 * @function module:core#slice
 *
 * @param {*} arr
 * The source array to be copied.
 *
 * @param {int} [off]
 * The index of the first element to copy.
 *
 * @param {int} [end]
 * The index of the first element to exclude from the returned array.
 *
 * @returns {*}
 *
 * @example
 * slice([1, 2, 3])          // [1, 2, 3]
 * slice([1, 2, 3], 1)       // [2, 3]
 * slice([1, 2, 3], -1)      // [3]
 * slice([1, 2, 3], -3, -1)  // [1, 2]
 * slice([1, 2, 3], 10)      // []
 * slice([1, 2, 3], 2, 1)    // []
 * slice("invalid", 1, 2)    // null
 */
export function slice(arr, off, end) {};

/**
 * Split the given string using the separator passed as the second argument
 * and return an array containing the resulting pieces.
 *
 * If a limit argument is supplied, the resulting array contains no more than
 * the given amount of entries, that means the string is split at most
 * `limit - 1` times total.
 *
 * The separator may either be a plain string or a regular expression.
 *
 * Returns a new array containing the resulting pieces.
 *
 * @function module:core#split
 *
 * @param {string} str
 * The input string to be split.
 *
 * @param {*} sep
 * The separator.
 *
 * @param {int} [limit]
 * The limit on the number of splits.
 *
 * @returns {*}
 *
 * @example
 * split("foo,bar,baz", ",")     // ["foo", "bar", "baz"]
 * split("foobar", "")           // ["f", "o", "o", "b", "a", "r"]
 * split("foo,bar,baz", /[ao]/)  // ["f", "", ",b", "r,b", "z"]
 * split("foo=bar=baz", "=", 2)  // ["foo", "bar=baz"]
 */
export function split(str, sep, limit) {};

/**
 * Extracts a substring out of `str` and returns it. First character is at
 * offset zero.
 *
 *  - If `off` is negative, starts that far back from the end of the string.
 *  - If `len` is omitted, returns everything through the end of the string.
 *  - If `len` is negative, leaves that many characters off the string end.
 *
 * Returns the extracted substring.
 *
 * @function module:core#substr
 *
 * @param {string} str
 * The input string.
 *
 * @param {int} off
 * The starting offset.
 *
 * @param {int} [len]
 * The length of the substring.
 *
 * @returns {string}
 *
 * @example
 * s = "The black cat climbed the green tree";
 * substr(s, 4, 5);      // black
 * substr(s, 4, -11);    // black cat climbed the
 * substr(s, 14);        // climbed the green tree
 * substr(s, -4);        // tree
 * substr(s, -4, 2);     // tr
 */
export function substr(str, off, len) {};

/**
 * Returns the current UNIX epoch.
 *
 * @function module:core#time
 *
 * @returns {int}
 *
 * @example
 * time();     // 1598043054
 */
export function time() {};

/**
 * Converts the given string to uppercase and returns the resulting string.
 *
 * Returns null if the given argument could not be converted to a string.
 *
 * @function module:core#uc
 *
 * @param {*} str
 * The string to be converted to uppercase.
 *
 * @returns {?string}
 *
 * @example
 * uc("hello");   // "HELLO"
 * uc(123);       // null
 */
export function uc(str) {};

/**
 * Converts each given numeric value to an UTF-8 multibyte sequence and returns
 * the resulting string.
 *
 * Invalid numeric values or values outside the range `0`..`0x10FFFF` are
 * represented by the unicode replacement character `0xFFFD`.
 *
 * Returns a new UTF-8 encoded string consisting of unicode characters
 * corresponding to the given numeric codepoints.
 *
 * @function module:core#uchr
 *
 * @param {*}
 * Numeric values to convert.
 *
 * @returns {string}
 *
 * @example
 * uchr(0x2600, 0x26C6, 0x2601);  // "☀⛆☁"
 * uchr(-1, 0x20ffff, "foo");     // "���"
 */
export function uchr() {};

/**
 * Returns an array containing all values of the given object.
 *
 * Returns null if no object was passed.
 *
 * @function module:core#values
 *
 * @param {*} obj
 * The object from which to extract values.
 *
 * @returns {*}
 *
 * @example
 * values({ foo: true, bar: false });   // [true, false]
 */
export function values(obj) {};

/**
 * Trim any of the specified characters in `c` from the start and end of `str`.
 * If the second argument is omitted, trims the characters, ` ` (space), `\t`,
 * `\r`, and `\n`.
 *
 * Returns the trimmed string.
 *
 * @function module:core#trim
 *
 * @param {string} str
 * The string to be trimmed.
 *
 * @param {string} [c]
 * The characters to be trimmed from the start and end of the string.
 *
 * @returns {string}
 */
export function trim(str, c) {};

/**
 * Trim any of the specified characters from the start of the string.
 * If the second argument is omitted, trims the characters ` ` (space), '\t',
 * '\r', and '\n'.
 *
 * Returns the left trimmed string.
 *
 * @function module:core#ltrim
 *
 * @param {string} s
 * The input string.
 *
 * @param {string} [c]
 * The characters to trim.
 *
 * @returns {string}
 *
 * @example
 * ltrim("  foo  \n")     // "foo  \n"
 * ltrim("--bar--", "-")  // "bar--"
 */
export function ltrim(s, c) {};

/**
 * Trim any of the specified characters from the end of the string.
 * If the second argument is omitted, trims the characters ` ` (space), '\t',
 * '\r', and '\n'.
 *
* Returns the right trimmed string.
 *
 * @function module:core#rtrim
 *
 * @param {string} str
 * The input string.
 *
 * @param {string} [c]
 * The characters to trim.
 *
 * @returns {string}
 *
 * @example
 * rtrim("  foo  \n")     // "  foo"
 * rtrim("--bar--", "-")  // "--bar"
 */
export function rtrim(str, c) {};

/**
 * Formats the given arguments according to the given format string.
 *
 * See `printf()` for details.
 *
 * Returns the formatted string.
 *
 * @function module:core#sprintf
 *
 * @param {string} fmt
 * The format string.
 *
 * @param {*}
 * Arguments to be formatted.
 *
 * @returns {string}
 *
 * @example
 * sprintf("Hello %s", "world");    // "Hello world"
 * sprintf("%08x", 123);            // "0000007b"
 * sprintf("%c%c%c", 65, 98, 99);   // "Abc"
 * sprintf("%g", 10 / 3.0);         // "3.33333"
 * sprintf("%2$d %1$d", 12, 34);    // "34 12"
 * sprintf("%J", [1,2,3]);          // "[1,2,3]"
 */
export function sprintf(fmt) {};

/**
 * Formats the given arguments according to the given format string and outputs
 * the result to stdout.
 *
 * Ucode supports a restricted subset of the formats allowed by the underlying
 * libc's `printf()` implementation, namely it allows the `d`, `i`, `o`, `u`,
 * `x`, `X`, `e`, `E`, `f`, `F`, `g`, `G`, `c` and `s` conversions.
 *
 * Additionally, an ucode specific `J` format is implemented, which causes the
 * corresponding value to be formatted as JSON string. By prefixing the `J`
 * format letter with a precision specifier, the resulting JSON output will be
 * pretty printed. A precision of `0` will use tabs for indentation, any other
 * positive precision will use that many spaces for indentation while a negative
 * or omitted precision specifier will turn off pretty printing.
 *
 * Other format specifiers such as `n` or `z` are not accepted and returned
 * verbatim. Format specifiers including `*` directives are rejected as well.
 *
 * Returns the number of bytes written to the standard output.
 *
 * @function module:core#printf
 *
 * @param {string} fmt
 * The format string.
 *
 * @param {*}
 * Arguments to be formatted.
 *
 * @returns {int}
 *
 * @example
 * {%
 *   printf("Hello %s\n", "world");  // Hello world
 *   printf("%08x\n", 123);          // 0000007b
 *   printf("%c%c%c\n", 65, 98, 99); // Abc
 *   printf("%g\n", 10 / 3.0);       // 3.33333
 *   printf("%2$d %1$d\n", 12, 34);  // 34 12
 *   printf("%J", [1,2,3]);          // [ 1, 2, 3 ]
 *
 *   printf("%.J", [1,2,3]);
 *   // [
 *   //         1,
 *   //         2,
 *   //         3
 *   // ]
 *
 *   printf("%.2J", [1,2,3]);
 *   // [
 *   //   1,
 *   //   2,
 *   //   3
 *   // ]
 * %}
 */
export function printf(fmt) {};

/**
 * Load and evaluate ucode scripts or shared library extensions.
 *
 * The `require()` function expands each member of the global
 * `REQUIRE_SEARCH_PATH` array to a filesystem path by replacing the `*`
 * placeholder with a slash-separated version of the given dotted module name
 * and subsequently tries to load a file at the resulting location.
 *
 * If a file is found at one of the search path locations, it is compiled and
 * evaluated or loaded via the C runtime's `dlopen()` function, depending on
 * whether the found file is a ucode script or a compiled dynamic library.
 *
 * The resulting program function of the compiled/loaded module is then
 * subsequently executed with the current global environment, without a `this`
 * context and without arguments.
 *
 * Finally, the return value of the invoked program function is returned back
 * by `require()` to the caller.
 *
 * By default, modules are cached in the global `modules` dictionary and
 * subsequent attempts to require the same module will return the cached module
 * dictionary entry without re-evaluating the module.
 *
 * To force reloading a module, the corresponding entry from the global
 * `modules` dictionary can be deleted.
 *
 * To preload a module or to provide a "virtual" module without a corresponding
 * filesystem resource, an entry can be manually added to the global `modules`
 * dictionary.
 *
 * Summarized, the `require()` function can be roughly described by the
 * following code:
 *
 * ```
 * function require(name) {
 *     if (exists(modules, name))
 *         return modules[name];
 *
 *     for (const item in REQUIRE_SEARCH_PATH) {
 *         const modpath = replace(item, '*', replace(name, '.', '/'));
 *         const entryfunc = loadfile(modpath, { raw_mode: true });
 *
 *         if (entryfunc) {
 *             const modval = entryfunc();
 *             modules[name] = modval;
 *
 *             return modval;
 *         }
 *     }
 *
 *     die(`Module ${name} not found`);
 * }
 * ```
 *
 * Due to the fact that `require()` is a runtime operation, module source code
 * is only lazily evaluated/loaded upon invoking the first require invocation,
 * which might lead to situations where errors in module sources are only
 * reported much later throughout the program execution. Unless runtime loading
 * of modules is absolutely required, e.g. to conditionally load extensions, the
 * compile time
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import|`import` syntax}
 * should be preferred.
 *
 * Returns the module value (typically an object) on success.
 *
 * Throws an exception if the module function threw an exception.
 *
 * Throws an exception if no matching module could be found, if the module
 * contains syntax errors or upon other I/O related problems.
 *
 * @function module:core#require
 *
 * @param {string} name
 * The name of the module to require in dotted notation.
 *
 * @returns {*}
 *
 * @example
 * // Require the `example/acme.uc` or `example/acme.so` module
 * const acme = require('example.acme');
 *
 * // Requiring the same name again will yield the cached instance
 * const acme2 = require('example.acme');
 * assert(acme === acme2);
 *
 * // Deleting the module dictionary entry will force a reload
 * delete modules['example.acme'];
 * const acme3 = require('example.acme');
 * assert(acme !== acme3);
 *
 * // Preloading a "virtual" module
 * modules['example.test'] = {
 *   hello: function() { print("This is the example module\n"); }
 * };
 *
 * const test = require('example.test');
 * test.hello();  // will print "This is the example module"
 */
export function require(name) {};

/**
 * Convert the given IP address string to an array of byte values.
 *
 * IPv4 addresses result in arrays of 4 integers while IPv6 ones in arrays
 * containing 16 integers. The resulting array can be turned back into IP
 * address strings using the inverse `arrtoip()` function.
 *
 * Returns an array containing the address byte values.
 * Returns `null` if the given argument is not a string or an invalid IP.
 *
 * @function module:core#iptoarr
 *
 * @param {string} address
 * The IP address string to convert.
 *
 * @returns {*}
 *
 * @example
 * iptoarr("192.168.1.1")              // [ 192, 168, 1, 1 ]
 * iptoarr("fe80::fc54:ff:fe82:abbd")  // [ 254, 128, 0, 0, 0, 0, 0, 0, 252, 84,
 *                                     //   0, 255, 254, 130, 171, 189 ])
 * iptoarr("foo")                      // null (invalid address)
 * iptoarr(123)                        // null (not a string)
 */
export function iptoarr(address) {};

/**
 * Convert the given input array of byte values to an IP address string.
 *
 * Input arrays of length 4 are converted to IPv4 addresses, arrays of length 16
 * to IPv6 ones. All other lengths are rejected. If any array element is not an
 * integer or exceeds the range 0..255 (inclusive), the array is rejected.
 *
 * Returns a string containing the formatted IP address.
 * Returns `null` if the input array was invalid.
 *
 * @function module:core#arrtoip
 *
 * @param {*} arr
 * The byte array to convert into an IP address string.
 *
 * @returns {?string}
 *
 * @example
 * arrtoip([ 192, 168, 1, 1 ])   // "192.168.1.1"
 * arrtoip([ 254, 128, 0, 0, 0, 0, 0, 0, 252, 84, 0, 255, 254, 130, 171, 189 ])
 *                               // "fe80::fc54:ff:fe82:abbd"
 * arrtoip([ 1, 2, 3])           // null (invalid length)
 * arrtoip([ 1, "2", -5, 300 ])  // null (invalid values)
 * arrtoip("123")                // null (not an array)
 */
export function arrtoip(arr) {};

/**
 * Match the given string against the regular expression pattern specified as
 * the second argument.
 *
 * If the passed regular expression uses the `g` flag, the return value will be
 * an array of arrays describing all found occurrences within the string.
 *
 * Without the `g` modifier, an array describing the first match is returned.
 *
 * Returns `null` if the pattern was not found within the given string.
 *
 * @function module:core#match
 *
 * @param {string} str
 * The string to be matched against the pattern.
 *
 * @param {*} pattern
 * The regular expression pattern.
 *
 * @returns {*}
 *
 * @example
 * match("foobarbaz", /b.(.)/)   // ["bar", "r"]
 * match("foobarbaz", /b.(.)/g)  // [["bar", "r"], ["baz", "z"]]
 */
export function match(str, pattern) {};

/**
 * Replace occurrences of the specified pattern in the string passed as the
 * first argument.
 *
 * - The pattern value may be either a regular expression or a plain string.
 * - The replace value may be a function which is invoked for each found pattern
 *   or any other value which is converted into a plain string and used as
 *   replacement.
 * - When an optional limit is specified, substitutions are performed only that
 *   many times.
 * - If the pattern is a regular expression and not using the `g` flag, then
 *   only the first occurrence in the string is replaced.
 * - If the `g` flag is used or if the pattern is not a regular expression, all
 *   occurrences are replaced.
 * - If the replace value is a callback function, it is invoked with the found
 *   substring as the first and any capture group values as subsequent
 *   parameters.
 * - If the replace value is a string, specific substrings are substituted
 *   before it is inserted into the result.
 *
 * Returns a new string with the pattern replaced.
 *
 * @function module:core#replace
 *
 * @param {string} str
 * The string in which to replace occurrences.
 *
 * @param {*} pattern
 * The pattern to be replaced.
 *
 * @param {*} replace
 * The replacement value.
 *
 * @param {int} [limit]
 * The optional limit of substitutions.
 *
 * @returns {string}
 *
 * @example
 * replace("barfoobaz", /(f)(o+)/g, "[$$|$`|$&|$'|$1|$2|$3]")  // bar[$|bar|foo|baz|f|oo|$3]baz
 * replace("barfoobaz", /(f)(o+)/g, uc)                        // barFOObaz
 * replace("barfoobaz", "a", "X")                              // bXrfoobXz
 * replace("barfoobaz", /(.)(.)(.)/g, function(m, c1, c2, c3) {
 *     return c3 + c2 + c1;
 * })                                                          // raboofzab
 * replace("aaaaa", "a", "x", 3)                               // xxxaa
 * replace("foo bar baz", /[ao]/g, "x", 3)                     // fxx bxr baz
 */
export function replace(str, pattern, replace, limit) {};

/**
 * Parse the given string or resource as JSON and return the resulting value.
 *
 * If the input argument is a plain string, it is directly parsed as JSON.
 *
 * If an array, object or resource value is given, this function will attempt to
 * invoke a `read()` method on it to read chunks of input text to incrementally
 * parse as JSON data. Reading will stop if the object's `read()` method returns
 * either `null` or an empty string.
 *
 * Throws an exception on parse errors, trailing garbage, or premature EOF.
 *
 * Returns the parsed JSON data.
 *
 * @function module:core#json
 *
 * @param {string} str_or_resource
 * The string or resource object to be parsed as JSON.
 *
 * @returns {*}
 *
 * @example
 * json('{"a":true, "b":123}')   // { "a": true, "b": 123 }
 * json('[1,2,')                 // Throws an exception
 *
 * import { open } from 'fs';
 * let fd = open('example.json', 'r');
 * json(fd);                     // will keep invoking `fd.read()` until EOF and
 *                               // incrementally parse each read chunk.
 *
 * let x = proto(
 *     [ '{"foo":', 'true, ', '"bar":', 'false}' ],
 *     { read: function() { return shift(this) } }
 * );
 * json(x);                      // will keep invoking `x.read()` until array
 *                               // is empty incrementally parse each piece
 *
 */
export function json(str_or_resource) {};

/**
 * Evaluate and include the file at the given path and optionally override the
 * execution scope with the given scope object.
 *
 * By default, the file is executed within the same scope as the calling
 * `include()`, but by passing an object as the second argument, it is possible
 * to extend the scope available to the included file.
 *
 * This is useful to supply additional properties as global variables to the
 * included code. To sandbox included code, that is giving it only access to
 * explicitly provided properties, the `proto()` function can be used to create
 * a scope object with an empty prototype.
 *
 * @function module:core#include
 *
 * @param {string} path
 * The path to the file to be included.
 *
 * @param {*} [scope]
 * The optional scope object to override the execution scope.
 *
 * @example
 * // Load and execute "foo.uc" immediately
 * include("./foo.uc")
 *
 * // Execute the "supplemental.ucode" in an extended scope and make the "foo"
 * // and "bar" properties available as global variables
 * include("./supplemental.uc", {
 *   foo: true,
 *   bar: 123
 * })
 *
 * // Execute the "untrusted.ucode" in a sandboxed scope and make the "foo" and
 * // "bar" variables as well as the "print" function available to it.
 * // By assigning an empty prototype object to the scope, included code has no
 * // access to other global values anymore.
 * include("./untrusted.uc", proto({
 *   foo: true,
 *   bar: 123,
 *   print: print
 * }, {}))
 */
export function include(path, scope) {};

/**
 * When invoked with a string value as the first argument, the function acts
 * like `include()` but captures the output of the included file as a string and
 * returns the captured contents.
 *
 * The second argument is treated as the scope.
 *
 * When invoked with a function value as the first argument, `render()` calls
 * the given function and passes all subsequent arguments to it.
 *
 * Any output produced by the called function is captured and returned as a
 * string. The return value of the called function is discarded.
 *
 * @function module:core#render
 *
 * @param {*} path_or_func
 * The path to the file or the function to be rendered.
 *
 * @param {*} [scope_or_fnarg1]
 * The optional scope or the first argument for the function.
 *
 * @param {*} [fnarg2]
 * The second argument for the function.
 *
 * @param {*} [fnargN]
 * Additional arguments for the function.
 *
 * @returns {string}
 *
 * @example
 * // Renders template file with given scope and captures the output as a string
 * const output = render("./template.uc", { foo: "bar" });
 *
 * // Calls a function, captures the output, and returns it as a string
 * const result = render(function(name) {
 *     printf("Hello, %s!\n", name);
 * }, "Alice");
 */
export function render(path_or_func, scope_or_fnarg1, fnarg2, fnargN) {};

/**
 * Print any of the given values to stderr. Arrays and objects are converted to
 * their JSON representation.
 *
 * Returns the amount of bytes printed.
 *
 * @function module:core#warn
 *
 * @param {*} x
 * The values to be printed.
 *
 * @returns {int}
 *
 * @example
 * warn("Hello", "world");  // Print "Helloworld" to stderr
 * warn({ key: "value" });  // Print JSON representation of the object to stderr
 */
export function warn(x) {};

/**
 * Executes the given command, waits for completion, and returns the resulting
 * exit code.
 *
 * The command argument may be either a string, in which case it is passed to
 * `/bin/sh -c`, or an array, which is directly converted into an `execv()`
 * argument vector.
 *
 *  - If the program terminated normally, a positive integer holding the
 *    program's `exit()` code is returned.
 *  - If the program was terminated by an uncaught signal, a negative signal
 *    number is returned.
 *  - If the optional timeout argument is specified, the program is terminated
 *    by `SIGKILL` after that many milliseconds if it doesn't complete within
 *    the timeout.
 *
 * Omitting the timeout argument or passing `0` disables the command timeout.
 *
 * Returns the program exit code.
 *
 * @function module:core#system
 *
 * @param {*} command
 * The command to be executed.
 *
 * @param {int} [timeout]
 * The optional timeout in milliseconds.
 *
 * @returns {int}
 *
 * @example
 * // Execute through `/bin/sh`
 * // prints "Hello world" to stdout and returns 3
 * system("echo 'Hello world' && exit 3");
 *
 * // Execute argument vector
 * // prints the UNIX timestamp to stdout and returns 0
 * system(["/usr/bin/date", "+%s"]);
 *
 * // Apply a timeout
 * // returns -9
 * system("sleep 3 && echo 'Success'", 1000);
 */
export function system(command, timeout) {};

/**
 * Enables or disables VM opcode tracing.
 *
 * When invoked with a positive non-zero level, opcode tracing is enabled and
 * debug information is printed to stderr as the program is executed.
 *
 * Invoking `trace()` with zero as an argument turns off opcode tracing.
 *
 * @function module:core#trace
 *
 * @param {int} level
 * The level of tracing to enable.
 *
 * @example
 * trace(1);   // Enables opcode tracing
 * trace(0);   // Disables opcode tracing
 */
export function trace(level) {};

/**
 * Get or set the prototype of the array or object value `val`.
 *
 * When invoked without a second argument, the function returns the current
 * prototype of the value in `val` or `null` if there is no prototype or if the
 * given value is neither an object nor an array.
 *
 * When invoked with a second prototype argument, the given `proto` value is set
 * as the prototype on the array or object in `val`.
 *
 * Throws an exception if the given prototype value is not an object.
 *
 * @function module:core#proto
 *
 * @param {*} val
 * The array or object value.
 *
 * @param {*} [proto]
 * The optional prototype object.
 *
 * @returns {*}
 *
 * @example
 * const arr = [1, 2, 3];
 * proto(arr);                 // Returns the current prototype of the array (null by default)
 * proto(arr, { foo: true });  // Sets the given object as the prototype of the array
 */
export function proto(val, proto) {};

/**
 * Pause execution for the given amount of milliseconds.
 *
 * @function module:core#sleep
 *
 * @param {int} milliseconds
 * The amount of milliseconds to sleep.
 *
 * @returns {boolean}
 *
 * @example
 * sleep(1000);                          // Sleeps for 1 second
 */
export function sleep(milliseconds) {};

/**
 * Raise an exception with the given message parameter when the value in `cond`
 * is not truthy.
 *
 * When `message` is omitted, the default value is `Assertion failed`.
 *
 * @function module:core#assert
 *
 * @param {*} cond
 * The value to check for truthiness.
 *
 * @param {string} [message]
 * The message to include in the exception.
 *
 * @throws {Error} When the condition is falsy.
 *
 * @example
 * assert(true, "This is true");  // No exception is raised
 * assert(false);                 // Exception is raised with the default message "Assertion failed"
 */
export function assert(cond, message) {};

/**
 * Construct a regular expression instance from the given `source` pattern
 * string and any flags optionally specified by the `flags` argument.
 *
 * Supported flags:
 *  - `i`: Case-insensitive matching
 *  - `s`: DotAll - makes `.` match newline characters (default: `.` does not match newlines)
 *  - `g`: Global matching (for match() function)
 *
 *  - Throws a type error exception if `flags` is not a string or if the string
 *    in `flags` contains unrecognized regular expression flag characters.
 *  - Throws a syntax error when the pattern in `source` cannot be compiled into
 *    a valid regular expression.
 *
 * Returns the compiled regular expression value.
 *
 * @function module:core#regexp
 *
 * @param {string} source
 * The pattern string.
 *
 * @param {string} [flags]
 * The optional regular expression flags (i=ignore case, s=dotAll, g=global).
 *
 * @returns {*}
 *
 * @example
 * regexp('foo.*bar', 'is');   // equivalent to /foo.*bar/is
 * regexp('foo.*bar', 'x');    // throws a "Type error: Unrecognized flag character 'x'" exception
 * regexp('foo.*(');           // throws a "Syntax error: Unmatched ( or \( exception"
 *
 * @example
 * // Without 's' flag, . does not match newlines
 * match("hello\nworld", /hello.world/);    // null
 *
 * @example
 * // With 's' flag, . matches newlines (dotAll behavior)
 * match("hello\nworld", /hello.world/s);   // matches
 */
export function regexp(source, flags) {};

/**
 * Match the given subject against the supplied wildcard (file glob) pattern.
 *
 *  - If a truthy value is supplied as the third argument, case-insensitive
 *    matching is performed.
 *  - If a non-string value is supplied as the subject, it is converted into a
 *    string before being matched.
 *
 * Returns `true` when the value matched the given pattern, otherwise `false`.
 *
 * @function module:core#wildcard
 *
 * @param {*} subject
 * The subject to match against the wildcard pattern.
 *
 * @param {string} pattern
 * The wildcard pattern.
 *
 * @param {boolean} [nocase]
 * Whether to perform case-insensitive matching.
 *
 * @returns {boolean}
 *
 * @example
 * wildcard("file.txt", "*.txt");        // Returns true
 * wildcard("file.txt", "*.TXT", true);  // Returns true (case-insensitive match)
 * wildcard("file.txt", "*.jpg");        // Returns false
 */
export function wildcard(subject, pattern, nocase) {};

/**
 * Determine the path of the source file currently being executed by ucode.
 *
 * @function module:core#sourcepath
 *
 * @param {int} [depth=0]
 * The depth to walk up the call stack.
 *
 * @param {boolean} [dironly]
 * Whether to return only the directory portion of the source file path.
 *
 * @returns {?string}
 *
 * @example
 * sourcepath();         // Returns the path of the currently executed file
 * sourcepath(1);        // Returns the path of the parent source file
 * sourcepath(2, true);  // Returns the directory portion of the grandparent source file path
 */
export function sourcepath(depth, dironly) {};

/**
 * Return the smallest value among all parameters passed to the function.
 *
 * @function module:core#min
 *
 * @param {*} [val]
 * The values to compare.
 *
 * @returns {*}
 *
 * @example
 * min(5, 2.1, 3, "abc", 0.3);            // Returns 0.3
 * min(1, "abc");                         // Returns 1
 * min("1", "abc");                       // Returns "1"
 * min("def", "abc", "ghi");              // Returns "abc"
 * min(true, false);                      // Returns false
 */
export function min(val) {};

/**
 * Return the largest value among all parameters passed to the function.
 *
 * @function module:core#max
 *
 * @param {*} [val]
 * The values to compare.
 *
 * @returns {*}
 *
 * @example
 * max(5, 2.1, 3, "abc", 0.3);            // Returns 5
 * max(1, "abc");                         // Returns 1 (!)
 * max("1", "abc");                       // Returns "abc"
 * max("def", "abc", "ghi");              // Returns "ghi"
 * max(true, false);                      // Returns true
 */
export function max(val) {};

/**
 * Decodes the given base64 encoded string and returns the decoded result.
 *
 *  - If non-whitespace, non-base64 characters are encountered, if invalid
 *    padding or trailing garbage is found, the function returns `null`.
 *  - If a non-string argument is given, the function returns `null`.
 *
 * @function module:core#b64dec
 *
 * @param {string} str
 * The base64 encoded string to decode.
 *
 * @returns {?string}
 *
 * @example
 * b64dec("VGhpcyBpcyBhIHRlc3Q=");         // Returns "This is a test"
 * b64dec(123);                           // Returns null
 * b64dec("XXX");                         // Returns null
 */
export function b64dec(str) {};

/**
 * Encodes the given string into base64 and returns the resulting string.
 *
 *  - If a non-string argument is given, the function returns `null`.
 *
 * @function module:core#b64enc
 *
 * @param {string} str
 * The string to encode.
 *
 * @returns {?string}
 *
 * @example
 * b64enc("This is a test");  // Returns "VGhpcyBpcyBhIHRlc3Q="
 * b64enc(123);               // Returns null
 */
export function b64enc(str) {};

/**
 * Returns a new array containing all unique values of the given input array.
 *
 *  - The order is preserved, and subsequent duplicate values are skipped.
 *  - If a non-array argument is given, the function returns `null`.
 *
 * @function module:core#uniq
 *
 * @param {*} array
 * The input array.
 *
 * @returns {*}
 *
 * @example
 * uniq([1, true, "foo", 2, true, "bar", "foo"]);       // Returns [1, true, "foo", 2, "bar"]
 * uniq("test");                                        // Returns null
 */
export function uniq(array) {};

/**
 * Return the given epoch timestamp (or now, if omitted) as a dictionary
 * containing broken-down date and time information according to the local
 * system timezone.
 *
 * See {@link module:core.TimeSpec|TimeSpec} for a description of the fields.
 *
 * Note that in contrast to the underlying `localtime(3)` C library function,
 * the values for `mon`, `wday`, and `yday` are 1-based, and the `year` is
 * 1900-based.
 *
 * @function module:core#localtime
 *
 * @param {int} [epoch]
 * The epoch timestamp.
 *
 * @returns {module:core.TimeSpec}
 *
 * @example
 * localtime(1647953502);
 * // Returns:
 * // {
 * //     sec: 42,
 * //     min: 51,
 * //     hour: 13,
 * //     mday: 22,
 * //     mon: 3,
 * //     year: 2022,
 * //     wday: 2,
 * //     yday: 81,
 * //     isdst: 0
 * // }
 */
export function localtime(epoch) {};

/**
 * Like `localtime()` but interpreting the given epoch value as UTC time.
 *
 * See {@link module:core#localtime|localtime()} for details on the return value.
 *
 * @function module:core#gmtime
 *
 * @param {int} [epoch]
 * The epoch timestamp.
 *
 * @returns {module:core.TimeSpec}
 *
 * @example
 * gmtime(1647953502);
 * // Returns:
 * // {
 * //     sec: 42,
 * //     min: 51,
 * //     hour: 13,
 * //     mday: 22,
 * //     mon: 3,
 * //     year: 2022,
 * //     wday: 2,
 * //     yday: 81,
 * //     isdst: 0
 * // }
 */
export function gmtime(epoch) {};

/**
 * Performs the inverse operation of {@link module:core#localtime|localtime()}
 * by taking a broken-down date and time dictionary and transforming it into an
 * epoch value according to the local system timezone.
 *
 * The `wday` and `yday` fields of the given date time specification are
 * ignored. Field values outside of their valid range are internally normalized,
 * e.g. October 40th is interpreted as November 9th.
 *
 * Returns the resulting epoch value or null if the input date time dictionary
 * was invalid or if the date time specification cannot be represented as epoch
 * value.
 *
 * @function module:core#timelocal
 *
 * @param {module:core.TimeSpec} datetimespec
 * The broken-down date and time dictionary.
 *
 * @returns {?int}
 *
 * @example
 * timelocal({ "sec": 42, "min": 51, "hour": 13, "mday": 22, "mon": 3, "year": 2022, "isdst": 0 });
 * // Returns 1647953502
 */
export function timelocal(datetimespec) {};

/**
 * Like `timelocal()` but interpreting the given date time specification as UTC
 * time.
 *
 * See {@link module:core#timelocal|timelocal()} for details.
 *
 * @function module:core#timegm
 *
 * @param {module:core.TimeSpec} datetimespec
 * The broken-down date and time dictionary.
 *
 * @returns {?int}
 *
 * @example
 * timegm({ "sec": 42, "min": 51, "hour": 13, "mday": 22, "mon": 3, "year": 2022, "isdst": 0 });
 * // Returns 1647953502
 */
export function timegm(datetimespec) {};

/**
 * Reads the current second and microsecond value of the system clock.
 *
 * By default, the realtime clock is queried which might skew forwards or
 * backwards due to NTP changes, system sleep modes etc. If a truthy value is
 * passed as argument, the monotonic system clock is queried instead, which will
 * return the monotonically increasing time since some arbitrary point in the
 * past (usually the system boot time).
 *
 * Returns a two element array containing the full seconds as the first element
 * and the nanosecond fraction as the second element.
 *
 * Returns `null` if a monotonic clock value is requested and the system does
 * not implement this clock type.
 *
 * @function module:core#clock
 *
 * @param {boolean} [monotonic]
 * Whether to query the monotonic system clock.
 *
 * @returns {*}
 *
 * @example
 * clock();        // [ 1647954926, 798269464 ]
 * clock(true);    // [ 474751, 527959975 ]
 */
export function clock(monotonic) {};

/**
 * Encodes the given byte string into a hexadecimal digit string, converting
 * the input value to a string if needed.
 *
 * @function module:core#hexenc
 *
 * @param {string} val
 * The byte string to encode.
 *
 * @returns {string}
 *
 * @example
 * hexenc("Hello world!\n");   // "48656c6c6f20776f726c64210a"
 */
export function hexenc(val) {};

/**
 * Decodes the given hexadecimal digit string into a byte string, optionally
 * skipping specified characters.
 *
 * If the characters to skip are not specified, a default of `" \t\n"` is used.
 *
 * Returns null if the input string contains invalid characters or an uneven
 * amount of hex digits.
 *
 * Returns the decoded byte string on success.
 *
 * @function module:core#hexdec
 *
 * @param {string} hexstring
 * The hexadecimal digit string to decode.
 *
 * @param {string} [skipchars]
 * The characters to skip during decoding.
 *
 * @returns {?string}
 *
 * @example
 * hexdec("48656c6c6f20776f726c64210a");  // "Hello world!\n"
 * hexdec("44:55:66:77:33:44", ":");      // "DUfw3D"
 */
export function hexdec(hexstring, skipchars) {};

/**
 * Interacts with the mark and sweep garbage collector of the running ucode
 * virtual machine.
 *
 * Depending on the given `operation` string argument, the meaning of `argument`
 * and the function return value differs.
 *
 * The following operations are defined:
 *
 * - `collect` - Perform a complete garbage collection cycle, returns `true`.
 * - `start` - (Re-)start periodic garbage collection, `argument` is an optional
 *             integer in the range `1..65535` specifying the interval.
 *             Defaults to `1000` if omitted. Returns `true` if the periodic GC
 *             was previously stopped and is now started or if the interval
 *             changed. Returns `false` otherwise.
 * - `stop` - Stop periodic garbage collection. Returns `true` if the periodic
 *            GC was previously started and is now stopped, `false` otherwise.
 * - `count` - Count the amount of active complex object references in the VM
 *             context, returns the counted amount.
 *
 * If the `operation` argument is omitted, the default is `collect`.
 *
 * @function module:core#gc
 *
 * @param {string} [operation]
 * The operation to perform.
 *
 * @param {*} [argument]
 * The argument for the operation.
 *
 * @returns {?boolean|?int}
 *
 * @example
 * gc();         // true
 * gc("start");  // true
 * gc("count");  // 42
 */
export function gc(operation, argument) {};

/**
 * Compiles the given code string into a ucode program and returns the resulting
 * program entry function.
 *
 * The optional `options` dictionary overrides parse and compile options.
 *
 *  - If a non-string `code` argument is given, it is implicitly converted to a
 *    string value first.
 *  - If `options` is omitted or a non-object value, the compile options of the
 *    running ucode program are reused.
 *
 * See {@link module:core.ParseConfig|ParseConfig} for known keys within the
 * `options` object. Unrecognized keys are ignored, unspecified options default
 * to those of the running program.
 *
 * Returns the compiled program entry function.
 *
 * Throws an exception on compilation errors.
 *
 * @function module:core#loadstring
 *
 * @param {string} code
 * The code string to compile.
 *
 * @param {module:core.ParseConfig} [options]
 * The options for compilation.
 *
 * @returns {*}
 *
 * @example
 * let fn1 = loadstring("Hello, {{ name }}", { raw_mode: false });
 *
 * global.name = "Alice";
 * fn1(); // prints `Hello, Alice`
 *
 *
 * let fn2 = loadstring("return 1 + 2;", { raw_mode: true });
 * fn2(); // 3
 */
export function loadstring(code, options) {};

/**
 * Compiles the given file into a ucode program and returns the resulting
 * program entry function.
 *
 * See {@link module:core#loadstring|`loadstring()`} for details.
 *
 * Returns the compiled program entry function.
 *
 * Throws an exception on compilation or file I/O errors.
 *
 * @function module:core#loadfile
 *
 * @param {string} path
 * The path of the file to compile.
 *
 * @param {module:core.ParseConfig} [options]
 * The options for compilation.
 *
 * @returns {*}
 *
 * @example
 * loadfile("./templates/example.uc");  // function main() { ... }
 */
export function loadfile(path, options) {};

/**
 * Calls the given function value with a modified environment.
 *
 * The given `ctx` argument is used as `this` context for the invoked function
 * and the given `scope` value as global environment. Any further arguments are
 * passed to the invoked function as-is.
 *
 * When `ctx` is omitted or `null`, the function will get invoked with `this`
 * being `null`.
 *
 * When `scope` is omitted or `null`, the function will get executed with the
 * current global environment of the running program. When `scope` is set to a
 * dictionary, the dictionary is used as global function environment.
 *
 * When the `scope` dictionary has no prototype, the current global environment
 * will be set as prototype, means the scope will inherit from it.
 *
 * When a scope prototype is set, it is kept. This allows passing an isolated
 * (sandboxed) function scope without access to the global environment.
 *
 * Any further argument is forwarded as-is to the invoked function as function
 * call argument.
 *
 * Returns `null` if the given function value `fn` is not callable.
 *
 * Returns the return value of the invoked function in all other cases.
 *
 * Forwards exceptions thrown by the invoked function.
 *
 * @function module:core#call
 *
 * @param {*} fn
 * Function value to call.
 *
 * @param {*} [ctx=null]
 * `this` context for the invoked function.
 *
 * @param {*} [scope=null]
 * Global environment for the invoked function.
 *
 * @param {*} [arg]
 * Additional arguments to pass to the invoked function.
 *
 * @returns {*}
 *
 * @example
 * // Override this context
 * call(function() { printf("%J\n", this) });            // null
 * call(function() { printf("%J\n", this) }, null);      // null
 * call(function() { printf("%J\n", this) }, { x: 1 });  // { "x": 1 }
 * call(function() { printf("%J\n", this) }, { x: 2 });  // { "x": 2 }
 *
 * // Run with default scope
 * global.a = 1;
 * call(function() { printf("%J\n", a) });                  // 1
 *
 * // Override scope, inherit from current global scope (implicit)
 * call(function() { printf("%J\n", a) }, null, { a: 2 });  // 2
 *
 * // Override scope, inherit from current global scope (explicit)
 * call(function() { printf("%J\n", a) }, null,
 *         proto({ a: 2 }, global));                        // 2
 *
 * // Override scope, don't inherit (pass `printf()` but not `a`)
 * call(function() { printf("%J\n", a) }, null,
 *         proto({}, { printf }));                          // null
 *
 * // Forward arguments
 * x = call((x, y, z) => x * y * z, null, null, 2, 3, 4);   // x = 24
 */
export function call(fn, ctx, scope, arg) {};

/**
 * Set or query process signal handler function.
 *
 * When invoked with two arguments, a signal specification and a signal handler
 * value, this function configures a new process signal handler.
 *
 * When invoked with one argument, a signal specification, this function returns
 * the currently configured handler for the given signal.
 *
 * The signal specification might either be an integer signal number or a string
 * value containing a signal name (with or without "SIG" prefix). Signal names
 * are treated case-insensitively.
 *
 * The signal handler might be either a callable function value or one of the
 * two special string values `"ignore"` and `"default"`. Passing `"ignore"` will
 * mask the given process signal while `"default"` will restore the operating
 * systems default behaviour for the given signal.
 *
 * In case a callable handler function is provided, it is invoked at the
 * earliest  opportunity after receiving the corresponding signal from the
 * operating system. The invoked function will receive a single argument, the
 * number of the signal it is invoked for.
 *
 * Note that within the ucode VM, process signals are not immediately delivered,
 * instead the VM keeps track of received signals and delivers them to the ucode
 * script environment at the next opportunity, usually before executing the next
 * byte code instruction. This means that if a signal is received while
 * performing a computationally expensive operation in C mode, such as a complex
 * regexp match, the corresponding ucode signal handler will only be invoked
 * after that operation concluded and control flow returns to the VM.
 *
 * Returns the signal handler function or one of the special values `"ignore"`
 * or `"default"` corresponding to the given signal specification.
 *
 * Returns `null` if an invalid signal spec or signal handler was provided.
 *
 * Returns `null` if changing the signal action failed, e.g. due to insufficient
 * permission, or when attempting to ignore a non-ignorable signal.
 *
 * @function module:core#signal
 *
 * @param {int|string} signal
 * The signal to query/set handler for.
 *
 * @param {*} [handler]
 * The signal handler to install for the given signal.
 *
 * @returns {*}
 *
 * @example
 * // Ignore signals
 * signal('INT', 'ignore');      // "ignore"
 * signal('SIGINT', 'ignore');   // "ignore" (equivalent to 'INT')
 * signal('sigterm', 'ignore');  // "ignore" (signal names are case insensitive)
 * signal(9, 'ignore');          // null (SIGKILL cannot be ignored)
 *
 * // Restore signal default behavior
 * signal('INT', 'default');     // "default"
 * signal('foobar', 'default');  // null (unknown signal name)
 * signal(-313, 'default');      // null (invalid signal number)
 *
 * // Set custom handler function
 * function intexit(signo) {
 *   printf("I received signal number %d\n", signo);
 *   exit(1);
 * }
 *
 * signal('SIGINT', intexit);    // returns intexit
 * signal('SIGINT') == intexit;  // true
 */
export function signal(signal, handler) {};

