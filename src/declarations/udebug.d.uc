// Source: https://github.com/openwrt/udebug
// Versions: 2025.08.24~edeb4d6d, 2026.01.16~875e1a7a
/**
 * # udebug — Shared-memory ring-buffer debug tracing
 *
 * The `udebug` module provides access to the OpenWrt
 * {@link https://github.com/openwrt/udebug udebug} shared-memory ring-buffer
 * system. Processes write diagnostic entries (strings, packets, or blobmsg
 * data) into named rings managed by the `udebugd` daemon; any other process
 * can open those rings and read or capture them as PCAPng.
 *
 * **Roles:**
 * - **Producer** — calls {@link module:udebug#create_ring|create_ring()} to
 *   register a local write ring, then calls
 *   {@link module:udebug.wbuf#add|wbuf.add()} to append entries.
 * - **Consumer** — calls {@link module:udebug#get_ring|get_ring()} to open a
 *   remote read ring, fetches snapshots, and either iterates them with
 *   {@link module:udebug#foreach_packet|foreach_packet()} or dumps them to a
 *   PCAPng stream with {@link module:udebug#pcap_file|pcap_file()} /
 *   {@link module:udebug#pcap_udp|pcap_udp()}.
 *
 * Requires {@link module:uloop|uloop} when using poll callbacks.
 *
 * ```javascript
 * import { init, run } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * // Producer: write string entries to a named ring
 * udebug.init();
 * const ring = udebug.create_ring({ name: 'myapp/events', size: 65536, entries: 256 });
 * ring.add('application started');
 *
 * // Consumer: capture a remote ring to a pcap file
 * udebug.init();
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'myapp', ring_name: 'events', pid: 1234 });
 * const pcap = udebug.pcap_file('/tmp/capture.pcapng');
 * rbuf.set_poll_cb(function() {
 *   pcap.write(this.fetch());
 * });
 * run();
 * ```
 *
 * @module udebug
 */

/**
 * Ring metadata returned by {@link module:udebug.rbuf#get_info|rbuf.get_info()}.
 *
 * @typedef {{
 *   ring_size: int,
 *   data_size: int,
 *   format: int,
 *   sub_format: int
 * }} UdebugRingInfo
 */

/**
 * Local write ring returned by {@link module:udebug#create_ring|create_ring()}.
 *
 * @typedef {{
 *   add: function(*): ?boolean,
 *   flags: function(): ?int,
 *   close: function(): void
 * }} UdebugWriteRing
 */

/**
 * Remote read ring returned by {@link module:udebug#get_ring|get_ring()}.
 *
 * @typedef {{
 *   fetch: function(): ?UdebugSnapshot,
 *   set_poll_cb: function(?function): ?boolean,
 *   change_flags: function(int, int): ?boolean,
 *   get_flags: function(): ?int,
 *   set_fetch_duration: function(int): ?boolean,
 *   set_fetch_count: function(int): ?boolean,
 *   get_info: function(): ?UdebugRingInfo,
 *   close: function(): void
 * }} UdebugReadRing
 */

/**
 * Kernel ftrace ring returned by {@link module:udebug#trace_ring|trace_ring()}.
 *
 * @typedef {{
 *   set_poll_cb: function(?function): ?boolean,
 *   set_file: function(string, string): ?boolean,
 *   fetch: function(): ?UdebugSnapshot,
 *   close: function(): void
 * }} UdebugTraceRing
 */

/**
 * Point-in-time snapshot of ring contents returned by
 * {@link module:udebug.rbuf#fetch|rbuf.fetch()} and
 * {@link module:udebug.tbuf#fetch|tbuf.fetch()}.
 *
 * @typedef {{
 *   get_ring: function(): ?UdebugReadRing,
 *   entries: function(): ?int
 * }} UdebugSnapshot
 */

/**
 * PCAPng output stream returned by {@link module:udebug#pcap_file|pcap_file()}
 * and {@link module:udebug#pcap_udp|pcap_udp()}.
 *
 * @typedef {{
 *   write: function(*): ?boolean,
 *   close: function(): void
 * }} UdebugPcap
 */

/**
 * Ring data format: raw network packets. The ring's `sub_format` field
 * holds the pcap DLT link type. Pass a `DLT_*` constant as the `format`
 * value in {@link module:udebug#create_ring|create_ring()}.
 *
 * @type {int}
 */
