// Source: https://github.com/openwrt/luci
// Versions: 1
/**
 * # Lua VM Bridge
 *
 * The `lua` module embeds a Lua interpreter inside a ucode script. It lets
 * ucode code create Lua VM instances, evaluate Lua source, call Lua functions,
 * and exchange values in both directions — including passing ucode closures
 * into Lua so they can be called from within Lua code.
 *
 * All standard Lua libraries (`os`, `io`, `string`, `math`, `table`, etc.)
 * are opened automatically when a VM is created.
 *
 * Lua errors (syntax errors, runtime panics) propagate as ucode exceptions
 * and can be caught with `try`/`catch`:
 *
 *   ```javascript
 *   import { create } from 'lua';
 *
 *   const L = create();
 *
 *   L.eval('function add(a, b) return a + b end');
 *
 *   try {
 *     L.eval('error("boom")');
 *   } catch (e) {
 *     print('Caught: ', e.message, '\n');
 *   }
 *   ```
 *
 * @module lua
 */

/**
 * Lua VM instance returned by {@link module:lua#create|create()}.
 *
 * @typedef {{
 *   invoke: function(string, *): *,
 *   eval:   function(string): *,
 *   include: function(string): *,
 *   set:    function(*): ?boolean,
 *   get:    function(string, *): ?LuaValue
 * }} LuaVm
 */

/**
 * Opaque reference to a Lua value held in a VM's registry, returned by
 * {@link module:lua.vm#get|vm.get()},
 * {@link module:lua.value#get|value.get()},
 * and {@link module:lua.value#getraw|value.getraw()}.
 *
 * The reference keeps the parent {@link module:lua.vm|LuaVm} alive. All
 * values derived from a VM share its lifetime.
 *
 * @typedef {{
 *   call:     function(*): *,
 *   invoke:   function(*, *): *,
 *   get:      function(*): ?LuaValue,
 *   getraw:   function(*): ?LuaValue,
 *   getmt:    function(?string): ?LuaValue,
 *   value:    function(): *,
 *   tostring: function(): string
 * }} LuaValue
 */

/**
 * Create a new Lua VM instance.
 *
 * Calls `luaL_newstate()` and opens all standard Lua libraries. The Lua
 * state is closed when the returned handle is garbage-collected.
 *
 * Always returns a valid handle; allocation failure aborts the process.
 *
 * @function module:lua#create
 *
 * @returns {LuaVm}
 *
 * @example
 * import { create } from 'lua';
 *
 * const L = create();
 * L.eval('print("Hello from Lua!")');
 */
export function create() {};

/**
 * Call a Lua global function by name.
 *
 * Looks up `name` in the Lua global table, then calls it with the remaining
 * arguments converted to Lua values. Returns the function's return value(s):
 * a single return value is returned directly; multiple return values are
 * returned as an array; no return values → `null`.
 *
 * Raises a ucode `RuntimeError` on any Lua runtime error, including the full
 * Lua call-stack traceback.
 *
 * Returns `null` if `name` is not a string or the VM handle is invalid.
 *
 * @function module:lua.vm#invoke
 *
 * @param {string} name
 * Name of the Lua global function to call.
 *
 * @param {...*} args
 * Arguments to pass. See value marshalling rules in
 * {@link module:lua|module description}.
 *
 * @returns {*}
 *
 * @example
 * L.eval('function greet(who) return "Hello, " .. who end');
 * const msg = L.invoke('greet', 'world');   // → "Hello, world"
 *
 * L.eval('function multi() return 1, 2, 3 end');
 * const [a, b, c] = L.invoke('multi');      // → [1, 2, 3]
 */

/**
 * Compile and execute a Lua source string.
 *
 * The source is compiled as a Lua chunk and executed immediately. Returns
 * the chunk's return value(s) using the same rules as
 * {@link module:lua.vm#invoke|invoke()}.
 *
 * Raises `SyntaxError` if the Lua source fails to compile.
 *
 * Raises `RuntimeError` on runtime errors, with the full Lua traceback.
 *
 * Returns `null` if the VM handle is invalid.
 *
 * @function module:lua.vm#eval
 *
 * @param {string} source
 * Lua source code to compile and run.
 *
 * @returns {*}
 *
 * @example
 * L.eval('x = 42');
 *
 * const pi = L.eval('return math.pi');   // → 3.14159…
 *
 * try {
 *   L.eval('error("something failed")');
 * } catch (e) {
 *   warn(e.message, '\n');
 * }
 */

