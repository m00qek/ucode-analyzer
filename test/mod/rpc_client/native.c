/*
 * Minimal native primitives for the rpc_client.uc JSON-RPC client.
 * Exposes spawn() + three raw I/O methods on the returned process resource;
 * all framing, buffering, and protocol logic lives in rpc_client.uc.
 *
 * Installed as lib/ucode/rpc_client/native.so (imported as 'rpc_client.native').
 * Only test/helpers/rpc_client.uc imports this module directly.
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <ucode/lib.h>
#include <ucode/module.h>

typedef struct {
	pid_t pid;
	int in_fd;  /* write end of the child's stdin, -1 once closed */
	int out_fd; /* read end of the child's stdout, -1 once closed */
} uc_rpc_process_t;

static uc_resource_type_t *process_type;

static void
set_cloexec(int fd)
{
	int flags = fcntl(fd, F_GETFD);

	if (flags != -1)
		fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

static uc_value_t *
uc_rpc_spawn(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pathval = uc_fn_arg(0);
	uc_value_t *argsval = uc_fn_arg(1);
	int stdin_pipe[2], stdout_pipe[2];
	char **argv;
	size_t nargv, i;
	pid_t pid;
	uc_rpc_process_t *proc;

	if (ucv_type(pathval) != UC_STRING || (argsval && ucv_type(argsval) != UC_ARRAY)) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE,
			"expecting an executable path string and an optional argument array");
		return NULL;
	}

	if (pipe(stdin_pipe) || pipe(stdout_pipe)) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "pipe() failed: %s", strerror(errno));
		return NULL;
	}

	/*
	 * CLOEXEC the ends each side keeps, so a grandchild execed later
	 * doesn't inherit them.
	 */
	set_cloexec(stdin_pipe[1]);
	set_cloexec(stdout_pipe[0]);

	/*
	 * ucv_string_get() for short inline strings returns a pointer into the
	 * local uc_value_t* variable's own storage -- reusing the loop variable
	 * would alias all argv entries. strdup() each string for a stable copy.
	 */
	nargv = argsval ? ucv_array_length(argsval) : 0;
	argv = xalloc(sizeof(char *) * (nargv + 2));
	argv[0] = strdup(ucv_string_get(pathval));

	for (i = 0; i < nargv; i++) {
		uc_value_t *argval = ucv_array_get(argsval, i);

		argv[i + 1] = strdup(ucv_string_get(argval));
	}

	argv[nargv + 1] = NULL;

	pid = fork();

	if (pid == -1) {
		for (i = 0; i <= nargv; i++)
			free(argv[i]);
		free(argv);
		close(stdin_pipe[0]);
		close(stdin_pipe[1]);
		close(stdout_pipe[0]);
		close(stdout_pipe[1]);
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "fork() failed: %s", strerror(errno));
		return NULL;
	}

	if (pid == 0) {
		dup2(stdin_pipe[0], STDIN_FILENO);
		dup2(stdout_pipe[1], STDOUT_FILENO);

		close(stdin_pipe[0]);
		close(stdin_pipe[1]);
		close(stdout_pipe[0]);
		close(stdout_pipe[1]);

		execvp(argv[0], argv);
		_exit(127);
	}

	for (i = 0; i <= nargv; i++)
		free(argv[i]);
	free(argv);

	close(stdin_pipe[0]);
	close(stdout_pipe[1]);

	proc = xalloc(sizeof(*proc));
	proc->pid = pid;
	proc->in_fd = stdin_pipe[1];
	proc->out_fd = stdout_pipe[0];

	return uc_resource_new(process_type, proc);
}

static void
process_free(void *ptr)
{
	uc_rpc_process_t *proc = ptr;

	if (proc->in_fd != -1)
		close(proc->in_fd);

	if (proc->out_fd != -1)
		close(proc->out_fd);

	if (proc->pid > 0) {
		kill(proc->pid, SIGKILL);
		waitpid(proc->pid, NULL, 0);
	}

	free(proc);
}

/* Single write() call; returns bytes written. The retry loop is in rpc_client.uc. */
static uc_value_t *
uc_rpc_write_raw(uc_vm_t *vm, size_t nargs)
{
	uc_rpc_process_t *proc = uc_fn_thisval("rpc_client.process");
	uc_value_t *dataval = uc_fn_arg(0);
	ssize_t wlen;

	if (!proc || ucv_type(dataval) != UC_STRING) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a data string");
		return NULL;
	}

	if (proc->in_fd == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "stdin already closed");
		return NULL;
	}

	do {
		wlen = write(proc->in_fd,
		             ucv_string_get(dataval),
		             ucv_string_length(dataval));
	} while (wlen == -1 && errno == EINTR);

	if (wlen == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "write() failed: %s", strerror(errno));
		return NULL;
	}

	return ucv_int64_new(wlen);
}

/* Single read() call; returns "" at EOF. The accumulation loop is in rpc_client.uc. */
static uc_value_t *
uc_rpc_read_raw(uc_vm_t *vm, size_t nargs)
{
	uc_rpc_process_t *proc = uc_fn_thisval("rpc_client.process");
	uc_value_t *nval = uc_fn_arg(0);
	int64_t n;
	char *buf;
	ssize_t rlen;
	uc_value_t *result;

	if (!proc || ucv_type(nval) != UC_INTEGER || ucv_int64_get(nval) <= 0) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a positive byte count");
		return NULL;
	}

	if (proc->out_fd == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "stdout already closed");
		return NULL;
	}

	n = ucv_int64_get(nval);
	buf = xalloc(n);

	do {
		rlen = read(proc->out_fd, buf, (size_t)n);
	} while (rlen == -1 && errno == EINTR);

	if (rlen == -1) {
		free(buf);
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "read() failed: %s", strerror(errno));
		return NULL;
	}

	result = ucv_string_new_length(buf, (size_t)rlen);
	free(buf);

	return result;
}

/*
 * Closes both pipe ends, waits for the child, and returns its exit status:
 * positive exit code, or negative signal number if killed by a signal.
 */
static uc_value_t *
uc_rpc_close(uc_vm_t *vm, size_t nargs)
{
	uc_rpc_process_t *proc = uc_fn_thisval("rpc_client.process");
	int status;

	if (!proc)
		return NULL;

	if (proc->in_fd != -1) {
		close(proc->in_fd);
		proc->in_fd = -1;
	}

	if (proc->out_fd != -1) {
		close(proc->out_fd);
		proc->out_fd = -1;
	}

	if (proc->pid <= 0)
		return ucv_int64_new(0);

	if (waitpid(proc->pid, &status, 0) == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "waitpid() failed: %s", strerror(errno));
		return NULL;
	}

	proc->pid = -1;

	if (WIFEXITED(status))
		return ucv_int64_new(WEXITSTATUS(status));

	if (WIFSIGNALED(status))
		return ucv_int64_new(-WTERMSIG(status));

	return ucv_int64_new(0);
}

static const uc_function_list_t process_fns[] = {
	{ "write_raw", uc_rpc_write_raw },
	{ "read_raw",  uc_rpc_read_raw },
	{ "close",     uc_rpc_close },
};

static const uc_function_list_t global_fns[] = {
	{ "spawn", uc_rpc_spawn },
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	process_type = uc_type_declare(vm, "rpc_client.process", process_fns, process_free);

	uc_function_list_register(scope, global_fns);
}