export const FORMAT_PACKET = 0;

/**
 * Ring data format: plain text strings.
 *
 * @type {int}
 */
export const FORMAT_STRING = 1;

/**
 * Ring data format: blobmsg binary-encoded data.
 *
 * @type {int}
 */
export const FORMAT_BLOBMSG = 2;

/**
 * pcap link type: Ethernet II.
 *
 * @type {int}
 */
export const DLT_ETHERNET = 1;

/**
 * pcap link type: PPP.
 *
 * @type {int}
 */
export const DLT_PPP = 50;

/**
 * pcap link type: raw IEEE 802.11.
 *
 * @type {int}
 */
export const DLT_IEEE_802_11 = 105;

/**
 * pcap link type: IEEE 802.11 with radiotap header.
 *
 * @type {int}
 */
export const DLT_IEEE_802_11_RADIOTAP = 127;

/**
 * pcap link type: Linux Netlink.
 *
 * @type {int}
 */
export const DLT_NETLINK = 253;

/**
 * Connect to the udebug daemon.
 *
 * Establishes a connection to `udebugd`. Must be called before any ring
 * operations. If already connected and `path` is `null`, returns `true`
 * immediately without reconnecting.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the daemon is unreachable and `auto` is falsy.
 *
 * @function module:udebug#init
 *
 * @param {string} [path=null]
 * Path to the udebug daemon socket. Defaults to `/var/run/udebug.sock`.
 *
 * @param {boolean} [auto=true]
 * When `true` (the default), uses auto-connect mode: the module reconnects
 * automatically if the daemon restarts. When explicitly `false`, uses a
 * one-shot connection that fails immediately if the daemon is absent.
 *
 * @returns {?boolean}
 *
 * @example
 * import * as udebug from 'udebug';
 *
 * // Connect with defaults (auto-reconnect, default socket path)
 * udebug.init();
 *
 * // One-shot connection to a custom socket
 * const ok = udebug.init('/var/run/myapp-udebug.sock', false);
 * if (!ok)
 *   die('udebug daemon not running\n');
 */
export function init(path, auto) {};

/**
 * Register a local write ring with the udebug daemon.
 *
 * Allocates a shared-memory ring buffer and registers it under the given
 * name. Other processes can then open this ring with
 * {@link module:udebug#get_ring|get_ring()} to read or capture entries.
 *
 * Returns a write-ring handle on success.
 *
 * Returns `null` on allocation or registration failure.
 *
 * @function module:udebug#create_ring
 *
 * @param {Object} meta
 * Ring configuration:
 * - `name` {string} — ring name as registered with the daemon, e.g.
 *   `"myapp/packets"`. By convention, `"process/ringname"` is used.
 * - `size` {int} — total data buffer capacity in bytes.
 * - `entries` {int} — maximum number of ring entries (circular slots).
 * - `format` {int} (optional) — when set to a `DLT_*` constant, the ring
 *   is created as `FORMAT_PACKET` with that link type. When omitted, the
 *   ring is `FORMAT_STRING`. `FORMAT_BLOBMSG` is not settable here.
 * - `flags` {string[]} (optional) — flag names for remotely-controlled
 *   verbosity. Each name maps to a bitmask bit (bit 0, 1, 2, …) readable
 *   via {@link module:udebug.wbuf#flags|wbuf.flags()}.
 *
 * @returns {?UdebugWriteRing}
 *
 * @example
 * import { init } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * init();
 * udebug.init();
 *
 * // String ring for log messages
 * const log_ring = udebug.create_ring({ name: 'myapp/log', size: 65536, entries: 512 });
 *
 * // Packet ring for captured Ethernet frames
 * const pkt_ring = udebug.create_ring({
 *   name: 'myapp/capture',
 *   size: 1048576,
 *   entries: 1024,
 *   format: udebug.DLT_ETHERNET,
 *   flags: ['capture_enabled', 'verbose'],
 * });
 *
 * if (pkt_ring.flags() & 1)
 *   pkt_ring.add(raw_frame);
 */
export function create_ring(meta) {};

