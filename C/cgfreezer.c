/*
 * SpeedBackup cgfreezer native helper
 * r200: package-atomic freeze + live-rescan package kill + emergency UID thaw + parent-direct daemon control.
 * cgroup v2 hot path + cgroup v1 fallback + optional Binder freezer barrier + LOG_ID_EVENTS + unix socket daemon.
 *
 * This helper is deliberately stateless for freezer lifecycle. Dex owns tokens,
 * persistent restore, ProcessObserver coordination, and fallback kill.
 *
 * Commands:
 *   cgfreezer check-root
 *   cgfreezer scan-package PACKAGE USER_ID
 *   cgfreezer freeze-pid PID TIMEOUT_MS
 *   cgfreezer freeze-package PACKAGE USER_ID TIMEOUT_MS
 *   cgfreezer thaw-path CGROUP_FREEZE_PATH TARGET_0_OR_1 TIMEOUT_MS
 *   cgfreezer thaw-pid PID CGROUP_FREEZE_PATH TARGET_0_OR_1 TIMEOUT_MS
 *   cgfreezer thaw-uid UID TIMEOUT_MS
 *   cgfreezer kill-package PACKAGE USER_ID EVENT_PID TIMEOUT_MS
 *   cgfreezer binder-info PID
 *   cgfreezer watch-logd PACKAGE USER_ID DURATION_MS
 *   cgfreezer backend-probe
 *   cgfreezer daemon SOCKET_PATH
 *
 * Daemon line protocol:
 *   HELLO
 *   CAPS
 *   PING
 *   STATUS
 *   STATS
 *   STATS_DETAIL
 *   LAST_ERROR
 *   BACKEND_PROBE
 *   SCAN PACKAGE USER_ID
 *   FREEZE PID TIMEOUT_MS
 *   FREEZE_PKG PACKAGE USER_ID TIMEOUT_MS
 *   THAW CGROUP_FREEZE_PATH TARGET_0_OR_1 TIMEOUT_MS
 *   THAW_PID PID CGROUP_FREEZE_PATH TARGET_0_OR_1 TIMEOUT_MS
 *   THAW_UID UID TIMEOUT_MS
 *   KILL_PKG PACKAGE USER_ID EVENT_PID TIMEOUT_MS
 *   FREEZE_PID_LIST USER_ID PIDCSV TIMEOUT_MS
 *   KILL_PID_LIST USER_ID PIDCSV SIGNAL
 *   PROC_SNAPSHOT PACKAGE USER_ID
 *   WCHAN_PID_LIST USER_ID PIDCSV [frozen|thawed|any]
 *   WCHAN_UID UID [frozen|thawed|any]
 *   BINDER_INFO PID
 *   SUBSCRIBE PACKAGE USER_ID DURATION_MS
 *   EXIT
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dlfcn.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CGROUP_ROOT "/sys/fs/cgroup"
#define MAX_TEXT 16384
#define MAX_PATH_LEN 2048
#define MAX_PKG_LEN 160
#define MAX_CACHE_PIDS 256
#define LOGGER_ENTRY_MAX_LEN 5120
#define LOG_ID_EVENTS 2
#define CGFREEZER_VERSION "r482-wchan-confirm-api28-r28c"
#define CGFREEZER_PROTOCOL "line-v8-wchan-confirm-r482"
#define MAX_UID_PATHS 128
#define MAX_UID_PIDS 512
#define MAX_DAEMON_CHILDREN 64
#define MAX_KILL_TARGETS 512
#define MAX_KILL_PASSES 8

#if defined(__has_include)
#  if __has_include(<linux/android/binder.h>)
#    include <linux/android/binder.h>
#    define CGFREEZER_HAVE_BINDER_UAPI 1
#  endif
#endif

#ifndef CGFREEZER_HAVE_BINDER_UAPI
struct binder_freeze_info {
    uint32_t pid;
    uint32_t enable;
    uint32_t timeout_ms;
};
struct binder_frozen_status_info {
    uint32_t pid;
    uint32_t sync_recv;
    uint32_t async_recv;
};
#endif
#ifndef BINDER_FREEZE
#define BINDER_FREEZE _IOW('b', 14, struct binder_freeze_info)
#endif
#ifndef BINDER_GET_FROZEN_INFO
#define BINDER_GET_FROZEN_INFO _IOWR('b', 15, struct binder_frozen_status_info)
#endif

struct LoggerEntry {
    uint16_t len;
    uint16_t hdr_size;
    int32_t pid;
    uint32_t tid;
    uint32_t sec;
    uint32_t nsec;
    uint32_t lid;
    uint32_t uid;
};

struct LogMsg {
    union {
        unsigned char buf[LOGGER_ENTRY_MAX_LEN + 1];
        struct LoggerEntry entry;
    } u;
};

typedef struct logger_list* (*FnLoggerListOpen)(int id, int mode, unsigned int tail, pid_t pid);
typedef int (*FnLoggerListRead)(struct logger_list* logger_list, struct LogMsg* log_msg);
typedef void (*FnLoggerListFree)(struct logger_list* logger_list);

static volatile sig_atomic_t g_running = 1;
static long g_daemon_started_ms = 0;
static unsigned long g_daemon_requests = 0;
static unsigned long g_daemon_direct_requests = 0;
static unsigned long g_daemon_worker_requests = 0;
static int g_daemon_active_children = 0;
static pid_t g_daemon_children[MAX_DAEMON_CHILDREN] = {0};
static long g_daemon_child_start_ms[MAX_DAEMON_CHILDREN] = {0};
static int g_daemon_child_class[MAX_DAEMON_CHILDREN] = {0};
#define CGSTAT_CLASSES 8
static const char *g_stat_class_names[CGSTAT_CLASSES] = {"other","freeze","freezePkg","kill","thaw","scan","direct","control"};
static unsigned long g_stat_detail_count[CGSTAT_CLASSES] = {0};
static unsigned long g_stat_detail_completed[CGSTAT_CLASSES] = {0};
static unsigned long g_stat_detail_failed[CGSTAT_CLASSES] = {0};
static long g_stat_detail_total_ms[CGSTAT_CLASSES] = {0};
static long g_stat_detail_min_ms[CGSTAT_CLASSES] = {0};
static long g_stat_detail_max_ms[CGSTAT_CLASSES] = {0};
static long g_stat_detail_last_ms[CGSTAT_CLASSES] = {0};
static char g_daemon_socket_path[MAX_PATH_LEN] = {0};
static unsigned long g_stat_freeze = 0;
static unsigned long g_stat_freeze_pkg = 0;
static unsigned long g_stat_kill_pkg = 0;
static unsigned long g_stat_thaw = 0;
static unsigned long g_stat_scan = 0;
static char g_daemon_last_command[64] = {0};
static char g_daemon_last_error[160] = "none";

static const char *cgfreezer_caps(void) {
    return "check-root,backend-probe,scan,freeze,freeze-package-single-request-v1,kill-package-live-rescan-v1,pidfd-signal-optional-v1,thaw,thaw-uid-emergency-v1,binder-freeze,binder-info,subscribe-logd,pid-cache,uid-cache,cgroup-v2-events,cgroup-v2-uid-root-fallback,cgroup-v1-freezer,daemon-parent-control-v1,daemon-stats-v1,daemon-stats-detail-v1,last-error-v1,daemon-control-plain-lines-v2,kill-report-v2,batch-pid-list-v1,proc-snapshot-v1,pidfd-kill-v1,cgroup-kill-fastpath-v1,cgroup-wchan-confirm-v1,proc-wchan-v1,uid-wchan-v1";
}

static void on_signal(int sig) {
    (void)sig;
    g_running = 0;
}

static char *log_msg_payload(struct LogMsg *m) {
    if (!m) return NULL;
    uint16_t hdr = m->u.entry.hdr_size;
    if (hdr < sizeof(struct LoggerEntry)) hdr = sizeof(struct LoggerEntry);
    if (hdr >= sizeof(m->u.buf)) return NULL;
    return (char*)m->u.buf + hdr;
}

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)(ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL);
}

static void sleep_ms(int ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static void sanitize_print(const char *s) {
    if (!s || !*s) { fputs("-", stdout); return; }
    for (int i = 0; s[i] && i < 1800; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '\n' || c == '\r' || c == '\t' || c == ' ') putchar('_');
        else if (c >= 0x21 && c <= 0x7e) putchar(c);
        else putchar('_');
    }
}

static int read_file(const char *path, char *buf, size_t cap) {
    if (!path || !buf || cap == 0) return -1;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, cap - 1);
    int saved = errno;
    close(fd);
    if (n < 0) { errno = saved; return -1; }
    buf[n] = '\0';
    while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ' || buf[n-1] == '\t')) {
        buf[n-1] = '\0';
        n--;
    }
    return (int)n;
}

static int write_file(const char *path, const char *value) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    size_t len = strlen(value);
    ssize_t n = write(fd, value, len);
    int saved = errno;
    close(fd);
    if (n != (ssize_t)len) { errno = saved ? saved : EIO; return -1; }
    return 0;
}

static bool is_pkg_char(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '.' || c == '_';
}

static bool is_valid_pkg_name(const char *pkg) {
    if (!pkg) return false;
    size_t len = strlen(pkg);
    if (len < 3 || len > 128) return false;
    bool dot = false;
    for (size_t i = 0; i < len; ++i) {
        if (pkg[i] == '.') dot = true;
        if (!is_pkg_char((unsigned char)pkg[i])) return false;
    }
    return dot;
}

static bool is_package_process(const char *cmd, const char *pkg) {
    if (!cmd || !pkg || !*cmd || !*pkg) return false;
    size_t n = strlen(pkg);
    return strcmp(cmd, pkg) == 0 || (strncmp(cmd, pkg, n) == 0 && cmd[n] == ':');
}

static int user_id_from_uid(int uid) {
    if (uid >= 100000) return uid / 100000;
    return 0;
}

static int parse_status_uid(pid_t pid) {
    char path[128], buf[4096];
    snprintf(path, sizeof(path), "/proc/%d/status", pid);
    if (read_file(path, buf, sizeof(buf)) < 0) return -1;
    char *save = NULL;
    char *line = strtok_r(buf, "\n", &save);
    while (line) {
        if (strncmp(line, "Uid:", 4) == 0) {
            char *p = line + 4;
            while (*p && isspace((unsigned char)*p)) p++;
            return atoi(p);
        }
        line = strtok_r(NULL, "\n", &save);
    }
    return -1;
}

static int read_cmdline(pid_t pid, char *out, size_t cap) {
    char path[128];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    int n = read_file(path, out, cap);
    if (n < 0) return -1;
    for (int i = 0; i < n; i++) {
        if (out[i] == '\0') { out[i] = '\0'; break; }
    }
    return n;
}

static int parse_unified_path(const char *raw, char *out, size_t cap) {
    if (!raw || !out || cap == 0) return -1;
    const char *p = raw;
    while (*p) {
        const char *line = p;
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        if (len >= 3 && line[0] == '0' && line[1] == ':' && line[2] == ':') {
            const char *path = line + 3;
            size_t plen = len - 3;
            while (plen > 0 && (*path == ' ' || *path == '\t')) { path++; plen--; }
            if (plen == 0) snprintf(out, cap, "/");
            else if (*path == '/') snprintf(out, cap, "%.*s", (int)plen, path);
            else snprintf(out, cap, "/%.*s", (int)plen, path);
            return 0;
        }
        if (!nl) break;
        p = nl + 1;
    }
    return -1;
}

static int build_freeze_path_from_pid(pid_t pid, char *freeze_path, size_t cap) {
    char proc_path[128], raw[MAX_TEXT], cg[1024];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cgroup", pid);
    if (read_file(proc_path, raw, sizeof(raw)) < 0) return -1;
    if (parse_unified_path(raw, cg, sizeof(cg)) < 0) return -2;
    if (strcmp(cg, "/") == 0) snprintf(freeze_path, cap, "%s/cgroup.freeze", CGROUP_ROOT);
    else snprintf(freeze_path, cap, "%s%s/cgroup.freeze", CGROUP_ROOT, cg);
    return 0;
}

static void events_path_for_freeze(const char *freeze_path, char *events_path, size_t cap) {
    snprintf(events_path, cap, "%s", freeze_path ? freeze_path : "");
    char *slash = strrchr(events_path, '/');
    if (slash) strcpy(slash + 1, "cgroup.events");
}

static char normalize_freeze(const char *v) {
    if (!v) return '-';
    while (*v && isspace((unsigned char)*v)) v++;
    if (*v == '0') return '0';
    if (*v == '1') return '1';
    return '-';
}

static char parse_events_value(const char *events, const char *key) {
    if (!events || !key) return '-';
    size_t klen = strlen(key);
    const char *p = events;
    while (*p) {
        while (*p == '\n' || *p == '\r') p++;
        if (strncmp(p, key, klen) == 0 && p[klen] == ' ') {
            p += klen + 1;
            while (*p && isspace((unsigned char)*p)) p++;
            if (*p == '0' || *p == '1') return *p;
            return '-';
        }
        const char *nl = strchr(p, '\n');
        if (!nl) break;
        p = nl + 1;
    }
    return '-';
}

static bool wait_frozen(const char *freeze_path, char expected, int timeout_ms, char *last_events, size_t last_cap, char *last_frozen, long *elapsed) {
    char events_path[MAX_PATH_LEN];
    events_path_for_freeze(freeze_path, events_path, sizeof(events_path));
    long start = now_ms();
    long deadline = start + (timeout_ms < 1 ? 1 : timeout_ms);
    char ev[MAX_TEXT];
    *last_frozen = '-';
    if (last_events && last_cap) last_events[0] = '\0';
    while (now_ms() <= deadline) {
        if (read_file(events_path, ev, sizeof(ev)) >= 0) {
            char f = parse_events_value(ev, "frozen");
            *last_frozen = f;
            if (last_events && last_cap) snprintf(last_events, last_cap, "%s", ev);
            if (f == expected) { if (elapsed) *elapsed = now_ms() - start; return true; }
        }
        sleep_ms(20);
    }
    if (elapsed) *elapsed = now_ms() - start;
    return false;
}

static int open_binder_device(const char **device_out);

static bool token_list_contains(const char *list, const char *needle) {
    if (!list || !needle || !*needle) return false;
    size_t n = strlen(needle);
    const char *p = list;
    while (*p) {
        while (*p == ',' || *p == ' ' || *p == '\t') p++;
        if (strncmp(p, needle, n) == 0 && (p[n] == '\0' || p[n] == ',' || p[n] == ' ' || p[n] == '\t' || p[n] == '\n' || p[n] == '\r')) return true;
        while (*p && *p != ',' && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r') p++;
    }
    return false;
}

static int mkdir_p(const char *path, mode_t mode) {
    if (!path || !*path) return -1;
    char tmp[MAX_PATH_LEN];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len == 0) return -1;
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';
    for (char *q = tmp + 1; *q; q++) {
        if (*q == '/') {
            *q = '\0';
            if (mkdir(tmp, mode) != 0 && errno != EEXIST) return -1;
            *q = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST) return -1;
    return 0;
}

static int find_v1_freezer_mount(char *mount_out, size_t mount_cap) {
    char buf[MAX_TEXT];
    if (read_file("/proc/mounts", buf, sizeof(buf)) >= 0) {
        char *save = NULL;
        char *line = strtok_r(buf, "\n", &save);
        while (line) {
            char src[256] = {0}, mnt[MAX_PATH_LEN] = {0}, fstype[64] = {0}, opts[1024] = {0};
            if (sscanf(line, "%255s %2047s %63s %1023s", src, mnt, fstype, opts) == 4) {
                if (strcmp(fstype, "cgroup") == 0 && token_list_contains(opts, "freezer")) {
                    snprintf(mount_out, mount_cap, "%s", mnt);
                    return 0;
                }
            }
            line = strtok_r(NULL, "\n", &save);
        }
    }
    static const char *fallbacks[] = { "/sys/fs/cgroup/freezer", "/dev/freezer", "/acct/freezer", NULL };
    for (int i = 0; fallbacks[i]; i++) {
        char p1[MAX_PATH_LEN], p2[MAX_PATH_LEN];
        snprintf(p1, sizeof(p1), "%s/cgroup.procs", fallbacks[i]);
        snprintf(p2, sizeof(p2), "%s/freezer.state", fallbacks[i]);
        if (access(p1, W_OK) == 0 || access(p2, R_OK) == 0) {
            snprintf(mount_out, mount_cap, "%s", fallbacks[i]);
            return 0;
        }
    }
    return -1;
}

static int parse_v1_freezer_relpath(pid_t pid, char *rel_out, size_t rel_cap) {
    char proc_path[128], raw[MAX_TEXT];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cgroup", pid);
    if (read_file(proc_path, raw, sizeof(raw)) < 0) return -1;
    const char *p = raw;
    while (*p) {
        const char *line = p;
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        char tmp[2048];
        if (len >= sizeof(tmp)) len = sizeof(tmp) - 1;
        memcpy(tmp, line, len); tmp[len] = '\0';
        char *c1 = strchr(tmp, ':');
        char *c2 = c1 ? strchr(c1 + 1, ':') : NULL;
        if (c1 && c2) {
            *c1 = '\0'; *c2 = '\0';
            const char *controllers = c1 + 1;
            const char *rel = c2 + 1;
            if (token_list_contains(controllers, "freezer")) {
                if (!rel || !*rel) rel = "/";
                if (rel[0] == '/') snprintf(rel_out, rel_cap, "%s", rel);
                else snprintf(rel_out, rel_cap, "/%s", rel);
                return 0;
            }
        }
        if (!nl) break;
        p = nl + 1;
    }
    return -2;
}

static void join_v1_path(const char *mount, const char *rel, const char *leaf, char *out, size_t cap) {
    if (!rel || strcmp(rel, "/") == 0 || rel[0] == '\0') snprintf(out, cap, "%s/%s", mount, leaf);
    else snprintf(out, cap, "%s%s/%s", mount, rel, leaf);
}

static char normalize_v1_state(const char *v) {
    if (!v) return '-';
    while (*v && isspace((unsigned char)*v)) v++;
    if (strncasecmp(v, "FROZEN", 6) == 0) return '1';
    if (strncasecmp(v, "THAWED", 6) == 0) return '0';
    if (strncasecmp(v, "FREEZING", 8) == 0) return 'P';
    return '-';
}

static bool wait_v1_state(const char *state_path, char expected, int timeout_ms, char *last_state, long *elapsed) {
    long start = now_ms();
    long deadline = start + (timeout_ms < 1 ? 1 : timeout_ms);
    char buf[4096];
    if (last_state) *last_state = '-';
    while (now_ms() <= deadline) {
        if (read_file(state_path, buf, sizeof(buf)) >= 0) {
            char st = normalize_v1_state(buf);
            if (last_state) *last_state = st;
            if (st == expected) { if (elapsed) *elapsed = now_ms() - start; return true; }
        }
        sleep_ms(20);
    }
    if (elapsed) *elapsed = now_ms() - start;
    return false;
}

static int write_pid_to_procs(const char *procs_path, pid_t pid) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%d\n", pid);
    return write_file(procs_path, buf);
}

static int cmd_backend_probe(void) {
    long start = now_ms();
    bool v2_root = access(CGROUP_ROOT, R_OK) == 0;
    bool v2_controllers = access(CGROUP_ROOT "/cgroup.controllers", R_OK) == 0;
    char controllers[4096] = {0};
    if (v2_controllers) read_file(CGROUP_ROOT "/cgroup.controllers", controllers, sizeof(controllers));
    char v1_mount[MAX_PATH_LEN] = {0};
    bool v1_ok = find_v1_freezer_mount(v1_mount, sizeof(v1_mount)) == 0;
    const char *binder_dev = NULL;
    int bfd = open_binder_device(&binder_dev);
    bool binder_ok = bfd >= 0;
    if (bfd >= 0) close(bfd);
    printf("CGFREEZER_BACKEND_PROBE ok=true v2Root=%s v2ControllersReadable=%s controllers=", v2_root ? "true" : "false", v2_controllers ? "true" : "false");
    sanitize_print(controllers);
    printf(" v1Freezer=%s v1Mount=", v1_ok ? "true" : "false"); sanitize_print(v1_ok ? v1_mount : "-");
    bool cgroup_kill_root = access(CGROUP_ROOT "/cgroup.kill", W_OK) == 0;
    printf(" binderDevice=%s binderPath=", binder_ok ? "true" : "false"); sanitize_print(binder_dev ? binder_dev : "-");
    printf(" cgroupKillRoot=%s cgroupKillFastpath=exact-package-only", cgroup_kill_root ? "true" : "false");
    printf(" elapsedMs=%ld\n", now_ms() - start);
    return 0;
}

static int cmd_freeze_pid_v1(pid_t pid, int timeout_ms) {
    long start = now_ms();
    int uid = parse_status_uid(pid);
    char cmd[512] = {0};
    read_cmdline(pid, cmd, sizeof(cmd));
    char mount[MAX_PATH_LEN] = {0}, rel[1024] = {0};
    if (find_v1_freezer_mount(mount, sizeof(mount)) != 0) {
        printf("CGFREEZER_FREEZE_V1_DONE ok=false pid=%d uid=%d backend=v1 reason=no_v1_mount elapsedMs=%ld\n", pid, uid, now_ms() - start);
        return 10;
    }
    if (parse_v1_freezer_relpath(pid, rel, sizeof(rel)) != 0) {
        printf("CGFREEZER_FREEZE_V1_DONE ok=false pid=%d uid=%d backend=v1 mount=", pid, uid); sanitize_print(mount);
        printf(" reason=no_freezer_controller elapsedMs=%ld\n", now_ms() - start);
        return 11;
    }
    char orig_procs[MAX_PATH_LEN], orig_state[MAX_PATH_LEN], group_dir[MAX_PATH_LEN], group_procs[MAX_PATH_LEN], group_state[MAX_PATH_LEN];
    join_v1_path(mount, rel, "cgroup.procs", orig_procs, sizeof(orig_procs));
    join_v1_path(mount, rel, "freezer.state", orig_state, sizeof(orig_state));
    snprintf(group_dir, sizeof(group_dir), "%s/speedbackup_frozen", mount);
    snprintf(group_procs, sizeof(group_procs), "%.*s/cgroup.procs", (int)(sizeof(group_procs) - 32), group_dir);
    snprintf(group_state, sizeof(group_state), "%.*s/freezer.state", (int)(sizeof(group_state) - 32), group_dir);
    char orig_state_buf[128] = {0};
    read_file(orig_state, orig_state_buf, sizeof(orig_state_buf));
    char before_freeze = normalize_v1_state(orig_state_buf);
    if (mkdir_p(group_dir, 0755) != 0) {
        printf("CGFREEZER_FREEZE_V1_DONE ok=false pid=%d uid=%d backend=v1 mount=", pid, uid); sanitize_print(mount);
        printf(" reason=mkdir_errno_%d elapsedMs=%ld\n", errno, now_ms() - start);
        return 12;
    }
    (void)write_file(group_state, "THAWED\n");
    if (write_pid_to_procs(group_procs, pid) != 0) {
        printf("CGFREEZER_FREEZE_V1_DONE ok=false pid=%d uid=%d backend=v1 path=", pid, uid); sanitize_print(orig_procs);
        printf(" groupProcs="); sanitize_print(group_procs);
        printf(" beforeFreeze=%c beforeFrozen=%c reason=move_errno_%d elapsedMs=%ld\n", before_freeze, before_freeze, errno, now_ms() - start);
        return 13;
    }
    if (write_file(group_state, "FROZEN\n") != 0) {
        printf("CGFREEZER_FREEZE_V1_DONE ok=false pid=%d uid=%d backend=v1 path=", pid, uid); sanitize_print(orig_procs);
        printf(" reason=state_errno_%d elapsedMs=%ld\n", errno, now_ms() - start);
        return 14;
    }
    char last = '-';
    long wait_ms = 0;
    bool ok = wait_v1_state(group_state, '1', timeout_ms, &last, &wait_ms);
    printf("CGFREEZER_FREEZE_DONE ok=%s backend=v1 pid=%d uid=%d path=", ok ? "true" : "false", pid, uid); sanitize_print(orig_procs);
    printf(" groupState="); sanitize_print(group_state);
    printf(" cmdline="); sanitize_print(cmd);
    printf(" beforeFreeze=%c beforeFrozen=%c readback=%c eventOk=%s frozen=%c waitMs=%ld reason=%s binderAttempted=false binderSkipped=v1_no_binder binderBarrierOk=true elapsedMs=%ld\n",
           before_freeze, before_freeze, last, ok ? "true" : "false", last, wait_ms, ok ? "ok_v1" : "v1_verify_failed", now_ms() - start);
    return ok ? 0 : 15;
}

static int cmd_thaw_pid_v1(pid_t pid, const char *orig_procs, char target, int timeout_ms) {
    long start = now_ms();
    (void)timeout_ms;
    if (!orig_procs || !*orig_procs || strstr(orig_procs, "cgroup.procs") == NULL) {
        printf("CGFREEZER_THAW_V1_DONE ok=false pid=%d backend=v1 reason=bad_path elapsedMs=%ld\n", pid, now_ms() - start);
        return 20;
    }
    char mount[MAX_PATH_LEN] = {0};
    if (find_v1_freezer_mount(mount, sizeof(mount)) != 0) {
        printf("CGFREEZER_THAW_V1_DONE ok=false pid=%d backend=v1 path=", pid); sanitize_print(orig_procs);
        printf(" reason=no_v1_mount elapsedMs=%ld\n", now_ms() - start);
        return 21;
    }
    char group_dir[MAX_PATH_LEN], group_state[MAX_PATH_LEN];
    snprintf(group_dir, sizeof(group_dir), "%s/speedbackup_frozen", mount);
    snprintf(group_state, sizeof(group_state), "%.*s/freezer.state", (int)(sizeof(group_state) - 32), group_dir);
    if (target == '0') {
        (void)write_file(group_state, "THAWED\n");
        char last_tmp = '-'; long thaw_wait = 0;
        (void)wait_v1_state(group_state, '0', 1000, &last_tmp, &thaw_wait);
    }
    int move_rc = write_pid_to_procs(orig_procs, pid);
    int move_err = errno;
    if (target == '1') {
        char orig_state[MAX_PATH_LEN];
        snprintf(orig_state, sizeof(orig_state), "%s", orig_procs);
        char *slash = strrchr(orig_state, '/');
        if (slash) {
            strcpy(slash + 1, "freezer.state");
            (void)write_file(orig_state, "FROZEN\n");
        }
    }
    bool ok = move_rc == 0;
    printf("CGFREEZER_THAW_DONE ok=%s backend=v1 pid=%d path=", ok ? "true" : "false", pid); sanitize_print(orig_procs);
    printf(" target=%c readback=%c eventOk=%s frozen=%c waitMs=0 cgroupOk=%s binderAttempted=false binderSkipped=v1_no_binder reason=%s binderRestoreOk=true elapsedMs=%ld",
           target, target, ok ? "true" : "false", target, ok ? "true" : "false", ok ? "ok_v1" : "move_errno", now_ms() - start);
    if (!ok) printf(" errno=%d", move_err);
    printf("\n");
    return ok ? 0 : 22;
}


struct BinderStatus {
    bool supported;
    bool ok;
    int err;
    uint32_t sync_recv;
    uint32_t async_recv;
    const char *device;
};

static int open_binder_device(const char **device_out) {
    static const char *paths[] = {
        "/dev/binder",
        "/dev/binderfs/binder",
        NULL
    };
    for (int i = 0; paths[i]; ++i) {
        int fd = open(paths[i], O_RDWR | O_CLOEXEC);
        if (fd >= 0) {
            if (device_out) *device_out = paths[i];
            return fd;
        }
    }
    if (device_out) *device_out = "-";
    return -1;
}

static struct BinderStatus binder_get_status(pid_t pid) {
    struct BinderStatus st;
    memset(&st, 0, sizeof(st));
    st.err = 0;
    st.device = "-";
    const char *dev = "-";
    int fd = open_binder_device(&dev);
    st.device = dev;
    if (fd < 0) {
        st.err = errno;
        return st;
    }
    struct binder_frozen_status_info info;
    memset(&info, 0, sizeof(info));
    info.pid = (uint32_t)pid;
    int rc;
    do {
        rc = ioctl(fd, BINDER_GET_FROZEN_INFO, &info);
    } while (rc != 0 && errno == EINTR);
    st.err = rc == 0 ? 0 : errno;
    st.supported = (rc == 0) || (st.err != ENOTTY && st.err != EINVAL);
    st.ok = (rc == 0);
    if (rc == 0) {
        st.sync_recv = info.sync_recv;
        st.async_recv = info.async_recv;
    }
    close(fd);
    return st;
}

static struct BinderStatus binder_freeze_set(pid_t pid, bool enable, int timeout_ms) {
    struct BinderStatus st;
    memset(&st, 0, sizeof(st));
    st.err = 0;
    st.device = "-";
    const char *dev = "-";
    int fd = open_binder_device(&dev);
    st.device = dev;
    if (fd < 0) {
        st.err = errno;
        return st;
    }
    struct binder_freeze_info info;
    memset(&info, 0, sizeof(info));
    info.pid = (uint32_t)pid;
    info.enable = enable ? 1u : 0u;
    info.timeout_ms = timeout_ms < 0 ? 0u : (uint32_t)timeout_ms;
    int rc = -1;
    int last_errno = 0;
    for (int attempt = 0; attempt < 4; ++attempt) {
        rc = ioctl(fd, BINDER_FREEZE, &info);
        if (rc == 0) break;
        last_errno = errno;
        if (last_errno == EINTR) continue;
        if (enable && last_errno == EAGAIN && attempt < 3) {
            sleep_ms(40);
            continue;
        }
        break;
    }
    st.err = rc == 0 ? 0 : (last_errno ? last_errno : errno);
    st.supported = (rc == 0) || (st.err != ENOTTY && st.err != EINVAL);
    st.ok = (rc == 0);
    struct BinderStatus after = binder_get_status(pid);
    if (after.ok) {
        st.sync_recv = after.sync_recv;
        st.async_recv = after.async_recv;
        st.supported = true;
    }
    close(fd);
    return st;
}

static void print_binder_fields(const char *prefix, struct BinderStatus st) {
    printf(" %sbinderSupported=%s %sbinderOk=%s %sbinderErrno=%d %sbinderDevice=", prefix, st.supported ? "true" : "false", prefix, st.ok ? "true" : "false", prefix, st.err, prefix);
    sanitize_print(st.device);
    printf(" %sbinderSyncRecv=%u %sbinderAsyncRecv=%u", prefix, st.sync_recv, prefix, st.async_recv);
}

static int cmd_binder_info(pid_t pid) {
    long start = now_ms();
    struct BinderStatus st = binder_get_status(pid);
    printf("CGFREEZER_BINDER_INFO ok=%s pid=%d", st.ok ? "true" : "false", pid);
    print_binder_fields("", st);
    printf(" elapsedMs=%ld\n", now_ms() - start);
    return st.ok ? 0 : (st.supported ? 3 : 2);
}

static int cmd_check_root(void) {
    struct stat st;
    bool root = stat(CGROUP_ROOT, &st) == 0 && S_ISDIR(st.st_mode);
    bool controllers = access(CGROUP_ROOT "/cgroup.controllers", R_OK) == 0;
    char buf[4096] = {0};
    if (controllers) read_file(CGROUP_ROOT "/cgroup.controllers", buf, sizeof(buf));
    printf("CGFREEZER_CHECK_ROOT ok=%s root=%s controllersReadable=%s controllers=", root ? "true" : "false", root ? "true" : "false", controllers ? "true" : "false");
    sanitize_print(buf);
    printf("\n");
    return root ? 0 : 2;
}

static int scan_package(const char *pkg, int user_id, bool print_lines, char *csv, size_t csv_cap, int *count_out) {
    if (csv && csv_cap) csv[0] = '\0';
    int count = 0;
    int dfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd < 0) return -1;
    DIR *dir = fdopendir(dfd);
    if (!dir) { close(dfd); return -1; }
    struct dirent *de;
    while ((de = readdir(dir)) != NULL) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 0) continue;
        int uid = parse_status_uid(pid);
        if (uid >= 0 && user_id_from_uid(uid) != user_id) continue;
        char cmd[512] = {0};
        if (read_cmdline(pid, cmd, sizeof(cmd)) < 0) continue;
        if (!is_package_process(cmd, pkg)) continue;
        count++;
        if (print_lines) {
            printf("CGFREEZER_SCAN_PID pid=%d uid=%d process=", pid, uid);
            sanitize_print(cmd);
            printf("\n");
        }
        if (csv && csv_cap && strlen(csv) + 64 + strlen(cmd) < csv_cap) {
            char item[700];
            snprintf(item, sizeof(item), "%s%d:%d:%s", csv[0] ? "," : "", pid, uid, cmd);
            strncat(csv, item, csv_cap - strlen(csv) - 1);
        }
    }
    closedir(dir);
    if (count_out) *count_out = count;
    return 0;
}


struct KillTarget {
    pid_t pid;
    int uid;
    unsigned long long start_time;
    char process[512];
};

struct KillSignalResult {
    bool signaled;
    bool disappeared;
    bool identity_mismatch;
    int err;
    const char *method;
};

static int read_proc_start_time(pid_t pid, unsigned long long *start_out) {
    if (!start_out || pid <= 0) return -1;
    char path[128], buf[4096];
    snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    if (read_file(path, buf, sizeof(buf)) < 0) return -1;
    char *rp = strrchr(buf, ')');
    if (!rp) return -1;
    char *cur = rp + 1;
    int field = 3;
    while (*cur && field <= 22) {
        while (*cur && isspace((unsigned char)*cur)) cur++;
        if (!*cur) break;
        char *end = cur;
        while (*end && !isspace((unsigned char)*end)) end++;
        if (field == 22) {
            char saved = *end;
            *end = '\0';
            errno = 0;
            char *num_end = NULL;
            unsigned long long value = strtoull(cur, &num_end, 10);
            bool parsed = errno == 0 && num_end != NULL && num_end == end && value > 0;
            *end = saved;
            if (!parsed) return -1;
            *start_out = value;
            return 0;
        }
        cur = end;
        field++;
    }
    return -1;
}

static int snapshot_package_target(pid_t pid, const char *pkg, int user_id, struct KillTarget *out) {
    if (!out || pid <= 0 || !is_valid_pkg_name(pkg) || user_id < 0) return -1;
    int uid = parse_status_uid(pid);
    if (uid < 0) return -2;
    if (user_id_from_uid(uid) != user_id) return -3;
    char process[512] = {0};
    if (read_cmdline(pid, process, sizeof(process)) < 0 || !is_package_process(process, pkg)) return -4;
    unsigned long long start_time = 0;
    if (read_proc_start_time(pid, &start_time) != 0 || start_time == 0) return -5;
    memset(out, 0, sizeof(*out));
    out->pid = pid;
    out->uid = uid;
    out->start_time = start_time;
    snprintf(out->process, sizeof(out->process), "%s", process);
    return 0;
}

static bool same_kill_target(const struct KillTarget *a, const struct KillTarget *b) {
    return a && b && a->pid == b->pid && a->uid == b->uid &&
           a->start_time == b->start_time && strcmp(a->process, b->process) == 0;
}

static int collect_package_targets(const char *pkg, int user_id, struct KillTarget *targets,
                                   int capacity, int *count_out, int *overflow_out) {
    if (count_out) *count_out = 0;
    if (overflow_out) *overflow_out = 0;
    if (!targets || capacity <= 0 || !is_valid_pkg_name(pkg) || user_id < 0) return -1;
    int dfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd < 0) return -1;
    DIR *dir = fdopendir(dfd);
    if (!dir) { close(dfd); return -1; }
    int count = 0;
    int overflow = 0;
    struct dirent *de;
    while ((de = readdir(dir)) != NULL) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 0) continue;
        struct KillTarget target;
        if (snapshot_package_target(pid, pkg, user_id, &target) != 0) continue;
        if (count < capacity) targets[count++] = target;
        else overflow++;
    }
    closedir(dir);
    if (count_out) *count_out = count;
    if (overflow_out) *overflow_out = overflow;
    return 0;
}


struct CgroupKillProbe {
    int checked;
    int accepted;
    int rejected;
    int errors;
    int dirs;
    bool contains_expected;
    bool overflow;
    pid_t reject_pid;
    int reject_uid;
    int reject_rc;
    char reason[96];
    char reject_process[512];
};

static void cgroup_kill_probe_reason(struct CgroupKillProbe *probe, const char *reason) {
    if (!probe || probe->reason[0]) return;
    snprintf(probe->reason, sizeof(probe->reason), "%s", reason ? reason : "unknown");
}

static bool safe_unified_cgroup_relpath(const char *cg) {
    if (!cg || !*cg || cg[0] != '/') return false;
    if (strstr(cg, "..") != NULL) return false;
    if (strchr(cg, '\n') || strchr(cg, '\r') || strchr(cg, '\t')) return false;
    return true;
}

static int build_cgroup_dir_from_pid(pid_t pid, char *dir_out, size_t cap) {
    char proc_path[128], raw[MAX_TEXT], cg[1024];
    if (!dir_out || cap == 0 || pid <= 0) return -1;
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cgroup", pid);
    if (read_file(proc_path, raw, sizeof(raw)) < 0) return -1;
    if (parse_unified_path(raw, cg, sizeof(cg)) < 0) return -2;
    if (!safe_unified_cgroup_relpath(cg)) return -3;
    if (strcmp(cg, "/") == 0) snprintf(dir_out, cap, "%s", CGROUP_ROOT);
    else snprintf(dir_out, cap, "%s%s", CGROUP_ROOT, cg);
    return 0;
}

static int validate_cgroup_procs_exact(const char *dir, const char *pkg, int user_id,
                                       pid_t expected_pid, struct CgroupKillProbe *probe) {
    char procs_path[MAX_PATH_LEN];
    char buf[MAX_TEXT];
    snprintf(procs_path, sizeof(procs_path), "%s/cgroup.procs", dir);
    int n = read_file(procs_path, buf, sizeof(buf));
    if (n < 0) {
        if (probe) { probe->errors++; cgroup_kill_probe_reason(probe, "read_procs_failed"); }
        return -1;
    }
    if (n >= (int)sizeof(buf) - 2) {
        if (probe) { probe->overflow = true; cgroup_kill_probe_reason(probe, "procs_too_large"); }
        return -1;
    }

    char *save = NULL;
    char *tok = strtok_r(buf, " \t\r\n", &save);
    while (tok) {
        char *end = NULL;
        long v = strtol(tok, &end, 10);
        if (end != tok && *end == '\0' && v > 0 && v <= 4194304L) {
            pid_t pid = (pid_t)v;
            if (probe) probe->checked++;
            if (pid == expected_pid && probe) probe->contains_expected = true;
            struct KillTarget kt;
            int rc = snapshot_package_target(pid, pkg, user_id, &kt);
            if (rc != 0) {
                if (probe) {
                    probe->rejected++;
                    probe->reject_pid = pid;
                    probe->reject_uid = parse_status_uid(pid);
                    probe->reject_rc = rc;
                    read_cmdline(pid, probe->reject_process, sizeof(probe->reject_process));
                    cgroup_kill_probe_reason(probe, "foreign_or_stale_pid");
                }
                return -1;
            }
            if (probe) probe->accepted++;
            if (probe && probe->checked > MAX_KILL_TARGETS) {
                probe->overflow = true;
                cgroup_kill_probe_reason(probe, "too_many_pids");
                return -1;
            }
        }
        tok = strtok_r(NULL, " \t\r\n", &save);
    }
    return 0;
}

static int validate_cgroup_tree_exact_recursive(const char *dir, const char *pkg, int user_id,
                                                pid_t expected_pid, int depth,
                                                struct CgroupKillProbe *probe) {
    if (!dir || !*dir || !probe) return -1;
    if (depth > 16) {
        probe->errors++;
        cgroup_kill_probe_reason(probe, "tree_too_deep");
        return -1;
    }
    probe->dirs++;
    if (probe->dirs > 256) {
        probe->overflow = true;
        cgroup_kill_probe_reason(probe, "too_many_cgroups");
        return -1;
    }
    if (validate_cgroup_procs_exact(dir, pkg, user_id, expected_pid, probe) != 0) return -1;

    DIR *dp = opendir(dir);
    if (!dp) {
        probe->errors++;
        cgroup_kill_probe_reason(probe, "opendir_failed");
        return -1;
    }
    struct dirent *de;
    while ((de = readdir(dp)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (strncmp(de->d_name, "cgroup.", 7) == 0) continue;
        if (strcmp(de->d_name, "cgroup.procs") == 0 || strcmp(de->d_name, "cgroup.threads") == 0) continue;
        char child[MAX_PATH_LEN];
        snprintf(child, sizeof(child), "%s/%s", dir, de->d_name);
        struct stat st;
        if (stat(child, &st) != 0) continue;
        if (!S_ISDIR(st.st_mode)) continue;
        if (validate_cgroup_tree_exact_recursive(child, pkg, user_id, expected_pid, depth + 1, probe) != 0) {
            closedir(dp);
            return -1;
        }
    }
    closedir(dp);
    return 0;
}

static int try_cgroup_kill_fastpath(const struct KillTarget *expected, const char *pkg, int user_id,
                                    char *method_out, size_t method_cap) {
    if (!expected || expected->pid <= 0 || !method_out || method_cap == 0) return -1;
    method_out[0] = '\0';

    char dir[MAX_PATH_LEN];
    if (build_cgroup_dir_from_pid(expected->pid, dir, sizeof(dir)) != 0) return -1;

    char kill_path[MAX_PATH_LEN];
    if (strlen(dir) + sizeof("/cgroup.kill") > sizeof(kill_path)) return -1;
    snprintf(kill_path, sizeof(kill_path), "%s/cgroup.kill", dir);
    if (access(kill_path, W_OK) != 0) return -1;

    struct CgroupKillProbe probe;
    memset(&probe, 0, sizeof(probe));
    probe.reject_pid = -1;
    probe.reject_uid = -1;
    probe.reject_rc = 0;

    if (validate_cgroup_tree_exact_recursive(dir, pkg, user_id, expected->pid, 0, &probe) != 0) return -1;
    if (!probe.contains_expected || probe.checked <= 0 || probe.rejected || probe.errors || probe.overflow) return -1;

    struct KillTarget before_write;
    if (snapshot_package_target(expected->pid, pkg, user_id, &before_write) != 0 ||
            !same_kill_target(expected, &before_write)) {
        return -1;
    }

    if (write_file(kill_path, "1\n") != 0) return -1;
    snprintf(method_out, method_cap, "cgroup.kill");
    return 0;
}

static int pidfd_open_compat(pid_t pid) {
#if defined(SYS_pidfd_open)
    return (int)syscall(SYS_pidfd_open, pid, 0U);
#else
    (void)pid;
    errno = ENOSYS;
    return -1;
#endif
}

static int pidfd_send_signal_compat(int pidfd, int sig) {
#if defined(SYS_pidfd_send_signal)
    return (int)syscall(SYS_pidfd_send_signal, pidfd, sig, NULL, 0U);
#else
    (void)pidfd;
    (void)sig;
    errno = ENOSYS;
    return -1;
#endif
}

static bool proc_pid_exists(pid_t pid) {
    if (pid <= 0) return false;
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d", pid);
    return access(path, F_OK) == 0;
}

static struct KillSignalResult signal_kill_target(const struct KillTarget *expected,
                                                   const char *pkg, int user_id) {
    struct KillSignalResult result;
    memset(&result, 0, sizeof(result));
    result.method = "none";
    if (!expected || expected->pid <= 0) {
        result.err = EINVAL;
        return result;
    }

    struct KillTarget current;
    int snap_rc = snapshot_package_target(expected->pid, pkg, user_id, &current);
    if (snap_rc != 0) {
        if (!proc_pid_exists(expected->pid)) result.disappeared = true;
        else result.identity_mismatch = true;
        result.err = result.disappeared ? ESRCH : ESTALE;
        return result;
    }
    if (!same_kill_target(expected, &current)) {
        result.identity_mismatch = true;
        result.err = ESTALE;
        return result;
    }

    char cgkill_method[32];
    if (try_cgroup_kill_fastpath(expected, pkg, user_id, cgkill_method, sizeof(cgkill_method)) == 0) {
        result.signaled = true;
        result.method = "cgroup.kill";
        return result;
    }

    int pidfd = pidfd_open_compat(expected->pid);
    if (pidfd >= 0) {
        struct KillTarget after_open;
        if (snapshot_package_target(expected->pid, pkg, user_id, &after_open) != 0 ||
                !same_kill_target(expected, &after_open)) {
            close(pidfd);
            if (!proc_pid_exists(expected->pid)) result.disappeared = true;
            else result.identity_mismatch = true;
            result.err = result.disappeared ? ESRCH : ESTALE;
            return result;
        }
        if (pidfd_send_signal_compat(pidfd, SIGKILL) == 0) {
            close(pidfd);
            result.signaled = true;
            result.method = "pidfd";
            return result;
        }
        int pidfd_err = errno;
        close(pidfd);
        if (pidfd_err != ENOSYS && pidfd_err != EINVAL && pidfd_err != ENOTTY) {
            if (pidfd_err == ESRCH) result.disappeared = true;
            result.err = pidfd_err;
            result.method = "pidfd";
            return result;
        }
    }

    struct KillTarget before_kill;
    if (snapshot_package_target(expected->pid, pkg, user_id, &before_kill) != 0) {
        if (!proc_pid_exists(expected->pid)) result.disappeared = true;
        else result.identity_mismatch = true;
        result.err = result.disappeared ? ESRCH : ESTALE;
        return result;
    }
    if (!same_kill_target(expected, &before_kill)) {
        result.identity_mismatch = true;
        result.err = ESTALE;
        return result;
    }
    if (kill(expected->pid, SIGKILL) == 0) {
        result.signaled = true;
        result.method = "kill";
        return result;
    }
    result.err = errno;
    result.method = "kill";
    if (errno == ESRCH) result.disappeared = true;
    return result;
}

static void print_kill_target_fields(const struct KillTarget *target) {
    printf(" pid=%d uid=%d process=", target ? target->pid : -1, target ? target->uid : -1);
    sanitize_print(target ? target->process : "-");
    printf(" startTime=%llu", target ? target->start_time : 0ULL);
}

static void render_kill_target_pids(const struct KillTarget *targets, int count, char *out, size_t cap) {
    if (!out || cap == 0) return;
    out[0] = '\0';
    if (!targets || count <= 0) return;
    for (int i = 0; i < count; ++i) {
        char item[48];
        snprintf(item, sizeof(item), "%s%d", out[0] ? "," : "", targets[i].pid);
        if (strlen(out) + strlen(item) + 1 >= cap) break;
        strncat(out, item, cap - strlen(out) - 1);
    }
}

/* Native package kill fallback. One request keeps /proc scan, identity verification,
 * SIGKILL, bounded live re-scan, and final remain verification inside cgfreezerd.
 * It never kills by UID alone: every signal requires exact package/package:process,
 * user-id, UID, and /proc start-time identity to match immediately before delivery.
 */
