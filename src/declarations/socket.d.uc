/**
 * # Socket Module
 *
 * The `socket` module provides functions for interacting with sockets.
 *
 * Functions can be individually imported and directly accessed using the
 * {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import#named_import named import}
 * syntax:
 *
 *   ```javascript
 *   import { AF_INET, SOCK_STREAM, create as socket } from 'socket';
 *
 *   let sock = socket(AF_INET, SOCK_STREAM, 0);
 *   sock.connect('192.168.1.1', 80);
 *   sock.send(…);
 *   sock.recv(…);
 *   sock.close();
 *   ```
 *
 * Alternatively, the module namespace can be imported
 * using a wildcard import statement:
 *
 *   ```javascript
 *   import * as socket from 'socket';
 *
 *   let sock = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
 *   sock.connect('192.168.1.1', 80);
 *   sock.send(…);
 *   sock.recv(…);
 *   sock.close();
 *   ```
 *
 * Additionally, the socket module namespace may also be imported by invoking
 * the `ucode` interpreter with the `-lsocket` switch.
 *
 * @module socket
 */

/**
 * Sets options on the socket.
 *
 * Sets the specified option on the socket to the given value.
 *
 * Returns `true` if the option was successfully set.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:socket.socket#setopt
 *
 * @param {int} level
 * The protocol level at which the option resides. This can be a level such as
 * `SOL_SOCKET` for the socket API level or a specific protocol level defined
 * by the system.
 *
 * @param {int} option
 * The socket option to set. This can be an integer representing the option,
 * such as `SO_REUSEADDR`, or a constant defined by the system.
 *
 * @param {*} value
 * The value to set the option to. The type of this argument depends on the
 * specific option being set. It can be an integer, a boolean, a string, or a
 * dictionary representing the value to set. If a dictionary is provided, it is
 * internally translated to the corresponding C struct type required by the
 * option.
 *
 * @returns {?boolean}
 */
export function socket(level, option, value) {};

/**
 * Gets options from the socket.
 *
 * Retrieves the value of the specified option from the socket.
 *
 * Returns the value of the requested option.
 *
 * Returns `null` if an error occurred or if the option is not supported.
 *
 * @function module:socket.socket#getopt
 *
 * @param {int} level
 * The protocol level at which the option resides. This can be a level such as
 * `SOL_SOCKET` for the socket API level or a specific protocol level defined
 * by the system.
 *
 * @param {int} option
 * The socket option to retrieve. This can be an integer representing the
 * option, such as `SO_REUSEADDR`, or a constant defined by the system.
 *
 * @returns {?*}
 * The value of the requested option. The type of the returned value depends
 * on the specific option being retrieved. It can be an integer, a boolean, a
 * string, or a dictionary representing a complex data structure.
 */
export function socket(level, option) {};

/**
 * Returns the UNIX file descriptor number associated with the socket.
 *
 * Returns the file descriptor number.
 *
 * Returns `-1` if an error occurred.
 *
 * @function module:socket.socket#fileno
 *
 * @returns {int}
 */
export function socket() {};

/**
 * Query error information.
 *
 * Returns a string containing a description of the last occurred error when
 * the *numeric* argument is absent or false.
 *
 * Returns a positive (`errno`) or negative (`EAI_*` constant) error code number
 * when the *numeric* argument is `true`.
 *
 * Returns `null` if there is no error information.
 *
 * @function module:socket#error
 *
 * @param {boolean} [numeric]
 * Whether to return a numeric error code (`true`) or a human readable error
 * message (false).
 *
 * @returns {?string|?int}
 *
 * @example
 * // Trigger socket error by attempting to bind IPv6 address with IPv4 socket
 * socket.create(socket.AF_INET, socket.SOCK_STREAM, 0).bind("::", 8080);
 *
 * // Print error (should yield "Address family not supported by protocol")
 * print(socket.error(), "\n");
 *
 * // Trigger resolve error
 * socket.addrinfo("doesnotexist.org");
 *
 * // Query error code (should yield -2 for EAI_NONAME)
 * print(socket.error(true), "\n");  //
 */
export function error(numeric) {};