/**
 * Open a remote ring for reading.
 *
 * Maps a ring owned by another process into the current process's address
 * space. The descriptor fields correspond to the information reported by
 * the udebug daemon (e.g. via ubus).
 *
 * Returns a read-ring handle on success.
 *
 * Returns `null` if the ring ID cannot be mapped.
 *
 * @function module:udebug#get_ring
 *
 * @param {Object} desc
 * Ring descriptor as reported by the daemon:
 * - `id` {int} — ring ID assigned by the daemon.
 * - `proc_name` {string} — owning process name.
 * - `ring_name` {string} — ring name.
 * - `pid` {int} — owning process PID.
 *
 * @returns {?UdebugReadRing}
 *
 * @example
 * import { init, run } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * init();
 * udebug.init();
 *
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'netifd', ring_name: 'packets', pid: 142 });
 * rbuf.set_fetch_duration(5); // only last 5 seconds
 * const snap = rbuf.fetch();
 * udebug.foreach_packet(snap, (snap, data, ts) => {
 *   printf('%d bytes at %d us\n', length(data), ts);
 * });
 */
export function get_ring(desc) {};

/**
 * Open the kernel ftrace pipe as a udebug ring.
 *
 * Creates (or recreates) a named ftrace instance under
 * `/sys/kernel/debug/tracing/instances/<instance>/` and opens its
 * `trace_pipe`. Requires debugfs to be mounted and root access.
 *
 * The resulting snapshots can be passed to
 * {@link module:udebug#foreach_packet|foreach_packet()} or
 * {@link module:udebug.pcap#write|pcap.write()}, but
 * {@link module:udebug.snapshot#get_ring|snapshot.get_ring()} returns
 * `null` for them (they have no user-visible read ring).
 *
 * Returns a trace-ring handle on success.
 *
 * Returns `null` on failure (debugfs not mounted, insufficient permissions,
 * or kernel tracing not supported).
 *
 * @function module:udebug#trace_ring
 *
 * @param {string} [instance="udebug"]
 * Name of the ftrace instance directory to create under
 * `/sys/kernel/debug/tracing/instances/`.
 *
 * @returns {?UdebugTraceRing}
 *
 * @example
 * import { init, run } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * init();
 * udebug.init();
 *
 * const tbuf = udebug.trace_ring('myapp');
 * tbuf.set_file('tracing_on', '1');
 * tbuf.set_file('events/net/enable', '1');
 *
 * const pcap = udebug.pcap_file('/tmp/trace.pcapng');
 * tbuf.set_poll_cb(function() {
 *   const snap = this.fetch();
 *   if (snap) pcap.write(snap);
 * });
 * run();
 */
export function trace_ring(instance) {};

/**
 * Open a PCAPng output file.
 *
 * Creates (or truncates) a file at `path` and writes a PCAPng Section
 * Header Block immediately. Snapshots are written with
 * {@link module:udebug.pcap#write|pcap.write()}.
 *
 * Returns a pcap handle on success.
 *
 * Returns `null` if the file cannot be opened.
 *
 * @function module:udebug#pcap_file
 *
 * @param {string} [path]
 * Output file path. If omitted or `null`, writes to stdout.
 *
 * @param {Object} [meta]
 * Optional PCAPng section header metadata:
 * - `hw` {string} — hardware description.
 * - `os` {string} — operating system description.
 * - `app` {string} — application description.
 *
 * @returns {?UdebugPcap}
 *
 * @example
 * import * as udebug from 'udebug';
 *
 * udebug.init();
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'hostapd', ring_name: 'wlan0', pid: 200 });
 * const pcap = udebug.pcap_file('/tmp/hostapd.pcapng', { app: 'my-capture' });
 * pcap.write(rbuf.fetch());
 * pcap.close();
 */
export function pcap_file(path, meta) {};

