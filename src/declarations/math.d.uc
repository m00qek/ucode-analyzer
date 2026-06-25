// Source: https://github.com/jow-/ucode @ fecacb8188c6a4f38d97434160b979d73e898b24
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
 * It should be noted that when the ucode interpreter is run as `-p "..."`,
 * values involving Infinity are returned as the max double precision value
 * +/-1e309 (JSON), whereas when run as `-e "print(...)"` Infinity is
 * represented by the string `Infinity`. The boolean check `isinf()` is
 * available to determine Infinity values.
 *
 * @module math
 */

/**
 * Returns the absolute value of the given numeric value.
 *
 * @function module:math#abs
 *
 * @param {*} number
 * The number to return the absolute value for.
 *
 * @returns {float}
 * Returns the absolute value or `NaN` if the given argument could
 * not be converted to a number.
 */
export function abs(number) {};

/**
 * Calculates the arc cosine of `x`.
 *
 * On success, this function returns the principal value of the arc
 * cosine of `x` in radians; the return value is in the range [pi, 0].
 *
 *  - If `x` is -1, pi is returned.
 *  - If `x` is  0, pi/2 is returned.
 *  - If `x` is +1, 0 is returned.
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#acos
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * acos(-1); // 3.1415926535898 i.e. pi
 * acos(0);  // 1.5707963267949 i.e. pi/2
 * acos(1);  // 0.0 i.e. 0 pi
 */
export function acos(x) {};

/**
 * Calculates the arc sine of `x`.
 *
 * On success, this function returns the principal value of the arc
 * sine of `x` in radians; the return value is in the range [-pi/2, pi/2].
 *
 *  - If `x` is +0 (-0), 0 is returned.
 *  - If `x` is +1 (-1), pi/2 (-pi/2) is returned.
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#asin
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * asin(-1); // -1.5707963267949 i.e. -pi/2
 * asin(0);  // 0.0 i.e. 0 pi
 * asin(1);  // 1.5707963267949 i.e. pi/2
 */
export function asin(x) {};

/**
 * Calculates the arc tangent of `x`.
 *
 * On success, this function returns the principal value of the arc
 * tangent of `x` in radians; the return value is in the range [-pi/2, pi/2].
 *
 *  - If `x` is +0 (-0), 0 is returned.
 *  - As `x` tends toward +Infinity (-Infinity), the return value asymptotically
 * converges toward pi/2 (-pi/2).
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#atan
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * atan(-100000); // -1.5707863267949 i.e. ~ -pi/2
 * atan(0);       // 0.0 i.e. 0 pi
 * atan(100000);  // 1.5707863267949 i.e. ~ pi/2
 */
export function atan(x) {};

/**
 * Calculates the hyperbolic cosine of `x`.
 *
 * On success, this function returns the principal value of the hyperbolic
 * cosine of `x`; the return value is in the range [Infinity, 1].
 * 
 * The relationship is: cosh = `((e^x) + (e^-x)) / 2`.
 *
 *  - As `x` decreases below -1, the return value exponentiates toward Infinity.
 *  - If `x` is  0, 1 is returned.
 *  - As `x` increases above +1, the return value exponentiates toward Infinity.
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#cosh
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * cosh(-10); // 11013.232920103
 * cosh(-1);  // 1.5430806348152
 * cosh(0);   // 1.0
 * cosh(1);   // 1.5430806348152
 * cosh(10);  // 11013.232920103
 */
export function cosh(x) {};

/**
 * Calculates the hyperbolic sine of `x`.
 *
 * On success, this function returns the principal value of the hyperbolic
 * sine of `x`; the return value is in the range [-Infinity, Infinity].
 *  
 * The relationship is: sinh = `((e^x) - (e^-x)) / 2`.
 *
 *  - As `x` decreases below -1, the return value exponentiates toward -Infinity.
 *  - If `x` is  0, 0 is returned.
 *  - As `x` increases above +1, the return value exponentiates toward Infinity.
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#sinh
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * sinh(-10); // -11013.232920103
 * sinh(-1);  // -1.1752011936438
 * sinh(0);   // 0.0
 * sinh(1);   // 1.1752011936438
 * sinh(10);  // 11013.232920103
 */
export function sinh(x) {};