/**
 * Returns a string containing a description of the positive (`errno`) or
 * negative (`EAI_*` constant) error code number given by the *code* argument.
 *
 * Returns `null` if the error code number is unknown.
 *
 * @function module:socket#strerror
 *
 * @param {int} code
 * The error code.
 *
 * @returns {?string}
 *
 * @example
 * // Should output 'Name or service not known'.
 * print(socket.strerror(-2), '\n');
 *
 * // Should output 'No route to host'.
 * print(socket.strerror(113), '\n');
 */
export function strerror(code) {};

/**
 * Parses the provided address value into a socket address representation.
 *
 * This function parses the given address value into a socket address
 * representation required for a number of socket operations. The address value
 * can be provided in various formats:
 * - For IPv4 addresses, it can be a string representing the IP address,
 *   optionally followed by a port number separated by colon, e.g.
 *   `192.168.0.1:8080`.
 * - For IPv6 addresses, it must be an address string enclosed in square
 *   brackets if a port number is specified, otherwise the brackets are
 *   optional. The address string may also include a scope ID in the form
 *   `%ifname` or `%number`, e.g. `[fe80::1%eth0]:8080` or `fe80::1%15`.
 * - Any string value containing a slash is treated as UNIX domain socket path.
 * - Alternatively, it can be provided as an array returned by
 *   {@link module:core#iptoarr|iptoarr()}, representing the address octets.
 * - It can also be an object representing a network address, with properties
 *   for `address` (the IP address) and `port` or a single property `path` to
 *   denote a UNIX domain socket address.
 *
 * @function module:socket#sockaddr
 *
 * @param {string|int[]|module:socket.socket.SocketAddress} address
 * The address value to parse.
 *
 * @returns {?module:socket.socket.SocketAddress}
 * A socket address representation of the provided address value, or `null` if
 * the address could not be parsed.
 *
 * @example
 * // Parse an IP address string with port
 * const address1 = sockaddr('192.168.0.1:8080');
 *
 * // Parse an IPv6 address string with port and scope identifier
 * const address2 = sockaddr('[fe80::1%eth0]:8080');
 *
 * // Parse an array representing an IP address
 * const address3 = sockaddr([192, 168, 0, 1]);
 *
 * // Parse a network address object
 * const address4 = sockaddr({ address: '192.168.0.1', port: 8080 });
 *
 * // Convert a path value to a UNIX domain socket address
 * const address5 = sockaddr('/var/run/daemon.sock');
 */
export function sockaddr(address) {};

/**
 * Resolves the given network address into hostname and service name.
 *
 * The `nameinfo()` function provides an API for reverse DNS lookup and service
 * name resolution. It returns an object containing the following properties:
 * - `hostname`: The resolved hostname.
 * - `service`: The resolved service name.
 *
 * Returns an object representing the resolved hostname and service name.
 * Return `null` if an error occurred during resolution.
 *
 * @function module:socket#nameinfo
 *
 * @param {string|module:socket.socket.SocketAddress} address
 * The network address to resolve. It can be specified as:
 * - A string representing the IP address.
 * - An object representing the address with properties `address` and `port`.
 *
 * @param {int} [flags]
 * Optional flags that provide additional control over the resolution process,
 * specified as bitwise OR-ed number of `NI_*` constants.
 *
 * @returns {?{hostname: string, service: string}}
 *
 * @see {@link module:socket~"Socket Types"|Socket Types}
 * @see {@link module:socket~"Name Info Constants"|AName Info Constants}
 *
 * @example
 * // Resolve a network address into hostname and service name
 * const result = network.getnameinfo('192.168.1.1:80');
 * print(result); // { "hostname": "example.com", "service": "http" }
 */
export function nameinfo(address, flags) {};

/**
 * Resolves the given hostname and optional service name into a list of network
 * addresses, according to the provided hints.
 *
 * The `addrinfo()` function provides an API for performing DNS and service name
 * resolution. It returns an array of objects, each representing a resolved
 * address.
 *
 * Returns an array of resolved addresses.
 * Returns `null` if an error occurred during resolution.
 *
 * @function module:socket#addrinfo
 *
 * @param {string} hostname
 * The hostname to resolve.
 *
 * @param {string} [service]
 * Optional service name to resolve. If not provided, the service field of the
 * resulting address information structures is left uninitialized.
 *
 * @param {Object} [hints]
 * Optional hints object that provides additional control over the resolution
 * process. It can contain the following properties:
 * - `family`: The preferred address family (`AF_INET` or `AF_INET6`).
 * - `socktype`: The socket type (`SOCK_STREAM`, `SOCK_DGRAM`, etc.).
 * - `protocol`: The protocol of returned addresses.
 * - `flags`: Bitwise OR-ed `AI_*` flags to control the resolution behavior.
 *
 * @returns {?module:socket.AddressInfo[]}
 *
 * @see {@link module:socket~"Socket Types"|Socket Types}
 * @see {@link module:socket~"Address Info Flags"|Address Info Flags}
 *
 * @example
 * // Resolve all addresses
 * const addresses = socket.addrinfo('example.org');
 *
 * // Resolve IPv4 addresses for a given hostname and service
 * const ipv4addresses = socket.addrinfo('example.com', 'http', { family: socket.AF_INET });
 *
 * // Resolve IPv6 addresses without specifying a service
 * const ipv6Addresses = socket.addrinfo('example.com', null, { family: socket.AF_INET6 });
 */
