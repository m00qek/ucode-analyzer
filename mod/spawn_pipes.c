/*
 * Bidirectional process spawning for the e2e test harness, installed as
 * spawn_pipes (test-only -- not installed by the OpenWrt package, see
 * openwrt/ucode-language-server/Makefile).
 *
 * Unlike fs.popen(), which only pipes one direction ("r" or "w"), the e2e
 * harness needs to write LSP requests to a long-running server process's
 * stdin and read its responses from stdout concurrently. uloop.process()
 * doesn't redirect the child's stdio at all. Neither covers this, hence a
 * small dedicated extension.
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
} uc_spawn_process_t;

static uc_resource_type_t *process_type;

static void
set_cloexec(int fd)
{
	int flags = fcntl(fd, F_GETFD);

	if (flags != -1)
		fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

static uc_value_t *
uc_spawn(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pathval = uc_fn_arg(0);
	uc_value_t *argsval = uc_fn_arg(1);
	int stdin_pipe[2], stdout_pipe[2];
	char **argv;
	size_t nargv, i;
	pid_t pid;
	uc_spawn_process_t *proc;

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
	 * doesn't inherit them. The ends being handed to the child via dup2()
	 * below land on stdin/stdout (fd 0/1), which are never CLOEXEC by
	 * definition, so this only needs to cover the parent-retained ends.
	 */
	set_cloexec(stdin_pipe[1]);
	set_cloexec(stdout_pipe[0]);

	/*
	 * ucv_string_get() for short inline strings returns a pointer into the
	 * local uc_value_t* variable's own storage. Storing those pointers in
	 * argv and reusing the variable each loop iteration means all entries
	 * would alias the same stack slot. strdup() each string immediately so
	 * every argv[i] owns a stable, independent copy.
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

	/* parent: close the ends handed to the child, keep the other ends */
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
	uc_spawn_process_t *proc = ptr;

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

static uc_value_t *
uc_spawn_write(uc_vm_t *vm, size_t nargs)
{
	uc_spawn_process_t *proc = uc_fn_thisval("spawn_pipes.process");
	uc_value_t *dataval = uc_fn_arg(0);
	const char *data;
	size_t len, off = 0;
	ssize_t wlen;

	if (!proc || ucv_type(dataval) != UC_STRING) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a data string");
		return NULL;
	}

	if (proc->in_fd == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "stdin already closed");
		return NULL;
	}

	data = ucv_string_get(dataval);
	len = ucv_string_length(dataval);

	while (off < len) {
		wlen = write(proc->in_fd, data + off, len - off);

		if (wlen == -1) {
			if (errno == EINTR)
				continue;

			uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "write() failed: %s", strerror(errno));
			return NULL;
		}

		off += (size_t)wlen;
	}

	return ucv_int64_new(off);
}

/* Reads up to `n` bytes, looping on short reads; returns fewer bytes only at EOF. */
static uc_value_t *
uc_spawn_read(uc_vm_t *vm, size_t nargs)
{
	uc_spawn_process_t *proc = uc_fn_thisval("spawn_pipes.process");
	uc_value_t *nval = uc_fn_arg(0);
	int64_t n;
	char *buf;
	size_t off = 0;
	ssize_t rlen;
	uc_value_t *result;

	if (!proc || ucv_type(nval) != UC_INTEGER || ucv_int64_get(nval) < 0) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a non-negative byte count");
		return NULL;
	}

	if (proc->out_fd == -1) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "stdout already closed");
		return NULL;
	}

	n = ucv_int64_get(nval);
	buf = xalloc(n);

	while (off < (size_t)n) {
		rlen = read(proc->out_fd, buf + off, (size_t)n - off);

		if (rlen == -1) {
			if (errno == EINTR)
				continue;

			free(buf);
			uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "read() failed: %s", strerror(errno));
			return NULL;
		}

		if (rlen == 0)
			break; /* EOF */

		off += (size_t)rlen;
	}

	result = ucv_string_new_length(buf, off);
	free(buf);

	return result;
}

/*
 * Closes stdin (signaling EOF to the child), then waits for it to exit and
 * returns its exit status: positive exit code, or the negative signal
 * number if it was killed by a signal -- matching fs.proc#close()'s
 * convention. Safe to call more than once.
 */
static uc_value_t *
uc_spawn_close(uc_vm_t *vm, size_t nargs)
{
	uc_spawn_process_t *proc = uc_fn_thisval("spawn_pipes.process");
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
	{ "write", uc_spawn_write },
	{ "read",  uc_spawn_read },
	{ "close", uc_spawn_close },
};

static const uc_function_list_t global_fns[] = {
	{ "spawn", uc_spawn },
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	process_type = uc_type_declare(vm, "spawn_pipes.process", process_fns, process_free);

	uc_function_list_register(scope, global_fns);
}