/**
 * Calculates the hyperbolic tangent of `x`.
 *
 * On success, this function returns the principal value of the hyperbolic
 * tangent of `x`; the return value is in the range [-1, 1].
 *
 * The relationship is: tanh = `((e^x) - (e^-x)) / ((e^x) + (e^-x))`, or
 * tanh = `sinh(x) / cosh(x)`.
 *
 *  - As `x` decreases below -1, the return value asymptotically expands
 * toward -1.
 *  - If `x` is  0, 0 is returned.
 *  - As `x` increases above +1, the return value asymptotically expands
 * toward 1.
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#tanh
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 * @example
 * atan(-100); // -1.0
 * atan(-10);  // -0.99999999587769
 * atan(0);    // 0.0
 * atan(10);   // 0.99999999587769
 * atan(100);  // 1.0
 */
export function tanh(x) {};

/**
 * Calculates the principal value of the arc tangent of `y`/`x`,
 * using the signs of the two arguments to determine the quadrant
 * of the result.
 *
 * On success, this function returns the principal value of the arc
 * tangent of `y`/`x` in radians; the return value is in the range [-pi, pi].
 *
 *  - If `y` is +0 (-0) and `x` is less than 0, +pi (-pi) is returned.
 *  - If `y` is +0 (-0) and `x` is greater than 0, +0 (-0) is returned.
 *  - If `y` is less than 0 and `x` is +0 or -0, -pi/2 is returned.
 *  - If `y` is greater than 0 and `x` is +0 or -0, pi/2 is returned.
 *  - If either `x` or `y` is NaN, a NaN is returned.
 *  - If `y` is +0 (-0) and `x` is -0, +pi (-pi) is returned.
 *  - If `y` is +0 (-0) and `x` is +0, +0 (-0) is returned.
 *  - If `y` is a finite value greater (less) than 0, and `x` is negative
 *    infinity, +pi (-pi) is returned.
 *  - If `y` is a finite value greater (less) than 0, and `x` is positive
 *    infinity, +0 (-0) is returned.
 *  - If `y` is positive infinity (negative infinity), and `x` is finite,
 *    pi/2 (-pi/2) is returned.
 *  - If `y` is positive infinity (negative infinity) and `x` is negative
 *    infinity, +3 * pi/4 (-3 * pi/4) is returned.
 *  - If `y` is positive infinity (negative infinity) and `x` is positive
 *    infinity, +pi/4 (-pi/4) is returned.
 *
 * When either `x` or `y` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#atan2
 *
 * @param {*} y
 * The `y` value.
 *
 * @param {*} x
 * The `x` value.
 *
 * @returns {float}
 */
export function atan2(y, x) {};

/**
 * Calculates the tangent of `x`, the floating-point value representing the
 * angle in radians.
 *
 * On success, this function returns the tangent of `x`.
 * 
 * The relationship is `tan(x) = sin(x) / cos (x)`. A graph of the tangent has
 * periodic patterns directly related to ratios of pi, where radian values of
 * whole multiples of (1, 2, 3, ...) pi are 0, and radian values of half
 * multiples of pi (1/2, 3/2, 5/2, ...) are +/-Infinity.
 *
 *
 * When `x` can't be converted to a numeric value, `NaN` is
 * returned.
 *
 * @function module:math#tan
 *
 * @param {float} x
 * The `x` value.
 *
 * @returns {float}
 */
export function tan(x) {};

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
 *  - If `x` is positive infinity, positive infinity is returned.
 *  - If `x` is negative infinity, `+0` is returned.
 *  - If the result underflows, a range error occurs, and zero is returned.
 *  - If the result overflows, a range error occurs, and `Infinity` is returned.
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
 *  - If `x` is `1`, the result is `+0`.
 *  - If `x` is positive infinity, positive infinity is returned.
 *  - If `x` is zero, then a pole error occurs, and the function
 *    returns negative infinity.
 *  - If `x` is negative (including negative infinity), then a domain
 *    error occurs, and `NaN` is returned.
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
 * Calculate base-10 log of x.
 *
 * @function module:math#log10
 *
 * @param {float} x number
 *
 * @returns {float}
 * The common (base-10) logarithm of x, or
 * `NaN` if the given argument could not be converted to a number.
 *
 * @example
 * log10(100);   // 2.0
 * log10(10);    // 1.0
 * log10(5);     // 0.69897000433602
 * log10(1);     // 0.0
 * log10(0);     // -1e309
 */
