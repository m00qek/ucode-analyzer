// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # Ubus IPC
 *
 * The `ubus` module provides functions for OpenWrt inter-process
 * communication, including access to ubus registered modules and their
 * methods, as well as monitoring and publish/subscribe activity on the
 * ubus message bus.
 *
 * Functions can be individually imported using named import syntax:
 *
 * ```js
 * import { connect } from 'ubus';
 *
 * const ubus = connect();
 * const result = ubus.call("session", "get", { key: "value" });
 * ```
 *
 * Alternatively, the module namespace can be imported using a wildcard
 * import:
 *
 * ```js
 * import * as ubus from 'ubus';
 *
 * const ctx = ubus.connect();
 * ```
 *
 * The `ubus` module may also be loaded via the `-lubus` interpreter switch.
 *
 * ## Architecture
 *
 * Ubus uses a broker pattern architecture with three main components:
 * - **`ubusd`**: The central message router/broker that manages
 *   registrations and forwards messages between objects
 * - **Server objects**: Interfaces/daemons that register methods for
 *   clients to call
 * - **Client objects**: Callers that invoke server object methods
 *
 * All connections go through `ubusd`, significantly reducing the number
 * of IPC connections compared to traditional client-server models.
 *
 * ## Communication Schemes
 *
 * Ubus provides three delivery schemes for IPC:
 *
 * 1. **Invoke** (one-to-one): Direct method calls to a specific object
 *    by ID
 * 2. **Subscribe/Notify** (one-to-many, group by object): Notifications
 *    sent to all subscribers of a particular object
 * 3. **Event Broadcast** (one-to-many, group by event): Events broadcast
 *    to all listeners registered for a matching event pattern
 *
 * ## Roles in Ubus
 *
 * - **Object**: Process registered to `ubusd`, including services and
 *   service callers
 * - **Method**: Procedures provided by objects; servers can provide
 *   multiple methods
 * - **Data**: Information in JSON format carried by requests or replies
 * - **Subscriber**: Object subscribed to a target service; notified when
 *   the target sends notifications
 * - **Event**: Identified by a string event pattern; objects can register
 *   to events and send data with matching patterns
 * - **Event Registrant**: Object registered to an event pattern; receives
 *   forwarded data when matching messages are received
 *
 * ## Data Format
 *
 * All data is transferred in JSON format via `blobmsg`. Method calls,
 * requests, and replies all use JSON for data serialization.
 *
 * ## Usage Examples
 *
 * ### Basic connection and method call
 * ```js
 * const ubus = require("ubus");
 *
 * // Connect to ubus and call a method
 * const conn = ubus.connect();
 * if (conn) {
 *     const result = conn.call("network.interface", "status", {});
 *     printf("Interface status: %.J\n", result);
 *     conn.disconnect();
 * }
 * ```
 *
 * ### Asynchronous method invocation with callback
 * ```js
 * const ubus = require("ubus");
 *
 * // Typical pattern: async call with callback
 * const conn = ubus.connect();
 *
 * conn.defer("some.object", "some_method", {}, (rc, result) => {
 *     if (rc == 0) {
 *         printf("Result: %.J\n", result);
 *     }
 * });
 * ```
 *
 * ### Persistent connection pattern
 * ```js
 * const ubus = require("ubus");
 *
 * // Keep connection alive to prevent GC
 * const ubus_conn = ubus.connect();
 *
 * function handle_request(request) {
 *     ubus_conn.defer("some.object", "some_method", {}, (rc, data) => {
 *         request.reply({ result: data });
 *     });
 * }
 * ```
 *
 * ### Publishing an object
 * ```js
 * const ubus = require("ubus");
 *
 * const conn = ubus.connect();
 * const obj = conn.publish("my.service", {
 *     "hello": (req, msg) => {
 *         req.reply({ message: "Hello from " + msg.name });
 *     }
 * });
 * ```
 *
 * ### Event broadcasting
 * ```js
 * const ubus = require("ubus");
 *
 * const conn = ubus.connect();
 *
 * // Register as event listener
 * const listener = conn.listener("my.event.*", (pattern, data) => {
 *     printf("Received event: %s %.J\n", pattern, data);
 * });
 *
 * // Send an event
 * conn.event("my.event.test", { data: "test payload" });
 * ```
 *
 * @module ubus
 * @see https://openwrt.org/docs/techref/ubus
 */