/**
 * Stream PCAPng output over UDP.
 *
 * Opens a UDP socket and sends PCAPng data to `host:port`. Snapshots are
 * written with {@link module:udebug.pcap#write|pcap.write()}.
 *
 * Suitable for live capture with Wireshark via its "UDP listener" source.
 *
 * Returns a pcap handle on success.
 *
 * Returns `null` if the socket cannot be created.
 *
 * @function module:udebug#pcap_udp
 *
 * @param {string} host
 * Destination hostname or IP address.
 *
 * @param {string|int} port
 * Destination UDP port.
 *
 * @param {Object} [meta]
 * Optional PCAPng section header metadata (same fields as
 * {@link module:udebug#pcap_file|pcap_file()}).
 *
 * @returns {?UdebugPcap}
 *
 * @example
 * import { init, run } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * init();
 * udebug.init();
 *
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'wpad', ring_name: 'wlan0', pid: 300 });
 * const pcap = udebug.pcap_udp('192.168.1.10', 34254);
 *
 * rbuf.set_poll_cb(function() {
 *   pcap.write(this.fetch());
 * });
 * run();
 */
export function pcap_udp(host, port, meta) {};

/**
 * Iterate entries across one or more snapshots.
 *
 * Calls `fn` for every entry in `snapshot` (or in all snapshots of an
 * array), in merged ascending timestamp order.
 *
 * When `fn` throws an exception, iteration stops and the exception
 * propagates. Always returns `null` regardless of success or failure
 * (it is not an error indicator).
 *
 * @function module:udebug#foreach_packet
 *
 * @param {UdebugSnapshot|UdebugSnapshot[]} snapshot
 * A single snapshot or an array of snapshots to iterate. Multiple
 * snapshots are merged by timestamp.
 *
 * @param {function} fn
 * Callback invoked for each entry. Called with `this` bound to the
 * udebug module resource. Receives:
 * - `snapshot` {UdebugSnapshot} — the snapshot this entry belongs to.
 * - `data` {string} — raw entry bytes.
 * - `timestamp` {int} — entry timestamp in microseconds since epoch.
 *
 * @returns {null}
 *
 * @example
 * import * as udebug from 'udebug';
 *
 * udebug.init();
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'netifd', ring_name: 'log', pid: 100 });
 * const snap = rbuf.fetch();
 *
 * udebug.foreach_packet(snap, function(snap, data, ts) {
 *   const secs = ts / 1000000;
 *   printf('[%.6f] %s\n', secs, data);
 * });
 */
export function foreach_packet(snapshot, fn) {};

/**
 * Append an entry to the write ring.
 *
 * Atomically timestamps and writes `data` into the ring. Strings are
 * written verbatim; arrays are flattened depth-first; any other value is
 * converted to its string representation.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the ring is closed or `data` is `null`.
 *
 * @function module:udebug.wbuf#add
 *
 * @param {any} data
 * Data to append. Strings are written as-is; arrays are recursively
 * flattened; all other values are stringified.
 *
 * @returns {?boolean}
 *
 * @example
 * const ring = udebug.create_ring({ name: 'myapp/log', size: 65536, entries: 256 });
 *
 * // Write a plain string
 * ring.add('connection established');
 *
 * // Write a multi-part entry (flattened into one entry)
 * ring.add(['request from ', remote_addr, ': ', method, ' ', path]);
 */

/**
 * Query the remotely-controlled verbosity flags for this ring.
 *
 * External tooling (e.g. `udebugctl`) can set per-ring flags to control
 * which entries a producer writes. Each bit corresponds to a flag name
 * supplied in the `flags` array of
 * {@link module:udebug#create_ring|create_ring()}.
 *
 * Returns the current flags bitmask.
 *
 * Returns `null` if the ring is closed.
 *
 * @function module:udebug.wbuf#flags
 *
 * @returns {?int}
 *
 * @example
 * const ring = udebug.create_ring({
 *   name: 'myapp/packets',
 *   size: 1048576,
 *   entries: 1024,
 *   format: udebug.DLT_ETHERNET,
 *   flags: ['capture_enabled'],
 * });
 *
 * // Only capture when remotely enabled (bit 0 = 'capture_enabled')
 * if (ring.flags() & 1)
 *   ring.add(raw_frame);
 */

/**
 * Close and unregister the write ring.
 *
 * Frees the shared-memory buffer and unregisters the ring from the daemon.
 * Further method calls on this handle return `null`.
 *
 * @function module:udebug.wbuf#close
 *
 * @returns {void}
 */