export function log10(x) {};

/**
 * Calculate base-2 log of x.
 *
 * @function module:math#log2
 *
 * @param {float} x number
 *
 * @returns {float}
 * The common (base-2) logarithm of x, or
 * `NaN` if the given argument could not be converted to a number.
 *
 * @example
 * log2(1024);  // 10.0
 * log2(512);   // 9.0
 * log2(16);    // 4.0
 * log2(4);     // 2.0
 * log2(2);     // 1.0
 * log2(1);     // 0.0
 * log2(0);     // -1e309
 */
export function log2(x) {};

/**
 * Computes the natural (base e) logarithm of 1 + x. This function is more
 * precise than the expression {@link module:math#log `log`}(1 + x) if x is
 * close to zero.
 *
 * @function module:math#log1p
 *
 * @param {float} x number
 *
 * @returns {float}
 * The natural (base e) logarithm of 1 + x, or
 * `NaN` if the given argument could not be converted to a number.
 *
 * @example
 * log1p(10);    // 2.3978952727984
 * log1p(1);     // 0.69314718055995
 * log1p(0.1);   // 0.095310179804325
 * log1p(0.001); // 0.00099950033308353
 * log1p(0);     // 0.0
 */
export function log1p(x) {};

/**
 * Computes the e (Euler's number, 2.7182818) raised to the given power x,
 * minus 1.0. This function is more accurate than the expression 
 * {@link module:math#exp `exp(x)`}-1.0
 * if x is close to zero.
 *
 * @function module:math#expm1
 *
 * @param {float} x number
 *
 * @returns {float}
 * The e (Euler's number, 2.7182818) raised to the given power x, minus 1.0, or
 * `NaN` if the given argument could not be converted to a number.
 *
 * @example
 * expm1(10);       // 22025.465794807
 * expm1(1);        // 1.718281828459
 * expm1(0.1);      // 0.10517091807565
 * expm1(0.001);    // 0.0010005001667083
 * exp(0.001)-1;    // 0.0010005001667084
 * expm1(0.0001);   // 0.00010000500016667
 * exp(0.0001)-1;   // 0.00010000500016671
 * expm1(0.000001); // 1.0000005000002e-06
 * exp(0.000001)-1; // 1.0000004999622e-06
 * expm1(0);        // 0.0
 */
export function expm1(x) {};

/**
 * Calculates the sine of `x`, where `x` is given in radians.
 *
 * Returns the resulting sine value.
 *
 *  - When `x` is positive or negative infinity, a domain error occurs
 *    and `NaN` is returned.
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
 *  - If `x` is `+0` (`-0`) then `+0` (`-0`) is returned.
 *  - If `x` is positive infinity, positive infinity is returned.
 *  - If `x` is less than `-0`, a domain error occurs, and `NaN` is returned.
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
 * Calculates the cube root of `x`.
 *
 * Returns the resulting cube root value.
 *
 *  - If `x` is `+0` (`-0`) then `+0` (`-0`) is returned.
 *  - If `x` is (+/-) infinity, (+/-) infinity is returned.
 *
 * Returns `NaN` if the `x` value can't be converted to a number.
 *
 * @function module:math#cbrt
 *
 * @param {float} x
 * Value to calculate cube root for.
 *
 * @returns {float}
 * @example
 * cbrt(27);  // 3.0
 * cbrt(0);   // 0.0
 * cbrt(-27); // -3.0
 */
export function cbrt(x) {};

/**
 * Computes the square root of the sum of the squares of `x` and `y`, i.e.
 * the hypotenuse without undue overflow or underflow at intermediate stages of
 * the computation.
 *
 * Returns the result of `sqrt(x^2 + y^2)`.
 *
 *  - If `x` and `y` are `+0` (`-0`) then `+0` (`-0`) is returned.
 *  - If `x` or `y` is `+0` (`-0`) then `+y` or `+x` is returned.
 *  - If `x` or `y` is (+/-) infinity, (+/-) infinity is returned.
 *
 * Returns `NaN` if the `x` or `y` value can't be converted to a number.
 *
 * @function module:math#hypot
 *
 * @param {float} x base
 * @param {float} y height
 *
 * @returns {float}
 * @example
 * hypot(3, 3);   // 4.2426406871193
 * hypot(2, 2);   // 2.8284271247462
 * hypot(1, 1);   // 1.4142135623731
 * hypot(0, 0);   // 0.0
 * hypot(-1, -1); // -1.4142135623731
 */