/**
 * Connection handle returned by {@link module:ubus#connect|connect()}.
 *
 * @typedef {{
 *   list: function(?string): ?*,
 *   call: function(string, string, ?*, ?int, ?int, ?function): ?*,
 *   defer: function(string, string, ?*, function, ?function, ?int, ?function): ?UbusDeferred,
 *   publish: function(string, ?*, ?function): ?UbusObject,
 *   listener: function(string, function): ?UbusListener,
 *   event: function(string, ?*): ?boolean,
 *   subscriber: function(function, ?function, ?string[]): ?UbusSubscriber,
 *   disconnect: function(): boolean
 * }} UbusConnection
 */

/**
 * Channel handle returned by {@link module:ubus#open_channel|open_channel()}.
 *
 * @typedef {{
 *   request: function(string, ?*, ?int, ?int, ?function): ?*,
 *   defer: function(string, ?*, function, ?function, ?int, ?function): ?UbusDeferred
 * }} UbusChannel
 */

/**
 * Pending request handle available in ubus method callbacks.
 *
 * @typedef {{
 *   reply: function(*): ?boolean,
 *   defer: function(): ?boolean,
 *   get_fd: function(): int,
 *   set_fd: function(int): ?boolean,
 *   error: function(int): ?boolean,
 *   new_channel: function(function, ?function, ?int): ?UbusChannel
 * }} UbusRequest
 */

/**
 * Notification handle returned by {@link module:ubus.object#notify|notify()}.
 *
 * @typedef {{
 *   completed: function(): boolean,
 *   abort: function(): boolean
 * }} UbusNotify
 */

/**
 * Published object handle returned by {@link module:ubus.connection#publish|publish()}.
 *
 * @typedef {{
 *   notify: function(string, ?*, ?function, ?function, ?function, ?int): ?UbusNotify,
 *   remove: function(): ?boolean,
 *   subscribed: function(): boolean
 * }} UbusObject
 */

/**
 * Event listener handle returned by {@link module:ubus.connection#listener|listener()}.
 *
 * @typedef {{
 *   remove: function(): ?boolean
 * }} UbusListener
 */

/**
 * Subscriber handle returned by {@link module:ubus.connection#subscriber|subscriber()}.
 *
 * @typedef {{
 *   subscribe: function(string): ?boolean,
 *   unsubscribe: function(string): ?boolean,
 *   remove: function(): ?boolean
 * }} UbusSubscriber
 */

/**
 * Deferred request handle returned by async ubus call methods.
 *
 * @typedef {{
 *   completed: function(): boolean,
 *   await: function(): boolean,
 *   abort: function(): boolean
 * }} UbusDeferred
 */

/**
 * Query ubus error information.
 *
 * Returns a string containing a description of the last ubus error when
 * the *numeric* argument is absent or false.
 *
 * Returns a ubus status code number when the *numeric* argument is `true`.
 *
 * Returns `null` if there is no error information.
 *
 * @function module:ubus#error
 *
 * @param {boolean} [numeric]
 * Whether to return a numeric status code (`true`) or a human readable
 * error message (false).
 *
 * @returns {?string|?int}
 */
export function error(numeric) {};

/**
 * Establish a connection to the ubus bus.
 *
 * Connects to the specified ubus socket path or the default socket if none
 * is provided.
 *
 * Returns a connection resource on success.
 *
 * Returns `null` if the connection could not be established.
 *
 * @function module:ubus#connect
 *
 * @param {string} [socket]
 * The path to the ubus socket to connect to. If omitted, the default socket
 * path is used.
 *
 * @param {int} [timeout=30]
 * The timeout in seconds to use for subsequent ubus operations.
 *
 * @returns {?UbusConnection}
 */
export function connect(socket, timeout) {};

/**
 * List available ubus objects.
 *
 * Queries the ubus bus for registered objects. If an object name pattern
 * is provided, returns signatures for matching objects. Otherwise, returns
 * a list of all registered object paths.
 *
 * Returns an array of object paths or object signatures.
 *
 * Returns `null` if the list operation failed.
 *
 * @function module:ubus.connection#list
 *
 * @param {string} [object_name]
 * Optional object name pattern to filter results. When provided, returns
 * signatures for matching objects; otherwise returns all object paths.
 *
 * @returns {?string[]}
 */