export function addrinfo(hostname, service, hints) {};

/**
 * Polls a number of sockets for state changes.
 *
 * Returns an array of `[socket, flags]` tuples for each socket with pending
 * events. When a tuple is passed as socket argument, it is included as-is into
 * the result tuple array, with the flags entry changed to a bitwise OR-ed value
 * describing the pending events for this socket. When a plain socket instance
 * (or another kind of handle) is passed, a new tuple array is created for this
 * socket within the result tuple array, containing this socket as first and the
 * bitwise OR-ed pending events as second element.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:socket#poll
 *
 * @param {int} timeout
 * Amount of milliseconds to wait for socket activity before aborting the poll
 * call. If set to `0`, the poll call will return immediately if none of the
 * provided sockets has pending events, if set to a negative value, the poll
 * call will wait indefinitely, in all other cases the poll call will wait at
 * most for the given amount of milliseconds before returning.
 *
 * @param {...(module:socket.socket|module:socket.PollSpec)} sockets
 * An arbitrary amount of socket arguments. Each argument may be either a plain
 * {@link module:socket.socket|socket instance} (or any other kind of handle
 * implementing a `fileno()` method) or a `[socket, flags]` tuple specifying the
 * socket and requested poll flags. If a plain socket (or other kind of handle)
 * instead of a tuple is provided, the requested poll flags default to
 * `POLLIN|POLLERR|POLLHUP` for this socket.
 *
 * @returns {module:socket.PollSpec[]}
 *
 * @example
 * let x = socket.connect("example.org", 80);
 * let y = socket.connect("example.com", 80);
 *
 * // Pass plain socket arguments
 * let events = socket.poll(10, x, y);
 * print(events); // [ [ "<socket 0x7>", 0 ], [ "<socket 0x8>", 0 ] ]
 *
 * // Passing tuples allows attaching state information and requesting
 * // different I/O events
 * let events = socket.poll(10,
 * 	[ x, socket.POLLOUT | socket.POLLHUP, "This is example.org" ],
 * 	[ y, socket.POLLOUT | socket.POLLHUP, "This is example.com" ]
 * );
 * print(events); // [ [ "<socket 0x7>", 4, "This is example.org" ],
 *                //   [ "<socket 0x8>", 4, "This is example.com" ] ]
 */
export function poll(timeout, sockets) {};

/**
 * Creates a network socket and connects it to the specified host and service.
 *
 * This high level function combines the functionality of
 * {@link module:socket#create|create()},
 * {@link module:socket#addrinfo|addrinfo()} and
 * {@link module:socket.socket#connect|connect()} to simplify connection
 * establishment with the socket module.
 *
 * @function module:socket#connect
 *
 * @param {string|int[]|module:socket.socket.SocketAddress} host
 * The host to connect to, can be an IP address, hostname,
 * {@link module:socket.socket.SocketAddress|SocketAddress}, or an array value
 * returned by {@link module:core#iptoarr|iptoarr()}.
 *
 * @param {string|int} [service]
 * The service to connect to, can be a symbolic service name (such as "http") or
 * a port number. Optional if host is specified as
 * {@link module:socket.socket.SocketAddress|SocketAddress}.
 *
 * @param {Object} [hints]
 * Optional preferences for the socket. It can contain the following properties:
 * - `family`: The preferred address family (`AF_INET` or `AF_INET6`).
 * - `socktype`: The socket type (`SOCK_STREAM`, `SOCK_DGRAM`, etc.).
 * - `protocol`: The protocol of the created socket.
 * - `flags`: Bitwise OR-ed `AI_*` flags to control the resolution behavior.
 *
 * If no hints are not provided, the default socket type preference is set to
 * `SOCK_STREAM`.
 *
 * @param {int} [timeout=-1]
 * The timeout in milliseconds for socket connect operations. If set to a
 * negative value, no specifc time limit is imposed and the function will
 * block until either a connection was successfull or the underlying operating
 * system timeout is reached.
 *
 * @returns {module:socket.socket}
 *
 * @example
 * // Resolve host, try to connect to both resulting IPv4 and IPv6 addresses
 * let conn = socket.connect("example.org", 80);
 *
 * // Enforce usage of IPv6
 * let conn = socket.connect("example.com", 80, { family: socket.AF_INET6 });
 *
 * // Connect a UDP socket
 * let conn = socket.connect("192.168.1.1", 53, { socktype: socket.SOCK_DGRAM });
 *
 * // Bypass name resolution by specifying a SocketAddress structure
 * let conn = socket.connect({ address: "127.0.0.1", port: 9000 });
 *
 * // Use SocketAddress structure to connect a UNIX domain socket
 * let conn = socket.connect({ path: "/var/run/daemon.sock" });
 */
