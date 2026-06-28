// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # Wireless Netlink
 *
 * The `nl80211` module provides direct access to the Linux nl80211 Generic
 * Netlink subsystem for configuring and monitoring IEEE 802.11 (Wi-Fi)
 * devices. This is the same kernel interface used by `iw`, `hostapd`, and
 * `wpa_supplicant`.
 *
 * The module maintains two internal sockets:
 * - A blocking request socket used by {@link module:nl80211#request|request()}
 * - A non-blocking event socket used by {@link module:nl80211#listener|listener()} and {@link module:nl80211#waitfor|waitfor()}, subscribed to the `config`, `scan`, `regulatory`, `mlme`, `vendor`, and `nan` multicast groups
 *
 * Both sockets are lazily initialized on first use.
 *
 * The module also exports a `const` property (type `Nl80211Constants`) that
 * contains all nl80211 command IDs, Netlink message flags, interface type
 * values, scan flags, BSS status values, and HWSIM command IDs as integer
 * constants.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```javascript
 *   import { error, request, listener, waitfor, const: C } from 'nl80211';
 *
 *   // Trigger a scan and wait for results
 *   let ok = request(C.NL80211_CMD_TRIGGER_SCAN, 0, {
 *       dev: 'wlan0',
 *       scan_ssids: [''],
 *   });
 *   if (!ok)
 *       die(`scan trigger failed: ${error()}`);
 *
 *   let ev = waitfor([C.NL80211_CMD_NEW_SCAN_RESULTS, C.NL80211_CMD_SCAN_ABORTED], 10000);
 *   if (!ev || ev.cmd === C.NL80211_CMD_SCAN_ABORTED)
 *       die('scan did not complete');
 *
 *   let results = request(C.NL80211_CMD_GET_SCAN, C.NLM_F_DUMP, { dev: 'wlan0' });
 *   for (let r of results) {
 *       let ssid = filter(r.bss?.information_elements, ie => ie.type === 0)?.[0]?.data;
 *       printf('%s  freq %d MHz  signal %.1f dBm\n',
 *           r.bss.bssid, r.bss.frequency, r.bss.signal_mbm / 100);
 *   }
 *   ```
 *
 * Alternatively, the module namespace can be imported using a wildcard import:
 *
 *   ```javascript
 *   import * as nl80211 from 'nl80211';
 *   const C = nl80211.const;
 *
 *   // Get phy capabilities
 *   let phy = nl80211.request(C.NL80211_CMD_GET_WIPHY, 0, { wiphy: 0 });
 *   printf('phy0 supports %d station associations\n', phy.max_ap_assoc ?? 0);
 *
 *   // Watch for new stations associating
 *   import * as uloop from 'uloop';
 *   uloop.init();
 *   let l = nl80211.listener(ev => {
 *       printf('new station %s on %s\n', ev.msg.mac, ev.msg.dev);
 *   }, [C.NL80211_CMD_NEW_STATION]);
 *   uloop.run();
 *   l.close();
 *   ```
 *
 * Additionally, the nl80211 module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lnl80211` switch.
 *
 * @module nl80211
 */

/**
 * Object containing all nl80211 and Netlink integer constants exported by the
 * module as `nl80211.const`.
 *
 * **Netlink message flags (`NLM_F_*`)** — combined with the `flags` argument
 * of {@link module:nl80211#request|request()}:
 * - `NLM_F_REQUEST` — message is a request
 * - `NLM_F_DUMP` — dump all entries (equivalent to `NLM_F_ROOT|NLM_F_MATCH`)
 * - `NLM_F_ACK` — request an acknowledgement
 * - `NLM_F_REPLACE` — replace an existing entry
 * - `NLM_F_EXCL` — do not touch if exists
 * - `NLM_F_CREATE` — create if not exists
 * - `NLM_F_APPEND` — add to tail of list
 *
 * **nl80211 commands (`NL80211_CMD_*`)** — passed as the `cmd` argument of
 * {@link module:nl80211#request|request()}, {@link module:nl80211#waitfor|waitfor()},
 * and {@link module:nl80211#listener|listener()}.
 *
 * **Interface types (`NL80211_IFTYPE_*`)** — used with the `iftype` payload
 * attribute: `ADHOC`, `STATION`, `AP`, `AP_VLAN`, `WDS`, `MONITOR`,
 * `MESH_POINT`, `P2P_CLIENT`, `P2P_GO`, `P2P_DEVICE`, `OCB`.
 *
 * **BSS status (`NL80211_BSS_STATUS_*`)**: `AUTHENTICATED` (0),
 * `ASSOCIATED` (1), `IBSS_JOINED` (2).
 *
 * **Scan flags (`NL80211_SCAN_FLAG_*`)**: `LOW_PRIORITY`, `FLUSH`, `AP`,
 * `RANDOM_ADDR`, `LOW_SPAN`, `LOW_POWER`, `HIGH_ACCURACY`, `FREQ_KHZ`, etc.
 *
 * **HWSIM commands (`HWSIM_CMD_*`)** — offset from `NL80211_CMD_MAX`,
 * baked in; use `HWSIM_CMD_OFFSET` to convert between raw and offset values:
 * `HWSIM_CMD_NEW_RADIO`, `HWSIM_CMD_DEL_RADIO`, `HWSIM_CMD_GET_RADIO`,
 * `HWSIM_CMD_FRAME`, `HWSIM_CMD_TX_INFO_FRAME`, etc.
 *
 * @typedef {{
 *   NLM_F_REQUEST: int,
 *   NLM_F_MULTI: int,
 *   NLM_F_ACK: int,
 *   NLM_F_ECHO: int,
 *   NLM_F_DUMP_INTR: int,
 *   NLM_F_DUMP_FILTERED: int,
 *   NLM_F_ROOT: int,
 *   NLM_F_MATCH: int,
 *   NLM_F_ATOMIC: int,
 *   NLM_F_DUMP: int,
 *   NLM_F_REPLACE: int,
 *   NLM_F_EXCL: int,
 *   NLM_F_CREATE: int,
 *   NLM_F_APPEND: int,
 *   NL80211_CMD_GET_WIPHY: int,
 *   NL80211_CMD_SET_WIPHY: int,
 *   NL80211_CMD_NEW_WIPHY: int,
 *   NL80211_CMD_DEL_WIPHY: int,
 *   NL80211_CMD_GET_INTERFACE: int,
 *   NL80211_CMD_SET_INTERFACE: int,
 *   NL80211_CMD_NEW_INTERFACE: int,
 *   NL80211_CMD_DEL_INTERFACE: int,
 *   NL80211_CMD_GET_KEY: int,
 *   NL80211_CMD_SET_KEY: int,
 *   NL80211_CMD_NEW_KEY: int,
 *   NL80211_CMD_DEL_KEY: int,
 *   NL80211_CMD_GET_BEACON: int,
 *   NL80211_CMD_SET_BEACON: int,
 *   NL80211_CMD_START_AP: int,
 *   NL80211_CMD_STOP_AP: int,
 *   NL80211_CMD_GET_STATION: int,
 *   NL80211_CMD_SET_STATION: int,
 *   NL80211_CMD_NEW_STATION: int,
 *   NL80211_CMD_DEL_STATION: int,
 *   NL80211_CMD_GET_MPATH: int,
 *   NL80211_CMD_SET_MPATH: int,
 *   NL80211_CMD_NEW_MPATH: int,
 *   NL80211_CMD_DEL_MPATH: int,
 *   NL80211_CMD_SET_BSS: int,
 *   NL80211_CMD_SET_REG: int,
 *   NL80211_CMD_REQ_SET_REG: int,
 *   NL80211_CMD_GET_MESH_CONFIG: int,
 *   NL80211_CMD_SET_MESH_CONFIG: int,
 *   NL80211_CMD_GET_REG: int,
 *   NL80211_CMD_GET_SCAN: int,
 *   NL80211_CMD_TRIGGER_SCAN: int,
 *   NL80211_CMD_NEW_SCAN_RESULTS: int,
 *   NL80211_CMD_SCAN_ABORTED: int,
 *   NL80211_CMD_ABORT_SCAN: int,
 *   NL80211_CMD_REG_CHANGE: int,
 *   NL80211_CMD_AUTHENTICATE: int,
 *   NL80211_CMD_ASSOCIATE: int,
 *   NL80211_CMD_DEAUTHENTICATE: int,
 *   NL80211_CMD_DISASSOCIATE: int,
 *   NL80211_CMD_GET_SURVEY: int,
 *   NL80211_CMD_CHANNEL_SWITCH: int,
 *   NL80211_CMD_VENDOR: int,
 *   NL80211_CMD_START_SCHED_SCAN: int,
 *   NL80211_CMD_STOP_SCHED_SCAN: int,
 *   NL80211_CMD_CONNECT: int,
 *   NL80211_CMD_DISCONNECT: int,
 *   NL80211_CMD_ROAM: int,
 *   NL80211_CMD_JOIN_IBSS: int,
 *   NL80211_CMD_LEAVE_IBSS: int,
 *   NL80211_CMD_JOIN_MESH: int,
 *   NL80211_CMD_LEAVE_MESH: int,
 *   NL80211_CMD_GET_MPP: int,
 *   NL80211_CMD_SET_WDS_PEER: int,
 *   NL80211_CMD_SET_REKEY_OFFLOAD: int,
 *   NL80211_CMD_PMKSA_CANDIDATE: int,
 *   NL80211_CMD_TDLS_MGMT: int,
 *   NL80211_CMD_TDLS_OPER: int,
 *   NL80211_CMD_UNEXPECTED_FRAME: int,
 *   NL80211_CMD_PROBE_CLIENT: int,
 *   NL80211_CMD_REGISTER_BEACONS: int,
 *   NL80211_CMD_UNEXPECTED_4ADDR_FRAME: int,
 *   NL80211_CMD_SET_NOACK_MAP: int,
 *   NL80211_CMD_CH_SWITCH_NOTIFY: int,
 *   NL80211_CMD_START_P2P_DEVICE: int,
 *   NL80211_CMD_STOP_P2P_DEVICE: int,
 *   NL80211_CMD_CONN_FAILED: int,
 *   NL80211_CMD_SET_MCAST_RATE: int,
 *   NL80211_CMD_SET_MAC_ACL: int,
 *   NL80211_CMD_RADAR_DETECT: int,
 *   NL80211_CMD_GET_PROTOCOL_FEATURES: int,
 *   NL80211_CMD_UPDATE_FT_IES: int,
 *   NL80211_CMD_FT_EVENT: int,
 *   NL80211_CMD_CRIT_PROTOCOL_START: int,
 *   NL80211_CMD_CRIT_PROTOCOL_STOP: int,
 *   NL80211_CMD_GET_COALESCE: int,
 *   NL80211_CMD_SET_COALESCE: int,
 *   NL80211_CMD_CHANNEL_SWITCH_STARTED_NOTIFY: int,
 *   NL80211_CMD_ADD_TX_TS: int,
 *   NL80211_CMD_DEL_TX_TS: int,
 *   NL80211_IFTYPE_ADHOC: int,
 *   NL80211_IFTYPE_STATION: int,
 *   NL80211_IFTYPE_AP: int,
 *   NL80211_IFTYPE_AP_VLAN: int,
 *   NL80211_IFTYPE_WDS: int,
 *   NL80211_IFTYPE_MONITOR: int,
 *   NL80211_IFTYPE_MESH_POINT: int,
 *   NL80211_IFTYPE_P2P_CLIENT: int,
 *   NL80211_IFTYPE_P2P_GO: int,
 *   NL80211_IFTYPE_P2P_DEVICE: int,
 *   NL80211_IFTYPE_OCB: int,
 *   NL80211_BSS_STATUS_AUTHENTICATED: int,
 *   NL80211_BSS_STATUS_ASSOCIATED: int,
 *   NL80211_BSS_STATUS_IBSS_JOINED: int,
 *   NL80211_SCAN_FLAG_LOW_PRIORITY: int,
 *   NL80211_SCAN_FLAG_FLUSH: int,
 *   NL80211_SCAN_FLAG_AP: int,
 *   NL80211_SCAN_FLAG_RANDOM_ADDR: int,
 *   NL80211_SCAN_FLAG_LOW_SPAN: int,
 *   NL80211_SCAN_FLAG_LOW_POWER: int,
 *   NL80211_SCAN_FLAG_HIGH_ACCURACY: int,
 *   NL80211_SCAN_FLAG_RANDOM_SN: int,
 *   NL80211_SCAN_FLAG_MIN_PREQ_CONTENT: int,
 *   NL80211_SCAN_FLAG_FREQ_KHZ: int,
 *   NL80211_SCAN_FLAG_COLOCATED_6GHZ: int,
 *   HWSIM_CMD_OFFSET: int,
 *   HWSIM_CMD_REGISTER: int,
 *   HWSIM_CMD_FRAME: int,
 *   HWSIM_CMD_TX_INFO_FRAME: int,
 *   HWSIM_CMD_NEW_RADIO: int,
 *   HWSIM_CMD_DEL_RADIO: int,
 *   HWSIM_CMD_GET_RADIO: int,
 *   HWSIM_CMD_ADD_MAC_ADDR: int,
 *   HWSIM_CMD_DEL_MAC_ADDR: int,
 *   HWSIM_CMD_START_PMSR: int,
 *   HWSIM_CMD_ABORT_PMSR: int,
 *   HWSIM_CMD_REPORT_PMSR: int
 * }} Nl80211Constants
 */

/**
 * Event object passed to {@link module:nl80211#listener|listener()} callbacks
 * and returned by {@link module:nl80211#waitfor|waitfor()}.
 *
 * The `cmd` field holds the raw `NL80211_CMD_*` integer (or `HWSIM_CMD_*`
 * with the `HWSIM_CMD_OFFSET` already applied). The `msg` field is the
 * decoded attribute object whose fields depend on the specific command; key
 * fields commonly present include:
 *
 * - `msg.wiphy` — wiphy index (integer)
 * - `msg.wiphy_name` — wiphy name such as `"phy0"` (string)
 * - `msg.dev` — interface name (string)
 * - `msg.iftype` — `NL80211_IFTYPE_*` value (integer)
 * - `msg.mac` — MAC address `"aa:bb:cc:dd:ee:ff"` (string)
 * - `msg.wdev` — wireless device ID (integer)
 *
 * @typedef {{ cmd: int, msg: * }} Nl80211Event
 */

/**
 * Asynchronous event listener resource returned by
 * {@link module:nl80211#listener|listener()}.
 *
 * The listener integrates with `uloop`: when the event socket becomes
 * readable, any registered listener callbacks are dispatched automatically
 * inside a `uloop.run()` loop.
 *
 * @typedef {{
 *   set_commands: function(int[]|int): null,
 *   request: function(int, ?int, ?*): *,
 *   close: function(): null
 * }} Nl80211Listener
 */

/**
 * Returns a description of the last error that occurred in any nl80211
 * operation, then clears the stored error.
 *
 * If the last error was a custom failure message, it is returned verbatim.
 * Otherwise the libnl textual description is returned, optionally followed by
 * the custom message if one was also stored.
 *
 * Returns `null` when no error is pending.
 *
 * @function module:nl80211#error
 *
 * @returns {?string}
 *
 * @example
 * import { error, request, const: C } from 'nl80211';
 *
 * const info = request(C.NL80211_CMD_GET_STATION, 0, {
 *     dev: 'wlan0',
 *     mac: 'de:ad:be:ef:00:01',
 * });
 * if (!info)
 *     print(`failed to get station info: ${error()}\n`);
 */
export function error() {};

/**
 * Object containing all nl80211 command IDs, Netlink message flags,
 * interface type values, scan flags, BSS status values, and HWSIM command
 * IDs as integer constants.
 *
 * @name module:nl80211.const
 * @type {object}
 */

/**
 * Sends a Generic Netlink message to the kernel nl80211 subsystem and returns
 * the decoded response.
 *
 * The `cmd` argument must be a non-negative integer. If `cmd` is greater than
 * or equal to `HWSIM_CMD_OFFSET` (= `NL80211_CMD_MAX`), the message is sent
 * to the `MAC80211_HWSIM` family instead of `nl80211` and the HWSIM attribute
 * codec is used.
 *
 * The `payload` argument is an object whose keys correspond to snake_case
 * attribute names from the nl80211 attribute spec. Common payload fields:
 *
 * - `dev` — interface name or index (string or integer)
 * - `wiphy` — wiphy index (integer)
 * - `mac` — MAC address `"aa:bb:cc:dd:ee:ff"` (string)
 * - `iftype` — `NL80211_IFTYPE_*` value (integer)
 * - `wiphy_freq` — frequency in MHz (integer)
 * - `channel_width` — channel width (integer)
 * - `center_freq1` / `center_freq2` — center frequencies (integer)
 * - `scan_ssids` — SSIDs to probe; `['']` for wildcard (string[])
 * - `scan_frequencies` — channel frequencies in MHz (integer[])
 * - `split_wiphy_dump` — split wiphy dump by phy (boolean)
 *
 * **Return value** depends on the kernel response:
 * - Single-part reply: decoded message object (`*`)
 * - Multi-part reply (`NLM_F_DUMP`): array of decoded message objects (`*[]`)
 * - ACK without data: `true`
 * - Error: `null` (call `error()` for details)
 *
 * **Special behaviour for `NL80211_CMD_GET_WIPHY`**: multi-part replies are
 * deep-merged by wiphy index instead of accumulated as an array. With
 * `payload.wiphy` set, a single merged object is returned. With
 * `payload.split_wiphy_dump: true` and `NLM_F_DUMP`, an array indexed by
 * wiphy number is returned.
 *
 * Response objects typically contain decoded attributes matching the
 * snake_case names of the nl80211 attribute constants:
 * - `bss` — BSS info object (scan results); key fields: `bssid`, `frequency`,
 *   `signal_mbm` (mBm; divide by 100 for dBm), `information_elements` array
 *   of `{type, data}` TLV objects, `status`, `last_seen_boottime`
 * - `sta_info` — station info object; key fields: `signal` (dBm), `inactive_time` (ms),
 *   `rx_bytes64`, `tx_bytes64`, `tx_bitrate` and `rx_bitrate` sub-objects
 *   with `bitrate32` (100 Kbps units), `mcs`, `vht_mcs`, `he_mcs`, `short_gi`
 * - `survey_info` — channel survey object; key fields: `frequency`, `noise` (dBm),
 *   `in_use`, `time`, `busy`, `time_rx`, `time_tx` (all u64 milliseconds)
 * - `wiphy_bands` — array of band objects indexed by band number; each has
 *   `freqs` (channel objects), `rates`, `ht_mcs_set`, `vht_mcs_set`,
 *   `ht_capa`, `vht_capa`, `iftype_data` (HE/EHT capabilities per iftype)
 * - `supported_iftypes` — object with interface type names as boolean keys
 * - `reg_alpha2` — ISO country code string
 *
 * @function module:nl80211#request
 *
 * @param {int} cmd
 * The nl80211 command ID (`NL80211_CMD_*`) or HWSIM command ID
 * (`HWSIM_CMD_*`). Must be a non-negative integer.
 *
 * @param {int} [flags=0]
 * Netlink message flags (`NLM_F_*`). Use `NLM_F_DUMP` to request a full
 * dump of all matching entries. Range 0–0xffff.
 *
 * @param {*} [payload]
 * Attribute map to include in the request message. Keys are snake_case
 * attribute names; values are coerced to the appropriate attribute type.
 *
 * @returns {*}
 *
 * @example
 * import { request, const: C } from 'nl80211';
 *
 * // Trigger a scan
 * request(C.NL80211_CMD_TRIGGER_SCAN, 0, {
 *     dev: 'wlan0',
 *     scan_ssids: [''],
 *     scan_frequencies: [2412, 2437, 2462, 5180, 5200, 5220],
 * });
 *
 * @example
 * // Get all scan results
 * const results = request(C.NL80211_CMD_GET_SCAN, C.NLM_F_DUMP, { dev: 'wlan0' });
 * for (const r of results) {
 *     const ssidIe = filter(r.bss.information_elements, ie => ie.type === 0)?.[0];
 *     printf('BSSID %-17s  freq %4d MHz  signal %+.1f dBm  SSID %s\n',
 *         r.bss.bssid, r.bss.frequency, r.bss.signal_mbm / 100,
 *         ssidIe ? ssidIe.data : '(hidden)');
 * }
 *
 * @example
 * // Get station info for a specific client
 * const info = request(C.NL80211_CMD_GET_STATION, 0, {
 *     dev: 'wlan0',
 *     mac: 'aa:bb:cc:dd:ee:ff',
 * });
 * const s = info?.sta_info;
 * if (s) {
 *     printf('signal %d dBm  inactive %d ms  tx rate %.1f Mbps\n',
 *         s.signal, s.inactive_time, (s.tx_bitrate?.bitrate32 ?? 0) / 10);
 * }
 *
 * @example
 * // Get phy capabilities (single merged object)
 * const phy = request(C.NL80211_CMD_GET_WIPHY, 0, { wiphy: 0 });
 * printf('phy0: max AP associations: %d\n', phy.max_ap_assoc ?? 0);
 * for (const [i, band] of entries(phy.wiphy_bands ?? [])) {
 *     if (!band) continue;
 *     printf('band %d: %d channels\n', i, length(band.freqs));
 * }
 *
 * @example
 * // Perform a channel switch (AP mode)
 * request(C.NL80211_CMD_CHANNEL_SWITCH, 0, {
 *     dev: 'wlan0',
 *     ch_switch_count: 10,
 *     wiphy_freq: 5180,
 *     channel_width: 1,
 *     center_freq1: 5190,
 * });
 */
export function request(cmd, flags, payload) {};

/**
 * Synchronously waits for one or more nl80211 events to arrive on the event
 * socket, with an optional timeout.
 *
 * `cmds` may be a single command integer, an array of command integers, or
 * `null` to match any command. HWSIM commands in `cmds` are automatically
 * adjusted by subtracting `HWSIM_CMD_OFFSET`.
 *
 * While waiting, any registered {@link module:nl80211#listener|listener()}
 * callbacks are also dispatched for incoming events.
 *
 * Returns `null` on timeout or socket error (call `error()` for details).
 *
 * @function module:nl80211#waitfor
 *
 * @param {int[]|int|null} cmds
 * Command ID(s) to wait for, or `null` to match all commands.
 *
 * @param {int} [timeout=-1]
 * Maximum time to wait in milliseconds. Negative values mean infinite wait.
 *
 * @returns {?Nl80211Event}
 *
 * @example
 * import { request, waitfor, error, const: C } from 'nl80211';
 *
 * request(C.NL80211_CMD_TRIGGER_SCAN, 0, { dev: 'wlan0', scan_ssids: [''] });
 *
 * // Wait up to 15 seconds for scan completion or abort
 * const ev = waitfor([C.NL80211_CMD_NEW_SCAN_RESULTS, C.NL80211_CMD_SCAN_ABORTED], 15000);
 * if (!ev)
 *     die(`scan wait failed: ${error()}`);
 * if (ev.cmd === C.NL80211_CMD_SCAN_ABORTED)
 *     die('scan was aborted by the kernel');
 *
 * print('scan completed on interface', ev.msg.dev, '\n');
 */
export function waitfor(cmds, timeout) {};

/**
 * Creates an asynchronous nl80211 event listener integrated with
 * {@link module:uloop|uloop}.
 *
 * When the event socket becomes readable inside a `uloop.run()` loop, any
 * incoming event whose command ID is in the registered filter set causes
 * `callback` to be called with an {@link Nl80211Event|Nl80211Event} argument.
 *
 * `cmds` may be a single command integer, an array of command integers, or
 * omitted/`null` to receive all commands. Invalid command IDs throw a type
 * error. Passing a non-callable `callback` also throws a type error.
 *
 * Returns an {@link Nl80211Listener|Nl80211Listener} resource on success, or
 * `null` on socket/subscription failure (call `error()` for details).
 *
 * @function module:nl80211#listener
 *
 * @param {function} callback
 * Called with a single {@link Nl80211Event|Nl80211Event} argument for each
 * matching event. If the callback throws, `uloop.end()` is called and the
 * event loop stops.
 *
 * @param {int[]|int|null} [cmds]
 * Command IDs to listen for, or `null`/omitted to receive all commands.
 *
 * @returns {?Nl80211Listener}
 *
 * @example
 * import * as nl80211 from 'nl80211';
 * import * as uloop from 'uloop';
 * const C = nl80211.const;
 *
 * uloop.init();
 *
 * const l = nl80211.listener(ev => {
 *     switch (ev.cmd) {
 *     case C.NL80211_CMD_NEW_STATION:
 *         printf('station %s associated on %s\n', ev.msg.mac, ev.msg.dev);
 *         break;
 *     case C.NL80211_CMD_DEL_STATION:
 *         printf('station %s disassociated from %s\n', ev.msg.mac, ev.msg.dev);
 *         break;
 *     case C.NL80211_CMD_NEW_SCAN_RESULTS:
 *         printf('scan completed on %s\n', ev.msg.dev);
 *         break;
 *     }
 * }, [C.NL80211_CMD_NEW_STATION, C.NL80211_CMD_DEL_STATION, C.NL80211_CMD_NEW_SCAN_RESULTS]);
 *
 * uloop.run();
 * l.close();
 */
export function listener(callback, cmds) {};

/**
 * Replaces the command filter bitmap of an existing listener with a new set
 * of command IDs.
 *
 * The existing filter is cleared first, then repopulated from `cmds`. Invalid
 * command IDs throw a type error. Passing a single integer is also accepted.
 *
 * Returns `null`.
 *
 * @function module:nl80211.listener#set_commands
 *
 * @param {int[]|int} cmds
 * New command IDs to listen for.
 *
 * @returns {null}
 *
 * @example
 * import * as nl80211 from 'nl80211';
 * const C = nl80211.const;
 *
 * const l = nl80211.listener(ev => {
 *     print('regulatory event\n');
 * }, [C.NL80211_CMD_REG_CHANGE]);
 *
 * // Later: also track interface changes
 * l.set_commands([
 *     C.NL80211_CMD_REG_CHANGE,
 *     C.NL80211_CMD_NEW_INTERFACE,
 *     C.NL80211_CMD_DEL_INTERFACE,
 * ]);
 */

/**
 * Sends a Generic Netlink request using the event socket instead of the
 * blocking request socket.
 *
 * Semantics are identical to the module-level
 * {@link module:nl80211#request|request()} function. Use this variant when
 * calling from within a listener callback to avoid blocking the event socket.
 *
 * @function module:nl80211.listener#request
 *
 * @param {int} cmd
 * The nl80211 command ID (`NL80211_CMD_*`) or HWSIM command ID
 * (`HWSIM_CMD_*`).
 *
 * @param {int} [flags=0]
 * Netlink message flags (`NLM_F_*`).
 *
 * @param {*} [payload]
 * Attribute map to include in the request message.
 *
 * @returns {*}
 *
 * @example
 * import * as nl80211 from 'nl80211';
 * import * as uloop from 'uloop';
 * const C = nl80211.const;
 *
 * uloop.init();
 *
 * const l = nl80211.listener(function(ev) {
 *     if (ev.cmd !== C.NL80211_CMD_NEW_SCAN_RESULTS) return;
 *     // Use listener.request() here — safe to call from inside the callback
 *     const results = this.request(C.NL80211_CMD_GET_SCAN, C.NLM_F_DUMP, {
 *         dev: ev.msg.dev,
 *     });
 *     printf('found %d BSSes on %s\n', length(results), ev.msg.dev);
 * }, [C.NL80211_CMD_NEW_SCAN_RESULTS]);
 *
 * uloop.run();
 * l.close();
 */

/**
 * Stops the listener and releases its resources.
 *
 * Removes the listener from the module-global registry and frees the
 * underlying structure. The event socket fd registration with uloop is
 * retained if other listeners are still active.
 *
 * Returns `null`.
 *
 * @function module:nl80211.listener#close
 *
 * @returns {null}
 *
 * @example
 * import * as nl80211 from 'nl80211';
 * import * as uloop from 'uloop';
 *
 * uloop.init();
 *
 * const l = nl80211.listener(ev => {
 *     print('got event\n');
 *     uloop.end();
 * });
 *
 * uloop.run();
 * l.close();
 */