/**
 * Invoke a ubus method synchronously.
 *
 * Calls the specified method on a ubus object and waits for the response.
 *
 * Returns the method response data, or an array of responses if multiple
 * replies were received.
 *
 * Returns `null` if the call failed.
 *
 * @function module:ubus.connection#call
 *
 * @param {string|int} object
 * The object name (string) or object ID (number) to call the method on.
 *
 * @param {string} method
 * The name of the method to invoke.
 *
 * @param {Object} [data]
 * Optional method arguments as an object with field names and values.
 *
 * @param {string|boolean} [return="single"]
 * Controls how multiple responses are handled: `"single"` returns only
 * the first response, `"multiple"` returns an array of all responses,
 * `"ignore"` discards the response.
 *
 * @param {int} [fd]
 * Optional file descriptor to send along with the call.
 *
 * @param {function} [fd_cb]
 * Optional callback function invoked when a file descriptor is received.
 *
 * @returns {?any}
 */

/**
 * Send a request on a channel connection.
 *
 * Similar to call() but uses object ID 0 for channel-based communication.
 *
 * Returns the method response data.
 *
 * Returns `null` if the request failed.
 *
 * @function module:ubus.channel#request
 *
 * @param {string} method
 * The name of the method to invoke.
 *
 * @param {Object} [data]
 * Optional method arguments as an object with field names and values.
 *
 * @param {string|boolean} [return="single"]
 * Controls how multiple responses are handled.
 *
 * @param {int} [fd]
 * Optional file descriptor to send along with the request.
 *
 * @param {function} [fd_cb]
 * Optional callback function invoked when a file descriptor is received.
 *
 * @returns {?any}
 *
 * @example
 * const chan = open_channel(…);
 * const result = chan.request("method_name", { arg: "value" });
 */

/**
 * Invoke a ubus method asynchronously.
 *
 * Initiates a non-blocking call to the specified method on a ubus object.
 * The provided callback will be invoked when the response is received or on
 * timeout.
 *
 * Returns a deferred request resource representing the pending operation.
 *
 * Returns `null` if the deferred call could not be initiated.
 *
 * @function module:ubus.connection#defer
 *
 * @param {string} object
 * The object name to call the method on.
 *
 * @param {string} method
 * The name of the method to invoke.
 *
 * @param {Object} [data]
 * Optional method arguments as an object with field names and values.
 *
 * @param {function} [cb]
 * Callback function invoked when the operation completes. Receives status
 * code and response data as arguments.
 *
 * @param {function} [data_cb]
 * Optional callback invoked for intermediate data notifications.
 *
 * @param {int} [fd]
 * Optional file descriptor to send along with the call.
 *
 * @param {function} [fd_cb]
 * Optional callback function invoked when a file descriptor is received.
 *
 * @returns {?UbusDeferred}
 *
 * @example
 * // Asynchronous call with callback - typical pattern for RPC handlers
 * const conn = connect();
 *
 * const req = conn.defer("some.object", "some_method", {}, (rc, data) => {
 *     if (rc == 0)
 *         printf("Result: %.J\n", data);
 * });
 *
 * @example
 * // Persistent connection pattern - avoid GC by keeping reference
 * const ubus = connect();
 *
 * function get_status(req) {
 *     // Use persistent ubus connection for async calls
 *     return ubus.defer("some.object", "some_method", {}, (rc, data) => {
 *         req.reply({ result: data });
 *     });
 * }
 */

