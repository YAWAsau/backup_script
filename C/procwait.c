/*
 * procwait.c - waitpid/pidfd based process waiter for Android/Linux
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PROCWAIT_VERSION "1.0.0-android23-r25c-static16k"

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

static void print_help(const char *program) {
    printf("用法:\n  %s run COMMAND [ARG...]\n  %s pid PID\n\n",
           program, program);
    puts("run：啟動自己的子程序並以 waitpid() 阻塞等待。");
    puts("pid：以 pidfd_open()+poll() 等待任意 PID；核心不支援就報錯，");
    puts("     不回退成 sleep/pidof 輪詢。");
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

    print_help(argv[0]);
    return 2;
}
