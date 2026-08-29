/*
 * eventwait.c - robust event wait primitives for SpeedBackup
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
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <time.h>
#include <unistd.h>

#define EVENTWAIT_VERSION "1.5.0-r470-complete-watch-api28-r28c"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

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

static bool file_exists(const char *path) {
    struct stat st;
    return path && *path && lstat(path, &st) == 0;
}

static bool file_nonempty(const char *path) {
    struct stat st;
    return path && *path && stat(path, &st) == 0 && st.st_size > 0;
}

static bool socket_ready(const char *path) {
    struct stat st;
    return path && *path && lstat(path, &st) == 0 && S_ISSOCK(st.st_mode);
}

static bool pid_alive(pid_t pid) {
    if (pid <= 0) return false;
    if (kill(pid, 0) == 0) return true;
    return errno == EPERM;
}

static bool file_contains(const char *path, const char *needle) {
    FILE *fp;
    char buf[4096];
    size_t nlen;
    if (!path || !*path || !needle || !*needle) return false;
    nlen = strlen(needle);
    fp = fopen(path, "rb");
    if (!fp) return false;
    size_t keep = nlen > 1 ? nlen - 1 : 0;
    char tail[512];
    size_t tail_len = 0;
    if (keep >= sizeof(tail)) keep = sizeof(tail) - 1;
    while (!feof(fp)) {
        size_t nr = fread(buf + tail_len, 1, sizeof(buf) - 1 - tail_len, fp);
        size_t total = tail_len + nr;
        buf[total] = '\0';
        if (total > 0 && strstr(buf, needle) != NULL) {
            fclose(fp);
            return true;
        }
        if (nr == 0) break;
        if (keep > 0) {
            tail_len = total < keep ? total : keep;
            memcpy(tail, buf + total - tail_len, tail_len);
            memcpy(buf, tail, tail_len);
        } else {
            tail_len = 0;
        }
    }
    fclose(fp);
    return false;
}

static int parent_dir_of(const char *path, char *dir, size_t dir_sz) {
    const char *slash;
    size_t len;
    if (!path || !*path || !dir || dir_sz == 0) return -1;
    slash = strrchr(path, '/');
    if (!slash) {
        if (dir_sz < 2) return -1;
        strcpy(dir, ".");
        return 0;
    }
    if (slash == path) len = 1;
    else len = (size_t)(slash - path);
    if (len + 1 > dir_sz) return -1;
    memcpy(dir, path, len);
    dir[len] = '\0';
    return 0;
}

static int basename_of(const char *path, char *base, size_t base_sz) {
    const char *slash;
    if (!path || !*path || !base || base_sz == 0) return -1;
    slash = strrchr(path, '/');
    const char *name = slash ? slash + 1 : path;
    if (strlen(name) + 1 > base_sz) return -1;
    strcpy(base, name);
    return 0;
}

typedef enum WaitMode {
    WM_FILE_CREATED,
    WM_FILE_NONEMPTY,
    WM_FILE_CONTAINS,
    WM_SOCKET_READY,
    WM_SIZE_STABLE
} WaitMode;

static bool condition_met(WaitMode mode, const char *path, const char *arg) {
    struct stat st;
    switch (mode) {
    case WM_FILE_CREATED: return file_exists(path);
    case WM_FILE_NONEMPTY: return file_nonempty(path);
    case WM_FILE_CONTAINS: return file_contains(path, arg);
    case WM_SOCKET_READY: return socket_ready(path);
    case WM_SIZE_STABLE:
        (void)arg;
        return path && *path && stat(path, &st) == 0 && st.st_size >= 0;
    }
    return false;
}

static int wait_path_condition(WaitMode mode, const char *path, const char *arg, int timeout_ms, const char *tag) {
    char dir[PATH_MAX];
    char base[PATH_MAX];
    int ifd = -1, wd_dir = -1, wd_file = -1;
    long long start = monotonic_ms();
    int stable_ms = 0;
    off_t last_size = -1;
    long long last_change = 0;
    struct stat st;

    if (!path || !*path) return 2;
    if (mode == WM_SIZE_STABLE) stable_ms = parse_int(arg, 500);

    if (mode != WM_SIZE_STABLE && condition_met(mode, path, arg)) {
        printf("ready\t0\t%s\timmediate\n", tag && *tag ? tag : "eventwait");
        return 0;
    }
    if (mode == WM_SIZE_STABLE && stat(path, &st) == 0) {
        last_size = st.st_size;
        last_change = start;
        if (stable_ms <= 0) {
            printf("ready\t0\t%s\tsize-stable\n", tag && *tag ? tag : "eventwait");
            return 0;
        }
    }

    if (parent_dir_of(path, dir, sizeof(dir)) == 0 && basename_of(path, base, sizeof(base)) == 0) {
        ifd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (ifd >= 0) {
            wd_dir = inotify_add_watch(ifd, dir, IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
            if (file_exists(path)) wd_file = inotify_add_watch(ifd, path, IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
        }
    }

    for (;;) {
        long long now = monotonic_ms();
        int wait_ms = 1000;
        if (timeout_ms > 0) {
            long long elapsed = now - start;
            if (elapsed >= timeout_ms) {
                if (ifd >= 0) close(ifd);
                printf("timeout\t124\t%s\ttimeout\n", tag && *tag ? tag : "eventwait");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }

        if (mode == WM_SIZE_STABLE) {
            if (stat(path, &st) == 0) {
                if (last_size != st.st_size) {
                    last_size = st.st_size;
                    last_change = now;
                } else if (last_change > 0 && now - last_change >= stable_ms) {
                    if (ifd >= 0) close(ifd);
                    printf("ready\t0\t%s\tsize-stable\n", tag && *tag ? tag : "eventwait");
                    return 0;
                }
            }
            long long to_stable = stable_ms - (now - last_change);
            if (last_change > 0 && to_stable >= 0 && to_stable < wait_ms) wait_ms = (int)to_stable + 1;
        } else if (condition_met(mode, path, arg)) {
            if (ifd >= 0) close(ifd);
            printf("ready\t0\t%s\tcondition\n", tag && *tag ? tag : "eventwait");
            return 0;
        }

        if (ifd >= 0) {
            struct pollfd pfd;
            pfd.fd = ifd;
            pfd.events = POLLIN;
            pfd.revents = 0;
            int prc = poll(&pfd, 1, wait_ms);
            if (prc < 0) {
                if (errno == EINTR) continue;
                close(ifd);
                return 4;
            }
            if (prc > 0 && (pfd.revents & POLLIN)) {
                char evbuf[4096];
                (void)read(ifd, evbuf, sizeof(evbuf));
                if (wd_file < 0 && file_exists(path)) wd_file = inotify_add_watch(ifd, path, IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
                (void)wd_dir;
            }
        } else {
            usleep((useconds_t)(wait_ms > 0 ? wait_ms : 100) * 1000U);
        }
    }
}

static int wait_pid_exit(pid_t pid, int timeout_ms, const char *tag) {
    long long start = monotonic_ms();
    char proc_path[64];
    int ifd = -1, wd = -1;
    if (pid <= 0) return 2;
    if (!pid_alive(pid)) {
        printf("done\t0\t%s\tpid-exit\n", tag && *tag ? tag : "pid_exit");
        return 0;
    }
    snprintf(proc_path, sizeof(proc_path), "/proc/%ld", (long)pid);
    ifd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (ifd >= 0) wd = inotify_add_watch(ifd, proc_path, IN_DELETE_SELF | IN_ATTRIB | IN_MOVE_SELF | IN_IGNORED);
    (void)wd;
    for (;;) {
        long long now = monotonic_ms();
        int wait_ms = 1000;
        if (!pid_alive(pid)) {
            if (ifd >= 0) close(ifd);
            printf("done\t0\t%s\tpid-exit\n", tag && *tag ? tag : "pid_exit");
            return 0;
        }
        if (timeout_ms > 0) {
            long long elapsed = now - start;
            if (elapsed >= timeout_ms) {
                if (ifd >= 0) close(ifd);
                printf("timeout\t124\t%s\ttimeout\n", tag && *tag ? tag : "pid_exit");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }
        if (ifd >= 0) {
            struct pollfd pfd;
            pfd.fd = ifd;
            pfd.events = POLLIN;
            pfd.revents = 0;
            int prc = poll(&pfd, 1, wait_ms);
            if (prc < 0) {
                if (errno == EINTR) continue;
                close(ifd);
                return 4;
            }
            if (prc > 0) {
                char evbuf[1024];
                (void)read(ifd, evbuf, sizeof(evbuf));
            }
        } else {
            usleep((useconds_t)(wait_ms > 0 ? wait_ms : 100) * 1000U);
        }
    }
}

static int wait_pid_or_file(pid_t pid, const char *fatal_file, int timeout_ms, const char *tag) {
    long long start = monotonic_ms();
    char proc_path[64];
    char dir[PATH_MAX];
    int ifd = -1;
    int wd_proc = -1;
    int wd_fatal_dir = -1;
    int wd_fatal_file = -1;

    if (pid <= 0) return 2;
    if (file_nonempty(fatal_file)) {
        printf("fatal\t126\t%s\tfatal-file\n", tag && *tag ? tag : "pid_or_file");
        return 126;
    }
    if (!pid_alive(pid)) {
        printf("done\t0\t%s\tpid-exit\n", tag && *tag ? tag : "pid_or_file");
        return 0;
    }

    ifd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (ifd >= 0) {
        snprintf(proc_path, sizeof(proc_path), "/proc/%ld", (long)pid);
        wd_proc = inotify_add_watch(ifd, proc_path, IN_DELETE_SELF | IN_ATTRIB | IN_MOVE_SELF | IN_IGNORED);
        (void)wd_proc;
        if (fatal_file && *fatal_file) {
            if (parent_dir_of(fatal_file, dir, sizeof(dir)) == 0) {
                wd_fatal_dir = inotify_add_watch(ifd, dir, IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
                (void)wd_fatal_dir;
            }
            if (file_exists(fatal_file)) {
                wd_fatal_file = inotify_add_watch(ifd, fatal_file, IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
                (void)wd_fatal_file;
            }
        }
    }

    for (;;) {
        long long now = monotonic_ms();
        int wait_ms = 1000;
        if (file_nonempty(fatal_file)) {
            if (ifd >= 0) close(ifd);
            printf("fatal\t126\t%s\tfatal-file\n", tag && *tag ? tag : "pid_or_file");
            return 126;
        }
        if (!pid_alive(pid)) {
            if (ifd >= 0) close(ifd);
            printf("done\t0\t%s\tpid-exit\n", tag && *tag ? tag : "pid_or_file");
            return 0;
        }
        if (timeout_ms > 0) {
            long long elapsed = now - start;
            if (elapsed >= timeout_ms) {
                if (ifd >= 0) close(ifd);
                printf("timeout\t124\t%s\ttimeout\n", tag && *tag ? tag : "pid_or_file");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }
        if (ifd >= 0) {
            struct pollfd pfd;
            pfd.fd = ifd;
            pfd.events = POLLIN;
            pfd.revents = 0;
            int prc = poll(&pfd, 1, wait_ms);
            if (prc < 0) {
                if (errno == EINTR) continue;
                close(ifd);
                return 4;
            }
            if (prc > 0 && (pfd.revents & POLLIN)) {
                char evbuf[4096];
                (void)read(ifd, evbuf, sizeof(evbuf));
                if (fatal_file && *fatal_file && wd_fatal_file < 0 && file_exists(fatal_file)) {
                    wd_fatal_file = inotify_add_watch(ifd, fatal_file, IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
                    (void)wd_fatal_file;
                }
            }
        } else {
            usleep((useconds_t)(wait_ms > 0 ? wait_ms : 100) * 1000U);
        }
    }
}


typedef struct PipelinePid {
    char label[64];
    pid_t pid;
    int ever_seen;
} PipelinePid;

static int parse_pid_line(const char *line, PipelinePid *out) {
    char buf[256];
    char *p;
    char *last = NULL;
    char *tok;
    char *end = NULL;
    long v;
    size_t n;
    if (!line || !out) return 0;
    while (*line == ' ' || *line == '\t') line++;
    if (*line == '\0' || *line == '#') return 0;
    n = strlen(line);
    if (n >= sizeof(buf)) n = sizeof(buf) - 1;
    memcpy(buf, line, n);
    buf[n] = '\0';
    while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ' || buf[n-1] == '\t')) buf[--n] = '\0';
    p = buf;
    while ((tok = strsep(&p, "\t ")) != NULL) {
        if (*tok) last = tok;
    }
    if (!last) return 0;
    errno = 0;
    v = strtol(last, &end, 10);
    if (errno != 0 || end == last || *end != '\0' || v <= 0 || v > 4194304L) return 0;
    out->pid = (pid_t)v;
    out->ever_seen = 0;
    out->label[0] = '\0';
    /* keep the first field as label when present */
    char *tab = strchr(buf, '\t');
    if (tab && tab != buf) {
        size_t ln = (size_t)(tab - buf);
        if (ln >= sizeof(out->label)) ln = sizeof(out->label) - 1;
        memcpy(out->label, buf, ln);
        out->label[ln] = '\0';
    } else {
        snprintf(out->label, sizeof(out->label), "pid%ld", v);
    }
    return 1;
}