/**
 * Send an asynchronous request on a channel connection.
 *
 * Similar to defer() but uses object ID 0 for channel-based communication.
 *
 * Returns a deferred request resource representing the pending operation.
 *
 * Returns `null` if the deferred call could not be initiated.
 *
 * @function module:ubus.channel#defer
 *
 * @param {string} method
 * The name of the method to invoke.
 *
 * @param {Object} [data]
 * Optional method arguments as an object with field names and values.
 *
 * @param {function} [cb]
 * Callback function invoked when the operation completes.
 *
 * @param {function} [data_cb]
 * Optional callback invoked for intermediate data notifications.
 *
 * @param {int} [fd]
 * Optional file descriptor to send along with the request.
 *
 * @param {function} [fd_cb]
 * Optional callback function invoked when a file descriptor is received.
 *
 * @returns {?UbusDeferred}
 *
 * @example
 * const chan = open_channel(…);
 * const req = chan.defer("method_name", { arg: "value" },
 *     (status, data) => {
 *         printf("Status: %d\n", status);
 *     });
 */

/**
 * Send a reply to a deferred ubus method call.
 *
 * Sends the specified reply data to the caller of a deferred method
 * request. After sending the reply, the request context is finished unless
 * `more` is set to `true`.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred or the reply was already sent.
 *
 * @function module:ubus.request#reply
 *
 * @param {Object} [reply]
 * The reply data to send as an object with field names and values.
 *
 * @param {int} [rcode=0]
 * Optional status code to return. Use negative values to indicate more
 * replies will follow.
 *
 * @returns {?boolean}
 *
 * @example
 * // In a published object method handler
 * publish("my.service", {
 *     "hello": (req, msg) => {
 *         req.reply({ message: "Hello, " + msg.name });
 *     }
 * });
 */

/**
 * Defer completion of a ubus method call.
 *
 * Marks the current request as deferred, allowing the handler to complete
 * the request asynchronously at a later time by calling reply().
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:ubus.request#defer
 *
 * @returns {?boolean}
 *
 * @example
 * // In a published object method handler
 * publish("my.service", {
 *     "async_method": (req, msg) => {
 *         req.defer();
 *         // Do async work...
 *         req.reply({ result: "done" });
 *     }
 * });
 */

/**
 * Get the caller's file descriptor from a ubus method call.
 *
 * Returns the UNIX file descriptor number that was passed by the caller,
 * or -1 if no file descriptor was sent.
 *
 * @function module:ubus.request#get_fd
 *
 * @returns {int}
 * The file descriptor number, or -1 if none was provided.
 */

/**
 * Set a file descriptor to send with a ubus method reply.
 *
 * Associates a file descriptor with the current request to be sent back to
 * the caller along with the reply.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:ubus.request#set_fd
 *
 * @param {int} fd
 * The file descriptor number to send.
 *
 * @returns {?boolean}
 *
 * @example
 * // In a published object method handler
 * publish("my.service", {
 *     "get_fd": (req, msg) => {
 *         let fd = some_file_descriptor;
 *         req.set_fd(fd);
 *         req.reply({ info: "fd sent" });
 *     }
 * });
 */

/**
 * Finish a ubus method call with an error status.
 *
 * Completes the current deferred request with the specified error status
 * code without sending any reply data.
 *
 * Returns `true` on success.
 *
 * Returns `null` if an error occurred or the reply was already sent.
 *
 * @function module:ubus.request#error
 *
 * @param {int} [rcode=UBUS_STATUS_UNKNOWN_ERROR]
 * The error status code to return.
 *
 * @returns {?boolean}
 *
 * @example
 * // In a published object method handler
 * publish("my.service", {
 *     "process": (req, msg) => {
 *         if (!msg.input) {
 *             req.error(UBUS_STATUS_INVALID_ARGUMENT);
 *             return;
 *         }
 *         req.reply({ result: "ok" });
 *     }
 * });
 */

/**
 * Check if a notification request has completed.
 *
 * Returns `true` if the notification request has finished.
 *
 * Returns `false` if the request is still pending.
 *
 * @function module:ubus.notify#completed
 *
 * @returns {boolean}
 *
 * @example
 * const n = obj.notify("method", { data: "value" });
 * if (n.completed()) {
 *     printf("Notification sent\n");
 * }
 */

/**
 * Abort a pending notification request.
 *
 * Cancels an asynchronous notification request that has not yet completed.
 *
 * Returns `true` if the request was aborted.
 *
 * Returns `false` if the request was already completed.
 *
 * @function module:ubus.notify#abort
 *
 * @returns {boolean}
 *
 * @example
 * const n = obj.notify("method", { data: "value" });
 * if (!n.completed()) {
 *     n.abort();
 * }
 */