static int cmd_kill_package(const char *pkg, int user_id, int event_pid, int timeout_ms) {
    long start = now_ms();
    if (!is_valid_pkg_name(pkg) || user_id < 0 || event_pid < -1) {
        printf("CGFREEZER_KILL_PKG_DONE ok=false package="); sanitize_print(pkg);
        printf(" user=%d eventPid=%d reason=bad_args elapsedMs=%ld\n", user_id, event_pid, now_ms() - start);
        return 64;
    }
    if (timeout_ms < 100 || timeout_ms > 5000) timeout_ms = 800;
    long deadline = start + timeout_ms;
    int max_passes = 1 + timeout_ms / 80;
    if (max_passes < 2) max_passes = 2;
    if (max_passes > MAX_KILL_PASSES) max_passes = MAX_KILL_PASSES;

    int scanned_total = 0, checked = 0, signaled = 0, disappeared = 0;
    int mismatched = 0, failed = 0, overflow_total = 0, passes = 0;
    bool event_valid = false, event_signaled = false;
    struct KillTarget event_target;
    memset(&event_target, 0, sizeof(event_target));

    printf("CGFREEZER_KILL_PKG_BEGIN ok=true package="); sanitize_print(pkg);
    printf(" user=%d eventPid=%d timeoutMs=%d maxPasses=%d liveRescan=true uidWideKill=false signal=9\n",
           user_id, event_pid, timeout_ms, max_passes);

    if (event_pid > 0) {
        int event_rc = snapshot_package_target((pid_t)event_pid, pkg, user_id, &event_target);
        if (event_rc == 0) {
            event_valid = true;
            checked++;
            struct KillSignalResult sr = signal_kill_target(&event_target, pkg, user_id);
            if (sr.signaled) { signaled++; event_signaled = true; }
            else if (sr.disappeared) disappeared++;
            else if (sr.identity_mismatch) mismatched++;
            else failed++;
            printf("CGFREEZER_KILL_PKG_ENTRY ok=%s package=", (sr.signaled || sr.disappeared) ? "true" : "false"); sanitize_print(pkg);
            printf(" user=%d pass=0 source=event", user_id); print_kill_target_fields(&event_target);
            printf(" signal=9 method=%s signaled=%s disappeared=%s identityMismatch=%s errno=%d\n",
                   sr.method, sr.signaled ? "true" : "false", sr.disappeared ? "true" : "false",
                   sr.identity_mismatch ? "true" : "false", sr.err);
            if (sr.signaled) sleep_ms(5);
        } else {
            printf("CGFREEZER_KILL_PKG_EVENT_SKIP ok=true package="); sanitize_print(pkg);
            printf(" user=%d eventPid=%d reason=not_exact_target snapshotRc=%d\n", user_id, event_pid, event_rc);
        }
    }

    struct KillTarget targets[MAX_KILL_TARGETS];
    int remain = 0, remain_overflow = 0;
    for (int pass = 1; pass <= max_passes && now_ms() <= deadline; ++pass) {
        int count = 0, overflow = 0;
        int scan_rc = collect_package_targets(pkg, user_id, targets, MAX_KILL_TARGETS, &count, &overflow);
        if (scan_rc != 0) {
            failed++;
            printf("CGFREEZER_KILL_PKG_PASS ok=false package="); sanitize_print(pkg);
            printf(" user=%d pass=%d reason=scan_failed rc=%d\n", user_id, pass, scan_rc);
            break;
        }
        passes = pass;
        scanned_total += count;
        overflow_total += overflow;
        char pass_pids[MAX_TEXT];
        render_kill_target_pids(targets, count, pass_pids, sizeof(pass_pids));
        printf("CGFREEZER_KILL_PKG_PASS ok=true package="); sanitize_print(pkg);
        printf(" user=%d pass=%d count=%d overflow=%d pids=", user_id, pass, count, overflow); sanitize_print(pass_pids);
        printf("\n");
        if (count == 0 && overflow == 0) {
            remain = 0;
            remain_overflow = 0;
            break;
        }
        for (int i = 0; i < count; ++i) {
            if (pass == 1 && event_valid && event_signaled && same_kill_target(&targets[i], &event_target)) {
                printf("CGFREEZER_KILL_PKG_ENTRY ok=true package="); sanitize_print(pkg);
                printf(" user=%d pass=%d source=event-pending", user_id, pass); print_kill_target_fields(&targets[i]);
                printf(" signal=9 method=event-first signaled=true disappeared=false identityMismatch=false errno=0\n");
                continue;
            }
            checked++;
            struct KillSignalResult sr = signal_kill_target(&targets[i], pkg, user_id);
            if (sr.signaled) signaled++;
            else if (sr.disappeared) disappeared++;
            else if (sr.identity_mismatch) mismatched++;
            else failed++;
            printf("CGFREEZER_KILL_PKG_ENTRY ok=%s package=", (sr.signaled || sr.disappeared) ? "true" : "false"); sanitize_print(pkg);
            printf(" user=%d pass=%d source=scan", user_id, pass); print_kill_target_fields(&targets[i]);
            printf(" signal=9 method=%s signaled=%s disappeared=%s identityMismatch=%s errno=%d\n",
                   sr.method, sr.signaled ? "true" : "false", sr.disappeared ? "true" : "false",
                   sr.identity_mismatch ? "true" : "false", sr.err);
        }
        if (now_ms() < deadline) sleep_ms(25);
    }

    int final_scan_rc = collect_package_targets(pkg, user_id, targets, MAX_KILL_TARGETS, &remain, &remain_overflow);
    char remain_pids[MAX_TEXT];
    render_kill_target_pids(targets, remain, remain_pids, sizeof(remain_pids));
    bool ok = final_scan_rc == 0 && remain == 0 && remain_overflow == 0;
    const char *reason = ok ? (scanned_total == 0 && !event_valid ? "no_alive_pid" : "ok")
                            : (final_scan_rc != 0 ? "final_scan_failed" : "remain_alive");
    printf("CGFREEZER_KILL_PKG_DONE ok=%s package=", ok ? "true" : "false"); sanitize_print(pkg);
    printf(" user=%d eventPid=%d eventValid=%s eventSignaled=%s scanned=%d checked=%d signaled=%d disappeared=%d mismatched=%d failed=%d overflow=%d remain=%d remainOverflow=%d remainPids=",
           user_id, event_pid, event_valid ? "true" : "false", event_signaled ? "true" : "false",
           scanned_total, checked, signaled, disappeared, mismatched, failed, overflow_total,
           remain, remain_overflow); sanitize_print(remain_pids);
    printf(" passes=%d liveRescan=true uidWideKill=false pidIdentity=starttime reason=%s elapsedMs=%ld\n",
           passes, reason, now_ms() - start);
    return ok ? 0 : 12;
}

