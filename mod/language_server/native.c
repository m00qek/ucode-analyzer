/*
 * Native read primitive for the language server's uloop-driven stdin loop.
 *
 * ucode's `fs` reads are stdio-buffered (fread): a numeric read(N) blocks until
 * N bytes or EOF, and stdio pull-ahead drains the kernel fd into the stdio
 * buffer -- both of which defeat uloop's level-triggered fd polling. A raw
 * read() syscall is the one thing that cannot be expressed with stock ucode
 * modules, so it is all this module provides. Everything else (uloop wiring,
 * buffering, LSP framing) lives in language_server/io.uc and protocol.uc.
 *
 * Installed as lib/ucode/language_server/native.so (imported as
 * 'language_server.native').
 */

#include <errno.h>
#include <string.h>
#include <unistd.h>

#include <ucode/lib.h>
#include <ucode/module.h>

/*
 * Single raw read() syscall on the given fd. Returns:
 *   - a string of the bytes read (length 1..n) when data is available,
 *   - null at end of file (read returned 0),
 *   - an empty string if the fd is non-blocking and no data is ready
 *     (EAGAIN / EWOULDBLOCK).
 * Any other error raises a runtime exception.
 *
 * Intended to be called once per uloop readable event. uloop is level-
 * triggered, so a single read per event suffices -- any remaining bytes raise
 * another event -- and the read never blocks because the event guarantees the
 * fd is readable.
 */
static uc_value_t *
uc_ls_read_raw(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *fdval = uc_fn_arg(0);
	uc_value_t *nval = uc_fn_arg(1);
	int fd;
	int64_t n;
	char *buf;
	ssize_t rlen;
	uc_value_t *result;

	if (ucv_type(fdval) != UC_INTEGER || ucv_type(nval) != UC_INTEGER ||
	    ucv_int64_get(nval) <= 0) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE,
			"expecting a file descriptor and a positive byte count");
		return NULL;
	}

	fd = (int)ucv_int64_get(fdval);
	n = ucv_int64_get(nval);
	buf = xalloc(n);

	do {
		rlen = read(fd, buf, (size_t)n);
	} while (rlen == -1 && errno == EINTR);

	if (rlen == 0) {
		free(buf);
		return NULL;
	}

	if (rlen == -1) {
		free(buf);

		if (errno == EAGAIN || errno == EWOULDBLOCK)
			return ucv_string_new("");

		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "read() failed: %s", strerror(errno));
		return NULL;
	}

	result = ucv_string_new_length(buf, (size_t)rlen);
	free(buf);

	return result;
}

static const uc_function_list_t global_fns[] = {
	{ "read_raw", uc_ls_read_raw },
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}
