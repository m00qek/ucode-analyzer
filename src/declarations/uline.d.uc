// Source: https://github.com/openwrt/openwrt @ 85e15f34ace3077d960682564119597dd82afea1 (package/utils/ucode-mod-uline/)
/**
 * # Interactive Terminal Line Editor
 *
 * The `uline` module provides an interactive line-editing interface similar
 * to libreadline, with no ncurses or readline dependency. It operates in
 * raw termios mode and implements VT100/ANSI terminal control, UTF-8 display
 * width calculation, multi-line editing, and a secondary editing area.
 *
 * Requires {@link module:uloop|uloop} when using
 * {@link module:uline.state#set_uloop|set_uloop()} for async input handling.
 *
 *   ```javascript
 *   import * as uline from 'uline';
 *   import { init, run } from 'uloop';
 *
 *   // Synchronous blocking REPL
 *   const ed = uline.new({
 *     cb: {
 *       line_check: (line) => true,
 *       eof:        ()     => exit(0),
 *       interrupt:  ()     => exit(1),
 *     },
 *   });
 *   ed.set_state({ prompt: '>> ' });
 *
 *   while (true) {
 *     const line = ed.poll();
 *     if (line != null)
 *       handle(line);
 *   }
 *   ```
 *
 * @module uline
 */

/**
 * Current line buffer contents returned by
 * {@link module:uline.state#get_line|state.get_line()}.
 *
 * @typedef {{ line: string, pos: int }} UlineLineInfo
 */

/**
 * Terminal dimensions returned by
 * {@link module:uline.state#get_window|state.get_window()}.
 *
 * @typedef {{ x: int, y: int }} UlineWindowInfo
 */

/**
 * Result of {@link module:uline.argp#parse|argp.parse()}.
 *
 * When created without a `line_separator`, `args` is a flat `string[]` and
 * `pos` is an array of `[start, end]` pairs.
 *
 * When created with a `line_separator`, `args` is a `string[][]` (one array
 * per group) and `pos` mirrors that shape.
 *
 * @typedef {{ args: *, pos: *, missing: ?string }} UlineParseResult
 */

/**
 * Line editor instance returned by {@link module:uline#new|new()}.
 *
 * @typedef {{
 *   poll: function(): ?string,
 *   poll_key: function(?int): ?string,
 *   poll_stop: function(): void,
 *   reset_key_input: function(): boolean,
 *   get_line: function(?boolean): ?UlineLineInfo,
 *   get_window: function(): ?UlineWindowInfo,
 *   set_state: function(object): ?boolean,
 *   set_hint: function(string): ?boolean,
 *   set_uloop: function(?function): ?boolean,
 *   hide_prompt: function(): void,
 *   refresh_prompt: function(): void,
 *   close: function(): void
 * }} UlineState
 */

/**
 * Shell argument parser returned by {@link module:uline#arg_parser|arg_parser()}.
 *
 * @typedef {{
 *   parse: function(string): ?UlineParseResult,
 *   check: function(string): ?string,
 *   escape: function(string, ?string): ?string
 * }} UlineArgParser
 */

/**
 * Create a new line editor instance.
 *
 * Switches the terminal to raw mode, installs a `SIGWINCH` handler, and
 * queries the initial terminal size. The original termios settings are
 * restored when the instance is closed or garbage-collected.
 *
 * Returns the editor handle on success.
 *
 * Returns `null` if `data` is not an object, `cb` is missing or not an
 * object, `input`/`output` are invalid file handles, or `key_input_list`
 * contains non-single-character strings.
 *
 * @function module:uline#new
 *
 * @param {object} data
 * Editor configuration:
 *
 * - `cb` {object} **(required)** — callback dispatch table. All callbacks
 *   are optional and are invoked with `this` bound to the editor state:
 *   - `line_check(line)` — called on every Enter press. Return `true` to
 *     accept the line and end editing; return `false` to insert a literal
 *     newline and continue multi-line editing.
 *   - `key_input(char, count)` — called for each keypress whose byte value
 *     is listed in `key_input_list`. Return `true` to consume the key;
 *     `false` to fall through to default handling. `count` is the current
 *     repeat count.
 *   - `cursor_up()` — Up-arrow or equivalent.
 *   - `cursor_down()` — Down-arrow or equivalent.
 *   - `window_changed(cols, rows)` — terminal resize (`SIGWINCH`).
 *   - `eof()` — Ctrl-D pressed with an empty buffer.
 *   - `interrupt()` — Ctrl-C pressed.
 *   - `line2_update(str)` — secondary line buffer changed.
 *   - `line2_cursor()` — cursor or Delete key pressed while the secondary
 *     line is active. Return `true` to route the key to the secondary line;
 *     `false` to route it to the primary line.
 *   - `line2_newline(str)` — Enter pressed in secondary-line mode. Return
 *     `true` to suppress (stay in secondary line); `false` to pass through.
 *
 * - `input` {object} (optional) — open `fs.file` handle to read from.
 *   Defaults to stdin.
 * - `output` {object} (optional) — open `fs.file` handle to write to.
 *   Defaults to stdout.
 * - `key_input_list` {string[]} (optional) — single-character strings whose
 *   keypresses are routed to the `key_input` callback before default
 *   handling.
 *
 * @returns {?UlineState}
 *
 * @example
 * import * as uline from 'uline';
 *
 * const history = [];
 * let hist_idx = 0;
 *
 * const ed = uline.new({
 *   cb: {
 *     line_check: (line) => true,
 *     cursor_up() {
 *       if (hist_idx > 0)
 *         this.set_state({ line: history[--hist_idx], pos: 9999 });
 *     },
 *     cursor_down() {
 *       if (hist_idx < history.length)
 *         this.set_state({ line: history[hist_idx++] ?? '', pos: 9999 });
 *     },
 *     eof:       () => exit(0),
 *     interrupt: () => exit(1),
 *   },
 * });
 *
 * ed.set_state({ prompt: '$ ' });
 *
 * while (true) {
 *   const line = ed.poll();
 *   if (line != null) {
 *     history.push(line);
 *     hist_idx = history.length;
 *     handle(line);
 *   }
 * }
 */