static int cmd_scan_package(const char *pkg, int user_id) {
    long start = now_ms();
    if (!is_valid_pkg_name(pkg)) {
        printf("CGFREEZER_SCAN_DONE ok=false package="); sanitize_print(pkg);
        printf(" reason=bad_package elapsedMs=%ld\n", now_ms() - start);
        return 2;
    }
    char csv[MAX_TEXT];
    int count = 0;
    int rc = scan_package(pkg, user_id, true, csv, sizeof(csv), &count);
    printf("CGFREEZER_SCAN_DONE ok=%s package=", rc == 0 ? "true" : "false"); sanitize_print(pkg);
    printf(" user=%d count=%d pids=", user_id, count); sanitize_print(csv);
    printf(" elapsedMs=%ld\n", now_ms() - start);
    return rc == 0 ? 0 : 3;
}

static int cmd_freeze_pid_v2(pid_t pid, int timeout_ms) {
    long start = now_ms();
    char path[MAX_PATH_LEN], rb[64] = {0}, events[MAX_TEXT] = {0}, cmd[512] = {0};
    int uid = parse_status_uid(pid);
    read_cmdline(pid, cmd, sizeof(cmd));
    int pr = build_freeze_path_from_pid(pid, path, sizeof(path));
    if (pr != 0) {
        printf("CGFREEZER_FREEZE_DONE ok=false pid=%d uid=%d reason=path_resolve_%d elapsedMs=%ld\n", pid, uid, pr, now_ms() - start);
        return 3;
    }
    char events_path[MAX_PATH_LEN];
    events_path_for_freeze(path, events_path, sizeof(events_path));
    char before_freeze_buf[64] = {0};
    char before_events[MAX_TEXT] = {0};
    read_file(path, before_freeze_buf, sizeof(before_freeze_buf));
    read_file(events_path, before_events, sizeof(before_events));
    char before_freeze = normalize_freeze(before_freeze_buf);
    char before_frozen = parse_events_value(before_events, "frozen");
    if (access(path, R_OK|W_OK) != 0 || access(events_path, R_OK) != 0) {
        printf("CGFREEZER_FREEZE_DONE ok=false pid=%d uid=%d path=", pid, uid); sanitize_print(path);
        printf(" beforeFreeze=%c beforeFrozen=%c reason=not_rw_events elapsedMs=%ld\n", before_freeze, before_frozen, now_ms() - start);
        return 4;
    }

    bool already_frozen = before_freeze == '1' || before_frozen == '1';
    bool binder_attempted = false;
    bool binder_should_restore_on_cgroup_fail = false;
    struct BinderStatus binder_before;
    struct BinderStatus binder_freeze;
    memset(&binder_before, 0, sizeof(binder_before)); binder_before.device = "-";
    memset(&binder_freeze, 0, sizeof(binder_freeze)); binder_freeze.device = "-";
    binder_before = binder_get_status(pid);
    if (!already_frozen) {
        binder_attempted = true;
        binder_freeze = binder_freeze_set(pid, true, timeout_ms > 300 ? timeout_ms : 300);
        binder_should_restore_on_cgroup_fail = binder_freeze.ok;
    } else {
        binder_freeze = binder_before;
    }

    if (write_file(path, "1\n") != 0) {
        int write_err = errno;
        if (binder_should_restore_on_cgroup_fail) (void)binder_freeze_set(pid, false, 0);
        printf("CGFREEZER_FREEZE_DONE ok=false pid=%d uid=%d path=", pid, uid); sanitize_print(path);
        printf(" cmdline="); sanitize_print(cmd);
        printf(" beforeFreeze=%c beforeFrozen=%c reason=write_errno_%d binderAttempted=%s binderSkipped=%s", before_freeze, before_frozen, write_err, binder_attempted ? "true" : "false", already_frozen ? "already_frozen" : "false");
        print_binder_fields("before", binder_before);
        print_binder_fields("freeze", binder_freeze);
        printf(" elapsedMs=%ld\n", now_ms() - start);
        return 5;
    }
    read_file(path, rb, sizeof(rb));
    char last_frozen = '-';
    long wait_elapsed = 0;
    bool event_ok = wait_frozen(path, '1', timeout_ms, events, sizeof(events), &last_frozen, &wait_elapsed);
    bool ok = normalize_freeze(rb) == '1' && event_ok;
    if (!ok && binder_should_restore_on_cgroup_fail) (void)binder_freeze_set(pid, false, 0);
    printf("CGFREEZER_FREEZE_DONE ok=%s pid=%d uid=%d path=", ok ? "true" : "false", pid, uid); sanitize_print(path);
    printf(" cmdline="); sanitize_print(cmd);
    printf(" beforeFreeze=%c beforeFrozen=%c readback=%c eventOk=%s frozen=%c waitMs=%ld reason=%s binderAttempted=%s binderSkipped=%s",
           before_freeze, before_frozen, normalize_freeze(rb), event_ok ? "true" : "false", last_frozen, wait_elapsed, ok ? "ok" : "verify_failed", binder_attempted ? "true" : "false", already_frozen ? "already_frozen" : "false");
    print_binder_fields("before", binder_before);
    print_binder_fields("freeze", binder_freeze);
    printf(" binderBarrierOk=%s elapsedMs=%ld\n", (!binder_attempted || binder_freeze.ok || !binder_freeze.supported || binder_freeze.err == EAGAIN) ? "true" : "false", now_ms() - start);
    return ok ? 0 : 6;
}

