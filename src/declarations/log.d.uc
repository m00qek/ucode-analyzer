/**
 * # System logging functions
 *
 * The `log` module provides bindings to the POSIX syslog functions `openlog()`,
 * `syslog()` and `closelog()` as well as - when available - the OpenWrt
 * specific ulog library functions.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { openlog, syslog, LOG_PID, LOG_USER, LOG_ERR } from 'log';
 *
 *   openlog("my-log-ident", LOG_PID, LOG_USER);
 *   syslog(LOG_ERR, "An error occurred!");
 *
 *   // OpenWrt specific ulog functions
 *   import { ulog_open, ulog, ULOG_SYSLOG, LOG_DAEMON, LOG_INFO } from 'log';
 *
 *   ulog_open(ULOG_SYSLOG, LOG_DAEMON, "my-log-ident");
 *   ulog(LOG_INFO, "The current epoch is %d", time());
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as log from 'log';
 *
 *   log.openlog("my-log-ident", log.LOG_PID, log.LOG_USER);
 *   log.syslog(log.LOG_ERR, "An error occurred!");
 *
 *   // OpenWrt specific ulog functions
 *   log.ulog_open(log.ULOG_SYSLOG, log.LOG_DAEMON, "my-log-ident");
 *   log.ulog(log.LOG_INFO, "The current epoch is %d", time());
 *   ```
 *
 * Additionally, the log module namespace may also be imported by invoking the
 * `ucode` interpreter with the `-llog` switch.
 *
 * ## Constants
 *
 * The `log` module declares a number of numeric constants to specify logging
 * facility, priority and option values, as well as ulog specific channels.
 *
 * ### Syslog Options
 *
 * | Constant Name | Description                                             |
 * |---------------|---------------------------------------------------------|
 * | `LOG_PID`     | Include PID with each message.                          |
 * | `LOG_CONS`    | Log to console if error occurs while sending to syslog. |
 * | `LOG_NDELAY`  | Open the connection to the logger immediately.          |
 * | `LOG_ODELAY`  | Delay open until the first message is logged.           |
 * | `LOG_NOWAIT`  | Do not wait for child processes created during logging. |
 *
 * ### Syslog Facilities
 *
 * | Constant Name  | Description                                      |
 * |----------------|--------------------------------------------------|
 * | `LOG_AUTH`     | Authentication/authorization messages.           |
 * | `LOG_AUTHPRIV` | Private authentication messages.                 |
 * | `LOG_CRON`     | Clock daemon (cron and at commands).             |
 * | `LOG_DAEMON`   | System daemons without separate facility values. |
 * | `LOG_FTP`      | FTP server daemon.                               |
 * | `LOG_KERN`     | Kernel messages.                                 |
 * | `LOG_LPR`      | Line printer subsystem.                          |
 * | `LOG_MAIL`     | Mail system.                                     |
 * | `LOG_NEWS`     | Network news subsystem.                          |
 * | `LOG_SYSLOG`   | Messages generated internally by syslogd.        |
 * | `LOG_USER`     | Generic user-level messages.                     |
 * | `LOG_UUCP`     | UUCP subsystem.                                  |
 * | `LOG_LOCAL0`   | Local use 0 (custom facility).                   |
 * | `LOG_LOCAL1`   | Local use 1 (custom facility).                   |
 * | `LOG_LOCAL2`   | Local use 2 (custom facility).                   |
 * | `LOG_LOCAL3`   | Local use 3 (custom facility).                   |
 * | `LOG_LOCAL4`   | Local use 4 (custom facility).                   |
 * | `LOG_LOCAL5`   | Local use 5 (custom facility).                   |
 * | `LOG_LOCAL6`   | Local use 6 (custom facility).                   |
 * | `LOG_LOCAL7`   | Local use 7 (custom facility).                   |
 *
 * ### Syslog Priorities
 *
 * | Constant Name | Description                         |
 * |---------------|-------------------------------------|
 * | `LOG_EMERG`   | System is unusable.                 |
 * | `LOG_ALERT`   | Action must be taken immediately.   |
 * | `LOG_CRIT`    | Critical conditions.                |
 * | `LOG_ERR`     | Error conditions.                   |
 * | `LOG_WARNING` | Warning conditions.                 |
 * | `LOG_NOTICE`  | Normal, but significant, condition. |
 * | `LOG_INFO`    | Informational message.              |
 * | `LOG_DEBUG`   | Debug-level message.                |
 *
 * ### Ulog channels
 *
 * | Constant Name | Description                          |
 * |---------------|--------------------------------------|
 * | `ULOG_KMSG`   | Log messages to `/dev/kmsg` (dmesg). |
 * | `ULOG_STDIO`  | Log messages to stdout.              |
 * | `ULOG_SYSLOG` | Log messages to syslog.              |
 *
 * @module log
 */

