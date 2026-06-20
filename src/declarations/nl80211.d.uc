/**
* # Wireless Netlink
*
* The `nl80211` module provides functions for interacting with the nl80211 netlink interface
* for wireless networking configuration and management.
*
* Functions can be individually imported and directly accessed using the
* {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
* syntax:
*
*   ```javascript
*   import { error, request, listener, waitfor, const } from 'nl80211';
*
*   // Send a nl80211 request
*   let response = request(const.NL80211_CMD_GET_WIPHY, 0, { wiphy: 0 });
*
*   // Create a listener for wireless events
*   let wifiListener = listener((msg) => {
*       print('Received wireless event:', msg, '\n');
*   }, [const.NL80211_CMD_NEW_INTERFACE, const.NL80211_CMD_DEL_INTERFACE]);
*
*   // Wait for a specific nl80211 event
*   let event = waitfor([const.NL80211_CMD_NEW_SCAN_RESULTS], 5000);
*   if (event)
*       print('Received scan results:', event.msg, '\n');
*   ```
*
* Alternatively, the module namespace can be imported
* using a wildcard import statement:
*
*   ```javascript
*   import * as nl80211 from 'nl80211';
*
*   // Send a nl80211 request
*   let response = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: 0 });
*
*   // Create a listener for wireless events
*   let listener = nl80211.listener((msg) => {
*       print('Received wireless event:', msg, '\n');
*   }, [nl80211.const.NL80211_CMD_NEW_INTERFACE, nl80211.const.NL80211_CMD_DEL_INTERFACE]);
*   ```
*
* Additionally, the nl80211 module namespace may also be imported by invoking
* the `ucode` interpreter with the `-lnl80211` switch.
*
* @module nl80211
*/

