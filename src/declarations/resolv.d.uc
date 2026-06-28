// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
/**
 * # DNS Resolution Module
 *
 * The `resolv` module provides DNS resolution functionality for ucode, allowing
 * you to perform DNS queries for various record types and handle responses.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```
 *   import { query } from 'resolv';
 *
 *   let result = query('example.com', { type: ['A'] });
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```
 *   import * as resolv from 'resolv';
 *
 *   let result = resolv.query('example.com', { type: ['A'] });
 *   ```
 *
 * Additionally, the resolv module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lresolv` switch.
 *
 * ## Record Types
 *
 * The module supports the following DNS record types:
 *
 * | Type    | Description                    |
 * |---------|--------------------------------|
 * | `A`     | IPv4 address record            |
 * | `AAAA`  | IPv6 address record            |
 * | `CNAME` | Canonical name record          |
 * | `MX`    | Mail exchange record           |
 * | `NS`    | Name server record             |
 * | `PTR`   | Pointer record (reverse DNS)   |
 * | `SOA`   | Start of authority record      |
 * | `SRV`   | Service record                 |
 * | `TXT`   | Text record                    |
 * | `ANY`   | Any available record type      |
 *
 * ## Response Codes
 *
 * DNS queries can return the following response codes:
 *
 * | Code        | Description                               |
 * |-------------|-------------------------------------------|
 * | `NOERROR`   | No error, query successful                |
 * | `FORMERR`   | Format error in query                     |
 * | `SERVFAIL`  | Server failure                            |
 * | `NXDOMAIN`  | Non-existent domain                       |
 * | `NOTIMP`    | Not implemented                           |
 * | `REFUSED`   | Query refused                             |
 * | `TIMEOUT`   | Query timed out                           |
 *
 * ## Response Format
 *
 * DNS query results are returned as objects where:
 * - Keys are the queried domain names
 * - Values are objects containing arrays of records grouped by type
 * - Special `rcode` property indicates query status for failed queries
 *
 * ### Record Format by Type
 *
 * **A and AAAA records:**
 * ```javascript
 * {
 *   "example.com": {
 *     "A": ["192.0.2.1", "192.0.2.2"],
 *     "AAAA": ["2001:db8::1", "2001:db8::2"]
 *   }
 * }
 * ```
 *
 * **MX records:**
 * ```javascript
 * {
 *   "example.com": {
 *     "MX": [
 *       [10, "mail1.example.com"],
 *       [20, "mail2.example.com"]
 *     ]
 *   }
 * }
 * ```
 *
 * **SRV records:**
 * ```javascript
 * {
 *   "_http._tcp.example.com": {
 *     "SRV": [
 *       [10, 5, 80, "web1.example.com"],
 *       [10, 10, 80, "web2.example.com"]
 *     ]
 *   }
 * }
 * ```
 *
 * **SOA records:**
 * ```javascript
 * {
 *   "example.com": {
 *     "SOA": [
 *       [
 *         "ns1.example.com",      // primary nameserver
 *         "admin.example.com",    // responsible mailbox
 *         2023010101,             // serial number
 *         3600,                   // refresh interval
 *         1800,                   // retry interval
 *         604800,                 // expire time
 *         86400                   // minimum TTL
 *       ]
 *     ]
 *   }
 * }
 * ```
 *
 * **TXT, NS, CNAME, PTR records:**
 * ```javascript
 * {
 *   "example.com": {
 *     "TXT": ["v=spf1 include:_spf.example.com ~all"],
 *     "NS": ["ns1.example.com", "ns2.example.com"],
 *     "CNAME": ["alias.example.com"]
 *   }
 * }
 * ```
 *
 * **Error responses:**
 * ```javascript
 * {
 *   "nonexistent.example.com": {
 *     "rcode": "NXDOMAIN"
 *   }
 * }
 * ```
 *
 * ## Examples
 *
 * Basic A record lookup:
 *
 * ```javascript
 * import { query } from 'resolv';
 *
 * const result = query(['example.com']);
 * print(result, "\n");
 * // {
 * //   "example.com": {
 * //     "A": ["192.0.2.1"],
 * //     "AAAA": ["2001:db8::1"]
 * //   }
 * // }
 * ```
 *
 * Specific record type query:
 *
 * ```javascript
 * const mxRecords = query(['example.com'], { type: ['MX'] });
 * print(mxRecords, "\n");
 * // {
 * //   "example.com": {
 * //     "MX": [[10, "mail.example.com"]]
 * //   }
 * // }
 * ```
 *
 * Multiple domains and types:
 *
 * ```javascript
 * const results = query(
 *   ['example.com', 'google.com'],
 *   { 
 *     type: ['A', 'MX'],
 *     timeout: 10000,
 *     nameserver: ['8.8.8.8', '1.1.1.1']
 *   }
 * );
 * ```
 *
 * Reverse DNS lookup:
 *
 * ```javascript
 * const ptrResult = query(['192.0.2.1'], { type: ['PTR'] });
 * print(ptrResult, "\n");
 * // {
 * //   "1.2.0.192.in-addr.arpa": {
 * //     "PTR": ["example.com"]
 * //   }
 * // }
 * ```
 *
 * @module resolv
 */