/**
 * Open connection to system logger.
 *
 * The `openlog()` function instructs the program to establish a connection to
 * the system log service and configures the default facility and identification
 * for use in subsequent log operations. It may be omitted, in which case the
 * first call to `syslog()` will implicitly call `openlog()` with a default
 * ident value representing the program name and a default `LOG_USER` facility.
 *
 * The log option argument may be either a single string value containing an
 * option name, an array of option name strings or a numeric value representing
 * a bitmask of `LOG_*` option constants.
 *
 * The facility argument may be either a single string value containing a
 * facility name or one of the numeric `LOG_*` facility constants in the module
 * namespace.
 *
 * Returns `true` if the system `openlog()` function was invoked.
 *
 * Returns `false` if an invalid argument, such as an unrecognized option or
 * facility name, was provided.
 *
 * @function module:log#openlog
 *
 * @param {string} [ident]
 * A string identifying the program name. If omitted, the name of the calling
 * process is used by default.
 *
 * @param {int|module:log.LogOption|module:log.LogOption[]} [options]
 * Logging options to use.
 *
 * See {@link module:log.LogOption|LogOption} for recognized option names.
 *
 * @param {int|module:log.LogFacility} [facility="user"]
 * The facility to use for log messages generated by subsequent syslog calls.
 *
 * See {@link module:log.LogFacility|LogFacility} for recognized facility names.
 *
 * @returns {boolean}
 *
 * @example
 * // Example usage of openlog function
 * openlog("myapp", LOG_PID | LOG_NDELAY, LOG_LOCAL0);
 *
 * // Using option names instead of bitmask and LOG_USER facility
 * openlog("myapp", [ "pid", "ndelay" ], "user");
 */
export function openlog(ident, options, facility) {};

/**
 * Log a message to the system logger.
 *
 * This function logs a message to the system logger. The function behaves in a
 * sprintf-like manner, allowing the use of format strings and associated
 * arguments to construct log messages.
 *
 * If the `openlog` function has not been called explicitly before, `syslog()`
 * implicitly calls `openlog()`, using a default ident and `LOG_USER` facility
 * value before logging the message.
 *
 * If the `format` argument is not a string and not `null`, it will be
 * implicitly converted to a string and logged as-is, without further format
 * string processing.
 *
 * Returns `true` if a message was passed to the system `syslog()` function.
 *
 * Returns `false` if an invalid priority value or an empty message was given.
 *
 * @function module:log#syslog
 *
 * @param {int|module:log.LogPriority} priority
 * Log message priority. May be either a number value (potentially bitwise OR-ed
 * with a log facility constant) which is passed as-is to the system `syslog()`
 * function or a priority name string.
 *
 * See {@link module:log.LogPriority|LogPriority} for recognized priority names.
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * // Example usage of syslog function with format string and arguments
 * const username = "user123";
 * const errorCode = 404;
 * syslog(LOG_ERR, "User %s encountered error: %d", username, errorCode);
 *
 * // If openlog has not been called explicitly, it is implicitly called with defaults:
 * syslog(LOG_INFO, "This message will be logged with default settings.");
 *
 * // Selectively override used facility by OR-ing numeric constant
 * const password =" secret";
 * syslog(LOG_DEBUG|LOG_AUTHPRIV, "The password %s has been wrong", secret);
 *
 * // Using priority names for logging
 * syslog("emerg", "System shutdown imminent!");
 *
 * // Implicit stringification
 * syslog("debug", { foo: 1, bar: true, baz: [1, 2, 3] });
 */