export function connect(host, service, hints, timeout) {};

/**
 * Binds a listening network socket to the specified host and service.
 *
 * This high-level function combines the functionality of
 * {@link module:socket#create|create()},
 * {@link module:socket#addrinfo|addrinfo()},
 * {@link module:socket.socket#bind|bind()}, and
 * {@link module:socket.socket#listen|listen()} to simplify setting up a
 * listening socket with the socket module.
 *
 * @function module:socket#listen
 *
 * @param {string|int[]|module:socket.socket.SocketAddress} host
 * The host to bind to, can be an IP address, hostname,
 * {@link module:socket.socket.SocketAddress|SocketAddress}, or an array value
 * returned by {@link module:core#iptoarr|iptoarr()}.
 *
 * @param {string|int} [service]
 * The service to listen on, can be a symbolic service name (such as "http") or
 * a port number. Optional if host is specified as
 * {@link module:socket.socket.SocketAddress|SocketAddress}.
 *
 * @param {Object} [hints]
 * Optional preferences for the socket. It can contain the following properties:
 * - `family`: The preferred address family (`AF_INET` or `AF_INET6`).
 * - `socktype`: The socket type (`SOCK_STREAM`, `SOCK_DGRAM`, etc.).
 * - `protocol`: The protocol of the created socket.
 * - `flags`: Bitwise OR-ed `AI_*` flags to control the resolution behavior.
 *
 * If no hints are provided, the default socket type preference is set to
 * `SOCK_STREAM`.
 *
 * @param {int} [backlog=128]
 * The maximum length of the queue of pending connections.
 *
 * @param {boolean} [reuseaddr]
 * Whether to set the SO_REUSEADDR option before calling bind().
 *
 * @returns {module:socket.socket}
 *
 * @example
 * // Listen for incoming TCP connections on port 80
 * let server = socket.listen("localhost", 80);
 *
 * // Listen on IPv6 address only
 * let server = socket.listen("machine.local", 8080, { family: socket.AF_INET6 });
 *
 * // Listen on a UNIX domain socket
 * let server = socket.listen({ path: "/var/run/server.sock" });
 */
export function listen(host, service, hints, backlog, reuseaddr) {};

/**
 * Creates a network socket instance.
 *
 * This function creates a new network socket with the specified domain and
 * type, determined by one of the modules `AF_*` and `SOCK_*` constants
 * respectively, and returns the resulting socket instance for use in subsequent
 * socket operations.
 *
 * The domain argument specifies the protocol family, such as AF_INET or
 * AF_INET6, and defaults to AF_INET if not provided.
 *
 * The type argument specifies the socket type, such as SOCK_STREAM or
 * SOCK_DGRAM, and defaults to SOCK_STREAM if not provided. It may also
 * be bitwise OR-ed with SOCK_NONBLOCK to enable non-blocking mode or
 * SOCK_CLOEXEC to enable close-on-exec semantics.
 *
 * The protocol argument may be used to indicate a particular protocol
 * to be used with the socket, and it defaults to 0 (automatically
 * determined protocol) if not provided.
 *
 * Returns a socket descriptor representing the newly created socket.
 *
 * Returns `null` if an error occurred during socket creation.
 *
 * @function module:socket#create
 *
 * @param {int} [domain=AF_INET]
 * The communication domain for the socket, e.g., AF_INET or AF_INET6.
 *
 * @param {int} [type=SOCK_STREAM]
 * The socket type, e.g., SOCK_STREAM or SOCK_DGRAM. It may also be
 * bitwise OR-ed with SOCK_NONBLOCK or SOCK_CLOEXEC.
 *
 * @param {int} [protocol=0]
 * The protocol to be used with the socket.
 *
 * @returns {?module:socket.socket}
 * A socket instance representing the newly created socket.
 *
 * @example
 * // Create a TCP socket
 * const tcp_socket = create(AF_INET, SOCK_STREAM);
 *
 * // Create a nonblocking IPv6 UDP socket
 * const udp_socket = create(AF_INET6, SOCK_DGRAM | SOCK_NONBLOCK);
 */