/**
 * Perform DNS queries for specified domain names.
 *
 * The `query()` function performs DNS lookups for one or more domain names
 * according to the specified options. It returns a structured object containing
 * all resolved DNS records grouped by domain name and record type.
 *
 * If no record types are specified in the options, the function will perform
 * both A and AAAA record lookups for regular domain names, or PTR record
 * lookups for IP addresses (reverse DNS).
 *
 * Returns an object containing DNS query results organized by domain name.
 *
 * Raises a runtime exception if invalid arguments are provided or if DNS
 * resolution encounters critical errors.
 *
 * @function module:resolv#query
 *
 * @param {string|string[]} names
 * Domain name(s) to query. Can be a single domain name string or an array
 * of domain name strings. IP addresses can also be provided for reverse
 * DNS lookups.
 *
 * @param {*} [options]
 * Query options object.
 *
 * @param {string[]} [options.type]
 * Array of DNS record types to query for. Valid types are: 'A', 'AAAA',
 * 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT', 'ANY'. If not specified,
 * defaults to 'A' and 'AAAA' for domain names, or 'PTR' for IP addresses.
 *
 * @param {string[]} [options.nameserver]
 * Array of DNS nameserver addresses to query. Each address can optionally
 * include a port number using '#' separator (e.g., '8.8.8.8#53'). IPv6
 * addresses can include interface scope using '%' separator. If not specified,
 * nameservers are read from /etc/resolv.conf, falling back to '127.0.0.1'.
 *
 * @param {int} [options.timeout=5000]
 * Total timeout for all queries in milliseconds.
 *
 * @param {int} [options.retries=2]
 * Number of retry attempts for failed queries.
 *
 * @param {int} [options.edns_maxsize=4096]
 * Maximum UDP packet size for EDNS (Extension Mechanisms for DNS). Set to 0
 * to disable EDNS.
 *
 * @param {boolean} [options.txt_as_array=false]
 * Return TXT record strings as array elements instead of space-joining all
 * record strings into one single string per record.
 *
 * @returns {*}
 * Object containing DNS query results. Keys are domain names, values are
 * objects containing arrays of records grouped by type, or error information
 * for failed queries.
 *
 * @example
 * // Basic A and AAAA record lookup
 * const result = query('example.com');
 * print(result, "\n");
 * // {
 * //   "example.com": {
 * //     "A": ["192.0.2.1"],
 * //     "AAAA": ["2001:db8::1"]
 * //   }
 * // }
 *
 * @example
 * // Specific record type queries
 * const mxResult = query('example.com', { type: ['MX'] });
 * print(mxResult, "\n");
 * // {
 * //   "example.com": {
 * //     "MX": [[10, "mail.example.com"]]
 * //   }
 * // }
 *
 * @example
 * // Multiple domains and types with custom nameserver
 * const results = query(
 *   ['example.com', 'google.com'],
 *   {
 *     type: ['A', 'MX'],
 *     nameserver: ['8.8.8.8', '1.1.1.1'],
 *     timeout: 10000
 *   }
 * );
 *
 * @example
 * // Reverse DNS lookup
 * const ptrResult = query(['192.0.2.1'], { type: ['PTR'] });
 * print(ptrResult, "\n");
 * // {
 * //   "1.2.0.192.in-addr.arpa": {
 * //     "PTR": ["example.com"]
 * //   }
 * // }
 *
 * @example
 * // TXT record with multiple elements
 * const txtResult = query(['_spf.facebook.com'], { type: ['TXT'], txt_as_array: true });
 * print(txtResult, "\n");
 * // {
 * //   "_spf.facebook.com": {
 * //     "TXT": [
 * //       [
 * //         "v=spf1 ip4:66.220.144.128/25 ip4:66.220.155.0/24 ip4:66.220.157.0/25 ip4:69.63.178.128/25 ip4:69.63.181.0/24 ip4:69.63.184.0/25",
 * //         " ip4:69.171.232.0/24 ip4:69.171.244.0/23 -all"
 * //       ]
 * //     ]
 * //   }
 * // }
 *
 * @example
 * // Handling errors
 * const errorResult = query(['nonexistent.example.com']);
 * print(errorResult, "\n");
 * // {
 * //   "nonexistent.example.com": {
 * //     "rcode": "NXDOMAIN"
 * //   }
 * // }
 */
export function query(names, options) {};

/**
 * Get the last error message from DNS operations.
 *
 * The `error()` function returns a descriptive error message for the last
 * failed DNS operation, or `null` if no error occurred. This function is
 * particularly useful for debugging DNS resolution issues.
 *
 * After calling this function, the stored error state is cleared, so
 * subsequent calls will return `null` unless a new error occurs.
 *
 * Returns a string describing the last error, or `null` if no error occurred.
 *
 * @function module:resolv#error
 *
 * @returns {string|null}
 * A descriptive error message for the last failed operation, or `null` if
 * no error occurred.
 *
 * @example
 * // Check for errors after a failed query
 * const result = query("example.org", { nameserver: "invalid..domain" });
 * const err = error();
 * if (err) {
 *   print("DNS query failed: ", err, "\n");
 * }
 */
export function error() {};