export function hypot(x, y) {};

/**
 * Calculates the value of `x` raised to the power of `y`.
 *
 * On success, returns the value of `x` raised to the power of `y`.
 *
 *  - If the result overflows, a range error occurs, and the function
 *    returns `Infinity`.
 *  - If result underflows, and is not representable, a range error
 *    occurs, and `0.0` with the appropriate sign is returned.
 *  - If `x` is `+0` or `-0`, and `y` is an odd integer less than `0`,
 *    a pole error occurs `Infinity` is returned, with the same sign
 *    as `x`.
 *  - If `x` is `+0` or `-0`, and `y` is less than `0` and not an odd
 *    integer, a pole error occurs and `Infinity` is returned.
 *  - If `x` is `+0` (`-0`), and `y` is an odd integer greater than `0`,
 *    the result is `+0` (`-0`).
 *  - If `x` is `0`, and `y` greater than `0` and not an odd integer,
 *    the result is `+0`.
 *  - If `x` is `-1`, and `y` is positive infinity or negative infinity,
 *    the result is `1.0`.
 *  - If `x` is `+1`, the result is `1.0` (even if `y` is `NaN`).
 *  - If `y` is `0`, the result is `1.0` (even if `x` is `NaN`).
 *  - If `x` is a finite value less than `0`, and `y` is a finite
 *    non-integer, a domain error occurs, and `NaN` is returned.
 *  - If the absolute value of `x` is less than `1`, and `y` is negative
 *    infinity, the result is positive infinity.
 *  - If the absolute value of `x` is greater than `1`, and `y` is
 *    negative infinity, the result is `+0`.
 *  - If the absolute value of `x` is less than `1`, and `y` is positive
 *    infinity, the result is `+0`.
 *  - If the absolute value of `x` is greater than `1`, and `y` is positive
 *    infinity, the result is positive infinity.
 *  - If `x` is negative infinity, and `y` is an odd integer less than `0`,
 *    the result is `-0`.
 *  - If `x` is negative infinity, and `y` less than `0` and not an odd
 *    integer, the result is `+0`.
 *  - If `x` is negative infinity, and `y` is an odd integer greater than
 *    `0`, the result is negative infinity.
 *  - If `x` is negative infinity, and `y` greater than `0` and not an odd
 *    integer, the result is positive infinity.
 *  - If `x` is positive infinity, and `y` less than `0`, the result is `+0`.
 *  - If `x` is positive infinity, and `y` greater than `0`, the result is
 *    positive infinity.
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
 * Without arguments it returns the calculated pseuo-random value. The value 
 * is within the range `0` to `RAND_MAX` inclusive where `RAND_MAX` is a platform 
 * specific value guaranteed to be at least `32767`.
 * 
 * With 2 arguments `a, b` it returns a number in the range `a` to `b` inclusive.
 * With a single argument `a` it returns a number in the range `0` to `a` inclusive.
 * 
 * The {@link module:math#srand `srand()`} function sets its argument as the
 * seed for a new sequence of pseudo-random integers to be returned by `rand()`.
 * These sequences are repeatable by calling {@link module:math#srand `srand()`}
 * with the same seed value.
 *
 * If no seed value is explicitly set by calling
 * {@link module:math#srand `srand()`} prior to the first call to `rand()`,
 * the math module will automatically seed the PRNG once, using the current
 * time of day in milliseconds as seed value.
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
 * This functions seeds the PRNG with the given value and thus affects the
 * pseudo-random integer sequence produced by subsequent calls to
 * {@link module:math#rand `rand()`}.
 *
 * Setting the same seed value will result in the same pseudo-random numbers
 * produced by {@link module:math#rand `rand()`}.
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
 * This functions checks whether the given argument is of type `double` with
 * a `NaN` (not a number) value.
 *
 * Returns `true` if the value is `NaN`, otherwise false.
 *
 * Note that a value can also be checked for `NaN` with the expression
 * `x !== x` which only evaluates to `true` if `x` is `NaN`.
 *
 * @function module:math#isnan
 *
 * @param {float} x
 * The value to test.
 *
 * @returns {boolean}
 */
