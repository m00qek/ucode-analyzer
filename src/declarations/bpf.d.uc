// Source: https://github.com/openwrt/openwrt @ 85e15f34ace3077d960682564119597dd82afea1 (package/utils/ucode-mod-bpf/src/bpf.c)
/**
 * # eBPF Programs and Maps
 *
 * The `bpf` module provides a ucode binding to
 * {@link https://github.com/libbpf/libbpf libbpf} for loading eBPF programs
 * and interacting with eBPF maps. It is aimed primarily at TC (traffic
 * control) eBPF classifiers and map-based runtime configuration on OpenWrt.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```javascript
 *   import { open_module, BPF_PROG_TYPE_SCHED_CLS } from 'bpf';
 *
 *   const mod = open_module('/usr/lib/bpf/classifier.o', {
 *     'program-type': { classifier: BPF_PROG_TYPE_SCHED_CLS },
 *   });
 *   mod.get_program('classifier').tc_attach('eth0', 'ingress', 1, 0);
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```javascript
 *   import * as bpf from 'bpf';
 *
 *   const mod = bpf.open_module('/usr/lib/bpf/classifier.o');
 *   const stats = mod.get_map('stats');
 *   const iter = stats.iterator();
 *   let key;
 *   while ((key = iter.next_int()) != null)
 *     printf('key=%d val=%s\n', key, stats.get(key));
 *   ```
 *
 * **Key/value encoding:** map keys and values are passed as either an integer
 * (for 4-byte or 8-byte fields) or a raw byte string whose length exactly
 * matches the field's size. Use the {@link module:struct|struct} module to
 * pack/unpack structured data.
 *
 * @module bpf
 */

/**
 * Loaded BPF object returned by {@link module:bpf#open_module|open_module()}.
 *
 * @typedef {{
 *   get_maps: function(): string[],
 *   get_map: function(string): ?BpfMap,
 *   get_programs: function(): string[],
 *   get_program: function(string): ?BpfProgram
 * }} BpfModule
 */

/**
 * BPF map returned by {@link module:bpf#open_map|open_map()} or
 * {@link module:bpf.module#get_map|module.get_map()}.
 *
 * Keys and values are passed as integers (u32 or u64) or exact-length raw
 * byte strings.
 *
 * @typedef {{
 *   get: function(*): ?string,
 *   set: function(*, *, ?int): ?string,
 *   delete: function(*, ?boolean): *,
 *   delete_all: function(?function): boolean,
 *   foreach: function(function): boolean,
 *   iterator: function(): ?BpfMapIter,
 *   pin: function(string): ?boolean
 * }} BpfMap
 */

/**
 * Stateful key iterator returned by {@link module:bpf.map#iterator|map.iterator()}.
 *
 * @typedef {{
 *   next: function(): ?string,
 *   next_int: function(): ?int
 * }} BpfMapIter
 */

/**
 * BPF program returned by {@link module:bpf#open_program|open_program()} or
 * {@link module:bpf.module#get_program|module.get_program()}.
 *
 * @typedef {{
 *   pin: function(string): ?boolean,
 *   tc_attach: function(string, string, int, int): ?boolean
 * }} BpfProgram
 */

/**
 * BPF program type constant: TC classifier (`BPF_PROG_TYPE_SCHED_CLS`).
 * Pass in the `program-type` option of {@link module:bpf#open_module|open_module()}.
 *
 * @type {int}
 */
export const BPF_PROG_TYPE_SCHED_CLS = 3;

/**
 * BPF program type constant: TC action (`BPF_PROG_TYPE_SCHED_ACT`).
 * Pass in the `program-type` option of {@link module:bpf#open_module|open_module()}.
 *
 * @type {int}
 */
export const BPF_PROG_TYPE_SCHED_ACT = 4;

/**
 * Map update flag: create a new entry or update an existing one.
 * Default behaviour for {@link module:bpf.map#set|map.set()}.
 *
 * @type {int}
 */
