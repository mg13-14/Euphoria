//
//  rootful_fakefs.c
//  libjailbreak — bootstrapfs engine orchestration
//

#include "rootful_fakefs.h"
#include "jbroot.h"

#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/wait.h>

extern char **environ;

int rootful_fakefs_available(void)
{
	static const char *path = NULL;
	if (!path) path = JBROOT_PATH("/basebin/bootstrapfs");
	return access(path, X_OK) == 0;
}

int rootful_fakefs_run(const char *action, const char *extraArg,
                       rootful_fakefs_progress_fn cb, void *ctx,
                       char *lastError, size_t lastErrorLen)
{
	if (lastError && lastErrorLen) lastError[0] = '\0';
	if (!rootful_fakefs_available()) {
		if (lastError && lastErrorLen)
			snprintf(lastError, lastErrorLen, "fakefs: bootstrapfs engine not present in basebin");
		return -1;
	}

	const char *engine = JBROOT_PATH("/basebin/bootstrapfs");

	int progressPipe[2];
	if (pipe(progressPipe) != 0) {
		if (lastError && lastErrorLen)
			snprintf(lastError, lastErrorLen, "fakefs: pipe() failed: %s", strerror(errno));
		return -1;
	}

	posix_spawn_file_actions_t fa;
	posix_spawn_file_actions_init(&fa);
	// engine stdout/stderr: inherit (human log lines flow to euphoria/jbctl
	// stdout, which the App shows as the live jailbreak log)
	posix_spawn_file_actions_adddup2(&fa, progressPipe[1], 3); // fd 3 = progress
	posix_spawn_file_actions_addclose(&fa, progressPipe[0]);

	char fdArg[16];
	snprintf(fdArg, sizeof(fdArg), "%d", 3);

	const char *argv[8];
	int ai = 0;
	argv[ai++] = engine;
	argv[ai++] = action;
	argv[ai++] = "--progress-fd";
	argv[ai++] = fdArg;
	if (extraArg && extraArg[0]) argv[ai++] = extraArg;
	argv[ai] = NULL;

	pid_t pid;
	int r = posix_spawn(&pid, engine, &fa, NULL, (char *const *)argv, environ);
	posix_spawn_file_actions_destroy(&fa);
	close(progressPipe[1]);
	if (r != 0) {
		close(progressPipe[0]);
		if (lastError && lastErrorLen)
			snprintf(lastError, lastErrorLen, "fakefs: posix_spawn(%s) failed: %s", engine, strerror(r));
		return -1;
	}

	// Stream progress events line-by-line.
	if (cb) {
		FILE *pf = fdopen(progressPipe[0], "r");
		if (pf) {
			char *line = NULL;
			size_t cap = 0;
			ssize_t n;
			while ((n = getline(&line, &cap, pf)) > 0) {
				while (n > 0 && (line[n-1] == '\n' || line[n-1] == '\r')) line[--n] = '\0';
				if (n > 0) cb(line, ctx);
			}
			free(line);
			fclose(pf); // closes progressPipe[0]
		}
		else {
			close(progressPipe[0]);
		}
	}
	else {
		close(progressPipe[0]);
	}

	int status = 0;
	waitpid(pid, &status, 0);
	int code = WIFEXITED(status) ? WEXITSTATUS(status) : 127;

	if (code != 0 && lastError && lastErrorLen && !lastError[0]) {
		snprintf(lastError, lastErrorLen, "fakefs: engine '%s' failed with exit code %d", action, code);
	}
	return code;
}