static int cmd_freeze_pid(pid_t pid, int timeout_ms) {
    int rc = cmd_freeze_pid_v2(pid, timeout_ms);
    if (rc == 0) return 0;
    return cmd_freeze_pid_v1(pid, timeout_ms);
}


static int parse_scan_csv_item(const char *item, pid_t *pid_out, int *uid_out, char *proc_out, size_t proc_cap) {
    if (!item || !pid_out || !uid_out || !proc_out || proc_cap == 0) return -1;
    const char *c1 = strchr(item, ':');
    if (!c1) return -1;
    const char *c2 = strchr(c1 + 1, ':');
    if (!c2) return -1;
    int pid = atoi(item);
    int uid = atoi(c1 + 1);
    if (pid <= 0 || uid < 0) return -1;
    snprintf(proc_out, proc_cap, "%s", c2 + 1);
    *pid_out = (pid_t)pid;
    *uid_out = uid;
    return 0;
}

static int capture_v1_restore_path(pid_t pid, char *orig_procs, size_t procs_cap, char *before_state) {
    if (orig_procs && procs_cap) orig_procs[0] = '\0';
    if (before_state) *before_state = '-';
    char mount[MAX_PATH_LEN] = {0}, rel[1024] = {0};
    if (find_v1_freezer_mount(mount, sizeof(mount)) != 0) return -1;
    if (parse_v1_freezer_relpath(pid, rel, sizeof(rel)) != 0) return -2;
    char state_path[MAX_PATH_LEN];
    join_v1_path(mount, rel, "cgroup.procs", orig_procs, procs_cap);
    join_v1_path(mount, rel, "freezer.state", state_path, sizeof(state_path));
    char raw[128] = {0};
    if (read_file(state_path, raw, sizeof(raw)) >= 0 && before_state) *before_state = normalize_v1_state(raw);
    return 0;
}

/* One daemon request performs the live package scan and all per-pid freezes.
 * It is request-atomic (one C-side scan/operation round), not transactional:
 * partial success is reported and retained exactly like the previous Dex per-pid loop.
 */
static int cmd_freeze_package(const char *pkg, int user_id, int timeout_ms) {
    long start = now_ms();
    if (!is_valid_pkg_name(pkg) || user_id < 0) {
        printf("CGFREEZER_FREEZE_PKG_DONE ok=false package="); sanitize_print(pkg);
        printf(" user=%d reason=bad_args elapsedMs=%ld\n", user_id, now_ms() - start);
        return 64;
    }
    if (timeout_ms < 100 || timeout_ms > 5000) timeout_ms = 1500;
    char csv[MAX_TEXT];
    int count = 0;
    int scan_rc = scan_package(pkg, user_id, false, csv, sizeof(csv), &count);
    printf("CGFREEZER_FREEZE_PKG_BEGIN ok=%s package=", scan_rc == 0 ? "true" : "false"); sanitize_print(pkg);
    printf(" user=%d timeoutMs=%d scanned=%d requestAtomic=true transactionalRollback=false pids=", user_id, timeout_ms, count); sanitize_print(csv);
    printf("\n");
    if (scan_rc != 0) {
        printf("CGFREEZER_FREEZE_PKG_DONE ok=false package="); sanitize_print(pkg);
        printf(" user=%d scanned=0 checked=0 frozen=0 failed=0 reason=scan_failed elapsedMs=%ld\n", user_id, now_ms() - start);
        return 3;
    }
    if (count <= 0) {
        printf("CGFREEZER_FREEZE_PKG_DONE ok=false package="); sanitize_print(pkg);
        printf(" user=%d scanned=0 checked=0 frozen=0 failed=0 reason=no_alive_pid elapsedMs=%ld\n", user_id, now_ms() - start);
        return 10;
    }

    int checked = 0, frozen = 0, failed = 0, already = 0;
    char tmp[MAX_TEXT];
    snprintf(tmp, sizeof(tmp), "%s", csv);
    char *save = NULL;
    char *item = strtok_r(tmp, ",", &save);
    while (item) {
        pid_t pid = -1;
        int uid = -1;
        char proc[512] = {0};
        if (parse_scan_csv_item(item, &pid, &uid, proc, sizeof(proc)) != 0) {
            failed++;
            printf("CGFREEZER_FREEZE_PKG_ENTRY ok=false package="); sanitize_print(pkg);
            printf(" user=%d reason=bad_scan_item item=", user_id); sanitize_print(item); printf("\n");
            item = strtok_r(NULL, ",", &save);
            continue;
        }
        checked++;

        char v2_path[MAX_PATH_LEN] = {0};
        char v2_before_freeze_buf[64] = {0}, v2_before_events[MAX_TEXT] = {0};
        char v2_before_freeze = '-', v2_before_frozen = '-';
        if (build_freeze_path_from_pid(pid, v2_path, sizeof(v2_path)) == 0) {
            char ep[MAX_PATH_LEN];
            events_path_for_freeze(v2_path, ep, sizeof(ep));
            if (read_file(v2_path, v2_before_freeze_buf, sizeof(v2_before_freeze_buf)) >= 0) v2_before_freeze = normalize_freeze(v2_before_freeze_buf);
            if (read_file(ep, v2_before_events, sizeof(v2_before_events)) >= 0) v2_before_frozen = parse_events_value(v2_before_events, "frozen");
        }
        char v1_orig_procs[MAX_PATH_LEN] = {0};
        char v1_before = '-';
        int v1_capture = capture_v1_restore_path(pid, v1_orig_procs, sizeof(v1_orig_procs), &v1_before);

        int rc = cmd_freeze_pid(pid, timeout_ms);
        if (rc != 0) {
            failed++;
            printf("CGFREEZER_FREEZE_PKG_ENTRY ok=false package="); sanitize_print(pkg);
            printf(" user=%d pid=%d uid=%d process=", user_id, pid, uid); sanitize_print(proc);
            printf(" rc=%d reason=freeze_failed\n", rc);
            item = strtok_r(NULL, ",", &save);
            continue;
        }

        const char *backend = "unknown";
        const char *restore_path = "-";
        char before_freeze = '-', before_frozen = '-';
        bool v2_frozen = false;
        if (v2_path[0]) {
            char rb[64] = {0}, ev[MAX_TEXT] = {0}, ep[MAX_PATH_LEN];
            events_path_for_freeze(v2_path, ep, sizeof(ep));
            if (read_file(v2_path, rb, sizeof(rb)) >= 0 && read_file(ep, ev, sizeof(ev)) >= 0) {
                v2_frozen = normalize_freeze(rb) == '1' && parse_events_value(ev, "frozen") == '1';
            }
        }
        if (v2_frozen) {
            backend = "v2";
            restore_path = v2_path;
            before_freeze = v2_before_freeze;
            before_frozen = v2_before_frozen;
        } else if (v1_capture == 0 && v1_orig_procs[0]) {
            backend = "v1";
            restore_path = v1_orig_procs;
            before_freeze = v1_before;
            before_frozen = v1_before;
        }
        if (before_freeze == '1' || before_frozen == '1') already++;
        frozen++;
        printf("CGFREEZER_FREEZE_PKG_ENTRY ok=true package="); sanitize_print(pkg);
        printf(" user=%d pid=%d uid=%d process=", user_id, pid, uid); sanitize_print(proc);
        printf(" backend=%s path=", backend); sanitize_print(restore_path);
        printf(" beforeFreeze=%c beforeFrozen=%c rc=0\n", before_freeze, before_frozen);
        item = strtok_r(NULL, ",", &save);
    }
    bool ok = frozen > 0;
    printf("CGFREEZER_FREEZE_PKG_DONE ok=%s package=", ok ? "true" : "false"); sanitize_print(pkg);
    printf(" user=%d scanned=%d checked=%d frozen=%d alreadyFrozen=%d failed=%d reason=%s requestAtomic=true transactionalRollback=false elapsedMs=%ld\n",
           user_id, count, checked, frozen, already, failed, ok ? (failed ? "partial" : "ok") : "all_failed", now_ms() - start);
    return ok ? 0 : 11;
}