static int load_pid_file(const char *path, PipelinePid *pids, int max_pids) {
    FILE *fp;
    char line[256];
    int count = 0;
    if (!path || !*path || !pids || max_pids <= 0) return 0;
    fp = fopen(path, "r");
    if (!fp) return 0;
    while (fgets(line, sizeof(line), fp) && count < max_pids) {
        PipelinePid ent;
        memset(&ent, 0, sizeof(ent));
        if (!parse_pid_line(line, &ent)) continue;
        int dup = 0;
        for (int i = 0; i < count; ++i) if (pids[i].pid == ent.pid) { dup = 1; break; }
        if (dup) continue;
        pids[count++] = ent;
    }
    fclose(fp);
    return count;
}

static int add_pid(PipelinePid *pids, int *count, int max_pids, pid_t pid, const char *label) {
    if (!pids || !count || pid <= 0 || *count >= max_pids) return 0;
    for (int i = 0; i < *count; ++i) if (pids[i].pid == pid) return 0;
    pids[*count].pid = pid;
    pids[*count].ever_seen = 0;
    snprintf(pids[*count].label, sizeof(pids[*count].label), "%s%ld", label ? label : "child", (long)pid);
    (*count)++;
    return 1;
}

static void discover_children_once(PipelinePid *pids, int *count, int max_pids) {
    char path[128];
    char buf[4096];
    int initial = *count;
    for (int i = 0; i < initial && *count < max_pids; ++i) {
        snprintf(path, sizeof(path), "/proc/%ld/task/%ld/children", (long)pids[i].pid, (long)pids[i].pid);
        int fd = open(path, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = '\0';
        char *save = buf;
        char *tok;
        while ((tok = strsep(&save, " \t\n\r")) != NULL) {
            if (!*tok) continue;
            char *end = NULL;
            errno = 0;
            long v = strtol(tok, &end, 10);
            if (errno == 0 && end != tok && *end == '\0' && v > 0 && v <= 4194304L) {
                add_pid(pids, count, max_pids, (pid_t)v, "child");
            }
        }
    }
}

static int stat_progress(const char *path, off_t *size, long long *stamp) {
    struct stat st;
    if (!path || !*path || strcmp(path, "-") == 0) return 0;
    if (stat(path, &st) != 0) return 0;
    if (size) *size = st.st_size;
#if defined(__ANDROID__) || defined(__linux__)
    if (stamp) *stamp = (long long)st.st_mtime * 1000000000LL + (long long)st.st_mtim.tv_nsec;
#else
    if (stamp) *stamp = (long long)st.st_mtime * 1000000000LL;
#endif
    return 1;
}


static int g_pipeline_format_json = 0;

static long long sum_pipeline_cpu_ticks(PipelinePid *pids, int pid_count) {
    long long total = 0;
    char path[128];
    char buf[1024];
    for (int i = 0; i < pid_count; ++i) {
        if (pids[i].pid <= 0) continue;
        snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pids[i].pid);
        int fd = open(path, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;
        ssize_t n = read(fd, buf, sizeof(buf)-1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = '\0';
        char *rp = strrchr(buf, ')');
        if (!rp) continue;
        char *rest = rp + 2;
        int field = 3;
        char *save = rest;
        char *tok;
        long long utime = 0, stime = 0;
        while ((tok = strsep(&save, " ")) != NULL) {
            if (!*tok) continue;
            if (field == 14) utime = atoll(tok);
            if (field == 15) { stime = atoll(tok); break; }
            field++;
        }
        total += utime + stime;
    }
    return total;
}

static void emit_pipeline_event(const char *event, int rc, const char *tag, const char *reason, int pid_count, int alive, const char *extra) {
    const char *t = tag && *tag ? tag : "pipeline_watch";
    const char *r = reason && *reason ? reason : event;
    if (g_pipeline_format_json) {
        printf("{\"event\":\"%s\",\"rc\":%d,\"tag\":\"%s\",\"reason\":\"%s\",\"pidCount\":%d,\"alive\":%d", event, rc, t, r, pid_count, alive);
        if (extra && *extra) printf(",%s", extra);
        printf("}\n");
    } else {
        printf("%s\t%d\t%s\t%s\tpidCount=%d", event, rc, t, r, pid_count);
        if (alive >= 0) printf("\talive=%d", alive);
        if (extra && *extra) printf("\t%s", extra);
        printf("\n");
    }
}

static int wait_pipeline_watch(const char *pid_file, const char *fatal_file, const char *progress_file,
                               int idle_ms, int timeout_ms, const char *tag) {
    PipelinePid pids[160];
    int pid_count = 0;
    long long start = monotonic_ms();
    long long last_progress_ms = start;
    off_t last_size = -1;
    long long last_stamp = -1;
    int progress_seen = 0;
    long long last_cpu_ticks = 0;
    int fatal_enabled = fatal_file && *fatal_file && strcmp(fatal_file, "-") != 0;
    int progress_enabled = progress_file && *progress_file && strcmp(progress_file, "-") != 0;
    const char *out_tag = tag && *tag ? tag : "pipeline_watch";

    pid_count = load_pid_file(pid_file, pids, (int)(sizeof(pids)/sizeof(pids[0])));
    if (pid_count <= 0) return 2;
    if (fatal_enabled && file_nonempty(fatal_file)) {
        emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pid_count, -1, "");
        return 126;
    }
    if (progress_enabled && stat_progress(progress_file, &last_size, &last_stamp)) {
        progress_seen = 1;
        last_progress_ms = start;
        last_cpu_ticks = sum_pipeline_cpu_ticks(pids, pid_count);
    } else if (idle_ms > 0) {
        /* idle is only meaningful after the progress file has appeared at least once */
        last_progress_ms = start;
    }

    for (;;) {
        long long now = monotonic_ms();
        int alive = 0;
        int wait_ms = 500;
        discover_children_once(pids, &pid_count, (int)(sizeof(pids)/sizeof(pids[0])));
        for (int i = 0; i < pid_count; ++i) {
            if (pid_alive(pids[i].pid)) {
                alive++;
                pids[i].ever_seen = 1;
            }
        }
        if (fatal_enabled && file_nonempty(fatal_file)) {
            emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pid_count, alive, "");
            return 126;
        }
        if (alive <= 0) {
            emit_pipeline_event("done", 0, out_tag, "pipeline-exit", pid_count, -1, "");
            return 0;
        }
        if (progress_enabled) {
            off_t sz = -1;
            long long stp = -1;
            if (stat_progress(progress_file, &sz, &stp)) {
                if (!progress_seen || sz != last_size || stp != last_stamp) {
                    progress_seen = 1;
                    last_size = sz;
                    last_stamp = stp;
                    last_progress_ms = now;
                    last_cpu_ticks = sum_pipeline_cpu_ticks(pids, pid_count);
                }
            }
            if (idle_ms > 0 && progress_seen && now - last_progress_ms >= idle_ms) {
                long long cpu_now = sum_pipeline_cpu_ticks(pids, pid_count);
                char extra[128];
                snprintf(extra, sizeof(extra), "idleMs=%lld\tcpuTicksDelta=%lld", (long long)(now - last_progress_ms), (long long)(cpu_now - last_cpu_ticks));
                emit_pipeline_event("idle", 125, out_tag, (cpu_now > last_cpu_ticks) ? "no-progress-but-cpu-active" : "progress-idle", pid_count, alive, extra);
                return 125;
            }
        }
        if (timeout_ms > 0) {
            long long elapsed = now - start;
            if (elapsed >= timeout_ms) {
                emit_pipeline_event("timeout", 124, out_tag, "timeout", pid_count, alive, "");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }
        if (idle_ms > 0 && progress_seen) {
            long long remain = idle_ms - (now - last_progress_ms);
            if (remain > 0 && remain < wait_ms) wait_ms = (int)remain;
        }
        usleep((useconds_t)(wait_ms > 0 ? wait_ms : 100) * 1000U);
    }
}



static int wait_pipeline_rate_watch(const char *pid_file, const char *fatal_file, const char *progress_file,
                                    int idle_ms, int timeout_ms, int min_bps, int window_ms, const char *tag) {
    PipelinePid pids[160];
    int pid_count = 0;
    long long start = monotonic_ms();
    long long last_progress_ms = start;
    long long window_start_ms = start;
    off_t last_size = -1;
    off_t window_size = -1;
    long long last_stamp = -1;
    int progress_seen = 0;
    long long last_cpu_ticks = 0;
    int fatal_enabled = fatal_file && *fatal_file && strcmp(fatal_file, "-") != 0;
    int progress_enabled = progress_file && *progress_file && strcmp(progress_file, "-") != 0;
    const char *out_tag = tag && *tag ? tag : "pipeline_rate_watch";
    if (window_ms <= 0) window_ms = 30000;

    pid_count = load_pid_file(pid_file, pids, (int)(sizeof(pids)/sizeof(pids[0])));
    if (pid_count <= 0) return 2;
    if (fatal_enabled && file_nonempty(fatal_file)) {
        emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pid_count, -1, "");
        return 126;
    }
    if (progress_enabled && stat_progress(progress_file, &last_size, &last_stamp)) {
        progress_seen = 1;
        last_progress_ms = start;
        last_cpu_ticks = sum_pipeline_cpu_ticks(pids, pid_count);
        window_start_ms = start;
        window_size = last_size;
    }

    for (;;) {
        long long now = monotonic_ms();
        int alive = 0;
        int wait_ms = 500;
        discover_children_once(pids, &pid_count, (int)(sizeof(pids)/sizeof(pids[0])));
        for (int i = 0; i < pid_count; ++i) {
            if (pid_alive(pids[i].pid)) { alive++; pids[i].ever_seen = 1; }
        }
        if (fatal_enabled && file_nonempty(fatal_file)) {
            emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pid_count, alive, "");
            return 126;
        }
        if (alive <= 0) {
            emit_pipeline_event("done", 0, out_tag, "pipeline-exit", pid_count, -1, "");
            return 0;
        }
        if (progress_enabled) {
            off_t sz = -1;
            long long stp = -1;
            if (stat_progress(progress_file, &sz, &stp)) {
                if (!progress_seen || sz != last_size || stp != last_stamp) {
                    progress_seen = 1;
                    last_size = sz;
                    last_stamp = stp;
                    last_progress_ms = now;
                    if (window_size < 0) { window_size = sz; window_start_ms = now; }
                }
                if (min_bps > 0 && progress_seen && now - window_start_ms >= window_ms) {
                    long long dt = now - window_start_ms;
                    long long db = (long long)(sz - window_size);
                    long long bps = dt > 0 ? (db * 1000LL) / dt : 0;
                    if (bps < min_bps) {
                        char extra[160];
                        snprintf(extra, sizeof(extra), "bytesPerSec=%lld\tminBytesPerSec=%d\twindowMs=%d", bps, min_bps, window_ms);
                        emit_pipeline_event("idle", 125, out_tag, "progress-rate-low", pid_count, alive, extra);
                        return 125;
                    }
                    window_start_ms = now;
                    window_size = sz;
                }
            }
            if (idle_ms > 0 && progress_seen && now - last_progress_ms >= idle_ms) {
                long long cpu_now = sum_pipeline_cpu_ticks(pids, pid_count);
                char extra[128];
                snprintf(extra, sizeof(extra), "idleMs=%lld\tcpuTicksDelta=%lld", (long long)(now - last_progress_ms), (long long)(cpu_now - last_cpu_ticks));
                emit_pipeline_event("idle", 125, out_tag, (cpu_now > last_cpu_ticks) ? "no-progress-but-cpu-active" : "progress-idle", pid_count, alive, extra);
                return 125;
            }
        }
        if (timeout_ms > 0) {
            long long elapsed = now - start;
            if (elapsed >= timeout_ms) {
                emit_pipeline_event("timeout", 124, out_tag, "timeout", pid_count, alive, "");
                return 124;
            }
            if (timeout_ms - elapsed < wait_ms) wait_ms = (int)(timeout_ms - elapsed);
        }
        if (idle_ms > 0 && progress_seen) {
            long long remain = idle_ms - (now - last_progress_ms);
            if (remain > 0 && remain < wait_ms) wait_ms = (int)remain;
        }
        usleep((useconds_t)(wait_ms > 0 ? wait_ms : 100) * 1000U);
    }
}