export function isnan(x) {};

/**
 * Tests whether `x` is double precision `Infinity`.
 *
 * This functions checks whether the given argument is of type `double` of
 * `Infinity` value. Double precision values >= 1.8e308 are considered `Infinity`.
 *
 * Returns `true` if the value is `Infinity`, otherwise false.
 *
 * @function module:math#isinf
 *
 * @param {float} x
 * The value to test.
 *
 * @returns {boolean}
 */
export function isinf(x) {};

/**
 * Returns the radian value of the given degree value.
 *
 * @function module:math#deg2rad
 *
 * @param {float} number
 * The number to return the radian value for.
 *
 * @returns {float}
 * Returns the absolute value or `NaN` if the given argument could
 * not be converted to a number.
 * @example
 * deg2rad(180);   // 3.1415926535898
 * deg2rad("180"); // 3.1415926535898
 */
export function deg2rad(number) {};

/**
 * Returns the degree value of the given radian value.
 *
 * @function module:math#rad2deg
 *
 * @param {float} number
 * The number to return the degree value for.
 *
 * @returns {float}
 * Returns the absolute value or `NaN` if the given argument could
 * not be converted to a number.
 * @example
 * rad2deg(3.1415926535898);   // 180.0
 * rad2deg("3.1415926535898"); // 180.0
 */
export function rad2deg(number) {};

/**
 * Returns the lesser of two values x and y.
 *
 * @function module:math#fmin
 *
 * @param {float} x first parameter
 * @param {float} y second parameter
 *
 * @returns {float}
 * Returns the lesser of the two values x or y or `NaN` if a given argument
 * could not be converted to a number. Use `(-)Infinity` or `NAN` for
 * comparisons involving said values.
 * @example
 * fmin("180", "-180");   // -180.0
 * fmin(180, -180);       // -180.0
 * fmin(-Infinity, 0);    // -1e309 i.e. -infinity in double type representation.
 */
export function fmin(x, y) {};

/**
 * Returns the greater of two values x and y.
 *
 * @function module:math#fmax
 *
 * @param {float} x first parameter
 * @param {float} y second parameter
 *
 * @returns {float}
 * Returns the greater of the two values x or y or `NaN` if a given argument
 * could not be converted to a number. Use `(-)Infinity` or `NAN` for
 * comparisons involving said values.
 * @example
 * fmax("180", "-180");   // 180.0
 * fmax(180, -180);       // 180.0
 * fmax(Infinity, 0);     // 1e309 i.e. infinity in double type representation.
 */
export function fmax(x, y) {};

/**
 * Clamps `x` to within `upper` and `lower` bounds if `x` exceeds them.
 *
 * The operation is effectively: `min(upper, max(x, lower))`.
 *
 * @function module:math#clamp
 *
 * @param {float} x number to clamp
 * @param {float} upper upper bound
 * @param {float} lower lower bound
 *
 * @returns {float}
 * Returns `x` if within `upper` and `lower`, otherwise one of `lower` or `upper`
 * if `x` exceeds those bounds, or `NaN` if any given argument
 * could not be converted to a number.
 * @example
 * clamp(1000, 200, 180);   // 200.0
 * clamp(-1000, 200, 180);  // 180.0
 * clamp(190, 200, 180);    // 190.0
 */
export function clamp(x, upper, lower) {};

/**
 * Returns -1 or 1 depending on the sign of the given number, or 0 if the given
 * number itself is zero.
 *
 * @function module:math#sign
 *
 * @param {float} x number
 *
 * @returns {int}
 * Returns -1 or 1 for negative and positive inputs respectively, 0 if the given
 * number is zero, or `NaN` if the given argument could not be converted to a
 * number.
 * @example
 * sign(2);   // 1
 * sign(-8);  // -1
 * sign(0);   // 0
 * sign(-0);  // 0
 */
export function sign(x) {};

/**
 * Returns -1 or 1 depending on the sign of the given number, or 0 if the given
 * number itself is zero. IEEE-754 behaviour.
 *
 * @function module:math#signbit
 *
 * @param {float} x number
 *
 * @returns {int}
 * Returns -1 or 1 for negative and positive inputs respectively, 0 if the given
 * number is zero, -1 for -0.0, or `NaN` if the given argument could not be
 * converted to a number.
 * @example
 * signbit(2);    // 1
 * signbit(-8);   // -1
 * signbit(0);    // 0
 * signbit(-0.0); // -1
 * signbit(-0);   // 0
 */