static bool uid_path_add(char paths[][MAX_PATH_LEN], int *count, int cap, const char *path) {
    if (!paths || !count || !path || !*path || *count >= cap) return false;
    for (int i = 0; i < *count; ++i) if (strcmp(paths[i], path) == 0) return false;
    snprintf(paths[*count], MAX_PATH_LEN, "%s", path);
    (*count)++;
    return true;
}

static bool uid_pid_add(pid_t *pids, int *count, int cap, pid_t pid) {
    if (!pids || !count || pid <= 0 || *count >= cap) return false;
    for (int i = 0; i < *count; ++i) if (pids[i] == pid) return false;
    pids[(*count)++] = pid;
    return true;
}

static bool is_app_uid_value(int uid) {
    if (uid < 10000) return false;
    int appid = uid % 100000;
    return appid >= 10000 && appid < 99000;
}

static void collect_uid_paths_and_pids(int uid, char paths[][MAX_PATH_LEN], int *path_count, pid_t *pids, int *pid_count) {
    const char *roots[] = { CGROUP_ROOT, CGROUP_ROOT "/apps", CGROUP_ROOT "/app", CGROUP_ROOT "/system", NULL };
    for (int i = 0; roots[i]; ++i) {
        char path[MAX_PATH_LEN];
        snprintf(path, sizeof(path), "%s/uid_%d/cgroup.freeze", roots[i], uid);
        if (access(path, R_OK | W_OK) == 0) uid_path_add(paths, path_count, MAX_UID_PATHS, path);
    }
    int dfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd >= 0) {
        DIR *dir = fdopendir(dfd);
        if (dir) {
            struct dirent *de;
            while ((de = readdir(dir)) != NULL) {
                if (!isdigit((unsigned char)de->d_name[0])) continue;
                pid_t pid = (pid_t)atoi(de->d_name);
                if (pid <= 0 || parse_status_uid(pid) != uid) continue;
                uid_pid_add(pids, pid_count, MAX_UID_PIDS, pid);
                char path[MAX_PATH_LEN];
                if (build_freeze_path_from_pid(pid, path, sizeof(path)) == 0 && access(path, R_OK | W_OK) == 0) {
                    uid_path_add(paths, path_count, MAX_UID_PATHS, path);
                }
            }
            closedir(dir);
        } else close(dfd);
    }
}

static int cmd_thaw_uid(int uid, int timeout_ms) {
    long start = now_ms();
    if (!is_app_uid_value(uid)) {
        printf("CGFREEZER_THAW_UID_DONE ok=false uid=%d reason=non_app_uid elapsedMs=%ld\n", uid, now_ms() - start);
        return 64;
    }
    if (timeout_ms < 100 || timeout_ms > 5000) timeout_ms = 1500;
    char paths[MAX_UID_PATHS][MAX_PATH_LEN];
    pid_t pids[MAX_UID_PIDS];
    int path_count = 0, pid_count = 0;
    memset(paths, 0, sizeof(paths));
    memset(pids, 0, sizeof(pids));
    collect_uid_paths_and_pids(uid, paths, &path_count, pids, &pid_count);

    char v1_mount[MAX_PATH_LEN] = {0}, v1_state[MAX_PATH_LEN] = {0};
    if (find_v1_freezer_mount(v1_mount, sizeof(v1_mount)) == 0) {
        snprintf(v1_state, sizeof(v1_state), "%s/speedbackup_frozen/freezer.state", v1_mount);
    }

    printf("CGFREEZER_THAW_UID_BEGIN ok=true uid=%d timeoutMs=%d paths=%d pids=%d emergencyOnly=true\n", uid, timeout_ms, path_count, pid_count);
    int ok_paths = 0, fail_paths = 0;
    for (int i = 0; i < path_count; ++i) {
        int wr = write_file(paths[i], "0\n");
        char last = '-'; long waited = 0;
        bool ev = wr == 0 && wait_frozen(paths[i], '0', timeout_ms, NULL, 0, &last, &waited);
        if (ev) ok_paths++; else fail_paths++;
        printf("CGFREEZER_THAW_UID_PATH ok=%s uid=%d path=", ev ? "true" : "false", uid); sanitize_print(paths[i]);
        printf(" writeRc=%d frozen=%c waitMs=%ld errno=%d\n", wr, last, waited, wr == 0 ? 0 : errno);
    }
    int v1_ok = 0;
    if (v1_state[0] && access(v1_state, W_OK) == 0) {
        int wr = write_file(v1_state, "THAWED\n");
        char last = '-'; long waited = 0;
        bool ev = wr == 0 && wait_v1_state(v1_state, '0', timeout_ms, &last, &waited);
        v1_ok = ev ? 1 : -1;
        printf("CGFREEZER_THAW_UID_V1 ok=%s uid=%d state=", ev ? "true" : "false", uid); sanitize_print(v1_state);
        printf(" readback=%c waitMs=%ld\n", last, waited);
    }
    int binder_ok = 0, binder_fail = 0, binder_unsupported = 0;
    for (int i = 0; i < pid_count; ++i) {
        struct BinderStatus st = binder_freeze_set(pids[i], false, 0);
        if (st.ok) binder_ok++;
        else if (!st.supported || st.err == ENOTTY || st.err == EINVAL || st.err == ENOENT || st.err == ESRCH) binder_unsupported++;
        else binder_fail++;
    }
    bool nothing_found = path_count == 0 && v1_ok == 0 && pid_count == 0;
    bool ok = fail_paths == 0 && binder_fail == 0 && v1_ok >= 0;
    printf("CGFREEZER_THAW_UID_DONE ok=%s uid=%d paths=%d okPaths=%d failPaths=%d pids=%d binderOk=%d binderUnsupported=%d binderFail=%d v1=%d nothingFound=%s emergencyOnly=true elapsedMs=%ld\n",
           ok ? "true" : "false", uid, path_count, ok_paths, fail_paths, pid_count, binder_ok, binder_unsupported, binder_fail, v1_ok, nothing_found ? "true" : "false", now_ms() - start);
    return ok ? 0 : 12;
}

static int cmd_thaw_path_internal(pid_t pid, const char *path, char target, int timeout_ms, bool have_pid) {
    long start = now_ms();
    char rb[64] = {0}, events[MAX_TEXT] = {0};
    if (!path || (target != '0' && target != '1')) {
        printf("CGFREEZER_THAW_DONE ok=false reason=bad_args elapsedMs=%ld\n", now_ms() - start);
        return 2;
    }
    if (have_pid && strstr(path, "cgroup.procs") != NULL) {
        return cmd_thaw_pid_v1(pid, path, target, timeout_ms);
    }
    char value[4] = {target, '\n', 0, 0};
    if (write_file(path, value) != 0) {
        printf("CGFREEZER_THAW_DONE ok=false pid=%d path=", have_pid ? pid : -1); sanitize_print(path);
        printf(" target=%c reason=write_errno_%d elapsedMs=%ld\n", target, errno, now_ms() - start);
        return 3;
    }
    read_file(path, rb, sizeof(rb));
    char last_frozen = '-';
    long wait_elapsed = 0;
    bool event_ok = wait_frozen(path, target, timeout_ms, events, sizeof(events), &last_frozen, &wait_elapsed);
    bool cgroup_ok = normalize_freeze(rb) == target && event_ok;
    bool binder_attempted = false;
    bool binder_skipped_originally_frozen = target == '1';
    struct BinderStatus binder_thaw;
    memset(&binder_thaw, 0, sizeof(binder_thaw)); binder_thaw.device = "-";
    if (have_pid && target == '0') {
        binder_attempted = true;
        binder_thaw = binder_freeze_set(pid, false, 0);
    }
    bool ok = cgroup_ok;
    printf("CGFREEZER_THAW_DONE ok=%s pid=%d path=", ok ? "true" : "false", have_pid ? pid : -1); sanitize_print(path);
    printf(" target=%c readback=%c eventOk=%s frozen=%c waitMs=%ld cgroupOk=%s binderAttempted=%s binderSkipped=%s reason=%s",
           target, normalize_freeze(rb), event_ok ? "true" : "false", last_frozen, wait_elapsed, cgroup_ok ? "true" : "false", binder_attempted ? "true" : "false", binder_skipped_originally_frozen ? "originally_frozen" : "false", ok ? "ok" : "verify_failed");
    print_binder_fields("thaw", binder_thaw);
    printf(" binderRestoreOk=%s elapsedMs=%ld\n", (!binder_attempted || binder_thaw.ok || !binder_thaw.supported || binder_thaw.err == EINVAL) ? "true" : "false", now_ms() - start);
    return ok ? 0 : 4;
}

static int cmd_thaw_path(const char *path, char target, int timeout_ms) {
    return cmd_thaw_path_internal(-1, path, target, timeout_ms, false);
}

static int cmd_thaw_pid(pid_t pid, const char *path, char target, int timeout_ms) {
    return cmd_thaw_path_internal(pid, path, target, timeout_ms, true);
}

struct ParsedEvent {
    uint32_t tag;
    uint32_t ints[16];
    int int_count;
    char strings[8][512];
    int string_count;
};

static bool read_u32_le(const uint8_t *p, size_t n, size_t *off, uint32_t *out) {
    if (!p || !off || !out || *off + 4 > n) return false;
    *out = ((uint32_t)p[*off]) | ((uint32_t)p[*off + 1] << 8) | ((uint32_t)p[*off + 2] << 16) | ((uint32_t)p[*off + 3] << 24);
    *off += 4;
    return true;
}

static bool skip_bytes(size_t n, size_t *off, size_t count) {
    if (!off || *off + count > n) return false;
    *off += count;
    return true;
}

static bool decode_event_element(const uint8_t *p, size_t n, size_t *off, int depth, struct ParsedEvent *ev) {
    if (depth > 8 || *off >= n) return false;
    uint8_t type = p[(*off)++];
    switch (type) {
        case 0: {
            uint32_t val;
            if (!read_u32_le(p, n, off, &val)) return false;
            if (ev->int_count < 16) ev->ints[ev->int_count++] = val;
            return true;
        }
        case 1: return skip_bytes(n, off, 8);
        case 2: {
            uint32_t len = 0;
            if (!read_u32_le(p, n, off, &len)) return false;
            if (*off + len > n) return false;
            if (ev->string_count < 8) {
                size_t copy = len < sizeof(ev->strings[0]) - 1 ? len : sizeof(ev->strings[0]) - 1;
                memcpy(ev->strings[ev->string_count], p + *off, copy);
                ev->strings[ev->string_count][copy] = '\0';
                ev->string_count++;
            }
            *off += len;
            return true;
        }
        case 3: {
            if (*off >= n) return false;
            uint8_t count = p[(*off)++];
            for (uint8_t i = 0; i < count; ++i) {
                if (!decode_event_element(p, n, off, depth + 1, ev)) return false;
            }
            return true;
        }
        case 4: return skip_bytes(n, off, 4);
        default: return false;
    }
}

static bool parse_event_payload(const uint8_t *data, size_t len, struct ParsedEvent *ev) {
    if (!data || len < 5 || !ev) return false;
    memset(ev, 0, sizeof(*ev));
    size_t off = 0;
    if (!read_u32_le(data, len, &off, &ev->tag)) return false;
    if (!decode_event_element(data, len, &off, 0, ev)) return false;
    return true;
}

struct PidCache {
    int pids[MAX_CACHE_PIDS];
    int count;
    int uid;
    long uid_at_ms;
};

static bool cache_contains(struct PidCache *cache, int pid) {
    if (!cache || pid <= 0) return false;
    for (int i = 0; i < cache->count; ++i) if (cache->pids[i] == pid) return true;
    return false;
}

static void cache_add(struct PidCache *cache, int pid, int uid) {
    if (!cache || pid <= 0) return;
    if (!cache_contains(cache, pid) && cache->count < MAX_CACHE_PIDS) cache->pids[cache->count++] = pid;
    if (uid > 0) { cache->uid = uid; cache->uid_at_ms = now_ms(); }
}

static void cache_remove(struct PidCache *cache, int pid) {
    if (!cache || pid <= 0) return;
    for (int i = 0; i < cache->count; ++i) {
        if (cache->pids[i] == pid) {
            cache->pids[i] = cache->pids[cache->count - 1];
            cache->count--;
            return;
        }
    }
}

static void emit_logd_event(const char *type, uint32_t tag, int user, int pid, int uid, const char *proc, struct PidCache *cache, const char *reason) {
    printf("CGFREEZER_LOGD_EVENT type="); sanitize_print(type);
    printf(" tag=%u user=%d pid=%d uid=%d process=", tag, user, pid, uid);
    sanitize_print(proc);
    printf(" cachePids=%d cacheUid=%d reason=", cache ? cache->count : 0, cache ? cache->uid : -1);
    sanitize_print(reason ? reason : "ok");
    printf("\n");
    fflush(stdout);
}