export const BPF_ANY = 0;

/**
 * Map update flag: create a new entry only; fail if the key already exists.
 *
 * @type {int}
 */
export const BPF_NOEXIST = 1;

/**
 * Map update flag: update an existing entry only; fail if the key is absent.
 *
 * @type {int}
 */
export const BPF_EXIST = 2;

/**
 * Map update flag: use the per-entry spinlock (requires `BPF_F_NO_PREALLOC`
 * map and kernel ≥ 5.1).
 *
 * @type {int}
 */
export const BPF_F_LOCK = 4;

/**
 * Query the last error from a bpf operation.
 *
 * Returns a human-readable error string when called without arguments.
 *
 * Returns the raw errno integer when called with a truthy argument.
 *
 * Returns `null` if no error is pending.
 *
 * Calling this function **clears** the pending error, so each error can
 * only be retrieved once.
 *
 * @function module:bpf#error
 *
 * @param {boolean} [numeric=false]
 * If truthy, return the raw errno integer instead of a string.
 *
 * @returns {?string|?int}
 *
 * @example
 * const map = bpf.open_map('/sys/fs/bpf/missing');
 * if (!map)
 *   die(`open_map failed: ${bpf.error()}\n`);
 */
export function error(numeric) {};

/**
 * Install a custom libbpf debug message handler.
 *
 * Overrides the default libbpf print function. The handler is called for
 * every diagnostic message libbpf emits during map/program operations.
 *
 * Pass `null` or any non-callable value to restore the default handler.
 *
 * Always returns `null`.
 *
 * @function module:bpf#set_debug_handler
 *
 * @param {function} handler
 * Callback receiving `(level, message)`:
 * - `level` {int} — severity: `0` = warning, `1` = info, `2` = debug.
 * - `message` {string} — the formatted log message.
 *
 * @returns {null}
 *
 * @example
 * bpf.set_debug_handler((level, msg) => {
 *   if (level === 0)
 *     warn(`[bpf] ${msg}`);
 * });
 */
export function set_debug_handler(handler) {};

/**
 * Load a BPF ELF object file.
 *
 * Opens and loads the BPF programs and maps defined in the given ELF `.o`
 * file using libbpf. On first call, raises `RLIMIT_MEMLOCK` to unlimited.
 *
 * Returns the loaded module handle on success.
 *
 * Returns `null` on any failure (file not found, verifier rejection, etc.).
 * Call {@link module:bpf#error|error()} for details.
 *
 * @function module:bpf#open_module
 *
 * @param {string} path
 * Filesystem path to the BPF ELF object file (e.g.
 * `"/usr/lib/bpf/classifier.o"`).
 *
 * @param {object} [opts]
 * Optional load-time configuration:
 * - `rodata` {string} — raw bytes written verbatim into the first
 *   `.rodata` map before loading. The length must exactly match the
 *   `.rodata` section size. Use this to inject compile-time constants
 *   into the BPF program at load time.
 * - `program-type` {object} — map of `{ programName: BPF_PROG_TYPE_* }`
 *   overriding the program type for each named program before loading.
 *
 * @returns {?BpfModule}
 *
 * @example
 * import * as bpf from 'bpf';
 *
 * const mod = bpf.open_module('/usr/lib/bpf/tc_filter.o', {
 *   'program-type': {
 *     ingress_filter: bpf.BPF_PROG_TYPE_SCHED_CLS,
 *   },
 * });
 *
 * if (!mod)
 *   die(`Failed to load BPF module: ${bpf.error()}\n`);
 *
 * mod.get_program('ingress_filter').tc_attach('eth0', 'ingress', 1, 0);
 */
export function open_module(path, opts) {};

