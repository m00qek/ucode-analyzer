// Source: https://github.com/jow-/ucode
// Versions: 2025.07.18~3f64c808, 2026.01.16~85922056
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

/** @typedef {{ family: ?int, address: ?string, port: ?int, path: ?string }} SocketAddress */

/** @typedef {{ family: int, socktype: int, protocol: int, address: SocketAddress }} AddressInfo */

/** @typedef {{ fd: Socket, events: int }} PollSpec */

/** @typedef {{ data: any, length: int, ancillary: any[], address: ?SocketAddress }} ReceivedMessage */

/** @typedef {{ uid: int, gid: int, pid: int }} PeerCredentials */

/**
 * Socket handle returned by {@link module:socket#create|create()},
 * {@link module:socket#connect|connect()}, {@link module:socket#listen|listen()},
 * {@link module:socket#open|open()}, and {@link module:socket#pair|pair()}.
 *
 * @typedef {{
 *   setopt: function(int, int, *): ?boolean,
 *   getopt: function(int, int): ?*,
 *   fileno: function(): int,
 *   connect: function(*): ?boolean,
 *   send: function(*, ?int, ?*): ?int,
 *   recv: function(?int, ?int, ?*): ?string,
 *   sendmsg: function(*, ?*, ?*, ?int): ?int,
 *   recvmsg: function(?*, ?int, ?int): ?ReceivedMessage,
 *   bind: function(*): ?boolean,
 *   listen: function(?int): ?boolean,
 *   accept: function(?*): ?Socket,
 *   shutdown: function(int): ?boolean,
 *   peercred: function(): ?PeerCredentials,
 *   peername: function(): ?SocketAddress,
 *   sockname: function(): ?SocketAddress,
 *   close: function(): ?boolean
 * }} Socket
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
 * @param {any} value
 * The value to set the option to. The type of this argument depends on the
 * specific option being set. It can be an integer, a boolean, a string, or a
 * dictionary representing the value to set. If a dictionary is provided, it is
 * internally translated to the corresponding C struct type required by the
 * option.
 *
 * @returns {?boolean}
 */

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
 * @returns {?any}
 * The value of the requested option. The type of the returned value depends
 * on the specific option being retrieved. It can be an integer, a boolean, a
 * string, or a dictionary representing a complex data structure.
 */

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