/**
 * Take a point-in-time snapshot of the remote ring.
 *
 * Copies the current ring contents into a snapshot that can be iterated
 * with {@link module:udebug#foreach_packet|foreach_packet()} or passed to
 * {@link module:udebug.pcap#write|pcap.write()}.
 *
 * Returns a snapshot resource on success.
 *
 * Returns `null` if the ring is closed or empty.
 *
 * @function module:udebug.rbuf#fetch
 *
 * @returns {?UdebugSnapshot}
 *
 * @example
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'wpad', ring_name: 'wlan0', pid: 200 });
 * rbuf.set_fetch_duration(10); // fetch last 10 seconds
 * const snap = rbuf.fetch();
 * if (snap)
 *   udebug.foreach_packet(snap, (s, data, ts) => print(data, '\n'));
 */

/**
 * Register a uloop callback for incoming ring data.
 *
 * When new entries arrive, `fn` is called with `this` bound to the
 * `UdebugReadRing`. Passing `null` disables polling.
 *
 * The ring handle is kept alive (marked persistent) while polling is
 * active and released when polling is disabled.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the ring is closed or `fn` is not callable.
 *
 * @function module:udebug.rbuf#set_poll_cb
 *
 * @param {function} [fn]
 * Callback invoked when new data is available. Receives no arguments;
 * `this` is the `UdebugReadRing`. Pass `null` to disable.
 *
 * @returns {?boolean}
 *
 * @example
 * import { init, run } from 'uloop';
 * import * as udebug from 'udebug';
 *
 * init();
 * udebug.init();
 *
 * const rbuf = udebug.get_ring({ id: 1, proc_name: 'netifd', ring_name: 'log', pid: 100 });
 * const pcap = udebug.pcap_file('/tmp/out.pcapng');
 *
 * rbuf.set_poll_cb(function() {
 *   const snap = this.fetch();
 *   if (snap) pcap.write(snap);
 * });
 * run();
 */

/**
 * Change the remotely-controlled flags on the ring's owning process.
 *
 * Sends a flag-change request to the producer. Bits within `mask` that
 * are set in `val` will be set; bits within `mask` that are clear in
 * `val` will be cleared.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the ring is closed or arguments are not integers.
 *
 * @function module:udebug.rbuf#change_flags
 *
 * @param {int} mask
 * Bitmask of flag bits to modify.
 *
 * @param {int} val
 * Desired state of the bits selected by `mask`.
 *
 * @returns {?boolean}
 *
 * @example
 * // Enable bit 0 ('capture_enabled'), leave other bits untouched
 * rbuf.change_flags(0x1, 0x1);
 *
 * // Disable bit 0
 * rbuf.change_flags(0x1, 0x0);
 */

/**
 * Read the current flags bitmask from the remote ring.
 *
 * Returns the flags integer as currently set on the ring.
 *
 * Returns `null` if the ring is closed.
 *
 * @function module:udebug.rbuf#get_flags
 *
 * @returns {?int}
 */

/**
 * Limit the next {@link module:udebug.rbuf#fetch|fetch()} to a time window.
 *
 * Sets the fetch start point to `now - abs(seconds) * 1_000_000` µs.
 * Only entries timestamped after that point are included in the next
 * snapshot.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the ring is closed or `seconds` is not a number.
 *
 * @function module:udebug.rbuf#set_fetch_duration
 *
 * @param {int} seconds
 * How many seconds back in time to start reading. The absolute value
 * is used, so negative numbers are accepted.
 *
 * @returns {?boolean}
 *
 * @example
 * rbuf.set_fetch_duration(30); // fetch last 30 seconds of entries
 * const snap = rbuf.fetch();
 */

/**
 * Limit the next {@link module:udebug.rbuf#fetch|fetch()} to a fixed entry count.
 *
 * Sets the fetch start point to `head - count` entries. Only the most
 * recent `count` entries are included in the next snapshot.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the ring is closed.
 *
 * @function module:udebug.rbuf#set_fetch_count
 *
 * @param {int} count
 * Number of most-recent entries to fetch.
 *
 * @returns {?boolean}
 *
 * @example
 * rbuf.set_fetch_count(100); // fetch last 100 entries
 * const snap = rbuf.fetch();
 */

