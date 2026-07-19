/*
 * filewatch.c - Minimal inotify event waiter for Android/Linux
 * SPDX-License-Identifier: MIT
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define FILEWATCH_VERSION "1.0.0-android23-r25c-static16k"
#define EVENT_BUFFER_SIZE (64U * 1024U)
static volatile sig_atomic_t g_stop = 0;

static void on_signal(int signo) { (void)signo; g_stop = 1; }

static int install_signals(void) {
    const int signals[] = {SIGINT, SIGTERM, SIGHUP};
    struct sigaction action;
    size_t i;
    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    for (i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) {
        if (sigaction(signals[i], &action, NULL) != 0) return -1;
    }
    return 0;
}

static int open_inotify(void) {
    int fd = inotify_init1(IN_CLOEXEC);
    if (fd >= 0) return fd;
    if (errno != ENOSYS && errno != EINVAL) return -1;
    fd = inotify_init();
    if (fd >= 0) (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}

static const char *event_name(uint32_t mask) {
    if ((mask & IN_CREATE) != 0U) return "CREATE";
    if ((mask & IN_CLOSE_WRITE) != 0U) return "CLOSE_WRITE";
    if ((mask & IN_MOVED_TO) != 0U) return "MOVED_TO";
    if ((mask & IN_MOVED_FROM) != 0U) return "MOVED_FROM";
    if ((mask & IN_DELETE) != 0U) return "DELETE";
    if ((mask & IN_MODIFY) != 0U) return "MODIFY";
    if ((mask & IN_ATTRIB) != 0U) return "ATTRIB";
    if ((mask & IN_DELETE_SELF) != 0U) return "DELETE_SELF";
    if ((mask & IN_MOVE_SELF) != 0U) return "MOVE_SELF";
    if ((mask & IN_IGNORED) != 0U) return "IGNORED";
    if ((mask & IN_Q_OVERFLOW) != 0U) return "OVERFLOW";
    return "OTHER";
}

static int split_parent_base(const char *path, char *parent, size_t parent_size,
                             char *base, size_t base_size) {
    char copy[PATH_MAX];
    char *slash;
    size_t length;
    if (path == NULL || path[0] == '\0') { errno = EINVAL; return -1; }
    length = strlen(path);
    if (length >= sizeof(copy)) { errno = ENAMETOOLONG; return -1; }
    memcpy(copy, path, length + 1U);
    while (length > 1U && copy[length - 1U] == '/') copy[--length] = '\0';
    slash = strrchr(copy, '/');
    if (slash == NULL) {
        if (snprintf(parent, parent_size, ".") >= (int)parent_size ||
            snprintf(base, base_size, "%s", copy) >= (int)base_size) {
            errno = ENAMETOOLONG; return -1;
        }
        return 0;
    }
    if (slash == copy) {
        if (snprintf(parent, parent_size, "/") >= (int)parent_size) {
            errno = ENAMETOOLONG; return -1;
        }
    } else {
        *slash = '\0';
        if (snprintf(parent, parent_size, "%s", copy) >= (int)parent_size) {
            errno = ENAMETOOLONG; return -1;
        }
    }
    if (snprintf(base, base_size, "%s", slash + 1) >= (int)base_size ||
        base[0] == '\0') { errno = EINVAL; return -1; }
    return 0;
}

static int wait_exists(const char *path) {
    char parent[PATH_MAX];
    char base[NAME_MAX + 1U];
    unsigned char buffer[EVENT_BUFFER_SIZE];
    const uint32_t mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO |
                          IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF;
    int fd, wd;
    if (access(path, F_OK) == 0) { printf("EXISTS path=%s\n", path); return 0; }
    if (split_parent_base(path, parent, sizeof(parent), base, sizeof(base)) != 0) {
        perror("filewatch: split path"); return 1;
    }
    fd = open_inotify();
    if (fd < 0) { perror("filewatch: inotify_init"); return 1; }
    wd = inotify_add_watch(fd, parent, mask);
    if (wd < 0) { perror("filewatch: inotify_add_watch"); close(fd); return 1; }
    if (access(path, F_OK) == 0) { printf("EXISTS path=%s\n", path); close(fd); return 0; }

    while (!g_stop) {
        ssize_t received = read(fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (received < 0) {
            if (errno == EINTR) continue;
            perror("filewatch: read"); close(fd); return 1;
        }
        while (offset + sizeof(struct inotify_event) <= (size_t)received) {
            const struct inotify_event *event =
                (const struct inotify_event *)(buffer + offset);
            const size_t record_size = sizeof(*event) + (size_t)event->len;
            if (record_size == 0U || offset + record_size > (size_t)received) {
                fputs("filewatch: malformed inotify event\n", stderr);
                close(fd); return 1;
            }
            if ((event->mask & (IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED)) != 0U) {
                fputs("filewatch: watched parent disappeared\n", stderr);
                close(fd); return 2;
            }
            if (event->len > 0U && strcmp(event->name, base) == 0 &&
                access(path, F_OK) == 0) {
                printf("%s path=%s\n", event_name(event->mask), path);
                close(fd); return 0;
            }
            offset += record_size;
        }
    }
    close(fd);
    return 130;
}

static int watch_path(const char *path, bool once) {
    unsigned char buffer[EVENT_BUFFER_SIZE];
    const uint32_t mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO |
                          IN_MOVED_FROM | IN_DELETE | IN_MODIFY |
                          IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF;
    int fd = open_inotify();
    int wd;
    if (fd < 0) { perror("filewatch: inotify_init"); return 1; }
    wd = inotify_add_watch(fd, path, mask);
    if (wd < 0) { perror("filewatch: inotify_add_watch"); close(fd); return 1; }

    while (!g_stop) {
        ssize_t received = read(fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (received < 0) {
            if (errno == EINTR) continue;
            perror("filewatch: read"); close(fd); return 1;
        }
        while (offset + sizeof(struct inotify_event) <= (size_t)received) {
            const struct inotify_event *event =
                (const struct inotify_event *)(buffer + offset);
            const size_t record_size = sizeof(*event) + (size_t)event->len;
            if (record_size == 0U || offset + record_size > (size_t)received) {
                fputs("filewatch: malformed inotify event\n", stderr);
                close(fd); return 1;
            }
            printf("%s mask=0x%x cookie=%u name=%s\n",
                   event_name(event->mask), event->mask, event->cookie,
                   event->len > 0U ? event->name : "-");
            if (once) { close(fd); return 0; }
            if ((event->mask & IN_IGNORED) != 0U) { close(fd); return 2; }
            offset += record_size;
        }
    }
    close(fd);
    return 130;
}

static void print_help(const char *program) {
    printf("用法:\n  %s --wait-exists PATH\n  %s --once PATH\n  %s PATH\n\n",
           program, program, program);
    puts("--wait-exists：檔案已存在就立即成功，否則阻塞等待建立/移入。");
    puts("--once：等待指定檔案或目錄的第一個 inotify 事件後退出。");
    puts("無選項：持續輸出指定檔案或目錄的事件。");
}

int main(int argc, char **argv) {
    if (install_signals() != 0) { perror("filewatch: sigaction"); return 1; }
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("filewatch %s\n", FILEWATCH_VERSION); return 0;
    }
    if (argc == 2 && (strcmp(argv[1], "--help") == 0 ||
                      strcmp(argv[1], "-h") == 0)) {
        print_help(argv[0]); return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--wait-exists") == 0) return wait_exists(argv[2]);
    if (argc == 3 && strcmp(argv[1], "--once") == 0) return watch_path(argv[2], true);
    if (argc == 2) return watch_path(argv[1], false);
    print_help(argv[0]);
    return 2;
}
