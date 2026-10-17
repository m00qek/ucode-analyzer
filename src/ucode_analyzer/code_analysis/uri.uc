// The analyzer reads local files only: a file:// URI is a path.

// The path of a file:// URI; any other URI is returned as it is.
export function toPath(uri) {
	return (substr(uri, 0, 7) === 'file://') ? substr(uri, 7) : uri;
};
