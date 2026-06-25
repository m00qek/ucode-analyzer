// Source: https://github.com/jow-/ucode @ fecacb8188c6a4f38d97434160b979d73e898b24
/**
 * # Debugger Module
 *
 * This module provides runtime debug functionality for ucode scripts.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { memdump, traceback } from 'debug';
 *
 *   let stacktrace = traceback(1);
 *
 *   memdump("/tmp/dump.txt");
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as debug from 'debug';
 *
 *   let stacktrace = debug.traceback(1);
 *
 *   debug.memdump("/tmp/dump.txt");
 *   ```
 *
 * Additionally, the debug module namespace may also be imported by invoking the
 * `ucode` interpreter with the `-ldebug` switch.
 *
 * Upon loading, the `debug` module will register a `SIGUSR2` signal handler
 * which, upon receipt of the signal, will write a memory dump of the currently
 * running program to `/tmp/ucode.$timestamp.$pid.memdump`. This default
 * behavior can be inhibited by setting the `UCODE_DEBUG_MEMDUMP_ENABLED`
 * environment variable to `0` when starting the process. The memory dump signal
 * and output directory can be overridden with the `UCODE_DEBUG_MEMDUMP_SIGNAL`
 * and `UCODE_DEBUG_MEMDUMP_PATH` environment variables respectively.
 *
 * @module debug
 */

/**
 * Entry in the call stack returned by {@link module:debug#traceback|traceback()}.
 *
 * @typedef {{ sourcefile: string, line: int, offset: int, funcname: ?string }} StackTraceEntry
 */

/**
 * Source code position returned by {@link module:debug#sourcepos|sourcepos()}.
 *
 * @typedef {{ filename: string, line: int, offset: int }} SourcePosition
 */

/**
 * Internal value information returned by {@link module:debug#getinfo|getinfo()}.
 *
 * @typedef {{ type: string, refcount: int, mark: boolean }} ValueInformation
 */

/**
 * Local variable information returned by {@link module:debug#getlocal|getlocal()}
 * and {@link module:debug#setlocal|setlocal()}.
 *
 * @typedef {{ name: string, value: * }} LocalInfo
 */

/**
 * Upvalue (captured variable) information returned by {@link module:debug#getupval|getupval()}
 * and {@link module:debug#setupval|setupval()}.
 *
 * @typedef {{ name: string, value: * }} UpvalInfo
 */

/**
 * Write a memory dump report to the given file.
 *
 * This function generates a human readable memory dump of ucode values
 * currently managed by the running VM which is useful to track down logical
 * memory leaks in scripts.
 *
 * The file parameter can be either a string value containing a file path, in
 * which case this function tries to create and write the report file at the
 * given location, or an already open file handle this function should write to.
 *
 * Returns `true` if the report has been written.
 *
 * Returns `null` if the file could not be opened or if the handle was invalid.
 *
 * @function module:debug#memdump
 *
 * @param {string|FsFile|FsProc} file
 * The file path or open file handle to write report to.
 *
 * @return {?boolean}
 */
export function memdump(file) {};

/**
 * Capture call stack trace.
 *
 * This function captures the current call stack and returns it. The optional
 * level parameter controls how many calls up the trace should start. It
 * defaults to `1`, that is the function calling this `traceback()` function.
 *
 * Returns an array of stack trace entries describing the function invocations
 * up to the point where `traceback()` is called.
 *
 * @function module:debug#traceback
 *
 * @param {int} [level=1]
 * The number of callframes up the call trace should start, `0` is this function
 * itself, `1` the function calling it and so on.
 *
 * @return {StackTraceEntry[]}
 */
export function traceback(level) {};

/**
 * Obtain information about the current source position.
 *
 * The `sourcepos()` function determines the source code position of the
 * current instruction invoking this function.
 *
 * Returns a dictionary containing the filename, line number and line byte
 * offset of the call site.
 *
 * Returns `null` if this function was invoked from C code.
 *
 * @function module:debug#sourcepos
 *
 * @return {?SourcePosition}
 */
export function sourcepos() {};

/**
 * Obtain information about the given value.
 *
 * The `getinfo()` function allows querying internal information about the
 * given ucode value, such as the current reference count, the mark bit state
 * etc.
 *
 * Returns a dictionary with value type specific details.
 *
 * Returns `null` if a `null` value was provided.
 *
 * @function module:debug#getinfo
 *
 * @param {*} value
 * The value to query information for.
 *
 * @return {?ValueInformation}
 */
export function getinfo(value) {};