/**
 * Send a notification from a ubus object.
 *
 * Sends an asynchronous notification of the specified type to all
 * subscribers of the object. Optional callbacks can be provided to handle
 * data, status, and completion events.
 *
 * Returns a notification request resource for asynchronous operations.
 *
 * Returns a status code number when a synchronous timeout is specified.
 *
 * Returns `null` if the notification could not be sent.
 *
 * @function module:ubus.object#notify
 *
 * @param {string} type
 * The notification type string.
 *
 * @param {Object} [data]
 * Optional notification data as an object with field names and values.
 *
 * @param {function} [data_cb]
 * Optional callback invoked for each data notification received.
 *
 * @param {function} [status_cb]
 * Optional callback invoked for status updates.
 *
 * @param {function} [cb]
 * Optional callback invoked when the notification operation completes.
 *
 * @param {int} [timeout]
 * Optional timeout in milliseconds. If specified, the operation waits
 * synchronously for completion.
 *
 * @returns {?UbusNotify|?int}
 *
 * @example
 * const obj = publish("my.service", {
 *     "trigger": (req, msg) => {
 *         obj.notify("update", { key: "value" }, (idx, ret) => {
 *             printf("Notification %d: status %d\n", idx, ret);
 *         });
 *         req.reply({ sent: true });
 *     }
 * });
 */

/**
 * Remove a ubus object from the bus.
 *
 * Unregisters the object from the ubus bus, making it no longer accessible
 * to other clients.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the object could not be removed.
 *
 * @function module:ubus.object#remove
 *
 * @returns {?boolean}
 *
 * @example
 * const obj = publish("my.service", { … });
 * // … do work …
 * obj.remove();
 */

/**
 * Check if a ubus object has subscribers.
 *
 * Returns `true` if there are active subscribers to the object.
 *
 * Returns `false` if no subscribers are currently connected.
 *
 * @function module:ubus.object#subscribed
 *
 * @returns {boolean}
 *
 * @example
 * const obj = publish("my.service", {
 *     "trigger": (req, msg) => {
 *         if (obj.subscribed()) {
 *             obj.notify("update", { data: "value" });
 *         }
 *         req.reply({ notified: obj.subscribed() });
 *     }
 * });
 */

/**
 * Publish a ubus object on the bus.
 *
 * Registers a new object with the specified name and methods on the ubus
 * bus. The object can define method handlers and an optional subscribe
 * callback.
 *
 * Returns an object resource representing the published object.
 *
 * Returns `null` if the object could not be registered.
 *
 * @function module:ubus.connection#publish
 *
 * @param {string} object_name
 * The name to register the object under.
 *
 * @param {Object} [methods]
 * Optional object defining methods with `call` functions and optional
 * `args` type specifications.
 *
 * @param {function} [subscribe_callback]
 * Optional callback invoked when a subscriber connects to the object.
 *
 * @returns {?UbusObject}
 *
 * @example
 * const conn = connect();
 * const obj = conn.publish("my.service", {
 *     "hello": {
 *         call: (req, msg) => {
 *             req.reply({ message: "Hello, " + msg.name });
 *         },
 *         args: { name: "string" }
 *     }
 * });
 */

/**
 * Remove an event listener from the bus.
 *
 * Unregisters the event handler, stopping it from receiving further events.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the listener could not be removed.
 *
 * @function module:ubus.listener#remove
 *
 * @returns {?boolean}
 *
 * @example
 * const listener = conn.listener("my.event.*", (type, data) => {
 *     printf("Event: %s, Data: %.J\n", type, data);
 * });
 * // … later …
 * listener.remove();
 */

/**
 * Register an event listener.
 *
 * Registers a callback to be invoked when events matching the specified
 * pattern are received. The listener receives the event type and data.
 *
 * Returns a listener resource that can be removed via
 * {@link module:ubus.listener#remove|remove()}.
 *
 * Returns `null` if the listener could not be registered.
 *
 * @function module:ubus.connection#listener
 *
 * @param {string} pattern
 * The event type pattern to match, supporting wildcards (e.g.,
 * `` `system.*` ``, `` `my.event.?` ``).
 *
 * @param {function} cb
 * Callback invoked when a matching event is received. Receives the event
 * type string and event data object as arguments.
 *
 * @returns {?UbusListener}
 *
 * @example
 * const conn = connect();
 * const listener = conn.listener("system.*", (type, data) => {
 *     printf("Event %s: %.J\n", type, data);
 * });
 */