export function create(domain, type, protocol) {};

/**
 * Creates a network socket instance from an existing file descriptor.
 *
 * Returns a socket descriptor representing the newly created socket.
 *
 * Returns `null` if an error occurred during socket creation.
 *
 * @function module:socket#open
 *
 * @param {int} [fd]
 * The file descriptor number
 *
 * @returns {?module:socket.socket}
 * A socket instance representing the socket.
 */
export function open(fd) {};

/**
 * Creates a connected socket instance with a pair file descriptor.
 *
 * This function creates new network sockets with the specified type,
 * determined by one of the `SOCK_*` constants, and returns resulting socket
 * instances for use in subsequent socket operations.
 *
 * The type argument specifies the socket type, such as SOCK_STREAM or
 * SOCK_DGRAM, and defaults to SOCK_STREAM if not provided. It may also
 * be bitwise OR-ed with SOCK_NONBLOCK to enable non-blocking mode or
 * SOCK_CLOEXEC to enable close-on-exec semantics.
 *
 * Returns an array of socket descriptors.
 *
 * Returns `null` if an error occurred during socket creation.
 *
 * @function module:socket#pair
 *
 * @param {int} [type=SOCK_STREAM]
 * The socket type, e.g., SOCK_STREAM or SOCK_DGRAM. It may also be
 * bitwise OR-ed with SOCK_NONBLOCK or SOCK_CLOEXEC.
 *
 * @returns {Array<?module:socket.socket>}
 * Socket instances representing the newly created sockets.
 *
 * @example
 * // Create a TCP socket pair
 * const tcp_sockets = pair(SOCK_STREAM);
 *
 * // Create a nonblocking IPv6 UDP socket pair
 * const udp_sockets = pair(SOCK_DGRAM | SOCK_NONBLOCK);
 */
export function pair(type) {};

/**
 * Connects the socket to a remote address.
 *
 * Attempts to establish a connection to the specified remote address.
 *
 * Returns `true` if the connection is successfully established.
 * Returns `null` if an error occurred during the connection attempt.
 *
 * @function module:socket.socket#connect
 *
 * @param {string|module:socket.socket.SocketAddress} address
 * The address of the remote endpoint to connect to.
 *
 * @param {int} port
 * The port number of the remote endpoint to connect to.
 *
 * @returns {?boolean}
 */
export function socket(address, port) {};

/**
 * Sends data through the socket.
 *
 * Sends the provided data through the socket handle to the specified remote
 * address, if provided.
 *
 * Returns the number of bytes sent.
 * Returns `null` if an error occurred during the send operation.
 *
 * @function module:socket.socket#send
 *
 * @param {*} data
 * The data to be sent through the socket. String data is sent as-is, any other
 * type is implicitly converted to a string first before being sent on the
 * socket.
 *
 * @param {int} [flags]
 * Optional flags that modify the behavior of the send operation.
 *
 * @param {module:socket.socket.SocketAddress|int[]|string} [address]
 * The address of the remote endpoint to send the data to. It can be either an
 * IP address string, an array returned by {@link module:core#iptoarr|iptoarr()},
 * or an object representing a network address. If not provided, the data is
 * sent to the remote endpoint the socket is connected to.
 *
 * @returns {?int}
 *
 * @see {@link module:socket#sockaddr|sockaddr()}
 *
 * @example
 * // Send to connected socket
 * let tcp_sock = socket.create(socket.AF_INET, socket.SOCK_STREAM);
 * tcp_sock.connect("192.168.1.1", 80);
 * tcp_sock.send("GET / HTTP/1.0\r\n\r\n");
 *
 * // Send a datagram on unconnected socket
 * let udp_sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
 * udp_sock.send("Hello there!", 0, "255.255.255.255:9000");
 * udp_sock.send("Hello there!", 0, {
 *   family: socket.AF_INET,      // optional
 *   address: "255.255.255.255",
 *   port: 9000
 * });
 */