/**
 * Obtain local variable.
 *
 * The `getlocal()` function retrieves information about the specified local
 * variable at the given call stack depth.
 *
 * The call stack depth specifies the amount of levels up local variables should
 * be queried. A value of `0` refers to this `getlocal()` function call itself,
 * `1` to the function calling `getlocal()` and so on.
 *
 * The variable to query might be either specified by name or by its index with
 * index numbers following the source code declaration order.
 *
 * Returns a dictionary holding information about the given variable.
 *
 * Returns `null` if the stack depth exceeds the size of the current call stack.
 *
 * Returns `null` if the invocation at the given stack depth is a C call.
 *
 * Returns `null` if the given variable name is not found or the given variable
 * index is invalid.
 *
 * @function module:debug#getlocal
 *
 * @param {int} [level=1]
 * The amount of call stack levels up local variables should be queried.
 *
 * @param {string|int} variable
 * The variable index or variable name to obtain information for.
 *
 * @returns {?LocalInfo}
 */
export function getlocal(level, variable) {};

/**
 * Set local variable.
 *
 * The `setlocal()` function manipulates the value of the specified local
 * variable at the given call stack depth.
 *
 * The call stack depth specifies the amount of levels up local variables should
 * be updated. A value of `0` refers to this `setlocal()` function call itself,
 * `1` to the function calling `setlocal()` and so on.
 *
 * The variable to update might be either specified by name or by its index with
 * index numbers following the source code declaration order.
 *
 * Returns a dictionary holding information about the updated variable.
 *
 * Returns `null` if the stack depth exceeds the size of the current call stack.
 *
 * Returns `null` if the invocation at the given stack depth is a C call.
 *
 * Returns `null` if the given variable name is not found or the given variable
 * index is invalid.
 *
 * @function module:debug#setlocal
 *
 * @param {int} [level=1]
 * The amount of call stack levels up local variables should be updated.
 *
 * @param {string|int} variable
 * The variable index or variable name to update.
 *
 * @param {*} [value=null]
 * The value to set the local variable to.
 *
 * @returns {?LocalInfo}
 */
export function setlocal(level, variable, value) {};

/**
 * Obtain captured variable (upvalue).
 *
 * The `getupval()` function retrieves information about the specified captured
 * variable associated with the given function value or the invoked function at
 * the given call stack depth.
 *
 * The call stack depth specifies the amount of levels up the function should be
 * selected to query associated captured variables for. A value of `0` refers to
 * this `getupval()` function call itself, `1` to the function calling
 * `getupval()` and so on.
 *
 * The variable to query might be either specified by name or by its index with
 * index numbers following the source code declaration order.
 *
 * Returns a dictionary holding information about the given variable.
 *
 * Returns `null` if the given function value is not a closure.
 *
 * Returns `null` if the stack depth exceeds the size of the current call stack.
 *
 * Returns `null` if the invocation at the given stack depth is not a closure.
 *
 * Returns `null` if the given variable name is not found or the given variable
 * index is invalid.
 *
 * @function module:debug#getupval
 *
 * @param {function|int} target
 * Either a function value referring to a closure to query upvalues for or a
 * stack depth number selecting a closure that many levels up.
 *
 * @param {string|int} variable
 * The variable index or variable name to obtain information for.
 *
 * @returns {?UpvalInfo}
 */
export function getupval(target, variable) {};

/**
 * Set upvalue.
 *
 * The `setupval()` function manipulates the value of the specified captured
 * variable associated with the given function value or the invoked function at
 * the given call stack depth.
 *
 * The call stack depth specifies the amount of levels up the function should be
 * selected to update associated captured variables for. A value of `0` refers
 * to this `setupval()` function call itself, `1` to the function calling
 * `setupval()` and so on.
 *
 * The variable to update might be either specified by name or by its index with
 * index numbers following the source code declaration order.
 *
 * Returns a dictionary holding information about the updated variable.
 *
 * Returns `null` if the given function value is not a closure.
 *
 * Returns `null` if the stack depth exceeds the size of the current call stack.
 *
 * Returns `null` if the invocation at the given stack depth is not a closure.
 *
 * Returns `null` if the given variable name is not found or the given variable
 * index is invalid.
 *
 * @function module:debug#setupval
 *
 * @param {function|int} target
 * Either a function value referring to a closure to update upvalues for or a
 * stack depth number selecting a closure that many levels up.
 *
 * @param {string|int} variable
 * The variable index or variable name to update.
 *
 * @param {*} value
 * The value to set the variable to.
 *
 * @returns {?UpvalInfo}
 */
export function setupval(target, variable, value) {};