/**
 * Open a pinned BPF map from the BPF filesystem.
 *
 * Retrieves the map fd from the bpffs path and reads its key/value sizes
 * from the kernel. The returned handle owns the fd and closes it on GC.
 *
 * Returns the map handle on success.
 *
 * Returns `null` if the path does not exist or is not a map.
 *
 * @function module:bpf#open_map
 *
 * @param {string} path
 * bpffs path to the pinned map (e.g. `"/sys/fs/bpf/mymap"`).
 *
 * @returns {?BpfMap}
 *
 * @example
 * import * as bpf from 'bpf';
 *
 * const map = bpf.open_map('/sys/fs/bpf/allowed_ips');
 * if (!map)
 *   die(`open_map: ${bpf.error()}\n`);
 *
 * // Integer key (4 bytes) → raw value bytes
 * const val = map.get(0x0101a8c0); // 192.168.1.1 in host-byte-order
 */
export function open_map(path) {};

/**
 * Open a pinned BPF program from the BPF filesystem.
 *
 * Retrieves the program fd from the bpffs path. The returned handle owns
 * the fd and closes it on GC.
 *
 * Returns the program handle on success.
 *
 * Returns `null` if the path does not exist or is not a program.
 *
 * @function module:bpf#open_program
 *
 * @param {string} path
 * bpffs path to the pinned program (e.g. `"/sys/fs/bpf/myprog"`).
 *
 * @returns {?BpfProgram}
 *
 * @example
 * const prog = bpf.open_program('/sys/fs/bpf/classifier');
 * prog.tc_attach('eth0', 'ingress', 1, 0);
 */
export function open_program(path) {};

/**
 * Detach a TC BPF program from a network interface.
 *
 * Removes any TC BPF attachment at the given interface, direction, and
 * priority. Creates the clsact qdisc if it does not exist (harmlessly).
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure (e.g. invalid direction, interface not found).
 *
 * @function module:bpf#tc_detach
 *
 * @param {string} ifname
 * Network interface name (e.g. `"eth0"`).
 *
 * @param {string} type
 * Attach point: `"ingress"` or `"egress"`.
 *
 * @param {int} prio
 * TC priority (0–65535). Must match the priority used during attach.
 *
 * @returns {?boolean}
 *
 * @example
 * // Clean up after attaching at priority 1
 * bpf.tc_detach('eth0', 'ingress', 1);
 */
export function tc_detach(ifname, type, prio) {};

/**
 * List all map names in the loaded BPF object.
 *
 * @function module:bpf.module#get_maps
 *
 * @returns {string[]}
 *
 * @example
 * const mod = bpf.open_module('/usr/lib/bpf/prog.o');
 * print(mod.get_maps(), '\n'); // e.g. ["stats", "config", "allowed_ips"]
 */

/**
 * Look up a map by name within the loaded BPF object.
 *
 * Returns the map handle on success. The handle does not own the
 * underlying fd — the module does. Do not use the map after the module
 * is garbage-collected.
 *
 * Returns `null` if no map with that name exists.
 *
 * @function module:bpf.module#get_map
 *
 * @param {string} name
 * Map name as defined in the BPF C source.
 *
 * @returns {?BpfMap}
 *
 * @example
 * const mod = bpf.open_module('/usr/lib/bpf/prog.o');
 * const stats = mod.get_map('pkt_stats');
 * printf('packets: %d\n', stats.get(0));
 */

/**
 * List all program names in the loaded BPF object.
 *
 * @function module:bpf.module#get_programs
 *
 * @returns {string[]}
 *
 * @example
 * const mod = bpf.open_module('/usr/lib/bpf/prog.o');
 * print(mod.get_programs(), '\n'); // e.g. ["ingress_cls", "egress_cls"]
 */

/**
 * Look up a program by name within the loaded BPF object.
 *
 * Returns the program handle on success. The handle does not own the
 * underlying fd — the module does.
 *
 * Returns `null` if no program with that name exists.
 *
 * @function module:bpf.module#get_program
 *
 * @param {string} name
 * Program name as defined in the BPF C source (the function name).
 *
 * @returns {?BpfProgram}
 *
 * @example
 * const prog = mod.get_program('ingress_cls');
 * prog.tc_attach('br-lan', 'ingress', 10, 0);
 */