/** @type {int} */ export let AF_UNSPEC;
/** @type {int} */ export let AF_UNIX;
/** @type {int} */ export let AF_INET;
/** @type {int} */ export let AF_INET6;
/** @type {int} */ export let AF_PACKET;
/** @type {int} */ export let SOCK_STREAM;
/** @type {int} */ export let SOCK_DGRAM;
/** @type {int} */ export let SOCK_RAW;
/** @type {int} */ export let SOCK_NONBLOCK;
/** @type {int} */ export let SOCK_CLOEXEC;
/** @type {int} */ export let SOCK_PACKET;
/** @type {int} */ export let MSG_DONTROUTE;
/** @type {int} */ export let MSG_DONTWAIT;
/** @type {int} */ export let MSG_EOR;
/** @type {int} */ export let MSG_NOSIGNAL;
/** @type {int} */ export let MSG_OOB;
/** @type {int} */ export let MSG_PEEK;
/** @type {int} */ export let MSG_TRUNC;
/** @type {int} */ export let MSG_WAITALL;
/** @type {int} */ export let MSG_CONFIRM;
/** @type {int} */ export let MSG_MORE;
/** @type {int} */ export let MSG_FASTOPEN;
/** @type {int} */ export let MSG_CMSG_CLOEXEC;
/** @type {int} */ export let MSG_ERRQUEUE;
/** @type {int} */ export let IPPROTO_IP;
/** @type {int} */ export let IP_ADD_MEMBERSHIP;
/** @type {int} */ export let IP_ADD_SOURCE_MEMBERSHIP;
/** @type {int} */ export let IP_BLOCK_SOURCE;
/** @type {int} */ export let IP_DROP_MEMBERSHIP;
/** @type {int} */ export let IP_DROP_SOURCE_MEMBERSHIP;
/** @type {int} */ export let IP_HDRINCL;
/** @type {int} */ export let IP_MSFILTER;
/** @type {int} */ export let IP_MULTICAST_IF;
/** @type {int} */ export let IP_MULTICAST_LOOP;
/** @type {int} */ export let IP_MULTICAST_TTL;
/** @type {int} */ export let IP_OPTIONS;
/** @type {int} */ export let IP_PKTINFO;
/** @type {int} */ export let IP_RECVOPTS;
/** @type {int} */ export let IP_RECVTOS;
/** @type {int} */ export let IP_RECVTTL;
/** @type {int} */ export let IP_RETOPTS;
/** @type {int} */ export let IP_TOS;
/** @type {int} */ export let IP_TTL;
/** @type {int} */ export let IP_UNBLOCK_SOURCE;
/** @type {int} */ export let IP_BIND_ADDRESS_NO_PORT;
/** @type {int} */ export let IP_FREEBIND;
/** @type {int} */ export let IP_MTU;
/** @type {int} */ export let IP_MTU_DISCOVER;
/** @type {int} */ export let IP_MULTICAST_ALL;
/** @type {int} */ export let IP_NODEFRAG;
/** @type {int} */ export let IP_PASSSEC;
/** @type {int} */ export let IP_RECVERR;
/** @type {int} */ export let IP_RECVORIGDSTADDR;
/** @type {int} */ export let IP_ROUTER_ALERT;
/** @type {int} */ export let IP_TRANSPARENT;
/** @type {int} */ export let IPPROTO_IPV6;
/** @type {int} */ export let IPV6_FLOWINFO_SEND;
/** @type {int} */ export let IPV6_FLOWINFO;
/** @type {int} */ export let IPV6_FLOWLABEL_MGR;
/** @type {int} */ export let IPV6_MULTICAST_HOPS;
/** @type {int} */ export let IPV6_MULTICAST_IF;
/** @type {int} */ export let IPV6_MULTICAST_LOOP;
/** @type {int} */ export let IPV6_RECVTCLASS;
/** @type {int} */ export let IPV6_TCLASS;
/** @type {int} */ export let IPV6_UNICAST_HOPS;
/** @type {int} */ export let IPV6_V6ONLY;
/** @type {int} */ export let IPV6_ADD_MEMBERSHIP;
/** @type {int} */ export let IPV6_ADDR_PREFERENCES;
/** @type {int} */ export let IPV6_ADDRFORM;
/** @type {int} */ export let IPV6_AUTHHDR;
/** @type {int} */ export let IPV6_AUTOFLOWLABEL;
/** @type {int} */ export let IPV6_DONTFRAG;
/** @type {int} */ export let IPV6_DROP_MEMBERSHIP;
/** @type {int} */ export let IPV6_DSTOPTS;
/** @type {int} */ export let IPV6_FREEBIND;
/** @type {int} */ export let IPV6_HOPLIMIT;
/** @type {int} */ export let IPV6_HOPOPTS;
/** @type {int} */ export let IPV6_JOIN_ANYCAST;
/** @type {int} */ export let IPV6_LEAVE_ANYCAST;
/** @type {int} */ export let IPV6_MINHOPCOUNT;
/** @type {int} */ export let IPV6_MTU_DISCOVER;
/** @type {int} */ export let IPV6_MTU;
/** @type {int} */ export let IPV6_MULTICAST_ALL;
/** @type {int} */ export let IPV6_PKTINFO;
/** @type {int} */ export let IPV6_RECVDSTOPTS;
/** @type {int} */ export let IPV6_RECVERR;
/** @type {int} */ export let IPV6_RECVFRAGSIZE;
/** @type {int} */ export let IPV6_RECVHOPLIMIT;
/** @type {int} */ export let IPV6_RECVHOPOPTS;
/** @type {int} */ export let IPV6_RECVORIGDSTADDR;
/** @type {int} */ export let IPV6_RECVPATHMTU;
/** @type {int} */ export let IPV6_RECVPKTINFO;
/** @type {int} */ export let IPV6_RECVRTHDR;
/** @type {int} */ export let IPV6_ROUTER_ALERT_ISOLATE;
/** @type {int} */ export let IPV6_ROUTER_ALERT;
/** @type {int} */ export let IPV6_RTHDR;
/** @type {int} */ export let IPV6_RTHDRDSTOPTS;
/** @type {int} */ export let IPV6_TRANSPARENT;
/** @type {int} */ export let IPV6_UNICAST_IF;
/** @type {int} */ export let SOL_SOCKET;
/** @type {int} */ export let SO_ACCEPTCONN;
/** @type {int} */ export let SO_BROADCAST;
/** @type {int} */ export let SO_DEBUG;
/** @type {int} */ export let SO_DONTROUTE;
/** @type {int} */ export let SO_ERROR;
/** @type {int} */ export let SO_KEEPALIVE;
/** @type {int} */ export let SO_LINGER;
/** @type {int} */ export let SO_OOBINLINE;
/** @type {int} */ export let SO_RCVBUF;
/** @type {int} */ export let SO_RCVLOWAT;
/** @type {int} */ export let SO_RCVTIMEO;
/** @type {int} */ export let SO_REUSEADDR;
/** @type {int} */ export let SO_REUSEPORT;
/** @type {int} */ export let SO_SNDBUF;
/** @type {int} */ export let SO_SNDLOWAT;
/** @type {int} */ export let SO_SNDTIMEO;
/** @type {int} */ export let SO_TIMESTAMP;
/** @type {int} */ export let SO_TYPE;
/** @type {int} */ export let SO_ATTACH_BPF;
/** @type {int} */ export let SO_ATTACH_FILTER;
/** @type {int} */ export let SO_ATTACH_REUSEPORT_CBPF;
/** @type {int} */ export let SO_ATTACH_REUSEPORT_EBPF;
/** @type {int} */ export let SO_BINDTODEVICE;
/** @type {int} */ export let SO_BUSY_POLL;
/** @type {int} */ export let SO_DETACH_BPF;
/** @type {int} */ export let SO_DETACH_FILTER;
/** @type {int} */ export let SO_DOMAIN;
/** @type {int} */ export let SO_INCOMING_CPU;
/** @type {int} */ export let SO_INCOMING_NAPI_ID;
/** @type {int} */ export let SO_LOCK_FILTER;
/** @type {int} */ export let SO_MARK;
/** @type {int} */ export let SO_PASSCRED;
/** @type {int} */ export let SO_PASSSEC;
/** @type {int} */ export let SO_PEEK_OFF;
/** @type {int} */ export let SO_PEERCRED;
/** @type {int} */ export let SO_PEERSEC;
/** @type {int} */ export let SO_PRIORITY;
/** @type {int} */ export let SO_PROTOCOL;
/** @type {int} */ export let SO_RCVBUFFORCE;
/** @type {int} */ export let SO_RXQ_OVFL;
/** @type {int} */ export let SO_SNDBUFFORCE;
/** @type {int} */ export let SO_TIMESTAMPNS;
/** @type {int} */ export let SCM_CREDENTIALS;
/** @type {int} */ export let SCM_RIGHTS;
/** @type {int} */ export let IPPROTO_TCP;
/** @type {int} */ export let TCP_FASTOPEN;
/** @type {int} */ export let TCP_KEEPCNT;
/** @type {int} */ export let TCP_KEEPINTVL;
/** @type {int} */ export let TCP_MAXSEG;
/** @type {int} */ export let TCP_NODELAY;
/** @type {int} */ export let TCP_CONGESTION;
/** @type {int} */ export let TCP_CORK;
/** @type {int} */ export let TCP_DEFER_ACCEPT;
/** @type {int} */ export let TCP_FASTOPEN_CONNECT;
/** @type {int} */ export let TCP_INFO;
/** @type {int} */ export let TCP_KEEPIDLE;
/** @type {int} */ export let TCP_LINGER2;
/** @type {int} */ export let TCP_QUICKACK;
/** @type {int} */ export let TCP_SYNCNT;
/** @type {int} */ export let TCP_USER_TIMEOUT;
/** @type {int} */ export let TCP_WINDOW_CLAMP;
/** @type {int} */ export let SOL_PACKET;
/** @type {int} */ export let PACKET_ADD_MEMBERSHIP;
/** @type {int} */ export let PACKET_DROP_MEMBERSHIP;
/** @type {int} */ export let PACKET_AUXDATA;
/** @type {int} */ export let PACKET_FANOUT;
/** @type {int} */ export let PACKET_LOSS;
/** @type {int} */ export let PACKET_RESERVE;
/** @type {int} */ export let PACKET_RX_RING;
/** @type {int} */ export let PACKET_STATISTICS;
/** @type {int} */ export let PACKET_TIMESTAMP;
/** @type {int} */ export let PACKET_TX_RING;
/** @type {int} */ export let PACKET_VERSION;
/** @type {int} */ export let PACKET_QDISC_BYPASS;
/** @type {int} */ export let PACKET_MR_PROMISC;
/** @type {int} */ export let PACKET_MR_MULTICAST;
/** @type {int} */ export let PACKET_MR_ALLMULTI;
/** @type {int} */ export let PACKET_HOST;
/** @type {int} */ export let PACKET_BROADCAST;
/** @type {int} */ export let PACKET_MULTICAST;
/** @type {int} */ export let PACKET_OTHERHOST;
/** @type {int} */ export let PACKET_OUTGOING;
/** @type {int} */ export let IPPROTO_UDP;
/** @type {int} */ export let UDP_CORK;
/** @type {int} */ export let SHUT_RD;
/** @type {int} */ export let SHUT_WR;
/** @type {int} */ export let SHUT_RDWR;
/** @type {int} */ export let AI_ADDRCONFIG;
/** @type {int} */ export let AI_ALL;
/** @type {int} */ export let AI_CANONIDN;
/** @type {int} */ export let AI_CANONNAME;
/** @type {int} */ export let AI_IDN;
/** @type {int} */ export let AI_NUMERICHOST;
/** @type {int} */ export let AI_NUMERICSERV;
/** @type {int} */ export let AI_PASSIVE;
/** @type {int} */ export let AI_V4MAPPED;
/** @type {int} */ export let NI_DGRAM;
/** @type {int} */ export let NI_IDN;
/** @type {int} */ export let NI_MAXHOST;
/** @type {int} */ export let NI_MAXSERV;
/** @type {int} */ export let NI_NAMEREQD;
/** @type {int} */ export let NI_NOFQDN;
/** @type {int} */ export let NI_NUMERICHOST;
/** @type {int} */ export let NI_NUMERICSERV;
/** @type {int} */ export let POLLIN;
/** @type {int} */ export let POLLPRI;
/** @type {int} */ export let POLLOUT;
/** @type {int} */ export let POLLERR;
/** @type {int} */ export let POLLHUP;
/** @type {int} */ export let POLLNVAL;
/** @type {int} */ export let POLLRDHUP;

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
 * @param {string|int[]|SocketAddress} address
 * The address value to parse.
 *
 * @returns {?SocketAddress}
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
 * @param {string|SocketAddress} address
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
 * @see {@link module:socket~"Name Info Constants"|Name Info Constants}
 *
 * @example
 * // Resolve a network address into hostname and service name
 * const result = nameinfo('192.168.1.1:80');
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
 * @returns {?AddressInfo[]}
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
 * @param {...(Socket|PollSpec)} sockets
 * An arbitrary amount of socket arguments. Each argument may be either a plain
 * {@link Socket|socket instance} (or any other kind of handle
 * implementing a `fileno()` method) or a `[socket, flags]` tuple specifying the
 * socket and requested poll flags. If a plain socket (or other kind of handle)
 * instead of a tuple is provided, the requested poll flags default to
 * `POLLIN|POLLERR|POLLHUP` for this socket.
 *
 * @returns {?PollSpec[]}
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
 * {@link Socket#connect|connect()} to simplify connection
 * establishment with the socket module.
 *
 * @function module:socket#connect
 *
 * @param {string|int[]|SocketAddress} host
 * The host to connect to, can be an IP address, hostname,
 * {@link SocketAddress|SocketAddress}, or an array value
 * returned by {@link module:core#iptoarr|iptoarr()}.
 *
 * @param {string|int} [service]
 * The service to connect to, can be a symbolic service name (such as "http") or
 * a port number. Optional if host is specified as
 * {@link SocketAddress|SocketAddress}.
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
 * @returns {?Socket}
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
 * {@link Socket#bind|bind()}, and
 * {@link Socket#listen|listen()} to simplify setting up a
 * listening socket with the socket module.
 *
 * @function module:socket#listen
 *
 * @param {string|int[]|SocketAddress} host
 * The host to bind to, can be an IP address, hostname,
 * {@link SocketAddress|SocketAddress}, or an array value
 * returned by {@link module:core#iptoarr|iptoarr()}.
 *
 * @param {string|int} [service]
 * The service to listen on, can be a symbolic service name (such as "http") or
 * a port number. Optional if host is specified as
 * {@link SocketAddress|SocketAddress}.
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
 * @returns {?Socket}
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
 * @returns {?Socket}
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
 * @since 2026.01.16~85922056
 *
 * @param {int} [fd]
 * The file descriptor number
 *
 * @returns {?Socket}
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
 * @since 2026.01.16~85922056
 *
 * @param {int} [type=SOCK_STREAM]
 * The socket type, e.g., SOCK_STREAM or SOCK_DGRAM. It may also be
 * bitwise OR-ed with SOCK_NONBLOCK or SOCK_CLOEXEC.
 *
 * @returns {Array<?Socket>}
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
 * @param {string|SocketAddress} address
 * The address of the remote endpoint to connect to.
 *
 * @param {int} port
 * The port number of the remote endpoint to connect to.
 *
 * @returns {?boolean}
 */

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
 * @param {any} data
 * The data to be sent through the socket. String data is sent as-is, any other
 * type is implicitly converted to a string first before being sent on the
 * socket.
 *
 * @param {int} [flags]
 * Optional flags that modify the behavior of the send operation.
 *
 * @param {SocketAddress|int[]|string} [address]
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
 * definition of {@link SocketAddress|SocketAddress} for
 * details on the format.
 *
 * @returns {?string}
 */

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
 * @param {any} [data]
 * The data to be sent. If a string is provided, it is sent as is. If an array
 * is specified, each item is sent as a separate `struct iovec`. Non-string
 * values are implicitly converted to a string and sent. If omitted, only
 * ancillary data and address are considered.
 *
 * @param {any[]|string} [ancillaryData]
 * Optional ancillary data to be sent. If an array is provided, each element is
 * converted to a control message. If a string is provided, it is sent as-is
 * without further interpretation. Refer to
 * {@link Socket#recvmsg|`recvmsg()`} and
 * {@link object|ControlMessage} for details.
 *
 * @param {SocketAddress} [address]
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
 * @returns {?ReceivedMessage}
 * An object containing the received message data, ancillary data,
 * and the sender's address.
 *
 * @example
 * // Receive file descriptors over domain socket
 * const sk = socket.listen({ family: socket.AF_UNIX, path: "/tmp/socket" });
 * sk.setopt(socket.SOL_SOCKET, socket.SO_PASSCRED, true);
 *
 * const msg = sk.recvmsg(1024, 1024);
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
 * @param {string|SocketAddress} address
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
 * @see {@link Socket#accept|accept()}
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
 * See {@link SocketAddress|SocketAddress} for details.
 *
 * @param {int} [flags]
 * Optional flags to modify the behavior of the peer socket.
 *
 * @returns {?Socket}
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
 * @returns {?PeerCredentials}
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
 * @returns {?SocketAddress}
 *
 * @see {@link Socket#sockname|sockname()}
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
 * @returns {?SocketAddress}
 *
 * @see {@link Socket#peername|peername()}
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