export function new(data) {};

/**
 * Create a shell argument parser.
 *
 * Parses shell-style command strings: unquoted tokens, single- and
 * double-quoted strings, and backslash escapes. Optionally groups tokens
 * into sub-arrays separated by a single delimiter character.
 *
 * Returns the parser handle on success.
 *
 * Returns `null` if `line_separator` is provided but is not a single
 * character.
 *
 * @function module:uline#arg_parser
 *
 * @param {object} [opts]
 * Parser options:
 * - `line_separator` {string} — a single character that splits the token
 *   stream into groups. When set, {@link module:uline.argp#parse|parse()}
 *   returns `args` as a `string[][]` (one array per group) rather than a
 *   flat `string[]`.
 *
 * @returns {?UlineArgParser}
 *
 * @example
 * import { arg_parser } from 'uline';
 *
 * // Flat parser
 * const argp = arg_parser();
 * const { args } = argp.parse('echo "hello world" foo');
 * // args → ['echo', 'hello world', 'foo']
 *
 * // Grouped by semicolon
 * const grouped = arg_parser({ line_separator: ';' });
 * const { args: cmds } = grouped.parse('ls -l; echo done');
 * // cmds → [['ls', '-l'], ['echo', 'done']]
 */
export function arg_parser(opts) {};

/**
 * Read a password from the terminal without echo.
 *
 * Displays `prompt` and reads a password using the system's `getpass(3)`,
 * which suppresses terminal echo.
 *
 * Returns the entered password string.
 *
 * Returns `null` if `prompt` is not a string or the system call fails.
 *
 * @function module:uline#getpass
 *
 * @param {string} prompt
 * Text to display before reading the password.
 *
 * @returns {?string}
 *
 * @example
 * import { getpass } from 'uline';
 *
 * const pw = getpass('Password: ');
 * if (pw == null)
 *   die('Failed to read password\n');
 */
export function getpass(prompt) {};

/**
 * Block until a complete line is entered.
 *
 * Ensures the prompt is visible, then reads input in a loop until the
 * `line_check` callback accepts a line or
 * {@link module:uline.state#poll_stop|poll_stop()} is called.
 *
 * Returns the accepted line string.
 *
 * Returns `null` if editing was stopped before a line was accepted (e.g.
 * via `poll_stop()`, Ctrl-C, or Ctrl-D) or if `line_check` rejected and
 * editing continues.
 *
 * @function module:uline.state#poll
 *
 * @returns {?string}
 *
 * @example
 * ed.set_state({ prompt: '> ' });
 * while (true) {
 *   const line = ed.poll();
 *   if (line != null)
 *     process(line);
 * }
 */

/**
 * Read a single raw keystroke, with an optional timeout.
 *
 * Blocks up to `timeout` milliseconds for a keypress. Passing `0` or
 * omitting `timeout` blocks indefinitely.
 *
 * Returns the pressed character as a 1-byte string.
 *
 * Returns `null` on timeout or read error.
 *
 * @function module:uline.state#poll_key
 *
 * @param {int} [timeout=0]
 * Timeout in milliseconds. `0` or omitted means wait indefinitely.
 *
 * @returns {?string}
 *
 * @example
 * // Wait up to 5 s for a keypress
 * const key = ed.poll_key(5000);
 * if (key == null)
 *   print('Timed out\n');
 */