/**
 * Look up a map entry by key.
 *
 * Returns the raw value bytes on success.
 *
 * Returns `null` on a cache miss or error. Note: a miss does **not** set
 * an error — {@link module:bpf#error|error()} returns `null` after a miss
 * too, so miss and error are indistinguishable.
 *
 * @function module:bpf.map#get
 *
 * @param {int|string} key
 * Key as a u32/u64 integer or an exact-length raw byte string.
 *
 * @returns {?string}
 * Raw value bytes, or `null` on miss/error.
 *
 * @example
 * // 4-byte integer key
 * const val = map.get(42);
 *
 * // Struct key via struct module
 * import { unpack } from 'struct';
 * const raw = map.get(pack('>I', [192 << 24 | 168 << 16 | 1 << 8 | 1]));
 */

/**
 * Create or update a map entry.
 *
 * Returns the written value bytes on success.
 *
 * Returns `null` on failure. Call {@link module:bpf#error|error()} for details.
 *
 * @function module:bpf.map#set
 *
 * @param {int|string} key
 * Key as a u32/u64 integer or an exact-length raw byte string.
 *
 * @param {int|string} value
 * Value as a u32/u64 integer or an exact-length raw byte string.
 *
 * @param {int} [flags=BPF_ANY]
 * Update semantics: {@link module:bpf.BPF_ANY|BPF_ANY} (default),
 * {@link module:bpf.BPF_NOEXIST|BPF_NOEXIST}, or
 * {@link module:bpf.BPF_EXIST|BPF_EXIST}.
 *
 * @returns {?string}
 *
 * @example
 * map.set(42, 1);                       // create or update with integer
 * map.set(42, 1, bpf.BPF_NOEXIST);     // create only
 * map.set(42, 0, bpf.BPF_EXIST);       // update only (clear counter)
 */

/**
 * Delete a map entry.
 *
 * When called without `return_value`, deletes the entry and returns `true`
 * on success or `false` if the key was not found.
 *
 * When `return_value` is truthy, atomically looks up and deletes the entry,
 * returning the old value bytes, or `null` on failure.
 *
 * @function module:bpf.map#delete
 *
 * @param {int|string} key
 * Key as a u32/u64 integer or an exact-length raw byte string.
 *
 * @param {boolean} [return_value=false]
 * When truthy, atomically fetch and delete (returns old value instead of
 * boolean).
 *
 * @returns {boolean|?string}
 *
 * @example
 * // Simple delete
 * if (!map.delete(42))
 *   print('key 42 not found\n');
 *
 * // Atomic fetch-and-delete
 * const old = map.delete(42, true);
 * if (old != null)
 *   printf('old value was: %H\n', old);
 */

/**
 * Delete all entries from the map, with an optional filter.
 *
 * Iterates every key in the map. Without a filter, deletes all entries.
 * With a filter, deletes only entries for which `filter(key)` returns
 * a truthy value. Iteration stops early if the filter returns `null` or
 * throws.
 *
 * Always returns `true`.
 *
 * @function module:bpf.map#delete_all
 *
 * @param {function} [filter]
 * Optional predicate receiving the raw key bytes. Return truthy to
 * delete the entry, falsy to keep it.
 *
 * @returns {boolean}
 *
 * @example
 * // Delete everything
 * map.delete_all();
 *
 * // Delete only entries with even integer keys
 * import { unpack } from 'struct';
 * map.delete_all((key) => unpack('>I', key)[0] % 2 === 0);
 */

/**
 * Iterate over all keys in the map.
 *
 * Calls `callback(key)` for each key (raw byte string). Stops early
 * if the callback returns exactly `false` (boolean). Any other falsy
 * return value (null, 0, "") does **not** stop iteration.
 *
 * Returns `true` if at least one key was visited, `false` if the map
 * was empty.
 *
 * @function module:bpf.map#foreach
 *
 * @param {function} callback
 * Called with the raw key bytes for each entry. Return `false` (boolean)
 * to stop early.
 *
 * @returns {boolean}
 *
 * @example
 * map.foreach((key) => {
 *   const val = map.get(key);
 *   printf('key=%H val=%H\n', key, val);
 * });
 */

