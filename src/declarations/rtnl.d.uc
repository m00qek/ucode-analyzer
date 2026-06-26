// Source: https://github.com/jow-/ucode @ fecacb8188c6a4f38d97434160b979d73e898b24
/**
 * # Routing Netlink
 *
 * The `rtnl` module provides functions for interacting with the routing netlink interface.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```javascript
 *   import { error, request, listener, RTM_GETROUTE, RTM_NEWROUTE, RTM_DELROUTE, AF_INET } from 'rtnl';
 *
 *   // Send a netlink request
 *   let response = request(RTM_GETROUTE, 0, { family: AF_INET });
 *
 *   // Create a listener for route changes
 *   let routeListener = listener((msg) => {
 *       print('Received route message:', msg, '\n');
 *   }, [RTM_NEWROUTE, RTM_DELROUTE]);
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```javascript
 *   import * as rtnl from 'rtnl';
 *
 *   // Send a netlink request
 *   let response = rtnl.request(rtnl.RTM_GETROUTE, 0, { family: rtnl.AF_INET });
 *
 *   // Create a listener for route changes
 *   let listener = rtnl.listener((msg) => {
 *       print('Received route message:', msg, '\n');
 *   }, [rtnl.RTM_NEWROUTE, rtnl.RTM_DELROUTE]);
 *   ```
 *
 * Additionally, the rtnl module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lrtnl` switch.
 *
 * @module rtnl
 */

/**
 * Netlink listener handle returned by {@link module:rtnl#listener|listener()}.
 *
 * @typedef {{ set_commands: function(int[]): boolean, close: function(): boolean }} RtnlListener
 */

/**
 * Query error information.
 *
 * Returns a string containing a description of the last occurred error or
 * `null` if there is no error information.
 *
 * @function module:rtnl#error
 *
 * @returns {?string}
 *
 * @example
 * // Trigger rtnl error
 * request('invalid_command', {}, {});
 *
 * // Print error (should yield error description)
 * print(error(), "\n");
 */
export function error() {};

/**
 * Send a netlink request.
 *
 * Sends a netlink request with the specified command, flags, and payload.
 *
 * @function module:rtnl#request
 *
 * @param {string} cmd - The netlink command to send
 * @param {int} flags - The netlink flags for the request
 * @param {*} payload - The payload data for the request
 *
 * @returns {?*} - The response data or null on error
 *
 * @example
 * // Send a route request
 * let response = request('RTM_GETROUTE', 0, { family: AF_INET });
 */
export function request(cmd, flags, payload) {};

/**
 * Create a netlink listener.
 *
 * Creates a new netlink listener that will receive messages matching the specified
 * commands and multicast groups.
 *
 * @function module:rtnl#listener
 *
 * @param {function} callback - The callback function to invoke when a message is received
 * @param {int[]} [commands] - Array of netlink commands to listen for (optional)
 * @param {int[]} [groups] - Array of multicast groups to join (optional)
 *
 * @returns {?RtnlListener}
 *
 * @example
 * // Create a listener for route changes
 * let routeListener = listener((msg) => {
 *     print('Received route message:', msg, '\n');
 * }, [RTM_NEWROUTE, RTM_DELROUTE]);
 */
export function listener(callback, commands, groups) {};

/**
 * Set the commands for a netlink listener.
 *
 * Updates the set of netlink commands that the listener will receive.
 *
 * @function module:rtnl.listener#set_commands
 *
 * @param {string[]} commands - Array of netlink commands to listen for
 *
 * @returns {boolean} - true if successful, false on error
 *
 * @example
 * // Update listener to only receive route messages
 * listener.set_commands([RTM_NEWROUTE, RTM_DELROUTE]);
 */

/**
 * Close a netlink listener.
 *
 * Closes the netlink listener and stops receiving messages.
 *
 * @function module:rtnl.listener#close
 *
 * @returns {boolean} - true if successful, false on error
 *
 * @example
 * // Close the listener
 * listener.close();
 */