static int cmd_watch_logd(const char *pkg, int user_id, int duration_ms) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    long start = now_ms();
    if (!is_valid_pkg_name(pkg)) {
        printf("CGFREEZER_LOGD_WATCH_DONE ok=false reason=bad_package package="); sanitize_print(pkg); printf(" elapsedMs=0\n");
        return 2;
    }
    struct PidCache cache;
    memset(&cache, 0, sizeof(cache));
    cache.uid = -1;
    char initial_csv[MAX_TEXT];
    int initial_count = 0;
    scan_package(pkg, user_id, false, initial_csv, sizeof(initial_csv), &initial_count);
    // Populate cache from the CSV without trusting it for correctness; this is only an acceleration hint.
    char tmp[MAX_TEXT];
    snprintf(tmp, sizeof(tmp), "%s", initial_csv);
    char *save = NULL;
    char *item = strtok_r(tmp, ",", &save);
    while (item) {
        int pid = -1, uid = -1;
        if (sscanf(item, "%d:%d:", &pid, &uid) == 2) cache_add(&cache, pid, uid);
        item = strtok_r(NULL, ",", &save);
    }

    void *liblog = dlopen("liblog.so", RTLD_NOW);
    if (!liblog) {
        printf("CGFREEZER_LOGD_WATCH_DONE ok=false reason=dlopen_liblog_failed error="); sanitize_print(dlerror()); printf(" elapsedMs=%ld\n", now_ms() - start);
        return 3;
    }
    FnLoggerListOpen logger_open = (FnLoggerListOpen)dlsym(liblog, "android_logger_list_open");
    FnLoggerListRead logger_read = (FnLoggerListRead)dlsym(liblog, "android_logger_list_read");
    FnLoggerListFree logger_free = (FnLoggerListFree)dlsym(liblog, "android_logger_list_free");
    if (!logger_open || !logger_read || !logger_free) {
        printf("CGFREEZER_LOGD_WATCH_DONE ok=false reason=dlsym_failed elapsedMs=%ld\n", now_ms() - start);
        dlclose(liblog);
        return 4;
    }
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    printf("CGFREEZER_LOGD_WATCH_START ok=true package="); sanitize_print(pkg);
    printf(" user=%d durationMs=%d initialPids=%d pids=", user_id, duration_ms, initial_count); sanitize_print(initial_csv);
    printf("\n");

    struct logger_list *list = logger_open(LOG_ID_EVENTS, 0, 0, 0);
    if (!list) {
        printf("CGFREEZER_LOGD_WATCH_DONE ok=false reason=open_events_failed elapsedMs=%ld\n", now_ms() - start);
        dlclose(liblog);
        return 5;
    }
    long deadline = duration_ms > 0 ? start + duration_ms : 0;
    int events = 0, matches = 0, starts = 0, deaths = 0, reconnects = 0;
    while (g_running) {
        if (deadline > 0 && now_ms() >= deadline) break;
        struct LogMsg msg;
        memset(&msg, 0, sizeof(msg));
        int ret = logger_read(list, &msg);
        if (ret == -EINTR) continue;
        if (ret == -EAGAIN || ret == 0) { sleep_ms(50); continue; }
        if (ret < 0) {
            logger_free(list);
            list = NULL;
            reconnects++;
            while (g_running && !list) {
                list = logger_open(LOG_ID_EVENTS, 0, 0, 0);
                if (!list) sleep_ms(250);
            }
            continue;
        }
        char *payload = log_msg_payload(&msg);
        if (!payload || msg.u.entry.len <= 0) continue;
        struct ParsedEvent ev;
        if (!parse_event_payload((const uint8_t*)payload, (size_t)msg.u.entry.len, &ev)) continue;
        events++;
        if (ev.tag == 30014 && ev.string_count >= 1 && ev.int_count >= 3) {
            int event_user = (int)ev.ints[0];
            int pid = (int)ev.ints[1];
            int uid = (int)ev.ints[2];
            const char *proc = ev.strings[0];
            if (event_user == user_id && pid > 0 && is_package_process(proc, pkg)) {
                cache_add(&cache, pid, uid);
                matches++; starts++;
                emit_logd_event("am_proc_start", ev.tag, event_user, pid, uid, proc, &cache, "ok");
            }
            continue;
        }
        if (ev.tag == 30011 && ev.int_count >= 2) {
            int event_user = user_id;
            int pid = (int)ev.ints[1];
            bool known = cache_contains(&cache, pid);
            if (known) {
                cache_remove(&cache, pid);
                matches++; deaths++;
                emit_logd_event("am_proc_died", ev.tag, event_user, pid, -1, pkg, &cache, "known-pid");
            }
            continue;
        }
    }
    if (list) logger_free(list);
    dlclose(liblog);
    printf("CGFREEZER_LOGD_WATCH_DONE ok=true package="); sanitize_print(pkg);
    printf(" user=%d events=%d matches=%d starts=%d deaths=%d cachePids=%d cacheUid=%d reconnects=%d elapsedMs=%ld\n",
           user_id, events, matches, starts, deaths, cache.count, cache.uid, reconnects, now_ms() - start);
    return 0;
}


static int parse_int_arg(const char *s, int fallback);

static int tokenize_line(char *line, char **argv, int max_args) {
    int argc = 0;
    char *save = NULL;
    char *tok = strtok_r(line, " \t\r\n", &save);
    while (tok && argc < max_args) {
        argv[argc++] = tok;
        tok = strtok_r(NULL, " \t\r\n", &save);
    }
    return argc;
}


static int signal_pid_user_checked(pid_t pid, int user_id, int sig, const char **method_out, int *uid_out) {
    if (method_out) *method_out = "none";
    if (uid_out) *uid_out = -1;
    if (pid <= 0) { errno = EINVAL; return -1; }
    int uid = parse_status_uid(pid);
    if (uid_out) *uid_out = uid;
    if (uid < 0) { errno = ESRCH; return -1; }
    if (user_id >= 0 && user_id_from_uid(uid) != user_id) { errno = EPERM; return -1; }
    int pidfd = pidfd_open_compat(pid);
    if (pidfd >= 0) {
        int prc = pidfd_send_signal_compat(pidfd, sig);
        int e = errno;
        close(pidfd);
        if (prc == 0) { if (method_out) *method_out = "pidfd"; return 0; }
        if (e != ENOSYS && e != EINVAL && e != ENOTTY) { errno = e; if (method_out) *method_out = "pidfd"; return -1; }
    }
    if (kill(pid, sig) == 0) { if (method_out) *method_out = "kill"; return 0; }
    if (method_out) *method_out = "kill";
    return -1;
}

static int cmd_freeze_pid_list(int user_id, const char *pid_csv, int timeout_ms) {
    long start = now_ms();
    char tmp[MAX_TEXT];
    int checked = 0, frozen = 0, failed = 0, skipped = 0;
    if (!pid_csv || !*pid_csv) {
        printf("CGFREEZER_FREEZE_PID_LIST_DONE ok=false user=%d checked=0 frozen=0 failed=0 skipped=0 reason=empty elapsedMs=%ld\n", user_id, now_ms() - start);
        return 64;
    }
    if (timeout_ms < 100 || timeout_ms > 5000) timeout_ms = 1500;
    snprintf(tmp, sizeof(tmp), "%s", pid_csv);
    printf("CGFREEZER_FREEZE_PID_LIST_BEGIN ok=true user=%d timeoutMs=%d pids=", user_id, timeout_ms); sanitize_print(pid_csv); printf("\n");
    char *save = NULL;
    char *item = strtok_r(tmp, ",", &save);
    while (item) {
        int pid = parse_int_arg(item, -1);
        int uid = pid > 0 ? parse_status_uid((pid_t)pid) : -1;
        char cmd[512] = {0};
        if (pid > 0) read_cmdline((pid_t)pid, cmd, sizeof(cmd));
        if (pid <= 0 || uid < 0 || (user_id >= 0 && user_id_from_uid(uid) != user_id)) {
            skipped++;
            printf("CGFREEZER_FREEZE_PID_LIST_ENTRY ok=false pid=%d uid=%d reason=skip_bad_pid_or_user\n", pid, uid);
            item = strtok_r(NULL, ",", &save);
            continue;
        }
        checked++;
        int rc = cmd_freeze_pid((pid_t)pid, timeout_ms);
        if (rc == 0) frozen++; else failed++;
        printf("CGFREEZER_FREEZE_PID_LIST_ENTRY ok=%s pid=%d uid=%d rc=%d process=", rc == 0 ? "true" : "false", pid, uid, rc); sanitize_print(cmd); printf("\n");
        item = strtok_r(NULL, ",", &save);
    }
    bool ok = frozen > 0 && failed == 0;
    printf("CGFREEZER_FREEZE_PID_LIST_DONE ok=%s user=%d checked=%d frozen=%d failed=%d skipped=%d reason=%s batch=true elapsedMs=%ld\n",
           ok ? "true" : "false", user_id, checked, frozen, failed, skipped, ok ? "ok" : (frozen > 0 ? "partial" : "none"), now_ms() - start);
    return frozen > 0 ? 0 : 11;
}

static int cmd_kill_pid_list(int user_id, const char *pid_csv, int sig) {
    long start = now_ms();
    char tmp[MAX_TEXT];
    int checked = 0, killed = 0, failed = 0, skipped = 0;
    if (!pid_csv || !*pid_csv) {
        printf("CGFREEZER_KILL_PID_LIST_DONE ok=false user=%d checked=0 killed=0 failed=0 skipped=0 reason=empty elapsedMs=%ld\n", user_id, now_ms() - start);
        return 64;
    }
    if (sig <= 0 || sig > 64) sig = SIGKILL;
    snprintf(tmp, sizeof(tmp), "%s", pid_csv);
    printf("CGFREEZER_KILL_PID_LIST_BEGIN ok=true user=%d signal=%d pids=", user_id, sig); sanitize_print(pid_csv); printf("\n");
    char *save = NULL;
    char *item = strtok_r(tmp, ",", &save);
    while (item) {
        int pid = parse_int_arg(item, -1);
        int uid = -1;
        const char *method = "none";
        char cmd[512] = {0};
        if (pid > 0) read_cmdline((pid_t)pid, cmd, sizeof(cmd));
        if (pid <= 0) {
            skipped++;
            printf("CGFREEZER_KILL_PID_LIST_ENTRY ok=false pid=%d uid=-1 method=none reason=bad_pid\n", pid);
            item = strtok_r(NULL, ",", &save);
            continue;
        }
        checked++;
        int rc = signal_pid_user_checked((pid_t)pid, user_id, sig, &method, &uid);
        int e = rc == 0 ? 0 : errno;
        if (rc == 0 || e == ESRCH) killed++; else failed++;
        printf("CGFREEZER_KILL_PID_LIST_ENTRY ok=%s pid=%d uid=%d signal=%d method=%s errno=%d process=", (rc == 0 || e == ESRCH) ? "true" : "false", pid, uid, sig, method, e); sanitize_print(cmd); printf("\n");
        item = strtok_r(NULL, ",", &save);
    }
    bool ok = killed > 0 && failed == 0;
    printf("CGFREEZER_KILL_PID_LIST_DONE ok=%s user=%d checked=%d killed=%d failed=%d skipped=%d reason=%s pidfdOptional=true batch=true elapsedMs=%ld\n",
           ok ? "true" : "false", user_id, checked, killed, failed, skipped, ok ? "ok" : (killed > 0 ? "partial" : "none"), now_ms() - start);
    return killed > 0 ? 0 : 12;
}

static char proc_state_char(pid_t pid) {
    char path[128], buf[4096];
    snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    if (read_file(path, buf, sizeof(buf)) < 0) return '-';
    char *rp = strrchr(buf, ')');
    if (!rp || !rp[1]) return '-';
    char *p = rp + 1;
    while (*p && isspace((unsigned char)*p)) p++;
    return *p ? *p : '-';
}

static int read_oom_score_adj(pid_t pid) {
    char path[128], buf[64];
    snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", pid);
    if (read_file(path, buf, sizeof(buf)) < 0) return 9999;
    return parse_int_arg(buf, 9999);
}

static int read_proc_wchan(pid_t pid, char *buf, size_t cap) {
    char path[128];
    if (!buf || cap == 0 || pid <= 0) return -1;
    buf[0] = '\0';
    snprintf(path, sizeof(path), "/proc/%d/wchan", pid);
    if (read_file(path, buf, cap) < 0) return -1;
    if (!buf[0]) snprintf(buf, cap, "-");
    return 0;
}

static const char *classify_wchan_freeze_kind(const char *wchan) {
    if (!wchan || !*wchan || strcmp(wchan, "-") == 0 || strcmp(wchan, "0") == 0) return "unknown";
    if (strstr(wchan, "__refrigerator") || strstr(wchan, "refrigerator")) return "v1";
    if (strstr(wchan, "do_freezer_trap") || strstr(wchan, "get_signal")) return "v2";
    if (strstr(wchan, "do_signal_stop")) return "sigstop";
    return "not-frozen";
}

static bool wchan_kind_is_frozen(const char *kind) {
    return kind && (strcmp(kind, "v1") == 0 || strcmp(kind, "v2") == 0);
}

static bool wchan_kind_is_stopped(const char *kind) {
    return kind && strcmp(kind, "sigstop") == 0;
}

static bool wchan_expect_ok(const char *expect, const char *kind) {
    if (!expect || !*expect || strcmp(expect, "any") == 0) return true;
    if (strcmp(expect, "frozen") == 0) return wchan_kind_is_frozen(kind);
    if (strcmp(expect, "thawed") == 0 || strcmp(expect, "not-frozen") == 0) return !wchan_kind_is_frozen(kind) && !wchan_kind_is_stopped(kind);
    return true;
}

static const char *normalize_wchan_expect(const char *expect) {
    if (!expect || !*expect) return "any";
    if (strcmp(expect, "frozen") == 0 || strcmp(expect, "thawed") == 0 || strcmp(expect, "not-frozen") == 0 || strcmp(expect, "any") == 0) return expect;
    return "any";
}

static void print_wchan_entry(const char *origin, int user_id, pid_t pid, int uid, const char *expect, const char *process, int *checked, int *frozen, int *sigstop, int *unknown, int *mismatch) {
    char wchan[256] = {0};
    char state = proc_state_char(pid);
    const char *kind = "unknown";
    bool match = true;
    if (read_proc_wchan(pid, wchan, sizeof(wchan)) == 0) {
        kind = classify_wchan_freeze_kind(wchan);
    } else {
        snprintf(wchan, sizeof(wchan), "-");
        kind = "unknown";
    }
    if (checked) (*checked)++;
    if (frozen && wchan_kind_is_frozen(kind)) (*frozen)++;
    if (sigstop && wchan_kind_is_stopped(kind)) (*sigstop)++;
    if (unknown && strcmp(kind, "unknown") == 0) (*unknown)++;
    match = wchan_expect_ok(expect, kind);
    if (!match && mismatch) (*mismatch)++;
    printf("CGFREEZER_WCHAN_ENTRY ok=%s origin=%s user=%d pid=%d uid=%d state=%c oomAdj=%d expect=%s match=%s freezeKind=%s wchan=", match ? "true" : "false", origin ? origin : "unknown", user_id, pid, uid, state, read_oom_score_adj(pid), expect ? expect : "any", match ? "true" : "false", kind);
    sanitize_print(wchan);
    printf(" process="); sanitize_print(process && *process ? process : "-"); printf("\n");
}

static int cmd_wchan_pid_list(int user_id, const char *pid_csv, const char *expect_arg) {
    long start = now_ms();
    const char *expect = normalize_wchan_expect(expect_arg);
    char tmp[MAX_TEXT];
    int checked = 0, frozen = 0, sigstop = 0, unknown = 0, mismatch = 0, skipped = 0;
    if (!pid_csv || !*pid_csv || strcmp(pid_csv, "-") == 0 || strcmp(pid_csv, "none") == 0) {
        bool ok = strcmp(expect, "thawed") == 0 || strcmp(expect, "not-frozen") == 0 || strcmp(expect, "any") == 0;
        printf("CGFREEZER_WCHAN_DONE ok=%s origin=pid-list user=%d checked=0 frozen=0 sigstop=0 unknown=0 mismatch=0 skipped=0 expect=%s reason=no_pids elapsedMs=%ld\n", ok ? "true" : "false", user_id, expect, now_ms() - start);
        return ok ? 0 : 11;
    }
    snprintf(tmp, sizeof(tmp), "%s", pid_csv);
    printf("CGFREEZER_WCHAN_BEGIN ok=true origin=pid-list user=%d expect=%s pids=", user_id, expect); sanitize_print(pid_csv); printf("\n");
    char *save = NULL;
    char *item = strtok_r(tmp, ",", &save);
    while (item) {
        int pid_i = parse_int_arg(item, -1);
        pid_t pid = (pid_t)pid_i;
        int uid = pid_i > 0 ? parse_status_uid(pid) : -1;
        char process[512] = {0};
        if (pid_i > 0) read_cmdline(pid, process, sizeof(process));
        if (pid_i <= 0 || uid < 0 || (user_id >= 0 && user_id_from_uid(uid) != user_id)) {
            skipped++;
            printf("CGFREEZER_WCHAN_ENTRY ok=false origin=pid-list user=%d pid=%d uid=%d expect=%s match=false freezeKind=unknown wchan=- process=- reason=skip_bad_pid_or_user\n", user_id, pid_i, uid, expect);
            item = strtok_r(NULL, ",", &save);
            continue;
        }
        print_wchan_entry("pid-list", user_id, pid, uid, expect, process, &checked, &frozen, &sigstop, &unknown, &mismatch);
        item = strtok_r(NULL, ",", &save);
    }
    bool ok = true;
    if (strcmp(expect, "frozen") == 0) ok = checked > 0 && frozen > 0 && mismatch == 0;
    else if (strcmp(expect, "thawed") == 0 || strcmp(expect, "not-frozen") == 0) ok = mismatch == 0;
    printf("CGFREEZER_WCHAN_DONE ok=%s origin=pid-list user=%d checked=%d frozen=%d sigstop=%d unknown=%d mismatch=%d skipped=%d expect=%s reason=%s elapsedMs=%ld\n", ok ? "true" : "false", user_id, checked, frozen, sigstop, unknown, mismatch, skipped, expect, ok ? "ok" : "expect_mismatch", now_ms() - start);
    return ok ? 0 : 12;
}