/**
 * Send a ubus event.
 *
 * Broadcasts an event of the specified type with optional data to all
 * registered event listeners.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the event could not be sent.
 *
 * @function module:ubus.connection#event
 *
 * @param {string} event_type
 * The type string identifying the event.
 *
 * @param {Object} [event_data]
 * Optional event data as an object with field names and values.
 *
 * @returns {?boolean}
 *
 * @example
 * const conn = connect();
 * conn.event("system.boot", { host: "router1", uptime: 3600 });
 */

/**
 * Subscribe to a ubus object.
 *
 * Registers interest in notifications from the specified object.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the subscription failed.
 *
 * @function module:ubus.subscriber#subscribe
 *
 * @param {string} object_name
 * The name of the object to subscribe to.
 *
 * @returns {?boolean}
 *
 * @example
 * const conn = connect();
 * const sub = conn.subscriber((event) => {
 *     printf("Notification: type=%s, data=%.J\n", event.type, event.data);
 * });
 * sub.subscribe("my.object");
 */

/**
 * Unsubscribe from a ubus object.
 *
 * Stops receiving notifications from the specified object.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the unsubscription failed.
 *
 * @function module:ubus.subscriber#unsubscribe
 *
 * @param {string} object_name
 * The name of the object to unsubscribe from.
 *
 * @returns {?boolean}
 *
 * @example
 * const sub = conn.subscriber("my.object", (event) => { … });
 * // … later, to unsubscribe temporarily …
 * sub.unsubscribe("my.object");
 */

/**
 * Remove a subscriber from the bus.
 *
 * Unregisters the subscriber, stopping it from receiving further
 * notifications.
 *
 * Returns `true` on success.
 *
 * Returns `null` if the subscriber could not be removed.
 *
 * @function module:ubus.subscriber#remove
 *
 * @returns {?boolean}
 *
 * @example
 * const sub = conn.subscriber("my.object", (event) => { … });
 * // … when done …
 * sub.remove();
 */

/**
 * Register a ubus subscriber.
 *
 * Creates a subscriber that can receive notifications from ubus objects.
 * The subscriber can define notify and remove callbacks, and optional
 * subscription patterns for automatic object discovery.
 *
 * Returns a subscriber resource representing the registered subscriber.
 *
 * Returns `null` if the subscriber could not be registered.
 *
 * @function module:ubus.connection#subscriber
 *
 * @param {function} notify_callback
 * Callback invoked when a notification is received from a subscribed
 * object.
 *
 * @param {function} remove_callback
 * Callback invoked when a subscribed object is removed from the bus.
 *
 * @param {string[]} [subscription_patterns]
 * Optional array of glob patterns for automatic object subscription.
 *
 * @returns {?UbusSubscriber}
 *
 * @example
 * const conn = connect();
 * const sub = conn.subscriber(
 *     (event) => {
 *         printf("Received: type=%s, data=%.J\n",
 *                event.type, event.data);
 *     },
 *     (objid) => {
 *         printf("Object removed: %d\n", objid);
 *     },
 *     ["network.interface.*"]  // Auto-subscribe to matching objects
 * );
 * // Subscribe to a specific object
 * sub.subscribe("some.object");
 */

/**
 * Disconnect from the ubus bus.
 *
 * Closes the connection to the ubus bus and releases associated resources.
 * All pending requests are aborted.
 *
 * Returns `true` on success.
 *
 * @function module:ubus.connection#disconnect
 *
 * @returns {boolean}
 *
 * @example
 * const conn = connect();
 * // … do work …
 * conn.disconnect();
 */

/**
 * Check if a deferred request has completed.
 *
 * Returns `true` if the deferred request has finished.
 *
 * Returns `false` if the request is still pending.
 *
 * @function module:ubus.deferred#completed
 *
 * @returns {boolean}
 */