/**
 * Signal a running {@link module:uline.state#poll|poll()} to stop.
 *
 * Sets an internal flag that causes the blocking poll loop to exit on its
 * next iteration. Safe to call from a callback.
 *
 * @function module:uline.state#poll_stop
 *
 * @returns {void}
 *
 * @example
 * const ed = uline.new({
 *   cb: {
 *     interrupt: () => ed.poll_stop(),
 *     line_check: (line) => true,
 *   },
 * });
 */

/**
 * Reset the repeat-count tracking for custom key handlers.
 *
 * Clears the internal `repeat_char` state used by the `key_input` callback's
 * `count` argument. Call this when your handler finishes processing a key
 * sequence.
 *
 * Returns `true`.
 *
 * @function module:uline.state#reset_key_input
 *
 * @returns {boolean}
 */

/**
 * Return the current line buffer contents.
 *
 * Returns an object with the buffer text and cursor byte offset.
 *
 * Returns `null` if the state is closed.
 *
 * @function module:uline.state#get_line
 *
 * @param {boolean} [line2=false]
 * When truthy, returns the secondary line buffer instead of the primary.
 *
 * @returns {?UlineLineInfo}
 *
 * @example
 * const { line, pos } = ed.get_line();
 * printf('cursor at byte %d in: %s\n', pos, line);
 */

/**
 * Return the current terminal dimensions.
 *
 * @function module:uline.state#get_window
 *
 * @returns {?UlineWindowInfo}
 *
 * @example
 * const { x: cols, y: rows } = ed.get_window();
 * printf('%d columns × %d rows\n', cols, rows);
 */

/**
 * Programmatically update editor state.
 *
 * Applies any combination of the following changes atomically and
 * redraws the terminal. Unrecognised keys are ignored.
 *
 * Returns `true` on success.
 *
 * Returns `null` if `obj` is not an object or any provided field has
 * the wrong type.
 *
 * @function module:uline.state#set_state
 *
 * @param {object} obj
 * State changes to apply:
 * - `prompt` {string} — primary prompt text (VT100 escapes permitted).
 * - `line` {string} — replace the primary line buffer.
 * - `pos` {int} — move the cursor to this byte offset. Values beyond the
 *   line length are clamped to end-of-line.
 * - `line2_prompt` {string|null} — secondary prompt text. Set to `null`
 *   to disable the secondary editor. The key must be explicitly present
 *   in `obj` (even as `null`) for this field to be processed.
 * - `line2` {string} — replace the secondary line buffer.
 * - `line2_pos` {int} — secondary line cursor byte offset.
 *
 * @returns {?boolean}
 *
 * @example
 * // Change prompt
 * ed.set_state({ prompt: '\x1b[32m$\x1b[0m ' });
 *
 * // Load a history entry
 * ed.set_state({ line: history[idx], pos: 9999 });
 *
 * // Enable a secondary search bar
 * ed.set_state({ line2_prompt: '(search): ', line2: '' });
 *
 * // Disable secondary bar
 * ed.set_state({ line2_prompt: null });
 */

/**
 * Display a hint line below the editing area.
 *
 * Writes `hint` below the current prompt without disturbing the editable
 * line. Erases any previously displayed hint first. Triggers a full redraw
 * if the hint would extend past the bottom of the terminal.
 *
 * Returns `true` on success.
 *
 * Returns `null` if `hint` is not a string.
 *
 * @function module:uline.state#set_hint
 *
 * @param {string} hint
 * Text to display below the prompt (plain text or VT100 sequences).
 *
 * @returns {?boolean}
 *
 * @example
 * // Show a completion hint
 * ed.set_hint('\x1b[2m  → /usr/bin/ls\x1b[0m');
 *
 * // Clear the hint
 * ed.set_hint('');
 */

/**
 * Register or unregister the editor with the uloop event loop.
 *
 * When registered, uloop delivers completed lines to `cb(line)` instead
 * of requiring a blocking {@link module:uline.state#poll|poll()} call.
 * Pass `null` or call without arguments to unregister.
 *
 * The editor handle is kept alive (marked persistent) while registered
 * and released when unregistered.
 *
 * Returns `true` on success.
 *
 * Returns `null` if `cb` is provided but is not callable.
 *
 * @function module:uline.state#set_uloop
 *
 * @param {function} [cb]
 * Callback invoked for each completed line. Receives the accepted line
 * string. Pass `null` or omit to unregister.
 *
 * @returns {?boolean}
 *
 * @example
 * import { init, run } from 'uloop';
 * import * as uline from 'uline';
 *
 * init();
 * const ed = uline.new({ cb: { line_check: (line) => true } });
 * ed.set_state({ prompt: '> ' });
 *
 * ed.set_uloop((line) => {
 *   printf('got: %s\n', line);
 *   ed.set_state({ prompt: '> ' });
 * });
 *
 * run();
 */

