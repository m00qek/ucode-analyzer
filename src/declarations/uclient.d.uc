// Source: https://github.com/openwrt/uclient
// Versions: 2024.10.22~88ae8f20, 2026.06.07~daad21fa
/**
 * # HTTP Client
 *
 * The `uclient` module provides an HTTP/HTTPS client interface built on top of
 * the OpenWrt {@link https://github.com/openwrt/uclient uclient} library.
 * It is event-driven: all network activity happens during `uloop.run()`, and
 * results are delivered through callbacks registered at construction time.
 *
 * Requires {@link module:uloop|uloop} to be initialized before use:
 *
 *   ```javascript
 *   import { init, run } from 'uloop';
 *   import { new as uclient } from 'uclient';
 *
 *   init();
 *
 *   const client = uclient('https://example.org/', null, {
 *     header_done(self) {
 *       print('Status: ', self.status().status, '\n');
 *     },
 *     data_read(self) {
 *       print(self.read());
 *     },
 *     data_eof(self) {
 *       self.disconnect();
 *     },
 *     error(self, code) {
 *       print('Error: ', code, '\n');
 *     }
 *   });
 *
 *   client.connect();
 *   client.request('GET');
 *   run();
 *   ```
 *
 * @module uclient
 */

/**
 * Connection status snapshot returned by {@link module:uclient.handle#status|status()}.
 *
 * @typedef {{
 *   eof: boolean,
 *   data_eof: boolean,
 *   status: int,
 *   redirect: boolean,
 *   local_addr: string,
 *   local_port: int,
 *   remote_addr: string,
 *   remote_port: int
 * }} UclientStatus
 */

/**
 * HTTP client handle returned by {@link module:uclient#new|new()}.
 *
 * All network operations are asynchronous; results arrive through the
 * callback object passed to {@link module:uclient#new|new()}.
 *
 * @typedef {{
 *   free: function(): void,
 *   ssl_init: function(?*): ?boolean,
 *   set_url: function(string, ?string): ?boolean,
 *   set_proxy_url: function(string, ?string): ?boolean,
 *   set_timeout: function(int): ?boolean,
 *   get_headers: function(): ?*,
 *   connect: function(): ?boolean,
 *   disconnect: function(): boolean,
 *   request: function(string, ?*): ?boolean,
 *   redirect: function(): ?boolean,
 *   status: function(): ?UclientStatus,
 *   read: function(?int): ?string
 * }} UclientHandle
 */

/**
 * Create a new uclient HTTP client instance.
 *
 * Allocates a client handle for the given URL. All network I/O is
 * non-blocking and event-driven via uloop; callbacks fire during
 * `uloop.run()`.
 *
 * Callbacks are called with `this` bound to the `UclientHandle`. Each
 * receives the original callback object as its first argument.
 *
 * Returns the client handle on success.
 *
 * Returns `null` if `url` is not a string, `auth_str` is not a string or
 * `null`, or `cb` is not an object.
 *
 * @function module:uclient#new
 *
 * @param {string} url
 * The initial request URL. May be changed later with
 * {@link module:uclient.handle#set_url|set_url()}.
 *
 * @param {?string} auth_str
 * HTTP Basic authentication credentials in `"user:password"` form, or
 * `null` to omit authentication.
 *
 * @param {*} cb
 * Dispatch object whose properties are optional callback functions:
 *
 * - `header_done(self)` — invoked once all response headers have been
 *   received. Call {@link module:uclient.handle#get_headers|get_headers()}
 *   and {@link module:uclient.handle#status|status()} here.
 * - `data_read(self)` — invoked when response body data is available.
 *   Call {@link module:uclient.handle#read|read()} inside to consume it.
 * - `data_eof(self)` — invoked when the response body is fully received.
 * - `get_post_data(self, offset)` — invoked repeatedly to supply outgoing
 *   request body chunks. `offset` is the number of bytes already sent.
 *   Return a non-empty string to send more data; return anything else to
 *   signal end of body.
 * - `error(self, code)` — invoked on error. `code` is one of the
 *   `UCLIENT_ERROR_*` integer constants (0 = unknown, 1 = connect,
 *   2 = timed out, 3 = SSL invalid cert, 4 = SSL CN mismatch,
 *   5 = missing SSL context).
 *
 * @returns {?UclientHandle}
 *
 * @example
 * import { init, run } from 'uloop';
 * import { new as uclient } from 'uclient';
 *
 * init();
 *
 * const client = uclient('http://example.org/', null, {
 *   header_done(self) {
 *     const s = self.status();
 *     print(`HTTP ${s.status}\n`);
 *     if (s.redirect)
 *       self.redirect();
 *   },
 *   data_read(self) {
 *     const chunk = self.read(4096);
 *     if (chunk)
 *       print(chunk);
 *   },
 *   data_eof(self) {
 *     self.disconnect();
 *   },
 *   error(self, code) {
 *     warn(`Error: ${code}\n`);
 *   }
 * });
 *
 * client.connect();
 * client.request('GET');
 * run();
 */
export function new(url, auth_str, cb) {};

/**
 * Free all resources held by the client handle.
 *
 * After calling `free()`, the handle is invalidated; any further method
 * calls on it return `null`.
 *
 * @function module:uclient.handle#free
 *
 * @returns {void}
 */

