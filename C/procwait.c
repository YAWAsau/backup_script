/*
 * procwait.c - waitpid/pidfd based process waiter for Android/Linux
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define PROCWAIT_VERSION "1.1.0-r413-package-stable-wait-api28-r28c"

#ifndef __NR_pidfd_open
#if defined(__aarch64__)
#define __NR_pidfd_open 434
#else
#error "This source package currently targets arm64 only."
#endif
#endif

static int wait_child(char **command) {
    pid_t child;
    int status;

    child = fork();
    if (child < 0) { perror("procwait: fork"); return 1; }

    if (child == 0) {
        execvp(command[0], command);
        perror("procwait: execvp");
        _exit(127);
    }

    for (;;) {
        const pid_t result = waitpid(child, &status, 0);
        if (result == child) break;
        if (result < 0 && errno == EINTR) continue;
        perror("procwait: waitpid");
        return 1;
    }

    if (WIFEXITED(status)) {
        const int code = WEXITSTATUS(status);
        printf("EXIT pid=%d code=%d\n", child, code);
        return code;
    }

    if (WIFSIGNALED(status)) {
        const int signo = WTERMSIG(status);
        printf("SIGNAL pid=%d signal=%d\n", child, signo);
        return 128 + signo;
    }

    printf("STATE pid=%d status=0x%x\n", child, status);
    return 1;
}

static int pidfd_open_compat(pid_t pid) {
    return (int)syscall(__NR_pidfd_open, pid, 0U);
}

static int wait_pidfd(pid_t pid) {
    struct pollfd descriptor;
    int fd;

    if (pid <= 0) {
        fputs("procwait: PID 必須大於 0\n", stderr);
        return 2;
    }

    fd = pidfd_open_compat(pid);
    if (fd < 0) {
        if (errno == ESRCH) {
            printf("EXIT pid=%d already-gone=1\n", pid);
            return 0;
        }
        if (errno == ENOSYS || errno == EINVAL) {
            fputs("procwait: 此核心不支援 pidfd_open；不使用輪詢 fallback\n",
                  stderr);
            return 3;
        }
        perror("procwait: pidfd_open");
        return 1;
    }

    descriptor.fd = fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;

    for (;;) {
        const int result = poll(&descriptor, 1U, -1);
        if (result > 0) break;
        if (result < 0 && errno == EINTR) continue;
        perror("procwait: poll");
        close(fd);
        return 1;
    }

    printf("EXIT pid=%d pidfd=1 revents=0x%x\n", pid, descriptor.revents);
    close(fd);
    return 0;
}


static long long monotonic_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000LL);
}

static int parse_long_arg(const char *text, long min_v, long max_v, long fallback) {
    char *end = NULL;
    long v;
    if (!text || !*text) return (int)fallback;
    errno = 0;
    v = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || v < min_v || v > max_v) return (int)fallback;
    return (int)v;
}

static int sleep_ms_interruptible(int ms) {
    struct timespec req;
    struct timespec rem;
    if (ms <= 0) return 0;
    req.tv_sec = ms / 1000;
    req.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&req, &rem) != 0) {
        if (errno != EINTR) return -1;
        req = rem;
    }
    return 0;
}

static bool numeric_name(const char *s) {
    if (!s || !*s) return false;
    while (*s) {
        if (*s < '0' || *s > '9') return false;
        s++;
    }
    return true;
}

static int read_cmdline_first(pid_t pid, char *buf, size_t cap) {
    char path[64];
    int fd;
    ssize_t n;
    size_t i;
    if (!buf || cap == 0) return -1;
    buf[0] = '\0';
    snprintf(path, sizeof(path), "/proc/%d/cmdline", (int)pid);
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    n = read(fd, buf, cap - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = '\0';
    for (i = 0; i < (size_t)n; i++) {
        if (buf[i] == '\0') { buf[i] = '\0'; break; }
    }
    return 0;
}

static bool cmdline_matches_package(const char *cmd, const char *pkg) {
    size_t n;
    if (!cmd || !pkg || !*cmd || !*pkg) return false;
    n = strlen(pkg);
    if (strncmp(cmd, pkg, n) != 0) return false;
    return cmd[n] == '\0' || cmd[n] == ':';
}

static int scan_package_pids(const char *pkg, char *out, size_t out_cap, int *count_out) {
    DIR *dir;
    struct dirent *de;
    int count = 0;
    size_t used = 0;
    char cmd[512];
    if (out && out_cap > 0) out[0] = '\0';
    if (count_out) *count_out = 0;
    if (!pkg || !*pkg) return -1;
    dir = opendir("/proc");
    if (!dir) return -1;
    while ((de = readdir(dir)) != NULL) {
        pid_t pid;
        char *end = NULL;
        int written;
        if (!numeric_name(de->d_name)) continue;
        errno = 0;
        long v = strtol(de->d_name, &end, 10);
        if (errno != 0 || !end || *end != '\0' || v <= 0 || v > INT32_MAX) continue;
        pid = (pid_t)v;
        if (read_cmdline_first(pid, cmd, sizeof(cmd)) != 0) continue;
        if (!cmdline_matches_package(cmd, pkg)) continue;
        count++;
        if (out && out_cap > used + 2) {
            written = snprintf(out + used, out_cap - used, "%s%d", used ? "," : "", (int)pid);
            if (written > 0) {
                if ((size_t)written >= out_cap - used) used = out_cap - 1;
                else used += (size_t)written;
            }
        }
    }
    closedir(dir);
    if (count_out) *count_out = count;
    return 0;
}

static int scan_uid_pids(uid_t uid, char *out, size_t out_cap, int *count_out) {
    DIR *dir;
    struct dirent *de;
    int count = 0;
    size_t used = 0;
    if (out && out_cap > 0) out[0] = '\0';
    if (count_out) *count_out = 0;
    dir = opendir("/proc");
    if (!dir) return -1;
    while ((de = readdir(dir)) != NULL) {
        char path[512];
        struct stat st;
        int written;
        if (!numeric_name(de->d_name)) continue;
        snprintf(path, sizeof(path), "/proc/%s", de->d_name);
        if (lstat(path, &st) != 0) continue;
        if (st.st_uid != uid) continue;
        count++;
        if (out && out_cap > used + 2) {
            written = snprintf(out + used, out_cap - used, "%s%s", used ? "," : "", de->d_name);
            if (written > 0) {
                if ((size_t)written >= out_cap - used) used = out_cap - 1;
                else used += (size_t)written;
            }
        }
    }
    closedir(dir);
    if (count_out) *count_out = count;
    return 0;
}

static int wait_scan_gone(const char *kind, int user_id, const char *target, int timeout_ms, int stable_ms) {
    long long start;
    long long first_empty = 0;
    char pids[2048];
    int count = 0;
    int rc;
    uid_t uid = 0;
    (void)user_id;
    if (!kind || !target || !*target) return 2;
    if (timeout_ms < 0) timeout_ms = 0;
    if (stable_ms < 0) stable_ms = 0;
    start = monotonic_ms();
    if (strcmp(kind, "uid") == 0) {
        char *end = NULL;
        unsigned long v;
        errno = 0;
        v = strtoul(target, &end, 10);
        if (errno != 0 || end == target || *end != '\0') return 2;
        uid = (uid_t)v;
    }
    for (;;) {
        if (strcmp(kind, "uid") == 0) rc = scan_uid_pids(uid, pids, sizeof(pids), &count);
        else rc = scan_package_pids(target, pids, sizeof(pids), &count);
        if (rc != 0) {
            printf("PROCWAIT_SCAN_FAIL kind=%s target=%s errno=%d\n", kind, target, errno);
            return 1;
        }
        if (count == 0) {
            long long now = monotonic_ms();
            if (first_empty == 0) first_empty = now;
            if (now - first_empty >= stable_ms) {
                printf("GONE kind=%s target=%s stableMs=%d elapsedMs=%lld\n", kind, target, stable_ms, now - start);
                return 0;
            }
        } else {
            first_empty = 0;
        }
        if (monotonic_ms() - start >= timeout_ms) {
            printf("TIMEOUT kind=%s target=%s count=%d pids=%s timeoutMs=%d stableMs=%d elapsedMs=%lld\n",
                   kind, target, count, pids, timeout_ms, stable_ms, monotonic_ms() - start);
            return 124;
        }
        sleep_ms_interruptible(20);
    }
}

static void print_help(const char *program) {
    printf("用法:\n  %s run COMMAND [ARG...]\n  %s pid PID\n  %s pkg-gone USER_ID PACKAGE [TIMEOUT_MS] [STABLE_MS]\n  %s pkg-stable USER_ID PACKAGE [TIMEOUT_MS] [STABLE_MS]\n  %s uid-gone UID [TIMEOUT_MS] [STABLE_MS]\n\n",
           program, program, program, program, program);
    puts("run：啟動自己的子程序並以 waitpid() 阻塞等待。");
    puts("pid：以 pidfd_open()+poll() 等待任意 PID；核心不支援就報錯，");
    puts("     不回退成 sleep/pidof 輪詢。");
    puts("pkg-gone/pkg-stable：掃 /proc/cmdline 等 package 或 package:process 消失並穩定。");
    puts("uid-gone：掃 /proc/<pid> owner uid 消失並穩定。");
}

int main(int argc, char **argv) {
    char *end = NULL;
    long value;

    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("procwait %s\n", PROCWAIT_VERSION); return 0;
    }
    if (argc == 2 && (strcmp(argv[1], "--help") == 0 ||
                      strcmp(argv[1], "-h") == 0)) {
        print_help(argv[0]); return 0;
    }
    if (argc >= 3 && strcmp(argv[1], "run") == 0)
        return wait_child(&argv[2]);

    if (argc == 3 && strcmp(argv[1], "pid") == 0) {
        errno = 0;
        value = strtol(argv[2], &end, 10);
        if (errno != 0 || end == argv[2] || *end != '\0' ||
            value <= 0 || value > INT32_MAX) {
            fputs("procwait: 無效 PID\n", stderr);
            return 2;
        }
        return wait_pidfd((pid_t)value);
    }

    if (argc >= 4 && (strcmp(argv[1], "pkg-gone") == 0 || strcmp(argv[1], "pkg-stable") == 0)) {
        int user = parse_long_arg(argv[2], 0, 9999, 0);
        int timeout_ms = argc >= 5 ? parse_long_arg(argv[4], 0, 600000, 700) : 700;
        int stable_ms = argc >= 6 ? parse_long_arg(argv[5], 0, 600000, 120) : 120;
        return wait_scan_gone("pkg", user, argv[3], timeout_ms, stable_ms);
    }

    if (argc >= 3 && strcmp(argv[1], "uid-gone") == 0) {
        int timeout_ms = argc >= 4 ? parse_long_arg(argv[3], 0, 600000, 700) : 700;
        int stable_ms = argc >= 5 ? parse_long_arg(argv[4], 0, 600000, 120) : 120;
        return wait_scan_gone("uid", 0, argv[2], timeout_ms, stable_ms);
    }

    print_help(argv[0]);
    return 2;
}
