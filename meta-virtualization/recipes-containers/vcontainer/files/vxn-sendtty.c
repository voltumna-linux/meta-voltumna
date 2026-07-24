/*
 * SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * vxn-sendtty - Send a PTY fd to a containerd shim via SCM_RIGHTS
 *
 * Usage: vxn-sendtty <console-socket-path> <pty-path>
 *
 * Opens pty-path, connects to console-socket (Unix socket), and sends
 * the PTY fd via sendmsg() with SCM_RIGHTS. This is the OCI runtime
 * protocol for terminal mode (--console-socket): the shim receives the
 * PTY master and bridges it to the user's terminal.
 *
 * Shell can't do SCM_RIGHTS natively, hence this small C helper.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/socket.h>
#include <sys/un.h>

int main(int argc, char *argv[])
{
	int pty_fd, sock_fd, rc;
	struct sockaddr_un addr;
	struct msghdr msg;
	struct iovec iov;
	char buf[1] = {0};
	char cmsg_buf[CMSG_SPACE(sizeof(int))];
	struct cmsghdr *cmsg;

	if (argc != 3) {
		fprintf(stderr, "Usage: %s <console-socket-path> <pty-path>\n",
			argv[0]);
		return 1;
	}

	pty_fd = open(argv[2], O_RDWR | O_NOCTTY);
	if (pty_fd < 0) {
		perror("open pty");
		return 1;
	}

	/* Set PTY to raw mode for direct terminal I/O.
	 * Without this, the PTY slave's line discipline (echo, canonical mode)
	 * buffers input and echoes characters, preventing the shim from
	 * bridging the terminal correctly. */
	{
		struct termios tio;
		if (tcgetattr(pty_fd, &tio) == 0) {
			cfmakeraw(&tio);
			tcsetattr(pty_fd, TCSANOW, &tio);
		}
	}

	sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock_fd < 0) {
		perror("socket");
		close(pty_fd);
		return 1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, argv[1], sizeof(addr.sun_path) - 1);

	if (connect(sock_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("connect");
		close(pty_fd);
		close(sock_fd);
		return 1;
	}

	memset(&msg, 0, sizeof(msg));
	iov.iov_base = buf;
	iov.iov_len = sizeof(buf);
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = cmsg_buf;
	msg.msg_controllen = sizeof(cmsg_buf);

	cmsg = CMSG_FIRSTHDR(&msg);
	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type = SCM_RIGHTS;
	cmsg->cmsg_len = CMSG_LEN(sizeof(int));
	memcpy(CMSG_DATA(cmsg), &pty_fd, sizeof(int));

	rc = sendmsg(sock_fd, &msg, 0);
	if (rc < 0) {
		perror("sendmsg");
		close(pty_fd);
		close(sock_fd);
		return 1;
	}

	close(pty_fd);
	close(sock_fd);
	return 0;
}