export function socket(data, flags, address) {};

/**
 * Receives data from the socket.
 *
 * Receives data from the socket handle, optionally specifying the maximum
 * length of data to receive, flags to modify the receive behavior, and an
 * optional address dictionary where the function will place the address from
 * which the data was received (for unconnected sockets).
 *
 * Returns a string containing the received data.
 * Returns an empty string if the remote side closed the socket.
 * Returns `null` if an error occurred during the receive operation.
 *
 * @function module:socket.socket#recv
 *
 * @param {int} [length=4096]
 * The maximum number of bytes to receive.
 *
 * @param {int} [flags]
 * Optional flags that modify the behavior of the receive operation.
 *
 * @param {Object} [address]
 * An object where the function will store the address from which the data was
 * received. If provided, it will be filled with the details obtained from the
 * sockaddr argument of the underlying `recvfrom()` syscall. See the type
 * definition of {@link module:socket.socket.SocketAddress|SocketAddress} for
 * details on the format.
 *
 * @returns {?string}
 */
export function socket(length, flags, address) {};

/**
 * Sends a message through the socket.
 *
 * Sends a message through the socket handle, supporting complex message
 * structures including multiple data buffers and ancillary data. This function
 * allows for precise control over the message content and delivery behavior.
 *
 * Returns the number of sent bytes.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:socket.socket#sendmsg
 *
 * @param {*} [data]
 * The data to be sent. If a string is provided, it is sent as is. If an array
 * is specified, each item is sent as a separate `struct iovec`. Non-string
 * values are implicitly converted to a string and sent. If omitted, only
 * ancillary data and address are considered.
 *
 * @param {module:socket.socket.ControlMessage[]|string} [ancillaryData]
 * Optional ancillary data to be sent. If an array is provided, each element is
 * converted to a control message. If a string is provided, it is sent as-is
 * without further interpretation. Refer to
 * {@link module:socket.socket#recvmsg|`recvmsg()`} and
 * {@link module:socket.socket.ControlMessage|ControlMessage} for details.
 *
 * @param {module:socket.socket.SocketAddress} [address]
 * The destination address for the message. If provided, it sets or overrides
 * the packet destination address.
 *
 * @param {int} [flags]
 * Optional flags to modify the behavior of the send operation. This should be a
 * bitwise OR-ed combination of `MSG_*` flag values.
 *
 * @returns {?int}
 * Returns the number of bytes sent on success, or `null` if an error occurred.
 *
 * @example
 * // Send file descriptors over domain socket
 * const f1 = fs.open("example.txt", "w");
 * const f2 = fs.popen("date +%s", "r");
 * const sk = socket.connect({ family: socket.AF_UNIX, path: "/tmp/socket" });

 * sk.sendmsg("Hi there, here's some descriptors!", [
 * 	{ level: socket.SOL_SOCKET, type: socket.SCM_RIGHTS, data: [ f1, f2 ] }
 * ]);
 *
 * // Send multiple values in one datagram
 * sk.sendmsg([ "This", "is", "one", "message" ]);
 */
export function socket(data, ancillaryData, address, flags) {};

