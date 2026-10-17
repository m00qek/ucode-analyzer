// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # Mathematical Functions
 *
 * The `math` module bundles various mathematical and trigonometrical functions.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { pow, rand } from 'math';
 *
 *   let x = pow(2, 5);
 *   let y = rand();
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as math from 'math';
 *
 *   let x = math.pow(2, 5);
 *   let y = math.rand();
 *   ```
 *
 * Additionally, the math module namespace may also be imported by invoking the
 * `ucode` interpreter with the `-lmath` switch.
 *
 * @module math
 */

/**
 * Returns the absolute value of the given numeric value.
 *
 * @function module:math#abs
 *
 * @param {int|double} number
 * The number to return the absolute value for.
 *
 * @returns {float}
 * Returns the absolute value or `NaN` if the given argument could
 * not be converted to a number.
 */
export function abs(number) {};

/**
 * Calculates the principal value of the arc tangent of `y`/`x`,
 * using the signs of the two arguments to determine the quadrant
 * of the result.
 *
 * On success, this function returns the principal value of the arc
 * tangent of `y`/`x` in radians; the return value is in the range [-pi, pi].
 *
 * When either `x` or `y` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#atan2
 *
 * @param {int|double} y
 * The `y` value.
 *
 * @param {int|double} x
 * The `x` value.
 *
 * @returns {float}
 */
export function atan2(y, x) {};

/**
 * Calculates the cosine of `x`, where `x` is given in radians.
 *
 * Returns the resulting cosine value.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#cos
 *
 * @param {float} x
 * Radians value to calculate cosine for.
 *
 * @returns {float}
 */
export function cos(x) {};

/**
 * Calculates the value of `e` (the base of natural logarithms)
 * raised to the power of `x`.
 *
 * On success, returns the exponential value of `x`.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#exp
 *
 * @param {float} x
 * Power to raise `e` to.
 *
 * @returns {float}
 */
export function exp(x) {};

/**
 * Calculates the natural logarithm of `x`.
 *
 * On success, returns the natural logarithm of `x`.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#log
 *
 * @param {float} x
 * Value to calculate natural logarithm of.
 *
 * @returns {float}
 */
export function log(x) {};

/**
 * Calculates the sine of `x`, where `x` is given in radians.
 *
 * Returns the resulting sine value.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#sin
 *
 * @param {float} x
 * Radians value to calculate sine for.
 *
 * @returns {float}
 */
export function sin(x) {};

/**
 * Calculates the non-negative square root of `x`.
 *
 * Returns the resulting square root value.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#sqrt
 *
 * @param {float} x
 * Value to calculate square root for.
 *
 * @returns {float}
 */
export function sqrt(x) {};

/**
 * Calculates the value of `x` raised to the power of `y`.
 *
 * On success, returns the value of `x` raised to the power of `y`.
 *
 * Returns `NaN` if either the `x` or `y` value can't be converted to a number.
 *
 * @function module:math#pow
 *
 * @param {float} x
 * The base value.
 *
 * @param {float} y
 * The power value.
 *
 * @returns {float}
 */
export function pow(x, y) {};

/**
 * Depending on the arguments, it produces a pseudo-random positive integer,
 * or a pseudo-random number in a supplied range.
 *
 * Without arguments it returns the calculated pseudo-random value. The value
 * is within the range `0` to `RAND_MAX` inclusive where `RAND_MAX` is a platform
 * specific value guaranteed to be at least `32767`.
 *
 * With 2 arguments `a, b` it returns a number in the range `a` to `b` inclusive.
 * With a single argument `a` it returns a number in the range `0` to `a` inclusive.
 *
 * @function module:math#rand
 *
 * @param {int} [a]
 * End of the desired range.
 *
 * @param {int} [b]
 * The other end of the desired range.
 *
 * @returns {int}
 */
export function rand(a, b) {};

/**
 * Seeds the pseudo-random number generator.
 *
 * @function module:math#srand
 *
 * @param {int} seed
 * The seed value.
 */
export function srand(seed) {};

/**
 * Tests whether `x` is a `NaN` double.
 *
 * Returns `true` if the value is `NaN`, otherwise false.
 *
 * @function module:math#isnan
 *
 * @param {float} x
 * The value to test.
 *
 * @returns {boolean}
 */
export function isnan(x) {};