/**
 * Initialize or reinitialize the SSL/TLS context.
 *
 * Must be called before {@link module:uclient.handle#connect|connect()} for
 * HTTPS URLs. Calling it again destroys the previous SSL context.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the SSL library is unavailable or a file path is bad.
 *
 * @function module:uclient.handle#ssl_init
 *
 * @param {*} [opts]
 * Optional SSL configuration:
 * - `cert_file` {string} — path to PEM client certificate file
 * - `key_file` {string} — path to PEM private key file
 * - `ca_files` {string[]} — paths to CA certificate files; presence of
 *   this key also enables certificate verification
 * - `verify` {boolean} — whether to validate the server certificate
 *   (overrides the implicit value set by `ca_files`)
 *
 * @returns {?boolean}
 *
 * @example
 * client.ssl_init({
 *   ca_files: ['/etc/ssl/certs/ca-certificates.crt'],
 *   verify: true
 * });
 * client.connect();
 */

/**
 * Replace the current request URL.
 *
 * Can be called between requests to reuse the same client handle for a
 * different URL.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure or if argument types are invalid.
 *
 * @function module:uclient.handle#set_url
 *
 * @param {string} url
 * The new request URL.
 *
 * @param {string} [auth_str]
 * Optional HTTP Basic auth credentials in `"user:password"` form.
 *
 * @returns {?boolean}
 */

/**
 * Set an HTTP proxy URL.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure or if argument types are invalid.
 *
 * @function module:uclient.handle#set_proxy_url
 *
 * @param {string} url
 * The proxy URL, e.g. `"http://proxy.example.org:3128/"`.
 *
 * @param {string} [auth_str]
 * Optional proxy Basic auth credentials in `"user:password"` form.
 *
 * @returns {?boolean}
 */

/**
 * Set the connection and read timeout.
 *
 * Applies to both the time to receive an HTTP response and the time
 * between data chunks. On expiry the `error` callback fires with code `2`
 * (`UCLIENT_ERROR_TIMEDOUT`).
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure.
 *
 * @function module:uclient.handle#set_timeout
 *
 * @param {int} msecs
 * Timeout in milliseconds. The library default is 30000 (30 s).
 *
 * @returns {?boolean}
 */

/**
 * Return the response headers as a plain object.
 *
 * Header names are lowercased as received from the server. Only valid
 * after the `header_done` callback has fired.
 *
 * Returns `null` if the handle is invalid.
 *
 * @function module:uclient.handle#get_headers
 *
 * @returns {?*}
 *
 * @example
 * const client = uclient(url, null, {
 *   header_done(self) {
 *     const h = self.get_headers();
 *     print('Content-Type: ', h['content-type'], '\n');
 *   }
 * });
 */

/**
 * Initiate the TCP (and TLS if `ssl_init()` was called) connection.
 *
 * Returns `true` if the connection was successfully initiated.
 *
 * Returns `null` on failure.
 *
 * @function module:uclient.handle#connect
 *
 * @returns {?boolean}
 */

/**
 * Drop the current connection.
 *
 * Safe to call at any time. Always returns `true`.
 *
 * @function module:uclient.handle#disconnect
 *
 * @returns {boolean}
 */

/**
 * Send an HTTP request.
 *
 * Must be called after {@link module:uclient.handle#connect|connect()}.
 * Response arrives asynchronously via the registered callbacks.
 *
 * If `get_post_data` is set on the callback object, it is called
 * repeatedly to supply body chunks after any `post_data` string supplied
 * here is sent.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the method is unknown or the handle is invalid.
 *
 * @function module:uclient.handle#request
 *
 * @param {string} method
 * HTTP method: `"GET"`, `"HEAD"`, `"POST"`, `"PUT"`, `"DELETE"`, or
 * `"PROPPATCH"`.
 *
 * @param {*} [opts]
 * Optional request options:
 * - `headers` {object} — additional request headers
 * - `post_data` {string} — body to send before `get_post_data` is called
 *
 * @returns {?boolean}
 *
 * @example
 * client.connect();
 * client.request('POST', {
 *   headers: { 'Content-Type': 'application/json' },
 *   post_data: '{"key":"value"}'
 * });
 */

/**
 * Follow an HTTP redirect.
 *
 * Call this from the `header_done` callback when `status().redirect` is
 * `true`. Internally replaces the URL and re-initiates the request.
 *
 * Returns `true` on success.
 *
 * Returns `null` on failure.
 *
 * @function module:uclient.handle#redirect
 *
 * @returns {?boolean}
 *
 * @example
 * const client = uclient(url, null, {
 *   header_done(self) {
 *     if (self.status().redirect)
 *       self.redirect();
 *   }
 * });
 */

/**
 * Return a snapshot of the current connection state.
 *
 * Returns `null` if the handle is invalid.
 *
 * @function module:uclient.handle#status
 *
 * @returns {?UclientStatus}
 *
 * @example
 * const client = uclient(url, null, {
 *   header_done(self) {
 *     const s = self.status();
 *     print(`${s.status} from ${s.remote_addr}:${s.remote_port}\n`);
 *   }
 * });
 */

/**
 * Read up to `len` bytes of the response body.
 *
 * Must be called from inside the `data_read` callback. Loops internally
 * over 4096-byte chunks up to `len` bytes total.
 *
 * Returns the accumulated data string on success.
 *
 * Returns `null` if no data is available (EOF or read error).
 *
 * @function module:uclient.handle#read
 *
 * @param {int} [len=4096]
 * Maximum bytes to read. Defaults to 4096 if omitted or `0`.
 *
 * @returns {?string}
 *
 * @example
 * const client = uclient(url, null, {
 *   data_read(self) {
 *     const chunk = self.read(65536);
 *     if (chunk)
 *       process(chunk);
 *   }
 * });
 */