export function signbit(x) {};

/**
 * Returns -1 or 1 depending on the sign of the given number only (no zero).
 * (-)Zero effectively becomes 1.
 *
 * @function module:math#signnz
 *
 * @param {float} x number
 *
 * @returns {int}
 * Returns -1 or +1 for negative and positive inputs respectively, and zero is
 * converted to +1, or `NaN` if the given argument could not be converted to a
 * number.
 * @example
 * signnz(2);   // 1
 * signnz(-8);  // -1
 * signnz(0);   // 1
 * signnz(-0);  // 1
 */
export function signnz(x) {};

/**
 * Returns a double whose magnitude is that of `x`, but whose sign is that of
 * `y`.
 *
 * @function module:math#copysign
 *
 * @param {float} x number
 * @param {float} y number
 *
 * @returns {float}
 * Returns `NaN` if a given argument could not be converted to a number.
 * @example
 * copysign(-3, -5);  // -3.0
 * copysign(8, -5);   // -8.0
 * copysign(-0, 3);   // 0.0
 */
export function copysign(x, y) {};

/**
 * Floors `x` to the largest integer value not greater than `x`.
 *
 * @function module:math#floor
 *
 * @param {float} x number
 * @param {boolean} output_type - false is `integer`, true is `double`.
 *
 * @returns {int|float}
 * Returns the largest integer value not greater than `x`, or `NaN` if the given
 * argument could not be converted to a number.
 * @example
 * floor(2.7);        // 2
 * floor(2.7, true);  // 2.0
 * floor(-2.7);       // -3
 * floor(-0.0);       // 0
 * floor(-0.0, true); // -0.0
 * floor(-Infinity);  // -1e309 i.e. -infinity in double type representation.
 */
export function floor(x, output_type) {};

/**
 * Computes the smallest integer value not less than `x`.
 *
 * @function module:math#ceil
 *
 * @param {float} x number
 * @param {boolean} output_type - false is `integer`, true is `double`.
 *
 * @returns {int|float}
 * Returns the smallest integer value not less than `x`, or `NaN` if the given
 * argument could not be converted to a number.
 * @example
 * ceil(2.7);        // 3
 * ceil(2.7, true);  // 3.0
 * ceil(-2.7);       // -2
 * ceil(-0.0);       // 0
 * ceil(-0.0, true); // -0.0
 * ceil(-Infinity);  // -1e309 i.e. -infinity in double type representation.
 */
export function ceil(x, output_type) {};

/**
 * Returns the integral value nearest to x rounding half-way cases away
 * from zero, regardless of the current rounding direction.
 *
 * @function module:math#round
 *
 * @param {float} x number
 * @param {boolean} output_type - false is `integer`, true is `double`.
 *
 * @returns {int|float}
 * Returns the rounded integer value of `x`, or `NaN` if the given
 * argument could not be converted to a number.
 *
 * @example
 * round(2.4);        // 2
 * round(2.5);        // 3
 * round(2.7);        // 3
 * round(2.7, true);  // 3.0
 * round(-2.4);       // -2
 * round(-2.5);       // -3
 * round(-2.7);       // -3
 * round(-0.0);       // 0
 * round(-0.0, true); // -0.0
 * round(-Infinity);  // -1e309 i.e. -infinity in double type representation.
 */
export function round(x, output_type) {};

/**
 * Truncate away the decimal portion to produce the nearest integer not greater
 * in magnitude than x.
 *
 * @function module:math#trunc
 *
 * @param {float} x number
 * @param {boolean} output_type - false is `integer`, true is `double`.
 *
 * @returns {int|float}
 * The integral portion remaining after the decimal portion is truncated, or
 * `NaN` if the given argument could not be converted to a number.
 *
 * @example
 * trunc(2.4);        // 2
 * trunc(2.5);        // 2
 * trunc(2.7);        // 2
 * trunc(2.7, true);  // 2.0
 * trunc(-2.4);       // -2
 * trunc(-2.5);       // -2
 * trunc(-2.7);       // -2
 * trunc(-0.0);       // 0
 * trunc(-0.0, true); // -0.0
 */
export function trunc(x, output_type) {};

