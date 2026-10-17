// Exports whose doc comments carry no tags, or that have none: what a hover
// shows comes from the declarations themselves.

/** The protocol version. */
export const VERSION = 2;

/** The timeout, in seconds. */
export const TIMEOUT = int('30');

/** Joins two names. */
export function joinNames(first, second) {
	return first + second;
};

export const pick = (list, ...rest) => list[0];