/**
 * Load and execute a Lua file.
 *
 * Reads the file at `path`, compiles it as a Lua chunk, and executes it.
 * Returns the chunk's return value(s) using the same rules as
 * {@link module:lua.vm#invoke|invoke()}.
 *
 * Raises `SyntaxError` if the Lua source fails to compile.
 *
 * Raises `RuntimeError` on I/O errors or runtime errors.
 *
 * Returns `null` if the VM handle is invalid.
 *
 * @function module:lua.vm#include
 *
 * @param {string} path
 * Filesystem path to the Lua file.
 *
 * @returns {*}
 *
 * @example
 * L.include('/usr/share/myapp/init.lua');
 *
 * // The file can return a value:
 * const exports = L.include('/usr/share/myapp/exports.lua');
 */

/**
 * Set one or more Lua global variables.
 *
 * **Two calling conventions:**
 *
 * `set(name, value)` — sets the single global `name` to `value`.
 *
 * `set(obj)` — iterates the object's key/value pairs and sets each as a Lua
 * global. This is equivalent to calling `set(key, val)` for each pair.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the VM handle is invalid.
 *
 * **Value marshalling:** ucode values are converted to Lua types. Plain
 * arrays become Lua tables with 1-based integer keys; plain objects become
 * Lua tables with string keys; closures and cfunctions become Lua userdata
 * callable via `__call`. Arrays and objects with prototypes become opaque
 * userdata handles.
 *
 * @function module:lua.vm#set
 *
 * @param {string|*} name_or_obj
 * Either a string global name, or an object whose keys become global names.
 *
 * @param {*} [value]
 * The value to assign (only used when the first argument is a string).
 *
 * @returns {?boolean}
 *
 * @example
 * L.set('DEBUG', true);
 * L.set('VERSION', '2.0');
 *
 * // Set multiple globals at once
 * L.set({
 *   APP_NAME: 'myapp',
 *   MAX_RETRIES: 3,
 * });
 *
 * // Pass a ucode function into Lua
 * L.set('ucfn', (x) => x * 2);
 * L.eval('print(ucfn(21))');   // prints 42
 */

/**
 * Get a Lua global (optionally nested via table traversal).
 *
 * Looks up `name` in the Lua global table. For each additional `key`
 * argument, performs a table lookup (`__index` metamethods are respected)
 * on the current value.
 *
 * Returns the final Lua value as an opaque {@link module:lua~LuaValue|LuaValue}
 * handle. Call {@link module:lua.value#value|.value()} on the result to
 * convert it to a native ucode value.
 *
 * Returns `null` if any intermediate table lookup fails (non-table
 * encountered), or if argument types are invalid.
 *
 * @function module:lua.vm#get
 *
 * @param {string} name
 * Lua global variable name.
 *
 * @param {...*} keys
 * Optional chain of table keys to traverse.
 *
 * @returns {?LuaValue}
 *
 * @example
 * L.eval('t = { nested = { val = 99 } }');
 *
 * // Single-level get
 * const raw = L.get('t').value();         // → { nested: { val: 99 } }
 *
 * // Nested traversal
 * const v = L.get('t', 'nested', 'val');  // LuaValue
 * print(v.value(), '\n');                  // → 99
 */

/**
 * Call the Lua value as a function.
 *
 * Pushes all arguments (converted from ucode) and calls the referenced Lua
 * value. Returns the result(s) using the same rules as
 * {@link module:lua.vm#invoke|invoke()}.
 *
 * Raises `RuntimeError` on Lua errors.
 *
 * Arguments are positional — no implicit `self` is passed. For method
 * calls use {@link module:lua.value#invoke|invoke()} instead.
 *
 * @function module:lua.value#call
 *
 * @param {...*} args
 * Arguments to pass to the Lua function.
 *
 * @returns {*}
 *
 * @example
 * L.eval('function square(x) return x * x end');
 * const sq = L.get('square');
 * print(sq.call(7), '\n');   // → 49
 */

