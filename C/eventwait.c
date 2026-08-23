/*
 * eventwait.c - robust FIFO event waiter for SpeedBackup stream children
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define EVENTWAIT_VERSION "1.0.0-r413-fifo-child-fastfail-api28-r28c"

static long long monotonic_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000LL);
}

static int parse_int(const char *s, int fallback) {
    char *end = NULL;
    long v;
    if (!s || !*s) return fallback;
    errno = 0;
    v = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || v < 0 || v > 86400000L) return fallback;
    return (int)v;
}

static bool file_nonempty(const char *path) {
    struct stat st;
    return path && *path && stat(path, &st) == 0 && st.st_size > 0;
}

static bool pid_alive(pid_t pid) {
    if (pid <= 0) return false;
    if (kill(pid, 0) == 0) return true;
    return errno == EPERM;
}

static int emit_fatal(const char *tag, const char *reason) {
    printf("fatal\t126\t%s\t%s\n", tag && *tag ? tag : "remote_stream_child", reason && *reason ? reason : "remote_stream_fatal");
    fflush(stdout);
    return 126;
}

static int wait_event(const char *fifo, pid_t pid, const char *fatal_file, int timeout_ms, const char *tag) {
    int fd;
    struct pollfd pfd;
    char buf[4096];
    size_t used = 0;
    long long start = monotonic_ms();

    if (!fifo || !*fifo || pid <= 0) return 2;
    fd = open(fifo, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "eventwait: open fifo failed: %s: %s\n", fifo, strerror(errno));
        return 3;
    }
    memset(buf, 0, sizeof(buf));
    pfd.fd = fd;
    pfd.events = POLLIN | POLLHUP | POLLERR;
    pfd.revents = 0;

    for (;;) {
        int wait_ms = 100;
        if (timeout_ms > 0) {
            long long elapsed = monotonic_ms() - start;
            if (elapsed >= timeout_ms) {
                close(fd);
                printf("timeout\t124\t%s\ttimeout\n", tag && *tag ? tag : "remote_stream_child");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }
        if (file_nonempty(fatal_file)) {
            close(fd);
            return emit_fatal(tag, "remote_stream_fatal_file");
        }
        if (!pid_alive(pid) && used == 0) {
            /* Child exited without emitting. Let shell wait() decide the real rc. */
            close(fd);
            printf("done\t0\t%s\tchild_gone_no_event\n", tag && *tag ? tag : "remote_stream_child");
            return 0;
        }
        pfd.revents = 0;
        int prc = poll(&pfd, 1, wait_ms);
        if (prc < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "eventwait: poll failed: %s\n", strerror(errno));
            close(fd);
            return 4;
        }
        if (prc == 0) continue;
        if (pfd.revents & (POLLIN | POLLHUP | POLLERR)) {
            for (;;) {
                ssize_t n = read(fd, buf + used, sizeof(buf) - 1 - used);
                if (n > 0) {
                    char *nl;
                    used += (size_t)n;
                    buf[used] = '\0';
                    nl = strchr(buf, '\n');
                    if (nl) {
                        *nl = '\0';
                        printf("%s\n", buf);
                        close(fd);
                        return 0;
                    }
                    if (used >= sizeof(buf) - 2) {
                        printf("%s\n", buf);
                        close(fd);
                        return 0;
                    }
                    continue;
                }
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) break;
                if (n < 0) {
                    fprintf(stderr, "eventwait: read failed: %s\n", strerror(errno));
                    close(fd);
                    return 5;
                }
                break;
            }
        }
    }
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("eventwait %s\n", EVENTWAIT_VERSION);
        return 0;
    }
    if (argc < 3 || (argc >= 2 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0))) {
        fprintf(stderr, "usage: %s FIFO PID [FATAL_FILE|-] [TIMEOUT_MS] [TAG]\n", argv[0]);
        return argc < 3 ? 2 : 0;
    }
    char *end = NULL;
    errno = 0;
    long v = strtol(argv[2], &end, 10);
    if (errno != 0 || end == argv[2] || *end != '\0' || v <= 0 || v > 4194304L) return 2;
    const char *fatal = (argc >= 4 && strcmp(argv[3], "-") != 0) ? argv[3] : "";
    int timeout_ms = argc >= 5 ? parse_int(argv[4], 0) : 0;
    const char *tag = argc >= 6 ? argv[5] : "remote_stream_child";
    return wait_event(argv[1], (pid_t)v, fatal, timeout_ms, tag);
}