static int emit_fatal(const char *tag, const char *reason) {
    printf("fatal\t126\t%s\t%s\n", tag && *tag ? tag : "remote_stream_child", reason && *reason ? reason : "remote_stream_fatal");
    fflush(stdout);
    return 126;
}

static int wait_fifo_event(const char *fifo, pid_t pid, const char *fatal_file, int timeout_ms, const char *tag) {
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


static int path_starts_with(const char *s, const char *prefix) {
    return s && prefix && strncmp(s, prefix, strlen(prefix)) == 0;
}

static int remove_tree_safe(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return errno == ENOENT ? 0 : 1;
    if (S_ISDIR(st.st_mode)) {
        DIR *d = opendir(path);
        if (!d) return 1;
        struct dirent *de;
        int rc = 0;
        while ((de = readdir(d)) != NULL) {
            if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
            char child[PATH_MAX];
            if (snprintf(child, sizeof(child), "%s/%s", path, de->d_name) >= (int)sizeof(child)) { rc = 1; continue; }
            if (remove_tree_safe(child) != 0) rc = 1;
        }
        closedir(d);
        if (rmdir(path) != 0) rc = 1;
        return rc;
    }
    return unlink(path) == 0 ? 0 : 1;
}

static int cmd_cleanup_owned(const char *run_id, const char *tmpdir) {
    const char *prefix = "/data/local/tmp/.speedbackup_run_";
    char owner_path[PATH_MAX];
    char owner_buf[128];
    int fd;
    ssize_t n;
    if (!run_id || !*run_id || !tmpdir || !*tmpdir) return 2;
    if (!path_starts_with(tmpdir, prefix)) { printf("skip\t0\tcleanup-owned\tunsafe-path\tpath=%s\n", tmpdir); return 0; }
    if (strstr(tmpdir, "..") != NULL) { printf("skip\t0\tcleanup-owned\tdotdot\tpath=%s\n", tmpdir); return 0; }
    if (snprintf(owner_path, sizeof(owner_path), "%s/owner.pid", tmpdir) >= (int)sizeof(owner_path)) return 2;
    fd = open(owner_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) { printf("skip\t0\tcleanup-owned\tno-owner\tpath=%s\n", tmpdir); return 0; }
    n = read(fd, owner_buf, sizeof(owner_buf)-1);
    close(fd);
    if (n <= 0) { printf("skip\t0\tcleanup-owned\tempty-owner\tpath=%s\n", tmpdir); return 0; }
    owner_buf[n] = '\0';
    owner_buf[strcspn(owner_buf, "\r\n\t ")] = '\0';
    if (strcmp(owner_buf, run_id) != 0) { printf("skip\t0\tcleanup-owned\towner-mismatch\tpath=%s\towner=%s\n", tmpdir, owner_buf); return 0; }
    int rc = remove_tree_safe(tmpdir);
    printf("%s\t%d\tcleanup-owned\t%s\tpath=%s\towner=%s\n", rc == 0 ? "done" : "fail", rc == 0 ? 0 : 1, rc == 0 ? "removed" : "remove-failed", tmpdir, owner_buf);
    return rc == 0 ? 0 : 1;
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "usage:\n"
        "  %s --version\n"
        "  %s FIFO PID [FATAL_FILE|-] [TIMEOUT_MS] [TAG]   # legacy remote stream waiter\n"
        "  %s file-created PATH TIMEOUT_MS [TAG]\n"
        "  %s file-nonempty PATH TIMEOUT_MS [TAG]\n"
        "  %s file-contains PATH PATTERN TIMEOUT_MS [TAG]\n"
        "  %s socket-ready PATH TIMEOUT_MS [TAG]\n"
        "  %s pid-exit PID TIMEOUT_MS [TAG]\n"
        "  %s pid-or-file PID FATAL_FILE TIMEOUT_MS [TAG]\n"
        "  %s pipeline-watch PID_LIST_FILE FATAL_FILE|- PROGRESS_FILE|- IDLE_MS TIMEOUT_MS [TAG] [--json|--tsv]\n        "
        "  %s pipeline-rate-watch PID_LIST_FILE FATAL_FILE|- PROGRESS_FILE|- IDLE_MS TIMEOUT_MS MIN_BPS WINDOW_MS [TAG] [--json|--tsv]\n"
        "  %s file-size-stable PATH STABLE_MS TIMEOUT_MS [TAG]\n        "
        "  %s cleanup-owned RUN_ID TMPDIR\n",
        argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0, argv0);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("eventwait %s\n", EVENTWAIT_VERSION);
        return 0;
    }
    if (argc >= 2 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
        usage(argv[0]);
        return 0;
    }
    if (argc >= 2) {
        if (strcmp(argv[1], "file-created") == 0) {
            if (argc < 4) return 2;
            return wait_path_condition(WM_FILE_CREATED, argv[2], "", parse_int(argv[3], 0), argc >= 5 ? argv[4] : "file_created");
        }
        if (strcmp(argv[1], "file-nonempty") == 0) {
            if (argc < 4) return 2;
            return wait_path_condition(WM_FILE_NONEMPTY, argv[2], "", parse_int(argv[3], 0), argc >= 5 ? argv[4] : "file_nonempty");
        }
        if (strcmp(argv[1], "file-contains") == 0) {
            if (argc < 5) return 2;
            return wait_path_condition(WM_FILE_CONTAINS, argv[2], argv[3], parse_int(argv[4], 0), argc >= 6 ? argv[5] : "file_contains");
        }
        if (strcmp(argv[1], "socket-ready") == 0) {
            if (argc < 4) return 2;
            return wait_path_condition(WM_SOCKET_READY, argv[2], "", parse_int(argv[3], 0), argc >= 5 ? argv[4] : "socket_ready");
        }
        if (strcmp(argv[1], "pid-exit") == 0) {
            if (argc < 4) return 2;
            char *end = NULL;
            errno = 0;
            long v = strtol(argv[2], &end, 10);
            if (errno != 0 || end == argv[2] || *end != '\0' || v <= 0 || v > 4194304L) return 2;
            return wait_pid_exit((pid_t)v, parse_int(argv[3], 0), argc >= 5 ? argv[4] : "pid_exit");
        }
        if (strcmp(argv[1], "pid-or-file") == 0) {
            if (argc < 5) return 2;
            char *end = NULL;
            errno = 0;
            long v = strtol(argv[2], &end, 10);
            if (errno != 0 || end == argv[2] || *end != '\0' || v <= 0 || v > 4194304L) return 2;
            return wait_pid_or_file((pid_t)v, argv[3], parse_int(argv[4], 0), argc >= 6 ? argv[5] : "pid_or_file");
        }
        if (strcmp(argv[1], "pipeline-watch") == 0) {
            if (argc < 7) return 2;
            const char *tag = argc >= 8 ? argv[7] : "pipeline_watch";
            if (argc >= 8 && strcmp(argv[7], "--json") == 0) { g_pipeline_format_json = 1; tag = "pipeline_watch"; }
            if (argc >= 9 && strcmp(argv[8], "--json") == 0) g_pipeline_format_json = 1;
            return wait_pipeline_watch(argv[2], argv[3], argv[4], parse_int(argv[5], 0), parse_int(argv[6], 0), tag);
        }
        if (strcmp(argv[1], "pipeline-rate-watch") == 0) {
            if (argc < 9) return 2;
            const char *tag = argc >= 10 ? argv[9] : "pipeline_rate_watch";
            if (argc >= 10 && strcmp(argv[9], "--json") == 0) { g_pipeline_format_json = 1; tag = "pipeline_rate_watch"; }
            if (argc >= 11 && strcmp(argv[10], "--json") == 0) g_pipeline_format_json = 1;
            return wait_pipeline_rate_watch(argv[2], argv[3], argv[4], parse_int(argv[5], 0), parse_int(argv[6], 0), parse_int(argv[7], 0), parse_int(argv[8], 30000), tag);
        }
        if (strcmp(argv[1], "file-size-stable") == 0) {
            if (argc < 5) return 2;
            return wait_path_condition(WM_SIZE_STABLE, argv[2], argv[3], parse_int(argv[4], 0), argc >= 6 ? argv[5] : "file_size_stable");
        }
        if (strcmp(argv[1], "cleanup-owned") == 0) {
            if (argc < 4) return 2;
            return cmd_cleanup_owned(argv[2], argv[3]);
        }
    }
    if (argc < 3) {
        usage(argv[0]);
        return 2;
    }
    char *end = NULL;
    errno = 0;
    long v = strtol(argv[2], &end, 10);
    if (errno != 0 || end == argv[2] || *end != '\0' || v <= 0 || v > 4194304L) return 2;
    const char *fatal = (argc >= 4 && strcmp(argv[3], "-") != 0) ? argv[3] : "";
    int timeout_ms = argc >= 5 ? parse_int(argv[4], 0) : 0;
    const char *tag = argc >= 6 ? argv[5] : "remote_stream_child";
    return wait_fifo_event(argv[1], (pid_t)v, fatal, timeout_ms, tag);
}