/**
 * Query metadata about the remote ring.
 *
 * Returns an object describing the ring's capacity and data format.
 *
 * Returns `null` if the ring is closed.
 *
 * @function module:udebug.rbuf#get_info
 *
 * @returns {?UdebugRingInfo}
 *
 * @example
 * const info = rbuf.get_info();
 * printf('format=%d, entries=%d, data=%d bytes\n',
 *   info.format, info.ring_size, info.data_size);
 */

/**
 * Unmap and close the remote ring.
 *
 * Further method calls on this handle return `null`.
 *
 * @function module:udebug.rbuf#close
 *
 * @returns {void}
 */

/**
 * Register a uloop callback for incoming ftrace data.
 *
 * Same semantics as {@link module:udebug.rbuf#set_poll_cb|rbuf.set_poll_cb()},
 * but operates on the ftrace pipe. `this` inside the callback is the
 * `UdebugTraceRing`.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the trace ring is closed or `fn` is not callable.
 *
 * @function module:udebug.tbuf#set_poll_cb
 *
 * @param {function} [fn]
 * Callback invoked when ftrace data is available. Pass `null` to
 * disable polling.
 *
 * @returns {?boolean}
 */

/**
 * Write to a file within the ftrace instance directory.
 *
 * Opens `name` relative to `/sys/kernel/debug/tracing/instances/<instance>/`
 * and writes `value` to it. Use this to configure which events to trace.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the trace ring is closed, the file does not exist, or
 * the write fails.
 *
 * @function module:udebug.tbuf#set_file
 *
 * @param {string} name
 * Relative filename within the ftrace instance, e.g. `"tracing_on"`,
 * `"set_event"`, or `"events/net/enable"`.
 *
 * @param {string} value
 * Content to write to the file.
 *
 * @returns {?boolean}
 *
 * @example
 * tbuf.set_file('tracing_on', '1');
 * tbuf.set_file('events/net/netif_rx/enable', '1');
 */

/**
 * Read available ftrace entries into a snapshot.
 *
 * Reads all currently available lines from the trace pipe (non-blocking),
 * parses their timestamps, and returns a snapshot for use with
 * {@link module:udebug#foreach_packet|foreach_packet()} or
 * {@link module:udebug.pcap#write|pcap.write()}.
 *
 * Returns a snapshot on success.
 *
 * Returns `null` if no data is available or an error occurs.
 *
 * @function module:udebug.tbuf#fetch
 *
 * @returns {?UdebugSnapshot}
 */

/**
 * Close the ftrace ring and remove the ftrace instance directory.
 *
 * Cancels any active uloop poll registration, closes the trace pipe,
 * and removes `/sys/kernel/debug/tracing/instances/<instance>/`.
 *
 * @function module:udebug.tbuf#close
 *
 * @returns {void}
 */

/**
 * Return the read ring this snapshot was taken from.
 *
 * Returns `null` for snapshots produced by
 * {@link module:udebug.tbuf#fetch|tbuf.fetch()} (ftrace snapshots have no
 * user-visible read ring) or if the ring has since been unmapped.
 *
 * @function module:udebug.snapshot#get_ring
 *
 * @returns {?UdebugReadRing}
 */

/**
 * Return the number of entries in this snapshot.
 *
 * @function module:udebug.snapshot#entries
 *
 * @returns {?int}
 *
 * @example
 * const snap = rbuf.fetch();
 * printf('%d entries captured\n', snap.entries());
 */

/**
 * Write snapshot entries to the PCAPng stream.
 *
 * Iterates entries in merged ascending timestamp order. The first time
 * a ring appears, its Interface Description Block is written to the
 * stream with the ring's DLT link type.
 *
 * Returns `true` if at least one entry was written.
 *
 * Returns `false` if the snapshot(s) contained zero entries.
 *
 * Returns `null` on I/O error or if any snapshot in an array is invalid.
 *
 * @function module:udebug.pcap#write
 *
 * @param {UdebugSnapshot|UdebugSnapshot[]} snapshot
 * A single snapshot or an array of snapshots. Multiple snapshots are
 * merged by timestamp.
 *
 * @returns {?boolean}
 *
 * @example
 * const snap1 = rbuf1.fetch();
 * const snap2 = rbuf2.fetch();
 * pcap.write([snap1, snap2]); // merged output
 */

/**
 * Flush and close the PCAPng output stream.
 *
 * @function module:udebug.pcap#close
 *
 * @returns {void}
 */