/**
 * Receives a message from the socket.
 *
 * Receives a message from the socket handle, allowing for more complex data
 * reception compared to `recv()`. This includes the ability to receive
 * ancillary data (such as file descriptors, credentials, etc.), multiple
 * message segments, and optional flags to modify the receive behavior.
 *
 * Returns an object containing the received message data, ancillary data,
 * and the sender's address.
 *
 * Returns `null` if an error occurred during the receive operation.
 *
 * @function module:socket.socket#recvmsg
 *
 * @param {int[]|int} [sizes]
 * Specifies the sizes of the buffers used for receiving the message. If an
 * array of numbers is provided, each number determines the size of an
 * individual buffer segment, creating multiple `struct iovec` for reception.
 * If a single number is provided, a single buffer of that size is used.
 *
 * @param {int} [ancillarySize]
 * The size allocated for the ancillary data buffer. If not provided, ancillary
 * data is not processed.
 *
 * @param {int} [flags]
 * Optional flags to modify the behavior of the receive operation. This should
 * be a bitwise OR-ed combination of flag values.
 *
 * @returns {?module:socket.socket.ReceivedMessage}
 * An object containing the received message data, ancillary data,
 * and the sender's address.
 *
 * @example
 * // Receive file descriptors over domain socket
 * const sk = socket.listen({ family: socket.AF_UNIX, path: "/tmp/socket" });
 * sk.setopt(socket.SOL_SOCKET, socket.SO_PASSCRED, true);
 *
 * const msg = sk.recvmsg(1024, 1024); *
 * for (let cmsg in msg.ancillary)
 *   if (cmsg.level == socket.SOL_SOCKET && cmsg.type == socket.SCM_RIGHTS)
 *     print(`Got some descriptors: ${cmsg.data}!\n`);
 *
 * // Receive message in segments of 10, 128 and 512 bytes
 * const msg = sk.recvmsg([ 10, 128, 512 ]);
 * print(`Message parts: ${msg.data[0]}, ${msg.data[1]}, ${msg.data[2]}\n`);
 *
 * // Peek buffer
 * const msg = sk.recvmsg(0, 0, socket.MSG_PEEK|socket.MSG_TRUNC);
 * print(`Received ${length(msg.data)} bytes, ${msg.length} bytes available\n`);
 */
export function socket(sizes, ancillarySize, flags) {};

/**
 * Binds a socket to a specific address.
 *
 * This function binds the socket to the specified address.
 *
 * Returns `true` if the socket is successfully bound.
 *
 * Returns `null` on error, e.g. when the address is in use.
 *
 * @function module:socket.socket#bind
 *
 * @param {string|module:socket.socket.SocketAddress} address
 * The IP address to bind the socket to.
 *
 * @returns {?boolean}
 *
 * @example
 * const sock = socket.create(…);
 * const success = sock.bind("192.168.0.1:80");
 *
 * if (success)
 *     print(`Socket bound successfully!\n`);
 * else
 *     print(`Failed to bind socket: ${sock.error()}.\n`);
 */
export function socket(address) {};

/**
 * Listen for connections on a socket.
 *
 * This function marks the socket as a passive socket, that is, as a socket that
 * will be used to accept incoming connection requests using `accept()`.
 *
 * The `backlog` parameter specifies the maximum length to which the queue of
 * pending connections may grow. If a connection request arrives when the queue
 * is full, the client connection might get refused.
 *
 * If `backlog` is not provided, it defaults to 128.
 *
 * Returns `true` if the socket is successfully marked as passive.
 * Returns `null` if an error occurred, e.g. when the requested port is in use.
 *
 * @function module:socket.socket#listen
 *
 * @param {int} [backlog=128]
 * The maximum length of the queue of pending connections.
 *
 * @returns {?boolean}
 *
 * @see {@link module:socket.socket#accept|accept()}
 *
 * @example
 * const sock = socket.create(…);
 * sock.bind(…);
 *
 * const success = sock.listen(10);
 * if (success)
 *     print(`Socket is listening for incoming connections!\n`);
 * else
 *     print(`Failed to listen on socket: ${sock.error()}\n`);
 */
export function socket(backlog) {};

/**
 * Accept a connection on a socket.
 *
 * This function accepts a connection on the socket. It extracts the first
 * connection request on the queue of pending connections, creates a new
 * connected socket, and returns a new socket handle referring to that socket.
 * The newly created socket is not in listening state and has no backlog.
 *
 * When a optional `address` dictionary is provided, it is populated with the
 * remote address details of the peer socket.
 *
 * The optional `flags` parameter is a bitwise-or-ed number of flags to modify
 * the behavior of accepted peer socket. Possible values are:
 * - `SOCK_CLOEXEC`: Enable close-on-exec semantics for the new socket.
 * - `SOCK_NONBLOCK`: Enable nonblocking mode for the new socket.
 *
 * Returns a socket handle representing the newly created peer socket of the
 * accepted connection.
 *
 * Returns `null` if an error occurred.
 *
 * @function module:socket.socket#accept
 *
 * @param {Object} [address]
 * An optional dictionary to receive the address details of the peer socket.
 * See {@link module:socket.socket.SocketAddress|SocketAddress} for details.
 *
 * @param {int} [flags]
 * Optional flags to modify the behavior of the peer socket.
 *
 * @returns {?module:socket.socket}
 *
 * @example
 * const sock = socket.create(…);
 * sock.bind(…);
 * sock.listen();
 *
 * const peerAddress = {};
 * const newSocket = sock.accept(peerAddress, socket.SOCK_CLOEXEC);
 * if (newSocket)
 *     print(`Accepted connection from: ${peerAddress}\n`);
 * else
 *     print(`Failed to accept connection: ${sock.error()}\n`);
 */