export function syslog(priority, format, args) {};

/**
 * Close connection to system logger.
 *
 * The usage of this function is optional, and usually an explicit log
 * connection tear down is not required.
 *
 * @function module:log#closelog
 */
export function closelog() {};

/**
 * Configure ulog logger.
 *
 * This functions configures the ulog mechanism and is analogous to using the
 * `openlog()` function in conjunction with `syslog()`.
 *
 * The `ulog_open()` function is OpenWrt specific and may not be present on
 * other systems. Use `openlog()` and `syslog()` instead for portability to
 * non-OpenWrt environments.
 *
 * A program may use multiple channels to simultaneously output messages using
 * different means. The channel argument may either be a single string value
 * containing a channel name, an array of channel names or a numeric value
 * representing a bitmask of `ULOG_*` channel constants.
 *
 * The facility argument may be either a single string value containing a
 * facility name or one of the numeric `LOG_*` facility constants in the module
 * namespace.
 *
 * The default facility value varies, depending on the execution context of the
 * program. In OpenWrt's preinit boot phase, or when stdout is not connected to
 * an interactive terminal, the facility defaults to `"daemon"` (`LOG_DAEMON`),
 * otherwise to `"user"` (`LOG_USER`).
 *
 * Likewise, the default channel is selected depending on the context. During
 * OpenWrt's preinit boot phase, the `"kmsg"` channel is used, for interactive
 * terminals the `"stdio"` one and for all other cases the `"syslog"` channel
 * is selected.
 *
 * Returns `true` if ulog was configured.
 *
 * Returns `false` if an invalid argument, such as an unrecognized channel or
 * facility name, was provided.
 *
 * @function module:log#ulog_open
 *
 * @param {int|module:log.UlogChannel|module:log.UlogChannel[]} [channel]
 * Specifies the log channels to use.
 *
 * See {@link module:log.UlogChannel|UlogChannel} for recognized channel names.
 *
 * @param {int|module:log.LogFacility} [facility]
 * The facility to use for log messages generated by subsequent `ulog()` calls.
 *
 * See {@link module:log.LogFacility|LogFacility} for recognized facility names.
 *
 * @param {string} [ident]
 * A string identifying the program name. If omitted, the name of the calling
 * process is used by default.
 *
 * @returns {boolean}
 *
 * @example
 * // Log to dmesg and stderr
 * ulog_open(["stdio", "kmsg"], "daemon", "my-program");
 *
 * // Use numeric constants and use implicit default ident
 * ulog_open(ULOG_SYSLOG, LOG_LOCAL0);
 */
export function ulog_open(channel, facility, ident) {};

/**
 * Log a message via the ulog mechanism.
 *
 * The `ulog()` function outputs the given log message to all configured ulog
 * channels unless the given priority level exceeds the globally configured ulog
 * priority threshold. See {@link module:log#ulog_threshold|ulog_threshold()}
 * for details.
 *
 * The `ulog()` function is OpenWrt specific and may not be present on other
 * systems. Use `syslog()` instead for portability to non-OpenWrt environments.
 *
 * Like `syslog()`, the function behaves in a sprintf-like manner, allowing the
 * use of format strings and associated arguments to construct log messages.
 *
 * If the `ulog_open()` function has not been called explicitly before, `ulog()`
 * implicitly configures certain defaults, see
 * {@link module:log#ulog_open|ulog_open()} for a detailed description.
 *
 * If the `format` argument is not a string and not `null`, it will be
 * implicitly converted to a string and logged as-is, without further format
 * string processing.
 *
 * Returns `true` if a message was passed to the underlying `ulog()` function.
 *
 * Returns `false` if an invalid priority value or an empty message was given.
 *
 * @function module:log#ulog
 *
 * @param {int|module:log.LogPriority} priority
 * Log message priority. May be either a number value or a priority name string.
 *
 * See {@link module:log.LogPriority|LogPriority} for recognized priority names.
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * // Example usage of ulog function with format string and arguments
 * const username = "user123";
 * const errorCode = 404;
 * ulog(LOG_ERR, "User %s encountered error: %d", username, errorCode);
 *
 * // Using priority names for logging
 * ulog("err", "General error encountered");
 *
 * // Implicit stringification
 * ulog("debug", { foo: 1, bar: true, baz: [1, 2, 3] });
 *
 * @see module:log#ulog_open
 * @see module:log#ulog_threshold
 * @see module:log#syslog
 */