/**
 * Create a stateful key iterator for the map.
 *
 * Returns an iterator that yields keys one at a time via
 * {@link module:bpf.map_iter#next|next()} or
 * {@link module:bpf.map_iter#next_int|next_int()}. The iterator holds a
 * strong reference to the map.
 *
 * Returns `null` on allocation failure.
 *
 * @function module:bpf.map#iterator
 *
 * @returns {?BpfMapIter}
 *
 * @example
 * const iter = map.iterator();
 * let key;
 * while ((key = iter.next_int()) != null)
 *   printf('key=%d\n', key);
 */

/**
 * Pin the map to the BPF filesystem.
 *
 * Creates a persistent reference at `path` so the map survives process
 * exit. The parent directory must exist.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure.
 *
 * @function module:bpf.map#pin
 *
 * @param {string} path
 * bpffs destination path (e.g. `"/sys/fs/bpf/mymap"`).
 *
 * @returns {?boolean}
 *
 * @example
 * mod.get_map('config').pin('/sys/fs/bpf/myapp_config');
 */

/**
 * Advance to the next key and return it as raw bytes.
 *
 * Returns the current key as a raw byte string, then advances to the
 * next position.
 *
 * Returns `null` when the iterator is exhausted.
 *
 * @function module:bpf.map_iter#next
 *
 * @returns {?string}
 *
 * @example
 * const iter = map.iterator();
 * let key;
 * while ((key = iter.next()) != null) {
 *   import { unpack } from 'struct';
 *   const [k] = unpack('>I', key);
 *   printf('key=%d\n', k);
 * }
 */

/**
 * Advance to the next key and return it as an integer.
 *
 * Only valid when the map's key size is 4 bytes (u32) or 8 bytes (u64).
 * Returns `null` for other key sizes or when the iterator is exhausted.
 *
 * @function module:bpf.map_iter#next_int
 *
 * @returns {?int}
 *
 * @example
 * const iter = map.iterator();
 * let key;
 * while ((key = iter.next_int()) != null)
 *   printf('key=%d val=%s\n', key, map.get(key));
 */

/**
 * Pin the program to the BPF filesystem.
 *
 * Creates a persistent reference at `path` so the program can be
 * retrieved later with {@link module:bpf#open_program|open_program()}.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure.
 *
 * @function module:bpf.program#pin
 *
 * @param {string} path
 * bpffs destination path (e.g. `"/sys/fs/bpf/myprog"`).
 *
 * @returns {?boolean}
 */

/**
 * Attach the program to a network interface as a TC classifier.
 *
 * Creates the clsact qdisc if absent, removes any existing attachment at
 * the given priority, then attaches this program. Only one attachment per
 * (interface, direction, priority) tuple is possible through this API.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure (invalid direction, interface error, etc.).
 *
 * @function module:bpf.program#tc_attach
 *
 * @param {string} ifname
 * Network interface name (e.g. `"eth0"`, `"br-lan"`).
 *
 * @param {string} type
 * Attach point: `"ingress"` or `"egress"`.
 *
 * @param {int} prio
 * TC priority (0–65535). Use a unique value per attachment.
 *
 * @param {int} classid
 * TC class ID (u32). Pass `0` for the default class.
 *
 * @returns {?boolean}
 *
 * @example
 * import * as bpf from 'bpf';
 *
 * const mod = bpf.open_module('/usr/lib/bpf/filter.o', {
 *   'program-type': { ingress: bpf.BPF_PROG_TYPE_SCHED_CLS },
 * });
 *
 * mod.get_program('ingress').tc_attach('eth0', 'ingress', 1, 0);
 *
 * // Later, to detach:
 * bpf.tc_detach('eth0', 'ingress', 1);
 */