static int cmd_wchan_uid(int uid_filter, const char *expect_arg) {
    long start = now_ms();
    const char *expect = normalize_wchan_expect(expect_arg);
    int checked = 0, frozen = 0, sigstop = 0, unknown = 0, mismatch = 0, skipped = 0, user_id = uid_filter >= 0 ? user_id_from_uid(uid_filter) : -1;
    if (uid_filter < 0) {
        printf("CGFREEZER_WCHAN_UID_DONE ok=false uid=%d checked=0 frozen=0 sigstop=0 unknown=0 mismatch=0 skipped=0 expect=%s reason=bad_uid elapsedMs=%ld\n", uid_filter, expect, now_ms() - start);
        return 64;
    }
    printf("CGFREEZER_WCHAN_BEGIN ok=true origin=uid uid=%d user=%d expect=%s\n", uid_filter, user_id, expect);
    int dfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd < 0) {
        printf("CGFREEZER_WCHAN_UID_DONE ok=false uid=%d checked=0 frozen=0 sigstop=0 unknown=0 mismatch=0 skipped=0 expect=%s reason=proc_open_errno_%d elapsedMs=%ld\n", uid_filter, expect, errno, now_ms() - start);
        return 3;
    }
    DIR *dir = fdopendir(dfd);
    if (!dir) { close(dfd); return 3; }
    struct dirent *de;
    while ((de = readdir(dir)) != NULL) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 0) continue;
        int uid = parse_status_uid(pid);
        if (uid != uid_filter) continue;
        char process[512] = {0};
        if (read_cmdline(pid, process, sizeof(process)) < 0) snprintf(process, sizeof(process), "-");
        print_wchan_entry("uid", user_id, pid, uid, expect, process, &checked, &frozen, &sigstop, &unknown, &mismatch);
    }
    closedir(dir);
    bool ok = true;
    if (strcmp(expect, "frozen") == 0) ok = checked > 0 && frozen > 0 && mismatch == 0;
    else if (strcmp(expect, "thawed") == 0 || strcmp(expect, "not-frozen") == 0) ok = mismatch == 0;
    printf("CGFREEZER_WCHAN_UID_DONE ok=%s uid=%d user=%d checked=%d frozen=%d sigstop=%d unknown=%d mismatch=%d skipped=%d expect=%s reason=%s elapsedMs=%ld\n", ok ? "true" : "false", uid_filter, user_id, checked, frozen, sigstop, unknown, mismatch, skipped, expect, ok ? "ok" : "expect_mismatch", now_ms() - start);
    return ok ? 0 : 12;
}

static int cmd_proc_snapshot(const char *pkg, int user_id) {
    long start = now_ms();
    int rows = 0, errors = 0;
    if (!is_valid_pkg_name(pkg) || user_id < 0) {
        printf("CGFREEZER_PROC_SNAPSHOT_DONE ok=false package="); sanitize_print(pkg); printf(" user=%d rows=0 reason=bad_args elapsedMs=%ld\n", user_id, now_ms() - start);
        return 64;
    }
    printf("CGFREEZER_PROC_SNAPSHOT_BEGIN ok=true package="); sanitize_print(pkg); printf(" user=%d\n", user_id);
    int dfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dfd < 0) {
        printf("CGFREEZER_PROC_SNAPSHOT_DONE ok=false package="); sanitize_print(pkg); printf(" user=%d rows=0 reason=proc_open_errno_%d elapsedMs=%ld\n", user_id, errno, now_ms() - start);
        return 3;
    }
    DIR *dir = fdopendir(dfd);
    if (!dir) { close(dfd); return 3; }
    struct dirent *de;
    while ((de = readdir(dir)) != NULL) {
        if (!isdigit((unsigned char)de->d_name[0])) continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 0) continue;
        int uid = parse_status_uid(pid);
        if (uid < 0 || user_id_from_uid(uid) != user_id) continue;
        char process[512] = {0};
        if (read_cmdline(pid, process, sizeof(process)) < 0 || !is_package_process(process, pkg)) continue;
        char cg[1024] = {0};
        char cgpath[128];
        snprintf(cgpath, sizeof(cgpath), "/proc/%d/cgroup", pid);
        if (read_file(cgpath, cg, sizeof(cg)) < 0) { snprintf(cg, sizeof(cg), "-"); errors++; }
        for (char *q = cg; *q; q++) if (*q == '\n' || *q == '\r' || *q == '\t' || *q == ' ') *q = '|';
        printf("CGFREEZER_PROC_SNAPSHOT_ENTRY package="); sanitize_print(pkg);
        printf(" user=%d pid=%d ppid=0 uid=%d state=%c oomAdj=%d frozen=unknown process=", user_id, pid, uid, proc_state_char(pid), read_oom_score_adj(pid)); sanitize_print(process);
        printf(" cgroup="); sanitize_print(cg); printf("\n");
        rows++;
    }
    closedir(dir);
    printf("CGFREEZER_PROC_SNAPSHOT_DONE ok=true package="); sanitize_print(pkg); printf(" user=%d rows=%d errors=%d hash=0 elapsedMs=%ld\n", user_id, rows, errors, now_ms() - start);
    return 0;
}

static int handle_daemon_command_line(char *line) {
    char *argv[8] = {0};
    int argc = tokenize_line(line, argv, 8);
    if (argc <= 0) {
        printf("CGFREEZER_DAEMON_RESULT ok=false reason=empty\n");
        return 64;
    }
    if (strcmp(argv[0], "HELLO") == 0) {
        printf("CGFREEZER_DAEMON_HELLO ok=true version=%s pid=%d protocol=%s parentDirect=false\n", CGFREEZER_VERSION, getpid(), CGFREEZER_PROTOCOL);
        return 0;
    }
    if (strcmp(argv[0], "CAPS") == 0) {
        printf("CGFREEZER_DAEMON_CAPS ok=true version=%s protocol=%s caps=%s\n", CGFREEZER_VERSION, CGFREEZER_PROTOCOL, cgfreezer_caps());
        return 0;
    }
    if (strcmp(argv[0], "BACKEND_PROBE") == 0) {
        return cmd_backend_probe();
    }
    if (strcmp(argv[0], "CHECK") == 0 || strcmp(argv[0], "CHECK_ROOT") == 0) {
        return cmd_check_root();
    }
    if (strcmp(argv[0], "SCAN") == 0) {
        if (argc < 3) { printf("CGFREEZER_SCAN_DONE ok=false reason=bad_args\n"); return 64; }
        int user = parse_int_arg(argv[2], 0);
        return cmd_scan_package(argv[1], user);
    }
    if (strcmp(argv[0], "FREEZE") == 0) {
        if (argc < 3) { printf("CGFREEZER_FREEZE_DONE ok=false reason=bad_args\n"); return 64; }
        int pid = parse_int_arg(argv[1], -1);
        int timeout = parse_int_arg(argv[2], 1500);
        if (pid <= 0) { printf("CGFREEZER_FREEZE_DONE ok=false reason=bad_pid pid=%d\n", pid); return 64; }
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_freeze_pid((pid_t)pid, timeout);
    }
    if (strcmp(argv[0], "FREEZE_PKG") == 0) {
        if (argc < 4) { printf("CGFREEZER_FREEZE_PKG_DONE ok=false reason=bad_args\n"); return 64; }
        int user = parse_int_arg(argv[2], 0);
        int timeout = parse_int_arg(argv[3], 1500);
        return cmd_freeze_package(argv[1], user, timeout);
    }
    if (strcmp(argv[0], "KILL_PKG") == 0) {
        if (argc < 5) { printf("CGFREEZER_KILL_PKG_DONE ok=false reason=bad_args\n"); return 64; }
        int user = parse_int_arg(argv[2], 0);
        int event_pid = parse_int_arg(argv[3], -1);
        int timeout = parse_int_arg(argv[4], 800);
        return cmd_kill_package(argv[1], user, event_pid, timeout);
    }
    if (strcmp(argv[0], "THAW") == 0) {
        if (argc < 4) { printf("CGFREEZER_THAW_DONE ok=false reason=bad_args\n"); return 64; }
        char target = argv[2][0];
        int timeout = parse_int_arg(argv[3], 1500);
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_thaw_path(argv[1], target, timeout);
    }
    if (strcmp(argv[0], "THAW_PID") == 0) {
        if (argc < 5) { printf("CGFREEZER_THAW_DONE ok=false reason=bad_args\n"); return 64; }
        int pid = parse_int_arg(argv[1], -1);
        char target = argv[3][0];
        int timeout = parse_int_arg(argv[4], 1500);
        if (pid <= 0) { printf("CGFREEZER_THAW_DONE ok=false reason=bad_pid pid=%d\n", pid); return 64; }
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_thaw_pid((pid_t)pid, argv[2], target, timeout);
    }
    if (strcmp(argv[0], "THAW_UID") == 0) {
        if (argc < 3) { printf("CGFREEZER_THAW_UID_DONE ok=false reason=bad_args\n"); return 64; }
        int uid = parse_int_arg(argv[1], -1);
        int timeout = parse_int_arg(argv[2], 1500);
        return cmd_thaw_uid(uid, timeout);
    }
    if (strcmp(argv[0], "WCHAN_PID_LIST") == 0) {
        if (argc < 3) { printf("CGFREEZER_WCHAN_DONE ok=false origin=pid-list reason=bad_args\n"); return 64; }
        int user = parse_int_arg(argv[1], -1);
        const char *expect = argc >= 4 ? argv[3] : "any";
        return cmd_wchan_pid_list(user, argv[2], expect);
    }
    if (strcmp(argv[0], "WCHAN_UID") == 0) {
        if (argc < 2) { printf("CGFREEZER_WCHAN_UID_DONE ok=false reason=bad_args\n"); return 64; }
        int uid = parse_int_arg(argv[1], -1);
        const char *expect = argc >= 3 ? argv[2] : "any";
        return cmd_wchan_uid(uid, expect);
    }
    if (strcmp(argv[0], "BINDER_INFO") == 0) {
        if (argc < 2) { printf("CGFREEZER_BINDER_INFO ok=false reason=bad_args\n"); return 64; }
        int pid = parse_int_arg(argv[1], -1);
        if (pid <= 0) { printf("CGFREEZER_BINDER_INFO ok=false reason=bad_pid pid=%d\n", pid); return 64; }
        return cmd_binder_info((pid_t)pid);
    }
    if (strcmp(argv[0], "SUBSCRIBE") == 0) {
        if (argc < 4) { printf("CGFREEZER_LOGD_WATCH_DONE ok=false reason=bad_args\n"); return 64; }
        int user = parse_int_arg(argv[2], 0);
        int duration = parse_int_arg(argv[3], 0);
        if (duration < 0) duration = 0;
        return cmd_watch_logd(argv[1], user, duration);
    }
    if (strcmp(argv[0], "EXIT") == 0 || strcmp(argv[0], "STOP") == 0) {
        printf("CGFREEZER_DAEMON_EXIT ok=true pid=%d\n", getpid());
        g_running = 0;
        return 0;
    }
    printf("CGFREEZER_DAEMON_RESULT ok=false reason=unknown_command command="); sanitize_print(argv[0]); printf("\n");
    return 64;
}

static void daemon_stat_note_done(int cls, long elapsed_ms, int failed);

static void daemon_child_add(pid_t pid, int cls, long start_ms) {
    if (pid <= 0) return;
    for (int i = 0; i < MAX_DAEMON_CHILDREN; ++i) {
        if (g_daemon_children[i] == 0) {
            g_daemon_children[i] = pid;
            g_daemon_child_class[i] = cls;
            g_daemon_child_start_ms[i] = start_ms;
            g_daemon_active_children++;
            return;
        }
    }
}

static void daemon_child_remove(pid_t pid, int status) {
    if (pid <= 0) return;
    for (int i = 0; i < MAX_DAEMON_CHILDREN; ++i) {
        if (g_daemon_children[i] == pid) {
            long elapsed = g_daemon_child_start_ms[i] > 0 ? now_ms() - g_daemon_child_start_ms[i] : 0;
            int failed = !(WIFEXITED(status) && WEXITSTATUS(status) == 0);
            daemon_stat_note_done(g_daemon_child_class[i], elapsed, failed);
            g_daemon_children[i] = 0;
            g_daemon_child_class[i] = 0;
            g_daemon_child_start_ms[i] = 0;
            if (g_daemon_active_children > 0) g_daemon_active_children--;
            return;
        }
    }
}

static void reap_children_nonblock(void) {
    int status = 0;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) daemon_child_remove(pid, status);
}

static void daemon_stop_children_bounded(void) {
    for (int i = 0; i < MAX_DAEMON_CHILDREN; ++i) if (g_daemon_children[i] > 0) kill(g_daemon_children[i], SIGTERM);
    long deadline = now_ms() + 500;
    while (g_daemon_active_children > 0 && now_ms() < deadline) {
        reap_children_nonblock();
        sleep_ms(10);
    }
    for (int i = 0; i < MAX_DAEMON_CHILDREN; ++i) if (g_daemon_children[i] > 0) kill(g_daemon_children[i], SIGKILL);
    deadline = now_ms() + 200;
    while (g_daemon_active_children > 0 && now_ms() < deadline) {
        reap_children_nonblock();
        sleep_ms(10);
    }
    reap_children_nonblock();
}

static int parent_tokenize(const char *line, char *buf, size_t cap, char **argv, int max_args) {
    if (!line || !buf || cap == 0) return 0;
    snprintf(buf, cap, "%s", line);
    return tokenize_line(buf, argv, max_args);
}



static int daemon_cmd_class(const char *cmd) {
    if (!cmd || !*cmd) return 0;
    if (strcmp(cmd, "FREEZE") == 0 || strcmp(cmd, "FREEZE_PID_LIST") == 0) return 1;
    if (strcmp(cmd, "FREEZE_PKG") == 0) return 2;
    if (strcmp(cmd, "KILL_PKG") == 0 || strcmp(cmd, "KILL_PID_LIST") == 0) return 3;
    if (strncmp(cmd, "THAW", 4) == 0) return 4;
    if (strcmp(cmd, "SCAN") == 0 || strcmp(cmd, "PROC_SNAPSHOT") == 0 || strcmp(cmd, "WCHAN_PID_LIST") == 0 || strcmp(cmd, "WCHAN_UID") == 0 || strcmp(cmd, "SUBSCRIBE") == 0) return 5;
    if (strcmp(cmd, "HELLO") == 0 || strcmp(cmd, "CAPS") == 0 || strcmp(cmd, "PING") == 0 || strcmp(cmd, "STATUS") == 0 || strcmp(cmd, "STATS") == 0 || strcmp(cmd, "STATS_DETAIL") == 0 || strcmp(cmd, "LAST_ERROR") == 0) return 7;
    return 0;
}

static void daemon_stat_note_start(int cls) {
    if (cls < 0 || cls >= CGSTAT_CLASSES) cls = 0;
    g_stat_detail_count[cls]++;
}

static void daemon_stat_note_done(int cls, long elapsed_ms, int failed) {
    if (cls < 0 || cls >= CGSTAT_CLASSES) cls = 0;
    if (elapsed_ms < 0) elapsed_ms = 0;
    g_stat_detail_completed[cls]++;
    if (failed) g_stat_detail_failed[cls]++;
    g_stat_detail_total_ms[cls] += elapsed_ms;
    g_stat_detail_last_ms[cls] = elapsed_ms;
    if (g_stat_detail_min_ms[cls] == 0 || elapsed_ms < g_stat_detail_min_ms[cls]) g_stat_detail_min_ms[cls] = elapsed_ms;
    if (elapsed_ms > g_stat_detail_max_ms[cls]) g_stat_detail_max_ms[cls] = elapsed_ms;
}

static int daemon_class_from_line(const char *line, char *cmd_out, size_t cmd_cap) {
    char buf[4096];
    char *argv[2] = {0};
    int argc;
    if (cmd_out && cmd_cap > 0) cmd_out[0] = '\0';
    if (!line) return 0;
    argc = parent_tokenize(line, buf, sizeof(buf), argv, 2);
    if (argc <= 0 || !argv[0]) return 0;
    if (cmd_out && cmd_cap > 0) snprintf(cmd_out, cmd_cap, "%s", argv[0]);
    return daemon_cmd_class(argv[0]);
}