export function socket(address, flags) {};

/**
 * Shutdown part of a full-duplex connection.
 *
 * This function shuts down part of the full-duplex connection associated with
 * the socket handle. The `how` parameter specifies which half of the connection
 * to shut down. It can take one of the following constant values:
 *
 * - `SHUT_RD`: Disables further receive operations.
 * - `SHUT_WR`: Disables further send operations.
 * - `SHUT_RDWR`: Disables further send and receive operations.
 *
 * Returns `true` if the shutdown operation is successful.
 * Returns `null` if an error occurred.
 *
 * @function module:socket.socket#shutdown
 *
 * @param {int} how
 * Specifies which half of the connection to shut down.
 * It can be one of the following constant values: `SHUT_RD`, `SHUT_WR`,
 * or `SHUT_RDWR`.
 *
 * @returns {?boolean}
 *
 * @example
 * const sock = socket.create(…);
 * sock.connect(…);
 * // Perform data exchange…
 *
 * const success = sock.shutdown(socket.SHUT_WR);
 * if (success)
 *     print(`Send operations on socket shut down successfully.\n`);
 * else
 *     print(`Failed to shut down send operations: ${sock.error()}\n`);
 */
export function socket(how) {};

/**
 * Retrieves the peer credentials.
 *
 * This function retrieves the remote uid, gid and pid of a connected UNIX
 * domain socket.
 *
 * Returns the remote credentials if the operation is successful.
 * Returns `null` on error.
 *
 * @function module:socket.socket#peercred
 *
 * @returns {?module:socket.socket.PeerCredentials}
 *
 * @example
 * const sock = socket.create(socket.AF_UNIX, …);
 * sock.connect(…);
 *
 * const peerCredentials = sock.peercred();
 * if (peerCredentials)
 *     print(`Peer credentials: ${peerCredentials}\n`);
 * else
 *     print(`Failed to retrieve peer credentials: ${sock.error()}\n`);
 */
export function socket() {};

/**
 * Retrieves the remote address.
 *
 * This function retrieves the remote address of a connected socket.
 *
 * Returns the remote address if the operation is successful.
 * Returns `null` on error.
 *
 * @function module:socket.socket#peername
 *
 * @returns {?module:socket.socket.SocketAddress}
 *
 * @see {@link module:socket.socket#sockname|sockname()}
 *
 * @example
 * const sock = socket.create(…);
 * sock.connect(…);
 *
 * const peerAddress = sock.peername();
 * if (peerAddress)
 *     print(`Connected to ${peerAddress}\n`);
 * else
 *     print(`Failed to retrieve peer address: ${sock.error()}\n`);
 */
export function socket() {};

/**
 * Retrieves the local address.
 *
 * This function retrieves the local address of a bound or connected socket.
 *
 * Returns the local address if the operation is successful.
 * Returns `null` on error.
 *
 * @function module:socket.socket#sockname
 *
 * @returns {?module:socket.socket.SocketAddress}
 *
 * @see {@link module:socket.socket#peername|peername()}
 *
 * @example
 * const sock = socket.create(…);
 * sock.connect(…);
 *
 * const myAddress = sock.sockname();
 * if (myAddress)
 *     print(`My source IP address is ${myAddress}\n`);
 * else
 *     print(`Failed to retrieve peer address: ${sock.error()}\n`);
 */
export function socket() {};

/**
 * Closes the socket.
 *
 * This function closes the socket, releasing its resources and terminating its
 * associated connections.
 *
 * Returns `true` if the socket was successfully closed.
 * Returns `null` on error.
 *
 * @function module:socket.socket#close
 *
 * @returns {?boolean}
 *
 * @example
 * const sock = socket.create(…);
 * sock.connect(…);
 * // Perform operations with the socket…
 * sock.close();
 */
export function socket() {};