export function ulog(priority, format, args) {};

/**
 * Close ulog logger.
 *
 * Resets the ulog channels, the default facility and the log ident value to
 * defaults.
 *
 * In case the `"syslog"` channel has been configured, the underlying
 * `closelog()` function will be invoked.
 *
 * The usage of this function is optional, and usually an explicit ulog teardown
 * is not required.
 *
 * The `ulog_close()` function is OpenWrt specific and may not be present on
 * other systems. Use `closelog()` in conjunction with `syslog()` instead for
 * portability to non-OpenWrt environments.
 *
 * @function module:log#ulog_close
 *
 * @see module:log#closelog
 */
export function ulog_close() {};

/**
 * Set ulog priority threshold.
 *
 * This function configures the application wide log message threshold for log
 * messages emitted with `ulog()`. Any message with a priority higher (= less
 * severe) than the threshold priority will be discarded. This is useful to
 * implement application wide verbosity settings without having to wrap `ulog()`
 * invocations into a helper function or guarding code.
 *
 * When no explicit threshold has been set, `LOG_DEBUG` is used by default,
 * allowing log messages with all known priorities.
 *
 * The `ulog_threshold()` function is OpenWrt specific and may not be present on
 * other systems. There is no syslog equivalent to this ulog specific threshold
 * mechanism.
 *
 * The priority argument may be either a string value containing a priority name
 * or one of the numeric `LOG_*` priority constants in the module namespace.
 *
 * Returns `true` if a threshold was set.
 *
 * Returns `false` if an invalid priority value was given.
 *
 * @function module:log#ulog_threshold
 *
 * @param {int|module:log.LogPriority} [priority]
 * The priority threshold to configure.
 *
 * See {@link module:log.LogPriority|LogPriority} for recognized priority names.
 *
 * @returns {boolean}
 *
 * @example
 * // Set threshold to "warning" or more severe
 * ulog_threshold(LOG_WARNING);
 *
 * // This message will be suppressed
 * ulog(LOG_DEBUG, "Testing thresholds");
 *
 * // Using priority name
 * ulog_threshold("debug");
 */
export function ulog_threshold(priority) {};

/**
 * Invoke ulog with LOG_INFO.
 *
 * This function is convenience wrapper for `ulog(LOG_INFO, ...)`.
 *
 * See {@link module:log#ulog|ulog()} for details.
 *
 * @function module:log#INFO
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * INFO("This is an info log message");
 */
export function INFO(format, args) {};

/**
 * Invoke ulog with LOG_NOTICE.
 *
 * This function is convenience wrapper for `ulog(LOG_NOTICE, ...)`.
 *
 * See {@link module:log#ulog|ulog()} for details.
 *
 * @function module:log#NOTE
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * NOTE("This is a notification log message");
 */
export function NOTE(format, args) {};

/**
 * Invoke ulog with LOG_WARNING.
 *
 * This function is convenience wrapper for `ulog(LOG_WARNING, ...)`.
 *
 * See {@link module:log#ulog|ulog()} for details.
 *
 * @function module:log#WARN
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * WARN("This is a warning");
 */
export function WARN(format, args) {};

/**
 * Invoke ulog with LOG_ERR.
 *
 * This function is convenience wrapper for `ulog(LOG_ERR, ...)`.
 *
 * See {@link module:log#ulog|ulog()} for details.
 *
 * @function module:log#ERR
 *
 * @param {*} format
 * The sprintf-like format string for the log message, or any other, non-null,
 * non-string value type which will be implicitly stringified and logged as-is.
 *
 * @param {...*} [args]
 * In case a format string value was provided in the previous argument, then
 * all subsequent arguments are used to replace the placeholders in the format
 * string.
 *
 * @returns {boolean}
 *
 * @example
 * ERR("This is an error!");
 */
export function ERR(format, args) {};