static void daemon_note_command(const char *line) {
    char buf[4096];
    char *argv[2] = {0};
    int argc;
    if (!line) return;
    argc = parent_tokenize(line, buf, sizeof(buf), argv, 2);
    if (argc <= 0 || !argv[0]) return;
    snprintf(g_daemon_last_command, sizeof(g_daemon_last_command), "%s", argv[0]);
    if (strcmp(argv[0], "FREEZE") == 0) g_stat_freeze++;
    else if (strcmp(argv[0], "FREEZE_PKG") == 0) g_stat_freeze_pkg++;
    else if (strcmp(argv[0], "KILL_PKG") == 0 || strcmp(argv[0], "KILL_PID_LIST") == 0) g_stat_kill_pkg++;
    else if (strcmp(argv[0], "FREEZE_PID_LIST") == 0) g_stat_freeze++;
    else if (strcmp(argv[0], "PROC_SNAPSHOT") == 0 || strcmp(argv[0], "WCHAN_PID_LIST") == 0 || strcmp(argv[0], "WCHAN_UID") == 0) g_stat_scan++;
    else if (strncmp(argv[0], "THAW", 4) == 0) g_stat_thaw++;
    else if (strcmp(argv[0], "SCAN") == 0) g_stat_scan++;
}

static bool handle_daemon_parent_command(int cfd, const char *line, bool *stop_out) {
    char buf[4096];
    char *argv[8] = {0};
    int argc = parent_tokenize(line, buf, sizeof(buf), argv, 8);
    if (argc <= 0) return false;
    const char *cmd = argv[0];
    if (strcmp(cmd, "HELLO") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_HELLO ok=true version=%s pid=%d protocol=%s parentDirect=true\n", CGFREEZER_VERSION, getpid(), CGFREEZER_PROTOCOL);
        return true;
    }
    if (strcmp(cmd, "CAPS") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_CAPS ok=true version=%s protocol=%s caps=%s parentDirect=true\n", CGFREEZER_VERSION, CGFREEZER_PROTOCOL, cgfreezer_caps());
        return true;
    }
    if (strcmp(cmd, "PING") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_PONG ok=true version=%s pid=%d uptimeMs=%ld activeChildren=%d\n",
                CGFREEZER_VERSION, getpid(), g_daemon_started_ms > 0 ? now_ms() - g_daemon_started_ms : 0L, g_daemon_active_children);
        return true;
    }
    if (strcmp(cmd, "STATUS") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_STATUS ok=true version=%s pid=%d protocol=plain-lines-r253 lineProtocol=%s uptimeMs=%ld requests=%lu directRequests=%lu workerRequests=%lu activeChildren=%d socket=%s running=%d freeze=%lu freezePkg=%lu killPkg=%lu thaw=%lu scan=%lu lastCommand=%s lastError=%s hash=0 policy=facts-only\n",
                CGFREEZER_VERSION, getpid(), CGFREEZER_PROTOCOL,
                g_daemon_started_ms > 0 ? now_ms() - g_daemon_started_ms : 0L,
                g_daemon_requests, g_daemon_direct_requests, g_daemon_worker_requests,
                g_daemon_active_children, g_daemon_socket_path[0] ? g_daemon_socket_path : "-", g_running ? 1 : 0,
                g_stat_freeze, g_stat_freeze_pkg, g_stat_kill_pkg, g_stat_thaw, g_stat_scan,
                g_daemon_last_command[0] ? g_daemon_last_command : "none", g_daemon_last_error[0] ? g_daemon_last_error : "none");
        dprintf(cfd, "CGFREEZER_DAEMON_STATUS_END ok=true rows=1\n");
        return true;
    }
    if (strcmp(cmd, "STATS") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_STATS ok=true version=%s pid=%d uptimeMs=%ld protocol=plain-lines-r253 hash=0 policy=facts-only\n",
                CGFREEZER_VERSION, getpid(), g_daemon_started_ms > 0 ? now_ms() - g_daemon_started_ms : 0L);
        dprintf(cfd, "CGFREEZER_DAEMON_STATS_ROW class=summary requests=%lu directRequests=%lu workerRequests=%lu activeChildren=%d freeze=%lu freezePkg=%lu killPkg=%lu thaw=%lu scan=%lu lastCommand=%s\n",
                g_daemon_requests, g_daemon_direct_requests, g_daemon_worker_requests, g_daemon_active_children,
                g_stat_freeze, g_stat_freeze_pkg, g_stat_kill_pkg, g_stat_thaw, g_stat_scan,
                g_daemon_last_command[0] ? g_daemon_last_command : "none");
        dprintf(cfd, "CGFREEZER_DAEMON_STATS_END ok=true rows=1\n");
        return true;
    }
    if (strcmp(cmd, "STATS_DETAIL") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_STATS_DETAIL ok=true version=%s pid=%d uptimeMs=%ld protocol=plain-lines-r253 hash=0 policy=facts-only\n",
                CGFREEZER_VERSION, getpid(), g_daemon_started_ms > 0 ? now_ms() - g_daemon_started_ms : 0L);
        for (int i = 0; i < CGSTAT_CLASSES; ++i) {
            long avg = g_stat_detail_completed[i] ? (g_stat_detail_total_ms[i] / (long)g_stat_detail_completed[i]) : 0;
            dprintf(cfd, "CGFREEZER_DAEMON_STATS_DETAIL_ROW class=%s count=%lu completed=%lu failed=%lu minMs=%ld avgMs=%ld p95Ms=%ld maxMs=%ld lastMs=%ld\n",
                    g_stat_class_names[i], g_stat_detail_count[i], g_stat_detail_completed[i], g_stat_detail_failed[i],
                    g_stat_detail_min_ms[i], avg, g_stat_detail_max_ms[i], g_stat_detail_max_ms[i], g_stat_detail_last_ms[i]);
        }
        dprintf(cfd, "CGFREEZER_DAEMON_STATS_DETAIL_END ok=true rows=%d\n", CGSTAT_CLASSES);
        return true;
    }
    if (strcmp(cmd, "LAST_ERROR") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_LAST_ERROR ok=true version=%s pid=%d protocol=plain-lines-r253 lastError=%s lastCommand=%s hash=0 policy=facts-only\n",
                CGFREEZER_VERSION, getpid(), g_daemon_last_error[0] ? g_daemon_last_error : "none",
                g_daemon_last_command[0] ? g_daemon_last_command : "none");
        dprintf(cfd, "CGFREEZER_DAEMON_LAST_ERROR_END ok=true rows=1\n");
        return true;
    }
    if (strcmp(cmd, "STOP") == 0 || strcmp(cmd, "EXIT") == 0) {
        dprintf(cfd, "CGFREEZER_DAEMON_EXIT ok=true version=%s pid=%d protocol=%s parentDirect=true activeChildren=%d\n",
                CGFREEZER_VERSION, getpid(), CGFREEZER_PROTOCOL, g_daemon_active_children);
        if (stop_out) *stop_out = true;
        return true;
    }
    return false;
}

static int cmd_daemon(const char *sock_path) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (!sock_path || !*sock_path || strlen(sock_path) >= sizeof(((struct sockaddr_un*)0)->sun_path)) {
        printf("CGFREEZER_DAEMON_START ok=false reason=bad_socket_path\n");
        return 2;
    }
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGPIPE, SIG_IGN);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        printf("CGFREEZER_DAEMON_START ok=false reason=socket_errno_%d\n", errno);
        return 3;
    }
    unlink(sock_path);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", sock_path);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        int e = errno;
        close(fd);
        printf("CGFREEZER_DAEMON_START ok=false reason=bind_errno_%d socket=", e); sanitize_print(sock_path); printf("\n");
        return 4;
    }
    chmod(sock_path, 0600);
    if (listen(fd, 8) != 0) {
        int e = errno;
        close(fd);
        unlink(sock_path);
        printf("CGFREEZER_DAEMON_START ok=false reason=listen_errno_%d socket=", e); sanitize_print(sock_path); printf("\n");
        return 5;
    }
    g_daemon_started_ms = now_ms();
    g_daemon_requests = 0;
    g_daemon_direct_requests = 0;
    g_daemon_worker_requests = 0;
    g_daemon_active_children = 0;
    g_stat_freeze = 0;
    g_stat_freeze_pkg = 0;
    g_stat_kill_pkg = 0;
    g_stat_thaw = 0;
    g_stat_scan = 0;
    snprintf(g_daemon_last_command, sizeof(g_daemon_last_command), "none");
    snprintf(g_daemon_last_error, sizeof(g_daemon_last_error), "none");
    memset(g_daemon_children, 0, sizeof(g_daemon_children));
    memset(g_daemon_child_start_ms, 0, sizeof(g_daemon_child_start_ms));
    memset(g_daemon_child_class, 0, sizeof(g_daemon_child_class));
    memset(g_stat_detail_count, 0, sizeof(g_stat_detail_count));
    memset(g_stat_detail_completed, 0, sizeof(g_stat_detail_completed));
    memset(g_stat_detail_failed, 0, sizeof(g_stat_detail_failed));
    memset(g_stat_detail_total_ms, 0, sizeof(g_stat_detail_total_ms));
    memset(g_stat_detail_min_ms, 0, sizeof(g_stat_detail_min_ms));
    memset(g_stat_detail_max_ms, 0, sizeof(g_stat_detail_max_ms));
    memset(g_stat_detail_last_ms, 0, sizeof(g_stat_detail_last_ms));
    snprintf(g_daemon_socket_path, sizeof(g_daemon_socket_path), "%s", sock_path);
    printf("CGFREEZER_DAEMON_START ok=true version=%s pid=%d socket=", CGFREEZER_VERSION, getpid()); sanitize_print(sock_path);
    printf(" protocol=%s parentControl=true\n", CGFREEZER_PROTOCOL);
    while (g_running) {
        reap_children_nonblock();
        int cfd = accept4(fd, NULL, NULL, SOCK_CLOEXEC);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            sleep_ms(50);
            continue;
        }
        char line[4096];
        ssize_t n = read(cfd, line, sizeof(line) - 1);
        if (n <= 0) { close(cfd); continue; }
        line[n] = '\0';
        g_daemon_requests++;
        char _cmd_name[64] = {0};
        int _cmd_class = daemon_class_from_line(line, _cmd_name, sizeof(_cmd_name));
        long _cmd_start_ms = now_ms();
        daemon_stat_note_start(_cmd_class);
        daemon_note_command(line);
        bool stop = false;
        if (handle_daemon_parent_command(cfd, line, &stop)) {
            g_daemon_direct_requests++;
            daemon_stat_note_done(_cmd_class, now_ms() - _cmd_start_ms, 0);
            shutdown(cfd, SHUT_WR);
            close(cfd);
            if (stop) g_running = 0;
            continue;
        }
        pid_t child = fork();
        if (child == 0) {
            close(fd);
            dup2(cfd, STDOUT_FILENO);
            dup2(cfd, STDERR_FILENO);
            close(cfd);
            setvbuf(stdout, NULL, _IOLBF, 0);
            int rc = handle_daemon_command_line(line);
            fflush(stdout);
            _exit(rc == 0 ? 0 : (rc & 0xff));
        }
        if (child > 0) {
            g_daemon_worker_requests++;
            daemon_child_add(child, _cmd_class, _cmd_start_ms);
        } else {
            dprintf(cfd, "CGFREEZER_DAEMON_RESULT ok=false reason=fork_errno_%d\n", errno);
        }
        close(cfd);
    }
    close(fd);
    unlink(sock_path);
    daemon_stop_children_bounded();
    printf("CGFREEZER_DAEMON_DONE ok=true version=%s socket=", CGFREEZER_VERSION); sanitize_print(sock_path);
    printf(" requests=%lu directRequests=%lu workerRequests=%lu activeChildren=%d\n",
           g_daemon_requests, g_daemon_direct_requests, g_daemon_worker_requests, g_daemon_active_children);
    return 0;
}

static int parse_int_arg(const char *s, int fallback) {
    if (!s || !*s) return fallback;
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (!end || *end) return fallback;
    if (v < -2147483647L || v > 2147483647L) return fallback;
    return (int)v;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("CGFREEZER_USAGE commands=check-root,backend-probe,scan-package,freeze-pid,freeze-pid-list,freeze-package,kill-pid-list,kill-package,proc-snapshot,proc-wchan,uid-wchan,thaw-path,thaw-pid,thaw-uid,binder-info,watch-logd,daemon\n");
        return 64;
    }
    if (strcmp(argv[1], "check-root") == 0) return cmd_check_root();
    if (strcmp(argv[1], "backend-probe") == 0) return cmd_backend_probe();
    if (strcmp(argv[1], "scan-package") == 0) {
        if (argc < 4) return 64;
        int user = parse_int_arg(argv[3], 0);
        return cmd_scan_package(argv[2], user);
    }
    if (strcmp(argv[1], "freeze-pid") == 0) {
        if (argc < 4) return 64;
        int pid = parse_int_arg(argv[2], -1);
        int timeout = parse_int_arg(argv[3], 1500);
        if (pid <= 0) return 64;
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_freeze_pid((pid_t)pid, timeout);
    }
    if (strcmp(argv[1], "freeze-package") == 0) {
        if (argc < 5) return 64;
        int user = parse_int_arg(argv[3], 0);
        int timeout = parse_int_arg(argv[4], 1500);
        return cmd_freeze_package(argv[2], user, timeout);
    }
    if (strcmp(argv[1], "freeze-pid-list") == 0) {
        if (argc < 5) return 64;
        int user = parse_int_arg(argv[2], 0);
        int timeout = parse_int_arg(argv[4], 1500);
        return cmd_freeze_pid_list(user, argv[3], timeout);
    }
    if (strcmp(argv[1], "kill-package") == 0) {
        if (argc < 6) return 64;
        int user = parse_int_arg(argv[3], 0);
        int event_pid = parse_int_arg(argv[4], -1);
        int timeout = parse_int_arg(argv[5], 800);
        return cmd_kill_package(argv[2], user, event_pid, timeout);
    }
    if (strcmp(argv[1], "kill-pid-list") == 0) {
        if (argc < 5) return 64;
        int user = parse_int_arg(argv[2], 0);
        int sig = parse_int_arg(argv[4], SIGKILL);
        return cmd_kill_pid_list(user, argv[3], sig);
    }
    if (strcmp(argv[1], "proc-snapshot") == 0) {
        if (argc < 4) return 64;
        int user = parse_int_arg(argv[3], 0);
        return cmd_proc_snapshot(argv[2], user);
    }
    if (strcmp(argv[1], "proc-wchan") == 0) {
        if (argc < 4) return 64;
        int user = parse_int_arg(argv[2], -1);
        const char *expect = argc >= 5 ? argv[4] : "any";
        return cmd_wchan_pid_list(user, argv[3], expect);
    }
    if (strcmp(argv[1], "uid-wchan") == 0) {
        if (argc < 3) return 64;
        int uid = parse_int_arg(argv[2], -1);
        const char *expect = argc >= 4 ? argv[3] : "any";
        return cmd_wchan_uid(uid, expect);
    }
    if (strcmp(argv[1], "thaw-path") == 0) {
        if (argc < 5) return 64;
        char target = argv[3][0];
        int timeout = parse_int_arg(argv[4], 1500);
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_thaw_path(argv[2], target, timeout);
    }
    if (strcmp(argv[1], "thaw-pid") == 0) {
        if (argc < 6) return 64;
        int pid = parse_int_arg(argv[2], -1);
        char target = argv[4][0];
        int timeout = parse_int_arg(argv[5], 1500);
        if (pid <= 0) return 64;
        if (timeout < 100 || timeout > 5000) timeout = 1500;
        return cmd_thaw_pid((pid_t)pid, argv[3], target, timeout);
    }
    if (strcmp(argv[1], "thaw-uid") == 0) {
        if (argc < 4) return 64;
        int uid = parse_int_arg(argv[2], -1);
        int timeout = parse_int_arg(argv[3], 1500);
        return cmd_thaw_uid(uid, timeout);
    }
    if (strcmp(argv[1], "binder-info") == 0) {
        if (argc < 3) return 64;
        int pid = parse_int_arg(argv[2], -1);
        if (pid <= 0) return 64;
        return cmd_binder_info((pid_t)pid);
    }
    if (strcmp(argv[1], "watch-logd") == 0) {
        if (argc < 5) return 64;
        int user = parse_int_arg(argv[3], 0);
        int duration = parse_int_arg(argv[4], 0);
        if (duration < 0) duration = 0;
        return cmd_watch_logd(argv[2], user, duration);
    }
    if (strcmp(argv[1], "daemon") == 0) {
        if (argc < 3) return 64;
        return cmd_daemon(argv[2]);
    }
    printf("CGFREEZER_USAGE unknown="); sanitize_print(argv[1]); printf("\n");
    return 64;
}