/**
 * Wait synchronously for a deferred request to complete.
 *
 * Blocks until the deferred request completes or times out.
 *
 * Returns `true` if the request completed.
 *
 * Returns `false` if the request was already completed.
 *
 * @function module:ubus.deferred#await
 *
 * @returns {boolean}
 */

/**
 * Abort a pending deferred request.
 *
 * Cancels an asynchronous request that has not yet completed.
 *
 * Returns `true` if the request was aborted.
 *
 * Returns `false` if the request was already completed.
 *
 * @function module:ubus.deferred#abort
 *
 * @returns {boolean}
 */

/**
 * Create a new ubus channel from a method call context.
 *
 * Creates a bidirectional channel communication path in response to an
 * incoming method call. The callback will be invoked for incoming messages
 * on the channel.
 *
 * Returns a channel connection resource.
 *
 * Returns `null` if the channel could not be created.
 *
 * @function module:ubus.request#new_channel
 *
 * @param {function} cb
 * Callback invoked for incoming messages on the channel.
 *
 * @param {function} [disconnect_cb]
 * Optional callback invoked when the channel is disconnected.
 *
 * @param {int} [timeout=30]
 * The timeout in seconds for subsequent operations.
 *
 * @returns {?UbusChannel}
 */

/**
 * Connect to a ubus channel from a file descriptor.
 *
 * Creates a channel connection from an existing file descriptor, typically
 * received from a method call. The callback will be invoked for incoming
 * messages on the channel.
 *
 * Returns a channel connection resource.
 *
 * Returns `null` if the channel could not be created.
 *
 * @function module:ubus#open_channel
 *
 * @param {int|FsFile|Socket} fd
 * The file descriptor or resource of the channel to connect to. When a plain
 * integer fd is passed, the ubus channel takes ownership and closes it on
 * disconnect. When a resource object with a `fileno()` method is passed, the
 * resource retains ownership of the fd; the channel merely detaches from it
 * on disconnect without closing.
 *
 * @param {function} cb
 * Callback invoked for incoming messages on the channel.
 *
 * @param {function} [disconnect_cb]
 * Optional callback invoked when the channel is disconnected.
 *
 * @param {int} [timeout=30]
 * The timeout in seconds for subsequent operations.
 *
 * @returns {?UbusChannel}
 */
export function open_channel(fd, cb, disconnect_cb, timeout) {};

/**
 * Get or set the ubus exception handler.
 *
 * When called without arguments, returns the currently registered exception
 * handler function. When called with a function argument, registers it as
 * the exception handler for ubus operations.
 *
 * Returns the current exception handler when called without arguments.
 *
 * Returns `true` when a new handler was set.
 *
 * @function module:ubus#guard
 *
 * @param {function} [handler]
 * The exception handler function to register.
 *
 * @returns {function|boolean}
 */
export function guard(handler) {};

/** @type {int} */ export let STATUS_OK;
/** @type {int} */ export let STATUS_INVALID_COMMAND;
/** @type {int} */ export let STATUS_INVALID_ARGUMENT;
/** @type {int} */ export let STATUS_METHOD_NOT_FOUND;
/** @type {int} */ export let STATUS_NOT_FOUND;
/** @type {int} */ export let STATUS_NO_DATA;
/** @type {int} */ export let STATUS_PERMISSION_DENIED;
/** @type {int} */ export let STATUS_TIMEOUT;
/** @type {int} */ export let STATUS_NOT_SUPPORTED;
/** @type {int} */ export let STATUS_UNKNOWN_ERROR;
/** @type {int} */ export let STATUS_CONNECTION_FAILED;
/** @type {int} */ export let STATUS_NO_MEMORY;
/** @type {int} */ export let STATUS_PARSE_ERROR;
/** @type {int} */ export let STATUS_SYSTEM_ERROR;
/** @type {int} */ export let STATUS_CONTINUE;
/** @type {string} */ export let SYSTEM_OBJECT_ACL;

export function list(pattern) {};
export function call(object, method, params, timeout) {};
export function defer(object, method, params, timeout, cb) {};
export function disconnect() {};
export function event(event, cb) {};
export function listener(pattern, cb) {};
export function subscriber(object, cb) {};
export function publish(object, methods) {};
export function remove(handle) {};