/**
 * Temporarily hide the prompt.
 *
 * Moves the cursor to the top-left, erases from the cursor down, and
 * marks a full redraw pending. Use this before printing asynchronous
 * output so it appears above the prompt. Call
 * {@link module:uline.state#refresh_prompt|refresh_prompt()} afterwards
 * to restore the prompt.
 *
 * @function module:uline.state#hide_prompt
 *
 * @returns {void}
 *
 * @example
 * // Print async log output without corrupting the prompt
 * ed.hide_prompt();
 * printf('[log] %s\n', message);
 * ed.refresh_prompt();
 */

/**
 * Redraw the prompt and current line.
 *
 * Switches to raw termios mode if not already active, then redraws the
 * full prompt and line buffer contents.
 *
 * @function module:uline.state#refresh_prompt
 *
 * @returns {void}
 */

/**
 * Close the editor and restore the terminal.
 *
 * Unregisters from uloop, frees the internal state, and restores the
 * original termios settings. After calling, further method calls on this
 * handle return `null`.
 *
 * @function module:uline.state#close
 *
 * @returns {void}
 */

/**
 * Parse a shell command string into tokens.
 *
 * Handles unquoted tokens, single- and double-quoted strings, backslash
 * escapes, and (if the parser was created with `line_separator`) grouping.
 *
 * When `missing` is present in the result, the string ended inside an
 * unclosed quote or after a line-continuation backslash. The value
 * indicates the missing delimiter: `"\\"`, `"'"`, `"\""`, or `"\\\""`.
 *
 * Returns `null` if `str` is not a string.
 *
 * @function module:uline.argp#parse
 *
 * @param {string} str
 * The command string to parse.
 *
 * @returns {?UlineParseResult}
 *
 * @example
 * const argp = uline.arg_parser();
 * const r = argp.parse('ls -l "/my dir"');
 * // r.args → ['ls', '-l', '/my dir']
 * // r.pos  → [[0,2], [3,5], [6,15]]
 *
 * // Detect incomplete input (e.g. for multi-line prompts)
 * const r2 = argp.parse('echo "unclosed');
 * if (r2.missing)
 *   print('Need closing: ', r2.missing, '\n');
 */

/**
 * Check whether a shell command string is syntactically complete.
 *
 * A lightweight scan that does not build token arrays. Returns the missing
 * delimiter string if the input is incomplete, or `null` if it is complete.
 * Possible return values: `"\\"`, `"'"`, `"\""`, `"\\\""`.
 *
 * Returns `null` (complete) if `str` is syntactically valid.
 *
 * Also returns `null` if `str` is not a string (error), which is
 * indistinguishable from a syntactically complete string.
 *
 * @function module:uline.argp#check
 *
 * @param {string} str
 * The string to check.
 *
 * @returns {?string}
 *
 * @example
 * // Use in a multi-line REPL: keep reading until the command is complete
 * let buf = '';
 * const argp = uline.arg_parser();
 * while (argp.check(buf) != null) {
 *   ed.set_state({ prompt: '... ' });
 *   buf += '\n' + ed.poll();
 * }
 * handle(buf);
 */

/**
 * Shell-escape a single token.
 *
 * Returns a safely quoted version of `str` suitable for inclusion in a
 * shell command. If no quoting is needed, returns the string unchanged.
 *
 * Quoting selection:
 * - If `ref` is `"` or `'`, that quoting style is preferred.
 * - Otherwise, the string is scanned for characters that require quoting
 *   (`\n`, `\t`, space, `'`, `"`, backtick); if any are found, double
 *   quotes are used.
 *
 * Returns `null` if `str` is not a string.
 *
 * @function module:uline.argp#escape
 *
 * @param {string} str
 * The token to escape.
 *
 * @param {string} [ref]
 * Preferred quoting character: `"` or `'`. Any other value is ignored.
 *
 * @returns {?string}
 *
 * @example
 * const argp = uline.arg_parser();
 * print(argp.escape('hello world'));   // → '"hello world"'
 * print(argp.escape("it's alive"));   // → '"it\'s alive"'
 * print(argp.escape('safe'));          // → 'safe'
 * print(argp.escape('safe', '"'));     // → '"safe"'
 */