/**
 * Call a method on the Lua table value.
 *
 * Looks up `method` in the table, then calls it with the table as the
 * implicit first argument (`self`) followed by `args`. This exactly
 * replicates the Lua `table:method(args)` syntax.
 *
 * Raises `RuntimeError` on Lua errors.
 *
 * @function module:lua.value#invoke
 *
 * @param {*} method
 * Method key (usually a string) to look up in the table.
 *
 * @param {...*} args
 * Additional arguments after `self`.
 *
 * @returns {*}
 *
 * @example
 * L.eval('obj = { greet = function(self, name) return "Hi " .. name end }');
 * const obj = L.get('obj');
 * const msg = obj.invoke('greet', 'world');
 * print(msg.value(), '\n');   // → "Hi world"
 */

/**
 * Traverse a chain of table lookups using `__index` metamethods.
 *
 * Performs `lua_gettable` for each key in sequence on the current value.
 * Stops and returns `null` if any intermediate value is not a table.
 *
 * Returns the final value as a {@link module:lua~LuaValue|LuaValue} handle.
 *
 * @function module:lua.value#get
 *
 * @param {...*} keys
 * Chain of table keys to traverse.
 *
 * @returns {?LuaValue}
 *
 * @example
 * L.eval('deep = { a = { b = { c = 42 } } }');
 * const val = L.get('deep').get('a', 'b', 'c');
 * print(val.value(), '\n');   // → 42
 */

/**
 * Traverse a chain of raw (no-metamethod) table lookups.
 *
 * Like {@link module:lua.value#get|get()} but uses `lua_rawget` / `lua_rawgeti`
 * at each step, bypassing any `__index` metamethods.
 *
 * Returns `null` if any intermediate value is not a table.
 *
 * @function module:lua.value#getraw
 *
 * @param {...*} keys
 * Chain of raw table keys to traverse.
 *
 * @returns {?LuaValue}
 *
 * @example
 * // Access a table value without triggering __index
 * const v = L.get('t').getraw('key');
 */

/**
 * Get the metatable or a field from the metatable.
 *
 * Without arguments, returns the entire metatable as a
 * {@link module:lua~LuaValue|LuaValue}.
 *
 * When `key` is provided, looks up that field inside the metatable.
 *
 * Returns `null` if the value has no metatable, if the requested key is
 * `nil` in the metatable, or if `key` is not a string when provided.
 *
 * @function module:lua.value#getmt
 *
 * @param {string} [key]
 * Optional field name to look up inside the metatable.
 *
 * @returns {?LuaValue}
 *
 * @example
 * const tostring_fn = obj.getmt('__tostring');
 * if (tostring_fn)
 *   print(tostring_fn.call(obj).value(), '\n');
 */

/**
 * Convert the Lua value to a native ucode value.
 *
 * Conversion rules:
 * - `nil` → `null`
 * - `boolean` → `bool`
 * - integer-valued number → `int`
 * - fractional number → `double`
 * - `string` → `string` (binary-safe)
 * - array-like table (integer keys 1…N, not too sparse) → `array`
 * - dict-like table (string keys) → `object`
 * - Lua function / thread / foreign userdata → opaque `LuaValue` handle
 *
 * @function module:lua.value#value
 *
 * @returns {*}
 *
 * @example
 * L.eval('t = { 1, 2, 3 }');
 * const arr = L.get('t').value();   // → [1, 2, 3]
 *
 * L.eval('t = { x = 1, y = 2 }');
 * const obj = L.get('t').value();   // → { x: 1, y: 2 }
 */

/**
 * Convert the Lua value to a string.
 *
 * Invokes `__tostring` if the value has a metatable with that method.
 * For plain scalars (nil, boolean, number, string), converts to its
 * natural string form. For functions, threads, and other types without
 * `__tostring`, returns `"typename (0xpointer)"`.
 *
 * Always returns a string (never `null`).
 *
 * @function module:lua.value#tostring
 *
 * @returns {string}
 *
 * @example
 * L.eval('obj = setmetatable({}, { __tostring = function() return "MyObj" end })');
 * print(L.get('obj').tostring(), '\n');   // → "MyObj"
 *
 * L.eval('f = function() end');
 * print(L.get('f').tostring(), '\n');     // → "function (0x…)"
 */
