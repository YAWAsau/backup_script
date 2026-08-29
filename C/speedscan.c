// SpeedBackup speedscan r470-api28-r28c-complete-native-facts
// Native local scanner for Android/Linux. No libc extensions beyond POSIX dirent/stat.
// Commands:
//   speedscan dir-size PATH
//   speedscan dir-size-map MANIFEST   # manifest: pkg<TAB>type<TAB>path; output: pkg<TAB>type<TAB>bytes
//   speedscan file-list ROOT          # output: rel<TAB>bytes for regular files
//   speedscan list-total-size LIST     # input: absolute file paths; output: total bytes
//   speedscan batch-stat LIST          # output: path<TAB>exists<TAB>type<TAB>mode<TAB>uid<TAB>gid<TAB>size<TAB>mtime
//   speedscan batch-exists LIST        # output: path<TAB>0|1
//   speedscan batch-chmod MODE LIST    # chmod every path from LIST
//   speedscan batch-chown UID GID LIST  # chown every path from LIST
//   speedscan tree-chown UID GID ROOT   # recursive lchown, no symlink follow
//   speedscan tree-fixup UID GID ROOT [DIR_MODE|-] [FILE_MODE|-] # recursive lchown plus optional chmod, no symlink follow
//   speedscan has-files ROOT           # exit 0 and print 1 when regular file exists, else 1/0
//   speedscan manifest ROOT OUT        # recursive manifest
//   speedscan scan-summary ROOT [MANIFEST_OUT|-] # one walk: size/files/dirs/hasFiles/maxMtime + optional manifest, no hash
//   speedscan path-audit ROOT LIST      # facts-only symlink/root escape/mount-cross audit, no hash
//   speedscan label-audit ROOT [MAX_ROWS] # quick SELinux/xattr ownership audit, no hash
//   speedscan facts ROOT [MANIFEST_OUT|-] # unified summary+manifest facts, no hash
//   speedscan restore-facts ROOT [MANIFEST_OUT|-] # restore-tree facts alias, no hash
//   speedscan appdetails-index ROOT OUT [MAXDEPTH] [MINDEPTH] # index app_details.json paths, facts-only
//   speedscan file-list-abs-filter ROOT OUT SKIP_APPDETAILS [EXCLUDE_PREFIX]
//   speedscan selected-list APPLIST BLACKLIST OUT BLACKLIST_MODE
//   speedscan apk-size-map PKG_APK_PATHS OUT
//   speedscan backup-prescan-summary SELECTED DIRSIZES APKMAP RSKIP LSKIP OUT REMOTE_STREAM REMOTE_TYPE
//   speedscan backup-root-index ROOT OUT [MAXDEPTH]
//   speedscan storage-summary PATH       # statvfs + mountinfo; output storage facts TSV
//   speedscan checksum-list ROOT OUT      # native FNV64 facts for regular files
//   speedscan manifest-verify ROOT MANIFEST # native manifest exists/size/mtime verifier
//   speedscan run-tmpdir-facts BASE OUT [PREFIX] # safe facts-only stale run tmpdir inventory

#define _GNU_SOURCE
#define _XOPEN_SOURCE 700
#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <sys/statvfs.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef struct ScanResult {
    uint64_t bytes;
    uint64_t files;
    uint64_t dirs;
    uint64_t errors;
    uint64_t max_mtime;
} ScanResult;

static int join_path(const char *base, const char *name, char *out, size_t out_sz) {
    size_t blen, nlen;
    if (!base || !name || !out || out_sz == 0) return -1;
    blen = strlen(base);
    nlen = strlen(name);
    if (blen + 1 + nlen + 1 > out_sz) return -1;
    memcpy(out, base, blen);
    if (blen > 0 && base[blen - 1] != '/') out[blen++] = '/';
    memcpy(out + blen, name, nlen);
    out[blen + nlen] = '\0';
    return 0;
}


static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)(ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL);
}

static void note_stat(ScanResult *res, const struct stat *st) {
    if (!res || !st) return;
    if ((uint64_t)st->st_mtime > res->max_mtime) res->max_mtime = (uint64_t)st->st_mtime;
    if (S_ISREG(st->st_mode)) {
        res->bytes += (uint64_t)st->st_size;
        res->files++;
    } else if (S_ISDIR(st->st_mode)) {
        res->dirs++;
    }
}

static int scan_dir_size(const char *path, ScanResult *res) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];

    if (!path || !res) return -1;
    if (lstat(path, &st) != 0) {
        res->errors++;
        return -1;
    }
    if (S_ISREG(st.st_mode)) {
        note_stat(res, &st);
        return 0;
    }
    if (!S_ISDIR(st.st_mode)) {
        if ((uint64_t)st.st_mtime > res->max_mtime) res->max_mtime = (uint64_t)st.st_mtime;
        return 0;
    }

    dir = opendir(path);
    if (!dir) {
        res->errors++;
        return -1;
    }
    note_stat(res, &st);
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) {
            res->errors++;
            continue;
        }
        if (lstat(child, &st) != 0) {
            res->errors++;
            continue;
        }
        if (S_ISREG(st.st_mode)) {
            note_stat(res, &st);
        } else if (S_ISDIR(st.st_mode)) {
            scan_dir_size(child, res);
        } else {
            if ((uint64_t)st.st_mtime > res->max_mtime) res->max_mtime = (uint64_t)st.st_mtime;
        }
    }
    closedir(dir);
    return 0;
}

static int cmd_dir_size(const char *path) {
    ScanResult res;
    memset(&res, 0, sizeof(res));
    if (!path || !*path) return 2;
    scan_dir_size(path, &res);
    printf("%" PRIu64 "\n", res.bytes);
    return 0;
}

static void trim_line(char *s) {
    size_t n;
    if (!s) return;
    n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) {
        s[--n] = '\0';
    }
}

static int cmd_dir_size_map(const char *manifest) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;

    if (!manifest || !*manifest) return 2;
    fp = fopen(manifest, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open manifest failed: %s: %s\n", manifest, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        char *pkg, *type, *path, *tab1, *tab2;
        ScanResult res;
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        pkg = line;
        tab1 = strchr(pkg, '\t');
        if (!tab1) { rc = 4; continue; }
        *tab1 = '\0';
        type = tab1 + 1;
        tab2 = strchr(type, '\t');
        if (!tab2) { rc = 4; continue; }
        *tab2 = '\0';
        path = tab2 + 1;
        memset(&res, 0, sizeof(res));
        scan_dir_size(path, &res);
        printf("%s\t%s\t%" PRIu64 "\n", pkg, type, res.bytes);
    }
    free(line);
    fclose(fp);
    return rc;
}

static int file_list_walk(const char *root, const char *path, size_t root_len) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];

    if (lstat(path, &st) != 0) return 1;
    if (S_ISREG(st.st_mode)) {
        const char *rel = path + root_len;
        if (*rel == '/') rel++;
        printf("%s\t%" PRIu64 "\n", rel, (uint64_t)st.st_size);
        return 0;
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) return 1;
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) continue;
        file_list_walk(root, child, root_len);
    }
    closedir(dir);
    return 0;
}

static int cmd_file_list(const char *root) {
    size_t root_len;
    if (!root || !*root) return 2;
    root_len = strlen(root);
    while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    return file_list_walk(root, root, root_len);
}


static int cmd_list_total_size(const char *list_path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    uint64_t bytes = 0;
    struct stat st;

    if (!list_path || !*list_path) return 2;
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open list failed: %s: %s\n", list_path, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        if (lstat(line, &st) == 0 && S_ISREG(st.st_mode)) bytes += (uint64_t)st.st_size;
    }
    free(line);
    fclose(fp);
    printf("%" PRIu64 "\n", bytes);
    return 0;
}


static const char *file_type_from_mode(mode_t mode) {
    if (S_ISREG(mode)) return "file";
    if (S_ISDIR(mode)) return "dir";
    if (S_ISLNK(mode)) return "link";
    if (S_ISCHR(mode)) return "char";
    if (S_ISBLK(mode)) return "block";
    if (S_ISFIFO(mode)) return "fifo";
    if (S_ISSOCK(mode)) return "sock";
    return "other";
}



typedef struct LabelAuditResult {
    uint64_t rows;
    uint64_t errors;
    uint64_t missingLabel;
    uint64_t xattrErrors;
    uint64_t truncated;
    uint64_t maxRows;
} LabelAuditResult;

static void print_tsv_sanitized(FILE *out, const char *s) {
    const unsigned char *p = (const unsigned char *)(s ? s : "");
    while (*p) {
        unsigned char c = *p++;
        if (c == '\t' || c == '\n' || c == '\r') fputc('_', out);
        else fputc((int)c, out);
    }
}

static int read_selinux_label(const char *path, char *buf, size_t cap, int *err_out) {
    ssize_t n;
    if (err_out) *err_out = 0;
    if (!buf || cap == 0) return -1;
    buf[0] = '\0';
    if (!path || !*path) { if (err_out) *err_out = EINVAL; return -1; }
    errno = 0;
    n = lgetxattr(path, "security.selinux", buf, cap - 1);
    if (n < 0) {
        if (err_out) *err_out = errno;
        return -1;
    }
    if ((size_t)n >= cap) n = (ssize_t)cap - 1;
    buf[n] = '\0';
    return 0;
}

static long count_xattrs_lite(const char *path, int *err_out) {
    ssize_t n;
    long count = 0;
    char *buf;
    ssize_t i;
    if (err_out) *err_out = 0;
    if (!path || !*path) { if (err_out) *err_out = EINVAL; return -1; }
    errno = 0;
    n = llistxattr(path, NULL, 0);
    if (n < 0) { if (err_out) *err_out = errno; return -1; }
    if (n == 0) return 0;
    if (n > 65536) n = 65536;
    buf = (char *)malloc((size_t)n);
    if (!buf) { if (err_out) *err_out = ENOMEM; return -1; }
    errno = 0;
    n = llistxattr(path, buf, (size_t)n);
    if (n < 0) { if (err_out) *err_out = errno; free(buf); return -1; }
    for (i = 0; i < n; ) {
        size_t len = strlen(buf + i);
        if (len == 0) { i++; continue; }
        count++;
        i += (ssize_t)len + 1;
    }
    free(buf);
    return count;
}

static void label_audit_print_row(const char *root, const char *path, const struct stat *st, int exists, LabelAuditResult *res) {
    char label[256];
    int label_err = 0;
    int xattr_err = 0;
    long xattr_count = -1;
    const char *rel = "";
    size_t root_len = root ? strlen(root) : 0;
    if (path && root && root_len > 0 && strncmp(path, root, root_len) == 0) {
        rel = path + root_len;
        if (*rel == '/') rel++;
    } else if (path) rel = path;
    if (!exists) {
        printf("LABEL_AUDIT_ROW\t"); print_tsv_sanitized(stdout, rel);
        printf("\t0\tmissing\t0000\t0\t0\t0\t0\t-\t-\t0\t%d\n", errno);
        if (res) res->errors++;
        return;
    }
    if (read_selinux_label(path, label, sizeof(label), &label_err) != 0) {
        snprintf(label, sizeof(label), "-");
        if (res) res->missingLabel++;
    }
    xattr_count = count_xattrs_lite(path, &xattr_err);
    if (xattr_count < 0 && res) res->xattrErrors++;
    printf("LABEL_AUDIT_ROW\t"); print_tsv_sanitized(stdout, rel);
    printf("\t1\t%s\t%04o\t%u\t%u\t%llu\t%lld\t",
           st ? file_type_from_mode(st->st_mode) : "missing",
           st ? (unsigned)(st->st_mode & 07777) : 0,
           st ? (unsigned)st->st_uid : 0,
           st ? (unsigned)st->st_gid : 0,
           st ? (unsigned long long)st->st_size : 0ULL,
           st ? (long long)st->st_mtime : 0LL);
    print_tsv_sanitized(stdout, label);
    printf("\t%ld\t%d\t%d\n", xattr_count, label_err, xattr_err);
}

static int label_audit_walk(const char *root, const char *path, LabelAuditResult *res) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    int rc = 0;
    if (!root || !path || !res) return 1;
    if (res->maxRows > 0 && res->rows >= res->maxRows) { res->truncated = 1; return 0; }
    if (lstat(path, &st) != 0) {
        label_audit_print_row(root, path, NULL, 0, res);
        res->rows++;
        return 1;
    }
    label_audit_print_row(root, path, &st, 1, res);
    res->rows++;
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) { res->errors++; return 1; }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (res->maxRows > 0 && res->rows >= res->maxRows) { res->truncated = 1; break; }
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) { res->errors++; rc = 1; continue; }
        if (label_audit_walk(root, child, res) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_label_audit(const char *root, const char *max_rows_s) {
    LabelAuditResult res;
    struct stat st;
    long start = now_ms();
    char *end = NULL;
    memset(&res, 0, sizeof(res));
    res.maxRows = 4096;
    if (max_rows_s && *max_rows_s) {
        errno = 0;
        unsigned long long v = strtoull(max_rows_s, &end, 10);
        if (errno == 0 && end && *end == '\0' && v > 0) res.maxRows = (uint64_t)v;
    }
    if (!root || !*root || lstat(root, &st) != 0) {
        printf("LABEL_AUDIT_SUMMARY ok=false root="); print_tsv_sanitized(stdout, root ? root : "");
        printf(" rows=0 errors=1 missingLabel=0 xattrErrors=0 truncated=0 maxRows=%llu hash=0 reason=stat_errno_%d elapsedMs=%ld\n",
               (unsigned long long)res.maxRows, errno, now_ms() - start);
        return 1;
    }
    int rc = label_audit_walk(root, root, &res);
    printf("LABEL_AUDIT_SUMMARY ok=%s root=", (rc == 0 && res.errors == 0) ? "true" : "false");
    print_tsv_sanitized(stdout, root);
    printf(" rows=%llu errors=%llu missingLabel=%llu xattrErrors=%llu truncated=%llu maxRows=%llu hash=0 policy=facts-only elapsedMs=%ld\n",
           (unsigned long long)res.rows, (unsigned long long)res.errors,
           (unsigned long long)res.missingLabel, (unsigned long long)res.xattrErrors,
           (unsigned long long)res.truncated, (unsigned long long)res.maxRows, now_ms() - start);
    return (rc == 0 && res.errors == 0) ? 0 : 1;
}

static int facts_walk(FILE *manifest, const char *root, const char *path, size_t root_len, ScanResult *res) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    const char *rel;
    int rc = 0;
    if (!path || !res || lstat(path, &st) != 0) { if (res) res->errors++; return 1; }
    rel = path + root_len;
    if (*rel == '/') rel++;
    note_stat(res, &st);
    if (manifest && *rel != '\0') {
        fprintf(manifest, "FACT_ROW\t%s\t%s\t%04o\t%u\t%u\t%" PRIu64 "\t%lld\t%llu\t%llu\t%llu\n",
                rel, file_type_from_mode(st.st_mode), (unsigned)(st.st_mode & 07777),
                (unsigned)st.st_uid, (unsigned)st.st_gid, (uint64_t)st.st_size, (long long)st.st_mtime,
                (unsigned long long)st.st_dev, (unsigned long long)st.st_ino, (unsigned long long)st.st_nlink);
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) { res->errors++; return 1; }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) { res->errors++; rc = 1; continue; }
        if (facts_walk(manifest, root, child, root_len, res) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_facts(const char *root, const char *facts_out) {
    FILE *manifest = NULL;
    ScanResult res;
    struct stat st;
    size_t root_len;
    long start = now_ms();
    int rc;
    if (!root || !*root) return 2;
    if (lstat(root, &st) != 0) {
        printf("FACTS_SUMMARY ok=false root=%s exists=0 type=missing bytes=0 files=0 dirs=0 hasFiles=0 maxMtime=0 errors=1 hash=0 reason=stat_errno_%d elapsedMs=%ld\n",
               root, errno, now_ms() - start);
        return 1;
    }
    if (facts_out && *facts_out && strcmp(facts_out, "-") != 0) {
        manifest = fopen(facts_out, "wb");
        if (!manifest) {
            fprintf(stderr, "speedscan: open facts output failed: %s: %s\n", facts_out, strerror(errno));
            return 3;
        }
    }
    memset(&res, 0, sizeof(res));
    root_len = strlen(root);
    while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    rc = facts_walk(manifest, root, root, root_len, &res);
    if (manifest) fclose(manifest);
    printf("FACTS_SUMMARY ok=%s root=%s exists=1 type=%s bytes=%" PRIu64 " files=%" PRIu64 " dirs=%" PRIu64 " hasFiles=%d maxMtime=%" PRIu64 " errors=%" PRIu64 " hash=0 policy=facts-only elapsedMs=%ld\n",
           rc == 0 ? "true" : "false", root, file_type_from_mode(st.st_mode), res.bytes, res.files, res.dirs,
           res.files > 0 ? 1 : 0, res.max_mtime, res.errors, now_ms() - start);
    return rc;
}

static int parse_octal_mode(const char *s, mode_t *out) {
    char *end = NULL;
    long v;
    if (!s || !*s || !out) return -1;
    errno = 0;
    v = strtol(s, &end, 8);
    if (errno != 0 || !end || *end != '\0' || v < 0 || v > 07777) return -1;
    *out = (mode_t)v;
    return 0;
}

static int parse_uint_id(const char *s, uid_t *out) {
    char *end = NULL;
    unsigned long v;
    if (!s || !*s || !out) return -1;
    errno = 0;
    v = strtoul(s, &end, 10);
    if (errno != 0 || !end || *end != '\0') return -1;
    *out = (uid_t)v;
    return 0;
}

static int cmd_batch_stat(const char *list_path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;
    struct stat st;

    if (!list_path || !*list_path) return 2;
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open list failed: %s: %s\n", list_path, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        if (lstat(line, &st) == 0) {
            printf("%s\t1\t%s\t%04o\t%u\t%u\t%" PRIu64 "\t%lld\t0\t%llu\t%llu\t%llu\n",
                   line, file_type_from_mode(st.st_mode), (unsigned)(st.st_mode & 07777),
                   (unsigned)st.st_uid, (unsigned)st.st_gid, (uint64_t)st.st_size, (long long)st.st_mtime,
                   (unsigned long long)st.st_dev, (unsigned long long)st.st_ino, (unsigned long long)st.st_nlink);
        } else {
            int e = errno;
            printf("%s\t0\tmissing\t0000\t0\t0\t0\t0\t%d\t0\t0\t0\n", line, e);
            rc = 1;
        }
    }
    free(line);
    fclose(fp);
    return rc;
}

static int cmd_batch_exists(const char *list_path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;
    struct stat st;

    if (!list_path || !*list_path) return 2;
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open list failed: %s: %s\n", list_path, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        if (lstat(line, &st) == 0) {
            printf("%s\t1\n", line);
        } else {
            printf("%s\t0\n", line);
            rc = 1;
        }
    }
    free(line);
    fclose(fp);
    return rc;
}

static int cmd_batch_chmod(const char *mode_s, const char *list_path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;
    mode_t mode;
    struct stat before;
    struct stat after;
    int e;

    if (parse_octal_mode(mode_s, &mode) != 0) return 2;
    if (!list_path || !*list_path) return 2;
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open list failed: %s: %s\n", list_path, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        memset(&before, 0, sizeof(before));
        memset(&after, 0, sizeof(after));
        if (lstat(line, &before) != 0) {
            e = errno;
            printf("%s\t0\tchmod\t0000\t%04o\t%d\t%s\n", line, (unsigned)(mode & 07777), e, strerror(e));
            rc = 1;
            continue;
        }
        if (chmod(line, mode) != 0) {
            e = errno;
            printf("%s\t0\tchmod\t%04o\t%04o\t%d\t%s\n", line, (unsigned)(before.st_mode & 07777), (unsigned)(mode & 07777), e, strerror(e));
            rc = 1;
            continue;
        }
        if (lstat(line, &after) != 0) {
            e = errno;
            printf("%s\t0\tchmod\t%04o\t%04o\t%d\t%s\n", line, (unsigned)(before.st_mode & 07777), (unsigned)(mode & 07777), e, strerror(e));
            rc = 1;
            continue;
        }
        printf("%s\t1\tchmod\t%04o\t%04o\t0\tOK\n", line, (unsigned)(before.st_mode & 07777), (unsigned)(after.st_mode & 07777));
    }
    free(line);
    fclose(fp);
    return rc;
}

static int cmd_batch_chown(const char *uid_s, const char *gid_s, const char *list_path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;
    uid_t uid;
    uid_t gid_tmp;
    gid_t gid;
    struct stat before;
    struct stat after;
    int e;

    if (parse_uint_id(uid_s, &uid) != 0) return 2;
    if (parse_uint_id(gid_s, &gid_tmp) != 0) return 2;
    gid = (gid_t)gid_tmp;
    if (!list_path || !*list_path) return 2;
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open list failed: %s: %s\n", list_path, strerror(errno));
        return 3;
    }
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        memset(&before, 0, sizeof(before));
        memset(&after, 0, sizeof(after));
        if (lstat(line, &before) != 0) {
            e = errno;
            printf("%s\t0\tchown\t0\t0\t%u\t%u\t%d\t%s\n", line, (unsigned)uid, (unsigned)gid, e, strerror(e));
            rc = 1;
            continue;
        }
        if (lchown(line, uid, gid) != 0) {
            e = errno;
            printf("%s\t0\tchown\t%u\t%u\t%u\t%u\t%d\t%s\n", line, (unsigned)before.st_uid, (unsigned)before.st_gid, (unsigned)uid, (unsigned)gid, e, strerror(e));
            rc = 1;
            continue;
        }
        if (lstat(line, &after) != 0) {
            e = errno;
            printf("%s\t0\tchown\t%u\t%u\t%u\t%u\t%d\t%s\n", line, (unsigned)before.st_uid, (unsigned)before.st_gid, (unsigned)uid, (unsigned)gid, e, strerror(e));
            rc = 1;
            continue;
        }
        printf("%s\t1\tchown\t%u\t%u\t%u\t%u\t0\tOK\n", line, (unsigned)before.st_uid, (unsigned)before.st_gid, (unsigned)after.st_uid, (unsigned)after.st_gid);
    }
    free(line);
    fclose(fp);
    return rc;
}

static int has_files_walk(const char *path) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    int hit = 0;

    if (!path || !*path) return 0;
    if (lstat(path, &st) != 0) return 0;
    if (S_ISREG(st.st_mode)) return 1;
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) return 0;
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) continue;
        if (has_files_walk(child)) { hit = 1; break; }
    }
    closedir(dir);
    return hit;
}

static int cmd_has_files(const char *root) {
    int hit = has_files_walk(root);
    printf("%d\n", hit ? 1 : 0);
    return hit ? 0 : 1;
}

static int tree_chown_walk(const char *path, uid_t uid, gid_t gid, uint64_t *changed, uint64_t *errors) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    int rc = 0;

    if (!path || !*path || !changed || !errors) return 2;
    if (lstat(path, &st) != 0) {
        (*errors)++;
        return 1;
    }
    if (lchown(path, uid, gid) != 0) {
        (*errors)++;
        rc = 1;
    } else {
        (*changed)++;
    }
    if (!S_ISDIR(st.st_mode)) return rc;
    dir = opendir(path);
    if (!dir) {
        (*errors)++;
        return 1;
    }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) {
            (*errors)++;
            rc = 1;
            continue;
        }
        if (tree_chown_walk(child, uid, gid, changed, errors) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_tree_chown(const char *uid_s, const char *gid_s, const char *root) {
    uid_t uid;
    uid_t gid_tmp;
    gid_t gid;
    uint64_t changed = 0;
    uint64_t errors = 0;
    int rc;

    if (parse_uint_id(uid_s, &uid) != 0) return 2;
    if (parse_uint_id(gid_s, &gid_tmp) != 0) return 2;
    gid = (gid_t)gid_tmp;
    if (!root || !*root) return 2;
    rc = tree_chown_walk(root, uid, gid, &changed, &errors);
    printf("TREE_CHOWN_SUMMARY changed=%" PRIu64 "\terrors=%" PRIu64 "\thash=0\tpolicy=facts-only\n", changed, errors);
    return rc;
}


typedef struct FixupResult {
    uint64_t visited;
    uint64_t chownChanged;
    uint64_t chownSkipped;
    uint64_t chmodChanged;
    uint64_t chmodSkipped;
    uint64_t typeSkipped;
    uint64_t symlinkSkipped;
    uint64_t errors;
    uint64_t chownMs;
    uint64_t chmodMs;
} FixupResult;

static int tree_fixup_walk(const char *path, uid_t uid, gid_t gid, int do_dir_mode, mode_t dir_mode, int do_file_mode, mode_t file_mode, FixupResult *res) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    int rc = 0;
    mode_t target_mode;
    long op_start;

    if (!path || !*path || !res) return 2;
    if (lstat(path, &st) != 0) {
        res->errors++;
        return 1;
    }
    res->visited++;

    /* r338: strict no-symlink-follow policy. Do not chown/chmod symlinks or their targets. */
    if (S_ISLNK(st.st_mode)) {
        res->symlinkSkipped++;
        return 0;
    }

    if ((uid_t)st.st_uid != uid || (gid_t)st.st_gid != gid) {
        op_start = now_ms();
        if (lchown(path, uid, gid) != 0) {
            res->errors++;
            rc = 1;
        } else {
            res->chownChanged++;
        }
        res->chownMs += (uint64_t)(now_ms() - op_start);
    } else {
        res->chownSkipped++;
    }

    if (S_ISDIR(st.st_mode) && do_dir_mode) {
        target_mode = (st.st_mode & ~07777) | (dir_mode & 07777);
        if ((st.st_mode & 07777) != (dir_mode & 07777)) {
            op_start = now_ms();
            if (chmod(path, target_mode & 07777) != 0) { res->errors++; rc = 1; }
            else res->chmodChanged++;
            res->chmodMs += (uint64_t)(now_ms() - op_start);
        } else res->chmodSkipped++;
    } else if (S_ISREG(st.st_mode) && do_file_mode) {
        target_mode = (st.st_mode & ~07777) | (file_mode & 07777);
        if ((st.st_mode & 07777) != (file_mode & 07777)) {
            op_start = now_ms();
            if (chmod(path, target_mode & 07777) != 0) { res->errors++; rc = 1; }
            else res->chmodChanged++;
            res->chmodMs += (uint64_t)(now_ms() - op_start);
        } else res->chmodSkipped++;
    } else {
        res->typeSkipped++;
    }
    if (!S_ISDIR(st.st_mode)) return rc;
    dir = opendir(path);
    if (!dir) {
        res->errors++;
        return 1;
    }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) {
            res->errors++;
            rc = 1;
            continue;
        }
        if (tree_fixup_walk(child, uid, gid, do_dir_mode, dir_mode, do_file_mode, file_mode, res) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int parse_optional_mode(const char *s, int *enabled, mode_t *out) {
    if (!s || !*s || strcmp(s, "-") == 0 || strcmp(s, "none") == 0) { *enabled = 0; *out = 0; return 0; }
    if (parse_octal_mode(s, out) != 0) return -1;
    *enabled = 1;
    return 0;
}

static int cmd_tree_fixup(const char *uid_s, const char *gid_s, const char *root, const char *dir_mode_s, const char *file_mode_s) {
    uid_t uid;
    uid_t gid_tmp;
    gid_t gid;
    int do_dir_mode = 0, do_file_mode = 0;
    mode_t dir_mode = 0, file_mode = 0;
    FixupResult res;
    int rc;
    long start = now_ms();

    if (parse_uint_id(uid_s, &uid) != 0) return 2;
    if (parse_uint_id(gid_s, &gid_tmp) != 0) return 2;
    gid = (gid_t)gid_tmp;
    if (!root || !*root) return 2;
    if (parse_optional_mode(dir_mode_s, &do_dir_mode, &dir_mode) != 0) return 2;
    if (parse_optional_mode(file_mode_s, &do_file_mode, &file_mode) != 0) return 2;
    memset(&res, 0, sizeof(res));
    rc = tree_fixup_walk(root, uid, gid, do_dir_mode, dir_mode, do_file_mode, file_mode, &res);
    printf("TREE_FIXUP_SUMMARY visited=%" PRIu64 "\tchownChanged=%" PRIu64 "\tchownSkipped=%" PRIu64 "\tchmodChanged=%" PRIu64 "\tchmodSkipped=%" PRIu64 "\ttypeSkipped=%" PRIu64 "\tsymlinkSkipped=%" PRIu64 "\tmetadataNoop=%" PRIu64 "\tskipped=%" PRIu64 "\terrors=%" PRIu64 "\tchownMs=%" PRIu64 "\tchmodMs=%" PRIu64 "\tdirMode=%s\tfileMode=%s\thash=0\tpolicy=no-symlink-follow\telapsedMs=%ld\n",
           res.visited, res.chownChanged, res.chownSkipped, res.chmodChanged, res.chmodSkipped, res.typeSkipped, res.symlinkSkipped,
           res.chownSkipped + res.chmodSkipped, res.symlinkSkipped, res.errors, res.chownMs, res.chmodMs,
           do_dir_mode ? dir_mode_s : "-", do_file_mode ? file_mode_s : "-", now_ms() - start);
    return rc;
}

static int manifest_walk(FILE *out, const char *root, const char *path, size_t root_len) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    const char *rel;
    int rc = 0;

    if (lstat(path, &st) != 0) return 1;
    rel = path + root_len;
    if (*rel == '/') rel++;
    if (*rel != '\0') {
        fprintf(out, "%s\t%s\t%04o\t%u\t%u\t%" PRIu64 "\t%lld\n",
                rel, file_type_from_mode(st.st_mode), (unsigned)(st.st_mode & 07777),
                (unsigned)st.st_uid, (unsigned)st.st_gid, (uint64_t)st.st_size, (long long)st.st_mtime);
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) return 1;
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) {
            rc = 1;
            continue;
        }
        if (manifest_walk(out, root, child, root_len) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_manifest(const char *root, const char *out_path) {
    FILE *out;
    size_t root_len;
    int rc;
    if (!root || !*root || !out_path || !*out_path) return 2;
    out = fopen(out_path, "wb");
    if (!out) {
        fprintf(stderr, "speedscan: open manifest output failed: %s: %s\n", out_path, strerror(errno));
        return 3;
    }
    root_len = strlen(root);
    while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    rc = manifest_walk(out, root, root, root_len);
    fclose(out);
    return rc;
}


static int scan_summary_walk(FILE *manifest, const char *root, const char *path, size_t root_len, ScanResult *res) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    const char *rel;
    int rc = 0;

    if (!path || !res || lstat(path, &st) != 0) {
        if (res) res->errors++;
        return 1;
    }
    rel = path + root_len;
    if (*rel == '/') rel++;
    if (S_ISREG(st.st_mode) || S_ISDIR(st.st_mode)) {
        note_stat(res, &st);
    } else if ((uint64_t)st.st_mtime > res->max_mtime) {
        res->max_mtime = (uint64_t)st.st_mtime;
    }
    if (manifest && *rel != '\0') {
        fprintf(manifest, "%s\t%s\t%04o\t%u\t%u\t%" PRIu64 "\t%lld\n",
                rel, file_type_from_mode(st.st_mode), (unsigned)(st.st_mode & 07777),
                (unsigned)st.st_uid, (unsigned)st.st_gid, (uint64_t)st.st_size, (long long)st.st_mtime);
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) {
        res->errors++;
        return 1;
    }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) {
            res->errors++;
            rc = 1;
            continue;
        }
        if (scan_summary_walk(manifest, root, child, root_len, res) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_scan_summary(const char *root, const char *manifest_out) {
    FILE *manifest = NULL;
    size_t root_len;
    ScanResult res;
    int rc;
    long start = now_ms();
    struct stat st;

    if (!root || !*root) return 2;
    if (lstat(root, &st) != 0) {
        printf("SCAN_SUMMARY ok=false root=%s exists=0 type=missing bytes=0 files=0 dirs=0 hasFiles=0 maxMtime=0 errors=1 hash=0 reason=stat_errno_%d elapsedMs=%ld\n",
               root, errno, now_ms() - start);
        return 1;
    }
    if (manifest_out && *manifest_out && strcmp(manifest_out, "-") != 0) {
        manifest = fopen(manifest_out, "wb");
        if (!manifest) {
            fprintf(stderr, "speedscan: open scan-summary manifest failed: %s: %s\n", manifest_out, strerror(errno));
            return 3;
        }
    }
    memset(&res, 0, sizeof(res));
    root_len = strlen(root);
    while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    rc = scan_summary_walk(manifest, root, root, root_len, &res);
    if (manifest) fclose(manifest);
    printf("SCAN_SUMMARY ok=%s root=%s exists=1 type=%s bytes=%" PRIu64 " files=%" PRIu64 " dirs=%" PRIu64 " hasFiles=%d maxMtime=%" PRIu64 " errors=%" PRIu64 " hash=0 policy=facts-only elapsedMs=%ld\n",
           rc == 0 ? "true" : "false", root, file_type_from_mode(st.st_mode), res.bytes, res.files, res.dirs,
           res.files > 0 ? 1 : 0, res.max_mtime, res.errors, now_ms() - start);
    return rc;
}


static bool path_under_root(const char *root_real, const char *path_real) {
    size_t n;
    if (!root_real || !path_real) return false;
    n = strlen(root_real);
    if (n == 0) return false;
    if (strcmp(root_real, "/") == 0) return path_real[0] == '/';
    if (strncmp(root_real, path_real, n) != 0) return false;
    return path_real[n] == '\0' || path_real[n] == '/';
}

static int cmd_path_audit(const char *root, const char *list_path) {
    char root_real[PATH_MAX];
    struct stat root_st;
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    int rc = 0;
    long start = now_ms();

    if (!root || !*root || !list_path || !*list_path) return 2;
    if (!realpath(root, root_real) || lstat(root_real, &root_st) != 0 || !S_ISDIR(root_st.st_mode)) {
        printf("PATH_AUDIT_SUMMARY ok=false root=%s rows=0 bad=0 escaped=0 mountCross=0 hash=0 reason=root_invalid elapsedMs=%ld\n", root, now_ms() - start);
        return 3;
    }
    fp = fopen(list_path, "rb");
    if (!fp) {
        fprintf(stderr, "speedscan: open path-audit list failed: %s: %s\n", list_path, strerror(errno));
        return 4;
    }
    uint64_t rows = 0, bad = 0, escaped = 0, mount_cross = 0, missing = 0;
    while ((len = getline(&line, &cap, fp)) >= 0) {
        struct stat st;
        char resolved[PATH_MAX];
        int exists = 0, escape = 0, cross = 0, e = 0;
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        rows++;
        if (lstat(line, &st) == 0) {
            exists = 1;
            if (realpath(line, resolved) == NULL) {
                e = errno;
                resolved[0] = '\0';
                escape = 1;
            } else {
                escape = path_under_root(root_real, resolved) ? 0 : 1;
                cross = st.st_dev != root_st.st_dev ? 1 : 0;
            }
        } else {
            e = errno;
            missing++;
            resolved[0] = '\0';
            escape = 1;
        }
        if (escape) escaped++;
        if (cross) mount_cross++;
        if (escape || e) bad++;
        printf("%s\t%d\t%s\t%04o\t%u\t%u\t%llu\t%llu\t%d\t%d\t%d\t%s\n",
               line, exists, exists ? file_type_from_mode(st.st_mode) : "missing",
               exists ? (unsigned)(st.st_mode & 07777) : 0,
               exists ? (unsigned)st.st_uid : 0,
               exists ? (unsigned)st.st_gid : 0,
               exists ? (unsigned long long)st.st_dev : 0ULL,
               exists ? (unsigned long long)st.st_ino : 0ULL,
               escape, cross, e, resolved[0] ? resolved : "-");
    }
    free(line);
    fclose(fp);
    printf("PATH_AUDIT_SUMMARY ok=%s root=%s rows=%llu bad=%llu escaped=%llu missing=%llu mountCross=%llu hash=0 policy=facts-only elapsedMs=%ld\n",
           bad == 0 ? "true" : "false", root_real,
           (unsigned long long)rows, (unsigned long long)bad, (unsigned long long)escaped,
           (unsigned long long)missing, (unsigned long long)mount_cross, now_ms() - start);
    if (bad || escaped) rc = 1;
    return rc;
}


static void parent_basename_from_path(const char *path, char *out, size_t out_sz) {
    const char *end, *slash;
    size_t len;
    if (!out || out_sz == 0) return;
    out[0] = '\0';
    if (!path || !*path) return;
    end = strrchr(path, '/');
    if (!end) return;
    slash = end;
    while (slash > path && *(slash - 1) == '/') slash--;
    while (slash > path && *(slash - 1) != '/') slash--;
    len = (size_t)(end - slash);
    if (len >= out_sz) len = out_sz - 1;
    memcpy(out, slash, len);
    out[len] = '\0';
}

static int appdetails_index_walk(FILE *out, const char *path, int depth, int maxdepth, int mindepth, uint64_t *rows, uint64_t *errors) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];

    if (!out || !path || !rows || !errors) return 1;
    if (lstat(path, &st) != 0) { (*errors)++; return 1; }
    if (S_ISREG(st.st_mode)) {
        const char *base = strrchr(path, '/');
        base = base ? base + 1 : path;
        if (strcmp(base, "app_details.json") == 0 && depth >= mindepth && depth <= maxdepth) {
            char app[PATH_MAX];
            parent_basename_from_path(path, app, sizeof(app));
            fprintf(out, "%s\t%s\t%" PRIu64 "\t%" PRIu64 "\n", app[0] ? app : "-", path, (uint64_t)st.st_size, (uint64_t)st.st_mtime);
            (*rows)++;
        }
        return 0;
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    if (depth >= maxdepth) return 0;
    dir = opendir(path);
    if (!dir) { (*errors)++; return 1; }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) { (*errors)++; continue; }
        appdetails_index_walk(out, child, depth + 1, maxdepth, mindepth, rows, errors);
    }
    closedir(dir);
    return 0;
}


static int string_has_suffix(const char *s, const char *suffix) {
    size_t sl, su;
    if (!s || !suffix) return 0;
    sl = strlen(s); su = strlen(suffix);
    if (su > sl) return 0;
    return strcmp(s + sl - su, suffix) == 0;
}

static int path_starts_with_prefix(const char *path, const char *prefix) {
    size_t n;
    if (!path || !prefix || !*prefix) return 0;
    n = strlen(prefix);
    if (strncmp(path, prefix, n) != 0) return 0;
    return path[n] == '\0' || path[n] == '/';
}

static int file_list_abs_filter_walk(FILE *out, const char *root, const char *path, size_t root_len, int skip_appdetails, const char *exclude_prefix, uint64_t *rows, uint64_t *errors) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    const char *rel;
    if (!out || !root || !path || !rows || !errors) return 1;
    if (lstat(path, &st) != 0) { (*errors)++; return 1; }
    if (S_ISREG(st.st_mode)) {
        rel = path + root_len;
        if (*rel == '/') rel++;
        if (skip_appdetails) { const char *bn = strrchr(rel, '/'); bn = bn ? bn + 1 : rel; if (strcmp(bn, "app_details.json") == 0) return 0; }
        if (exclude_prefix && *exclude_prefix && path_starts_with_prefix(path, exclude_prefix)) return 0;
        fprintf(out, "%s\n", path);
        (*rows)++;
        return 0;
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    if (exclude_prefix && *exclude_prefix && path_starts_with_prefix(path, exclude_prefix)) return 0;
    dir = opendir(path);
    if (!dir) { (*errors)++; return 1; }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) { (*errors)++; continue; }
        file_list_abs_filter_walk(out, root, child, root_len, skip_appdetails, exclude_prefix, rows, errors);
    }
    closedir(dir);
    return 0;
}

static int cmd_file_list_abs_filter(const char *root, const char *out_path, const char *skip_s, const char *exclude_prefix) {
    FILE *out;
    struct stat st;
    uint64_t rows = 0, errors = 0;
    size_t root_len;
    long start = now_ms();
    int skip = 0;
    if (!root || !*root || !out_path || !*out_path) return 2;
    if (skip_s && strcmp(skip_s, "1") == 0) skip = 1;
    if (lstat(root, &st) != 0 || !S_ISDIR(st.st_mode)) return 3;
    out = fopen(out_path, "wb");
    if (!out) return 4;
    root_len = strlen(root);
    while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    file_list_abs_filter_walk(out, root, root, root_len, skip, exclude_prefix && strcmp(exclude_prefix, "-") != 0 ? exclude_prefix : "", &rows, &errors);
    fclose(out);
    printf("FILE_LIST_ABS_FILTER ok=%s root=%s out=%s rows=%" PRIu64 " errors=%" PRIu64 " skipAppDetails=%d elapsedMs=%ld policy=facts-only\n", errors == 0 ? "true" : "partial", root, out_path, rows, errors, skip, now_ms() - start);
    return 0;
}

typedef struct StrSetNode { char *s; struct StrSetNode *next; } StrSetNode;

static int set_contains(StrSetNode *head, const char *s) {
    StrSetNode *n;
    if (!s) return 0;
    for (n=head; n; n=n->next) if (strcmp(n->s, s) == 0) return 1;
    return 0;
}

static void set_add(StrSetNode **head, const char *s) {
    StrSetNode *n;
    if (!head || !s || !*s || set_contains(*head, s)) return;
    n = (StrSetNode *)calloc(1, sizeof(StrSetNode));
    if (!n) return;
    n->s = strdup(s);
    if (!n->s) { free(n); return; }
    n->next = *head;
    *head = n;
}

static void set_free(StrSetNode *head) {
    StrSetNode *n;
    while (head) { n=head->next; free(head->s); free(head); head=n; }
}

static StrSetNode *load_set_file(const char *path) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    StrSetNode *head = NULL;
    if (!path || !*path || strcmp(path, "-") == 0) return NULL;
    fp = fopen(path, "rb");
    if (!fp) return NULL;
    while ((len = getline(&line, &cap, fp)) >= 0) {
        (void)len;
        trim_line(line);
        if (line[0] == '\0') continue;
        if (line[0] == '#' || (unsigned char)line[0] == 0xef) continue;
        set_add(&head, line);
    }
    free(line);
    fclose(fp);
    return head;
}

static void safe_name_for_backup(const char *name, const char *pkg, char *out, size_t cap) {
    const unsigned char *p;
    size_t j = 0;
    if (!out || cap == 0) return;
    out[0] = '\0';
    p = (const unsigned char *)(name && *name ? name : (pkg ? pkg : "app"));
    while (*p && j + 1 < cap) {
        unsigned char c = *p++;
        if (c == '\t' || c == '\n' || c == '\r' || c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') out[j++] = '_';
        else out[j++] = (char)c;
    }
    out[j] = '\0';
    if (out[0] == '\0') snprintf(out, cap, "%s", pkg && *pkg ? pkg : "app");
}

static void parse_app_line(char *line, char **name_out, char **pkg_out, int *nodata_out) {
    char *name, *pkg, *sp;
    if (name_out) *name_out = NULL;
    if (pkg_out) *pkg_out = NULL;
    if (nodata_out) *nodata_out = 0;
    if (!line) return;
    trim_line(line);
    if (!*line || *line == '#' || (unsigned char)line[0] == 0xef) return;
    name = line;
    sp = strchr(line, ' ');
    if (!sp) return;
    *sp++ = '\0';
    while (*sp == ' ') sp++;
    pkg = sp;
    sp = strchr(pkg, ' ');
    if (sp) *sp = '\0';
    if (!*name || !*pkg) return;
    if (name[0] == '!') { name++; if (nodata_out) *nodata_out = 1; }
    else if ((unsigned char)name[0] == 0xef && (unsigned char)name[1] == 0xbc && (unsigned char)name[2] == 0x81) { name += 3; if (nodata_out) *nodata_out = 1; }
    if (name_out) *name_out = name;
    if (pkg_out) *pkg_out = pkg;
}

static int cmd_selected_list(const char *applist, const char *blacklist, const char *out_path, const char *blacklist_mode_s) {
    FILE *in, *out;
    char *line = NULL, safe[PATH_MAX];
    size_t cap = 0;
    ssize_t len;
    StrSetNode *black;
    uint64_t rows=0, excluded=0;
    int blacklist_full = 0;
    long start = now_ms();
    if (!applist || !out_path) return 2;
    if (blacklist_mode_s && (strcmp(blacklist_mode_s,"1")==0 || strcmp(blacklist_mode_s,"true")==0)) blacklist_full = 1;
    in = fopen(applist, "rb"); if (!in) return 3;
    out = fopen(out_path, "wb"); if (!out) { fclose(in); return 4; }
    black = load_set_file(blacklist);
    while ((len = getline(&line, &cap, in)) >= 0) {
        char *name=NULL, *pkg=NULL;
        int nodata=0, hit=0;
        (void)len;
        parse_app_line(line, &name, &pkg, &nodata);
        if (!name || !pkg) continue;
        hit = set_contains(black, pkg);
        if (hit && blacklist_full) { fprintf(out, "EXCLUDED\t"); print_tsv_sanitized(out, name); fprintf(out, "\t"); print_tsv_sanitized(out, pkg); fprintf(out, "\n"); excluded++; continue; }
        if (hit) nodata = 1;
        safe_name_for_backup(name, pkg, safe, sizeof(safe));
        fprintf(out, "APP\t"); print_tsv_sanitized(out, safe); fprintf(out, "\t"); print_tsv_sanitized(out, pkg); fprintf(out, "\t%d\n", nodata ? 1 : 0);
        rows++;
    }
    free(line); fclose(in); fclose(out); set_free(black);
    printf("SELECTED_LIST ok=true out=%s rows=%" PRIu64 " excluded=%" PRIu64 " elapsedMs=%ld policy=facts-only\n", out_path, rows, excluded, now_ms()-start);
    return 0;
}

static int cmd_apk_size_map(const char *pkg_apk_paths, const char *out_path) {
    FILE *in, *out;
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    uint64_t rows=0, ok=0;
    long start = now_ms();
    if (!pkg_apk_paths || !out_path) return 2;
    in = fopen(pkg_apk_paths, "rb"); if (!in) return 3;
    out = fopen(out_path, "wb"); if (!out) { fclose(in); return 4; }
    while ((len = getline(&line, &cap, in)) >= 0) {
        char *pkg, *path, *tab;
        struct stat st;
        (void)len;
        trim_line(line); if (!*line) continue;
        pkg = line;
        tab = strchr(pkg, '\t'); if (!tab) continue;
        *tab = '\0'; path = tab + 1;
        tab = strchr(path, '\t'); if (tab) *tab = '\0';
        if (!string_has_suffix(path, ".apk")) continue;
        rows++;
        if (lstat(path, &st) == 0 && S_ISREG(st.st_mode)) { fprintf(out, "%s\t%" PRIu64 "\n", pkg, (uint64_t)st.st_size); ok++; }
    }
    free(line); fclose(in); fclose(out);
    printf("APK_SIZE_MAP ok=true in=%s out=%s rows=%" PRIu64 " ok=%" PRIu64 " elapsedMs=%ld policy=facts-only\n", pkg_apk_paths, out_path, rows, ok, now_ms()-start);
    return 0;
}

typedef struct AppSum { char *pkg; char *name; int nodata; uint64_t apk, appdata, external, cache; struct AppSum *next; } AppSum;

static AppSum *appsum_get(AppSum **head, const char *pkg, int create) {
    AppSum *n;
    if (!head || !pkg || !*pkg) return NULL;
    for (n=*head; n; n=n->next) if (strcmp(n->pkg, pkg) == 0) return n;
    if (!create) return NULL;
    n = (AppSum *)calloc(1, sizeof(AppSum)); if (!n) return NULL;
    n->pkg = strdup(pkg); if (!n->pkg) { free(n); return NULL; }
    n->next = *head; *head = n;
    return n;
}
static void appsum_free(AppSum *head) { AppSum *n; while(head){ n=head->next; free(head->pkg); free(head->name); free(head); head=n; } }

static uint64_t parse_u64(const char *s) {
    char *end=NULL; unsigned long long v;
    if (!s || !*s) return 0;
    errno=0; v=strtoull(s,&end,10);
    if (errno || !end || *end) return 0;
    return (uint64_t)v;
}

static int read_selected_for_summary(const char *path, AppSum **apps, uint64_t *app_count, uint64_t *excluded_count) {
    FILE *fp; char *line=NULL; size_t cap=0; ssize_t len;
    if (!path || !apps) return 1;
    fp=fopen(path,"rb"); if(!fp) return 1;
    while((len=getline(&line,&cap,fp))>=0){
        char *kind,*name,*pkg,*nd,*t;
        (void)len; trim_line(line); if(!*line) continue;
        kind=line; t=strchr(kind,'\t'); if(!t) continue; *t='\0'; name=t+1;
        t=strchr(name,'\t'); if(!t) continue; *t='\0'; pkg=t+1;
        if(strcmp(kind,"EXCLUDED")==0){ if(excluded_count) (*excluded_count)++; continue; }
        t=strchr(pkg,'\t'); if(!t) continue; *t='\0'; nd=t+1;
        if(strcmp(kind,"APP")==0){ AppSum *a=appsum_get(apps,pkg,1); if(a){ if(!a->name) a->name=strdup(name); a->nodata=(strcmp(nd,"1")==0); if(app_count) (*app_count)++; } }
    }
    free(line); fclose(fp); return 0;
}

static void add_dirsize_to_summary(AppSum **apps, uint64_t *mediaTotal, uint64_t *mediaCache, uint64_t *mediaMapped, uint64_t *cacheMapped, const char *path) {
    FILE *fp; char *line=NULL; size_t cap=0; ssize_t len;
    fp=fopen(path,"rb"); if(!fp) return;
    while((len=getline(&line,&cap,fp))>=0){
        char *pkg,*typ,*szs,*t; uint64_t sz;
        (void)len; trim_line(line); if(!*line) continue;
        pkg=line; t=strchr(pkg,'\t'); if(!t) continue; *t='\0'; typ=t+1;
        t=strchr(typ,'\t'); if(!t) continue; *t='\0'; szs=t+1; sz=parse_u64(szs);
        if(strcmp(pkg,"__speedbackup_custom_media__")==0){
            if(strstr(typ,"_exclude_cache") && strncmp(typ,"media_",6)==0){ *mediaCache += sz; if(cacheMapped) (*cacheMapped)++; }
            else if(strncmp(typ,"media_",6)==0){ *mediaTotal += sz; if(mediaMapped) (*mediaMapped)++; }
            continue;
        }
        AppSum *a=appsum_get(apps,pkg,0); if(!a) continue;
        if(strcmp(typ,"user")==0 || strcmp(typ,"user_de")==0) a->appdata += sz;
        else if(strcmp(typ,"data")==0 || strcmp(typ,"obb")==0 || strcmp(typ,"media")==0) a->external += sz;
        else if(strstr(typ,"_exclude_cache") || strstr(typ,"_exclude_code_cache")) a->cache += sz;
    }
    free(line); fclose(fp);
}

static void add_apk_to_summary(AppSum **apps, const char *path) {
    FILE *fp; char *line=NULL; size_t cap=0; ssize_t len;
    fp=fopen(path,"rb"); if(!fp) return;
    while((len=getline(&line,&cap,fp))>=0){ char *pkg,*szs,*t; AppSum *a; (void)len; trim_line(line); if(!*line) continue; pkg=line; t=strchr(pkg,'\t'); if(!t) continue; *t='\0'; szs=t+1; a=appsum_get(apps,pkg,0); if(a) a->apk += parse_u64(szs); }
    free(line); fclose(fp);
}

static int cmd_backup_prescan_summary(const char *selected, const char *dirsizes, const char *apkmap, const char *rskip_path, const char *lskip_path, const char *out_path, const char *remote_stream_s, const char *remote_type) {
    AppSum *apps=NULL, *a;
    StrSetNode *rskip=NULL, *lskip=NULL;
    FILE *out;
    uint64_t app_count=0, excluded=0, apkT=0, appdataT=0, extT=0, cacheT=0, mediaT=0, mediaCache=0, mediaMapped=0, cacheMapped=0, total=0, remoteSkip=0, localSkip=0, expected=0;
    int remote_stream = (remote_stream_s && strcmp(remote_stream_s,"1")==0);
    int remote_on = (remote_type && *remote_type && strcmp(remote_type,"-")!=0);
    long start=now_ms();
    if (!selected || !out_path) return 2;
    read_selected_for_summary(selected, &apps, &app_count, &excluded);
    if (dirsizes && strcmp(dirsizes,"-")!=0) add_dirsize_to_summary(&apps,&mediaT,&mediaCache,&mediaMapped,&cacheMapped,dirsizes);
    if (apkmap && strcmp(apkmap,"-")!=0) add_apk_to_summary(&apps,apkmap);
    if (rskip_path && strcmp(rskip_path,"-")!=0) rskip=load_set_file(rskip_path);
    if (lskip_path && strcmp(lskip_path,"-")!=0) lskip=load_set_file(lskip_path);
    for (a=apps; a; a=a->next) {
        uint64_t raw, eff, ca;
        if (a->nodata || strcmp(a->pkg,"bin.mt.plus")==0) { a->appdata=0; a->external=0; a->cache=0; }
        raw = a->apk + a->appdata + a->external;
        ca = a->cache;
        eff = raw > ca ? raw - ca : 0;
        apkT += a->apk; appdataT += a->appdata; extT += a->external; cacheT += ca; total += eff;
        if (remote_stream && remote_on && a->name && set_contains(rskip,a->name)) remoteSkip += eff;
        else if (!remote_on && !remote_stream && a->name && set_contains(lskip,a->name)) localSkip += eff;
    }
    total += mediaT;
    cacheT += mediaCache;
    total = total > mediaCache ? total - mediaCache : 0;
    expected = total;
    if (remoteSkip + localSkip < expected) expected -= (remoteSkip + localSkip); else expected = 0;
    out=fopen(out_path,"wb"); if(!out){ appsum_free(apps); set_free(rskip); set_free(lskip); return 4; }
    fprintf(out,"apps\t%" PRIu64 "\nexcludedApps\t%" PRIu64 "\napk\t%" PRIu64 "\nappData\t%" PRIu64 "\nexternal\t%" PRIu64 "\nmediaCustom\t%" PRIu64 "\nexcludedCache\t%" PRIu64 "\ntotal\t%" PRIu64 "\nremoteSkip\t%" PRIu64 "\nlocalSkip\t%" PRIu64 "\nexpected\t%" PRIu64 "\npartialMedia\t%d\nmediaMapped\t%" PRIu64 "\ncacheMapped\t%" PRIu64 "\n", app_count, excluded, apkT, appdataT, extT, mediaT, cacheT, total, remoteSkip, localSkip, expected, mediaMapped>0?0:1, mediaMapped, cacheMapped);
    fclose(out);
    printf("BACKUP_PRESCAN_SUMMARY_NATIVE ok=true out=%s apps=%" PRIu64 " total=%" PRIu64 " expected=%" PRIu64 " elapsedMs=%ld policy=facts-only\n", out_path, app_count, total, expected, now_ms()-start);
    appsum_free(apps); set_free(rskip); set_free(lskip); return 0;
}

static int backup_root_index_walk(FILE *out, const char *root, const char *path, int depth, int maxdepth, uint64_t *rows, uint64_t *errors) {
    DIR *dir; struct dirent *de; struct stat st; char child[PATH_MAX]; const char *name;
    if(lstat(path,&st)!=0){ (*errors)++; return 1; }
    name=strrchr(path,'/'); name=name?name+1:path;
    if(depth>0){
        const char *kind="other";
        if(S_ISDIR(st.st_mode) && strncmp(name,"Backup_",7)==0) kind="backup_dir";
        else if(S_ISDIR(st.st_mode)) kind="dir";
        else if(S_ISREG(st.st_mode) && strcmp(name,"app_details.json")==0) kind="app_details_json";
        else if(S_ISREG(st.st_mode) && (strstr(name,".tar") || strstr(name,".zst"))) kind="tar_payload";
        else if(S_ISREG(st.st_mode) && (strcmp(name,"start.sh")==0 || strcmp(name,"recover.sh")==0 || strcmp(name,"backup.sh")==0 || strcmp(name,"upload.sh")==0)) kind="sidecar_script";
        fprintf(out,"%s\t%s\t%s\t%d\t%" PRIu64 "\t%" PRIu64 "\n", kind, path, name, depth, (uint64_t)st.st_mtime, S_ISREG(st.st_mode)?(uint64_t)st.st_size:0);
        (*rows)++;
    }
    if(!S_ISDIR(st.st_mode) || depth>=maxdepth) return 0;
    dir=opendir(path); if(!dir){ (*errors)++; return 1; }
    while((de=readdir(dir))!=NULL){ if(strcmp(de->d_name,".")==0 || strcmp(de->d_name,"..")==0) continue; if(join_path(path,de->d_name,child,sizeof(child))!=0){(*errors)++; continue;} backup_root_index_walk(out,root,child,depth+1,maxdepth,rows,errors); }
    closedir(dir); return 0;
}

static int cmd_backup_root_index(const char *root, const char *out_path, const char *maxdepth_s) {
    FILE *out; uint64_t rows=0, errors=0; int maxdepth=3; struct stat st; long start=now_ms();
    if(!root||!*root||!out_path||!*out_path) return 2;
    if(maxdepth_s&&*maxdepth_s){ maxdepth=atoi(maxdepth_s); if(maxdepth<1) maxdepth=1; if(maxdepth>16) maxdepth=16; }
    if(lstat(root,&st)!=0||!S_ISDIR(st.st_mode)) return 3;
    out=fopen(out_path,"wb"); if(!out) return 4;
    backup_root_index_walk(out,root,root,0,maxdepth,&rows,&errors);
    fclose(out);
    printf("BACKUP_ROOT_INDEX ok=%s root=%s out=%s rows=%" PRIu64 " errors=%" PRIu64 " maxdepth=%d elapsedMs=%ld policy=facts-only\n", errors==0?"true":"partial",root,out_path,rows,errors,maxdepth,now_ms()-start);
    return 0;
}

static int cmd_appdetails_index(const char *root, const char *out_path, const char *maxdepth_s, const char *mindepth_s) {
    FILE *out;
    uint64_t rows = 0, errors = 0;
    long start = now_ms();
    int maxdepth = 2;
    int mindepth = 0;
    struct stat st;
    if (!root || !*root || !out_path || !*out_path) return 2;
    if (maxdepth_s && *maxdepth_s) { maxdepth = atoi(maxdepth_s); if (maxdepth < 0) maxdepth = 2; if (maxdepth > 64) maxdepth = 64; }
    if (mindepth_s && *mindepth_s) { mindepth = atoi(mindepth_s); if (mindepth < 0) mindepth = 0; if (mindepth > maxdepth) mindepth = maxdepth; }
    if (lstat(root, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "speedscan: appdetails-index root invalid: %s: %s\n", root, strerror(errno));
        return 3;
    }
    out = fopen(out_path, "wb");
    if (!out) {
        fprintf(stderr, "speedscan: appdetails-index open output failed: %s: %s\n", out_path, strerror(errno));
        return 4;
    }
    appdetails_index_walk(out, root, 0, maxdepth, mindepth, &rows, &errors);
    fclose(out);
    printf("APPDETAILS_INDEX ok=%s root=%s out=%s rows=%" PRIu64 " errors=%" PRIu64 " maxdepth=%d mindepth=%d elapsedMs=%ld policy=facts-only\n",
           errors == 0 ? "true" : "partial", root, out_path, rows, errors, maxdepth, mindepth, now_ms() - start);
    return 0;
}


static void sanitize_tsv(char *s) {
    if (!s) return;
    for (; *s; ++s) {
        if (*s == '\t' || *s == '\n' || *s == '\r' || *s == '\0') *s = ' ';
    }
}

static void mountinfo_unescape(const char *in, char *out, size_t out_sz) {
    size_t oi = 0;
    if (!out || out_sz == 0) return;
    if (!in) { out[0] = '\0'; return; }
    for (size_t i = 0; in[i] && oi + 1 < out_sz; i++) {
        if (in[i] == '\\' && in[i+1] >= '0' && in[i+1] <= '7' && in[i+2] >= '0' && in[i+2] <= '7' && in[i+3] >= '0' && in[i+3] <= '7') {
            int v = (in[i+1]-'0')*64 + (in[i+2]-'0')*8 + (in[i+3]-'0');
            out[oi++] = (char)v;
            i += 3;
        } else {
            out[oi++] = in[i];
        }
    }
    out[oi] = '\0';
}

static int path_prefix_match(const char *path, const char *mp) {
    size_t ml;
    if (!path || !mp || !*path || !*mp) return 0;
    if (strcmp(mp, "/") == 0) return 1;
    ml = strlen(mp);
    if (strncmp(path, mp, ml) != 0) return 0;
    return path[ml] == '\0' || path[ml] == '/';
}

static void human_bytes(uint64_t bytes, char *out, size_t out_sz) {
    static const char *units[] = {"B", "K", "M", "G", "T", "P", "E"};
    double v = (double)bytes;
    int u = 0;
    if (!out || out_sz == 0) return;
    while (v >= 1024.0 && u < 6) { v /= 1024.0; u++; }
    if (u == 0) snprintf(out, out_sz, "%" PRIu64 "B", bytes);
    else snprintf(out, out_sz, "%.1f%s", v, units[u]);
}

static int mountinfo_lookup(const char *target, char *fs, size_t fs_sz, char *mp, size_t mp_sz, char *src, size_t src_sz) {
    FILE *fp;
    char line[8192];
    char target_real[PATH_MAX];
    const char *match_target = target;
    size_t best = 0;
    int found = 0;
    if (!target || !*target) return -1;
    if (realpath(target, target_real)) match_target = target_real;
    fp = fopen("/proc/self/mountinfo", "r");
    if (!fp) return -1;
    while (fgets(line, sizeof(line), fp)) {
        char copy[8192];
        char *save = NULL, *tok = NULL;
        char *fields[256];
        int nf = 0, sep = -1;
        char dec_mp[PATH_MAX], dec_src[PATH_MAX];
        strncpy(copy, line, sizeof(copy)-1);
        copy[sizeof(copy)-1] = '\0';
        for (tok = strtok_r(copy, " \n", &save); tok && nf < 256; tok = strtok_r(NULL, " \n", &save)) fields[nf++] = tok;
        if (nf < 10) continue;
        for (int i = 0; i < nf; i++) if (strcmp(fields[i], "-") == 0) { sep = i; break; }
        if (sep < 0 || sep + 2 >= nf) continue;
        mountinfo_unescape(fields[4], dec_mp, sizeof(dec_mp));
        if (!path_prefix_match(match_target, dec_mp) && !path_prefix_match(target, dec_mp)) continue;
        size_t ml = strlen(dec_mp);
        if (ml < best) continue;
        best = ml;
        found = 1;
        if (fs && fs_sz) { snprintf(fs, fs_sz, "%s", fields[sep + 1]); sanitize_tsv(fs); }
        if (mp && mp_sz) { snprintf(mp, mp_sz, "%s", dec_mp); sanitize_tsv(mp); }
        mountinfo_unescape(fields[sep + 2], dec_src, sizeof(dec_src));
        if (src && src_sz) { snprintf(src, src_sz, "%s", dec_src); sanitize_tsv(src); }
    }
    fclose(fp);
    return found ? 0 : -1;
}

static int cmd_storage_summary(const char *path) {
    struct statvfs vfs;
    char real[PATH_MAX];
    char target[PATH_MAX];
    char fs[128] = "unknown", mp[PATH_MAX] = "", src[PATH_MAX] = "";
    char total_h[64], used_h[64], avail_h[64];
    uint64_t bsize, total, freeb, avail, used, denom;
    unsigned long use_pct = 0;
    if (!path || !*path) return 2;
    if (statvfs(path, &vfs) != 0) {
        fprintf(stderr, "storage-summary: statvfs failed path=%s errno=%d\n", path, errno);
        return 1;
    }
    bsize = (uint64_t)(vfs.f_frsize ? vfs.f_frsize : vfs.f_bsize);
    total = (uint64_t)vfs.f_blocks * bsize;
    freeb = (uint64_t)vfs.f_bfree * bsize;
    avail = (uint64_t)vfs.f_bavail * bsize;
    used = total >= freeb ? total - freeb : 0;
    denom = used + avail;
    if (denom > 0) use_pct = (unsigned long)((used * 100ULL + denom - 1ULL) / denom);
    snprintf(target, sizeof(target), "%s", path);
    sanitize_tsv(target);
    if (!realpath(path, real)) snprintf(real, sizeof(real), "%s", path);
    sanitize_tsv(real);
    mountinfo_lookup(path, fs, sizeof(fs), mp, sizeof(mp), src, sizeof(src));
    human_bytes(total, total_h, sizeof(total_h));
    human_bytes(used, used_h, sizeof(used_h));
    human_bytes(avail, avail_h, sizeof(avail_h));
    printf("#schema\tspeedbackup.storage_summary.v1\n");
    printf("#fields\tstatus\ttarget\trealpath\ttotalBytes\tusedBytes\tavailBytes\tusePct\tfsType\tmountPoint\tsource\ttotalHuman\tusedHuman\tavailHuman\n");
    printf("OK\t%s\t%s\t%" PRIu64 "\t%" PRIu64 "\t%" PRIu64 "\t%lu\t%s\t%s\t%s\t%s\t%s\t%s\n",
           target, real, total, used, avail, use_pct, fs, mp, src, total_h, used_h, avail_h);
    return 0;
}



static uint64_t fnv1a64_file(const char *path, int *ok) {
    FILE *fp;
    unsigned char buf[65536];
    size_t n;
    uint64_t h = 1469598103934665603ULL;
    if (ok) *ok = 0;
    fp = fopen(path, "rb");
    if (!fp) return 0;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        for (size_t i = 0; i < n; i++) {
            h ^= (uint64_t)buf[i];
            h *= 1099511628211ULL;
        }
    }
    if (ferror(fp)) { fclose(fp); return 0; }
    fclose(fp);
    if (ok) *ok = 1;
    return h;
}

static int checksum_list_walk(FILE *out, const char *root, const char *path, size_t root_len, uint64_t *rows, uint64_t *errors) {
    DIR *dir;
    struct dirent *de;
    struct stat st;
    char child[PATH_MAX];
    int rc = 0;
    if (lstat(path, &st) != 0) { if (errors) (*errors)++; return 1; }
    if (S_ISREG(st.st_mode)) {
        const char *rel = path + root_len;
        int ok = 0;
        uint64_t h;
        if (*rel == '/') rel++;
        h = fnv1a64_file(path, &ok);
        fprintf(out, "%s\t%" PRIu64 "\t%lld\t%016" PRIx64 "\t%s\n", rel, (uint64_t)st.st_size, (long long)st.st_mtime, h, ok ? "OK" : "READ_ERROR");
        if (rows) (*rows)++;
        if (!ok) { if (errors) (*errors)++; rc = 1; }
        return rc;
    }
    if (!S_ISDIR(st.st_mode)) return 0;
    dir = opendir(path);
    if (!dir) { if (errors) (*errors)++; return 1; }
    while ((de = readdir(dir)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;
        if (join_path(path, de->d_name, child, sizeof(child)) != 0) { if (errors) (*errors)++; rc = 1; continue; }
        if (checksum_list_walk(out, root, child, root_len, rows, errors) != 0) rc = 1;
    }
    closedir(dir);
    return rc;
}

static int cmd_checksum_list(const char *root, const char *out_path) {
    FILE *out;
    size_t root_len;
    uint64_t rows = 0, errors = 0;
    int rc;
    if (!root || !*root || !out_path || !*out_path) return 2;
    out = fopen(out_path, "wb");
    if (!out) { fprintf(stderr, "speedscan: checksum-list open failed: %s: %s\n", out_path, strerror(errno)); return 3; }
    fprintf(out, "#schema\tspeedbackup.checksum_list.v1\n#fields\trel\tbytes\tmtime\tfnv64\tstatus\n");
    root_len = strlen(root); while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    rc = checksum_list_walk(out, root, root, root_len, &rows, &errors);
    fprintf(out, "#summary\trows=%" PRIu64 "\terrors=%" PRIu64 "\trc=%d\n", rows, errors, rc);
    fclose(out);
    return rc;
}

static int cmd_manifest_verify(const char *root, const char *manifest) {
    FILE *fp;
    char *line = NULL;
    size_t cap = 0, root_len;
    ssize_t len;
    uint64_t rows = 0, ok = 0, missing = 0, changed = 0, bad = 0;
    int rc = 0;
    if (!root || !*root || !manifest || !*manifest) return 2;
    fp = fopen(manifest, "rb");
    if (!fp) { fprintf(stderr, "speedscan: manifest-verify open failed: %s: %s\n", manifest, strerror(errno)); return 3; }
    printf("#schema\tspeedbackup.manifest_verify.v1\n#fields\tstatus\trel\texpectedSize\tactualSize\texpectedMtime\tactualMtime\treason\n");
    root_len = strlen(root); while (root_len > 1 && root[root_len - 1] == '/') root_len--;
    while ((len = getline(&line, &cap, fp)) >= 0) {
        char *rel, *type, *mode, *uid, *gid, *size_s, *mtime_s;
        char path[PATH_MAX];
        struct stat st;
        uint64_t exp_size = 0, act_size = 0;
        long long exp_mtime = 0, act_mtime = 0;
        (void)len;
        trim_line(line);
        if (line[0] == '\0' || line[0] == '#') continue;
        rel = line;
        type = strchr(rel, '\t'); if (!type) { bad++; rc = 1; continue; } *type++ = '\0';
        mode = strchr(type, '\t'); if (!mode) { bad++; rc = 1; continue; } *mode++ = '\0';
        uid = strchr(mode, '\t'); if (!uid) { bad++; rc = 1; continue; } *uid++ = '\0';
        gid = strchr(uid, '\t'); if (!gid) { bad++; rc = 1; continue; } *gid++ = '\0';
        size_s = strchr(gid, '\t'); if (!size_s) { bad++; rc = 1; continue; } *size_s++ = '\0';
        mtime_s = strchr(size_s, '\t'); if (!mtime_s) { bad++; rc = 1; continue; } *mtime_s++ = '\0';
        exp_size = (uint64_t)strtoull(size_s, NULL, 10);
        exp_mtime = strtoll(mtime_s, NULL, 10);
        if (join_path(root, rel, path, sizeof(path)) != 0) { bad++; rc = 1; continue; }
        rows++;
        if (lstat(path, &st) != 0) {
            printf("MISSING\t%s\t%" PRIu64 "\t0\t%lld\t0\tstat_errno_%d\n", rel, exp_size, exp_mtime, errno);
            missing++; rc = 1; continue;
        }
        act_size = (uint64_t)st.st_size;
        act_mtime = (long long)st.st_mtime;
        if (act_size != exp_size || act_mtime != exp_mtime) {
            printf("CHANGED\t%s\t%" PRIu64 "\t%" PRIu64 "\t%lld\t%lld\tsize_or_mtime\n", rel, exp_size, act_size, exp_mtime, act_mtime);
            changed++; rc = 1;
        } else {
            printf("OK\t%s\t%" PRIu64 "\t%" PRIu64 "\t%lld\t%lld\tOK\n", rel, exp_size, act_size, exp_mtime, act_mtime);
            ok++;
        }
    }
    free(line);
    fclose(fp);
    printf("#summary\trows=%" PRIu64 "\tok=%" PRIu64 "\tmissing=%" PRIu64 "\tchanged=%" PRIu64 "\tbad=%" PRIu64 "\trc=%d\n", rows, ok, missing, changed, bad, rc);
    return rc;
}

static int cmd_run_tmpdir_facts(const char *base, const char *out_path, const char *prefix) {
    DIR *dir;
    struct dirent *de;
    FILE *out;
    char child[PATH_MAX];
    struct stat st;
    uint64_t rows = 0, errors = 0;
    const char *pref = (prefix && *prefix) ? prefix : ".speedbackup_run_";
    if (!base || !*base || !out_path || !*out_path) return 2;
    dir = opendir(base);
    if (!dir) { fprintf(stderr, "speedscan: run-tmpdir-facts open base failed: %s: %s\n", base, strerror(errno)); return 3; }
    out = fopen(out_path, "wb");
    if (!out) { closedir(dir); fprintf(stderr, "speedscan: run-tmpdir-facts open out failed: %s: %s\n", out_path, strerror(errno)); return 4; }
    fprintf(out, "#schema\tspeedbackup.run_tmpdir_facts.v1\n#fields\tname\tpath\ttype\tmode\tuid\tgid\tbytes\tmtime\tageSec\n");
    time_t now = time(NULL);
    while ((de = readdir(dir)) != NULL) {
        if (strncmp(de->d_name, pref, strlen(pref)) != 0) continue;
        if (join_path(base, de->d_name, child, sizeof(child)) != 0) { errors++; continue; }
        if (lstat(child, &st) != 0) { errors++; continue; }
        fprintf(out, "%s\t%s\t%s\t%04o\t%u\t%u\t%" PRIu64 "\t%lld\t%lld\n",
                de->d_name, child, file_type_from_mode(st.st_mode), (unsigned)(st.st_mode & 07777), (unsigned)st.st_uid, (unsigned)st.st_gid,
                (uint64_t)st.st_size, (long long)st.st_mtime, (long long)(now - st.st_mtime));
        rows++;
    }
    fprintf(out, "#summary\trows=%" PRIu64 "\terrors=%" PRIu64 "\n", rows, errors);
    fclose(out);
    closedir(dir);
    return errors ? 1 : 0;
}


static int cmd_zst_file_facts(const char *path) {
    struct stat st;
    unsigned char hdr[4] = {0,0,0,0};
    int fd, magic = 0;
    if (!path || !*path) return 2;
    printf("#schema\tspeedbackup.zst_file_facts.v1\n");
    printf("#fields\tpath\texists\tregular\tbytes\tmtime\tzstdMagic\n");
    if (stat(path, &st) != 0) {
        printf("%s\t0\t0\t0\t0\t0\n", path);
        return 1;
    }
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        ssize_t n = read(fd, hdr, sizeof(hdr));
        close(fd);
        if (n == 4 && hdr[0] == 0x28 && hdr[1] == 0xB5 && hdr[2] == 0x2F && hdr[3] == 0xFD) magic = 1;
    }
    printf("%s\t1\t%d\t%" PRIu64 "\t%lld\t%d\n", path, S_ISREG(st.st_mode) ? 1 : 0,
           (uint64_t)st.st_size, (long long)st.st_mtime, magic);
    return (S_ISREG(st.st_mode) && magic) ? 0 : 1;
}

static void usage(void) {
    fprintf(stderr, "speedscan r470-api28-r28c-complete-native-facts\n");
    fprintf(stderr, "usage:\n");
    fprintf(stderr, "  speedscan dir-size PATH\n");
    fprintf(stderr, "  speedscan dir-size-map MANIFEST\n");
    fprintf(stderr, "  speedscan file-list ROOT\n");
    fprintf(stderr, "  speedscan list-total-size LIST\n");
    fprintf(stderr, "  speedscan batch-stat LIST\n");
    fprintf(stderr, "  speedscan batch-exists LIST\n");
    fprintf(stderr, "  speedscan batch-chmod MODE LIST\n");
    fprintf(stderr, "  speedscan batch-chown UID GID LIST\n");
    fprintf(stderr, "  speedscan tree-chown UID GID ROOT\n");
    fprintf(stderr, "  speedscan tree-fixup UID GID ROOT [DIR_MODE|-] [FILE_MODE|-]\n");
    fprintf(stderr, "  speedscan has-files ROOT\n");
    fprintf(stderr, "  speedscan manifest ROOT OUT\n");
    fprintf(stderr, "  speedscan scan-summary ROOT [MANIFEST_OUT|-]\n");
    fprintf(stderr, "  speedscan path-audit ROOT LIST\n");
    fprintf(stderr, "  speedscan label-audit ROOT [MAX_ROWS]\n");
    fprintf(stderr, "  speedscan facts ROOT [FACTS_OUT|-]\n");
    fprintf(stderr, "  speedscan restore-facts ROOT [FACTS_OUT|-]\n");
    fprintf(stderr, "  speedscan appdetails-index ROOT OUT [MAXDEPTH] [MINDEPTH]\n");
    fprintf(stderr, "  speedscan file-list-abs-filter ROOT OUT SKIP_APPDETAILS [EXCLUDE_PREFIX]\n");
    fprintf(stderr, "  speedscan selected-list APPLIST BLACKLIST OUT BLACKLIST_MODE\n");
    fprintf(stderr, "  speedscan apk-size-map PKG_APK_PATHS OUT\n");
    fprintf(stderr, "  speedscan backup-prescan-summary SELECTED DIRSIZES APKMAP RSKIP LSKIP OUT REMOTE_STREAM REMOTE_TYPE\n");
    fprintf(stderr, "  speedscan backup-root-index ROOT OUT [MAXDEPTH]\n");
    fprintf(stderr, "  speedscan storage-summary PATH\n");
    fprintf(stderr, "  speedscan checksum-list ROOT OUT\n");
    fprintf(stderr, "  speedscan manifest-verify ROOT MANIFEST\n");
    fprintf(stderr, "  speedscan run-tmpdir-facts BASE OUT [PREFIX]\n");
    fprintf(stderr, "  speedscan zst-file-facts FILE\n");
}

int main(int argc, char **argv) {
    if (argc >= 2 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "version") == 0)) {
        printf("speedscan r470-api28-r28c-complete-native-facts\n");
        return 0;
    }
    if (argc < 3) {
        usage();
        return 2;
    }
    if (strcmp(argv[1], "dir-size") == 0) return cmd_dir_size(argv[2]);
    if (strcmp(argv[1], "dir-size-map") == 0) return cmd_dir_size_map(argv[2]);
    if (strcmp(argv[1], "file-list") == 0) return cmd_file_list(argv[2]);
    if (strcmp(argv[1], "list-total-size") == 0) return cmd_list_total_size(argv[2]);
    if (strcmp(argv[1], "batch-stat") == 0) return cmd_batch_stat(argv[2]);
    if (strcmp(argv[1], "batch-exists") == 0) return cmd_batch_exists(argv[2]);
    if (strcmp(argv[1], "batch-chmod") == 0) { if (argc < 4) { usage(); return 2; } return cmd_batch_chmod(argv[2], argv[3]); }
    if (strcmp(argv[1], "batch-chown") == 0) { if (argc < 5) { usage(); return 2; } return cmd_batch_chown(argv[2], argv[3], argv[4]); }
    if (strcmp(argv[1], "tree-chown") == 0) { if (argc < 5) { usage(); return 2; } return cmd_tree_chown(argv[2], argv[3], argv[4]); }
    if (strcmp(argv[1], "tree-fixup") == 0) { if (argc < 5) { usage(); return 2; } return cmd_tree_fixup(argv[2], argv[3], argv[4], argc >= 6 ? argv[5] : "-", argc >= 7 ? argv[6] : "-"); }
    if (strcmp(argv[1], "has-files") == 0) return cmd_has_files(argv[2]);
    if (strcmp(argv[1], "manifest") == 0) { if (argc < 4) { usage(); return 2; } return cmd_manifest(argv[2], argv[3]); }
    if (strcmp(argv[1], "scan-summary") == 0) return cmd_scan_summary(argv[2], argc >= 4 ? argv[3] : "-");
    if (strcmp(argv[1], "path-audit") == 0) { if (argc < 4) { usage(); return 2; } return cmd_path_audit(argv[2], argv[3]); }
    if (strcmp(argv[1], "label-audit") == 0) return cmd_label_audit(argv[2], argc >= 4 ? argv[3] : "4096");
    if (strcmp(argv[1], "facts") == 0) return cmd_facts(argv[2], argc >= 4 ? argv[3] : "-");
    if (strcmp(argv[1], "restore-facts") == 0) return cmd_facts(argv[2], argc >= 4 ? argv[3] : "-");
    if (strcmp(argv[1], "appdetails-index") == 0) { if (argc < 4) { usage(); return 2; } return cmd_appdetails_index(argv[2], argv[3], argc >= 5 ? argv[4] : "2", argc >= 6 ? argv[5] : "0"); }
    if (strcmp(argv[1], "file-list-abs-filter") == 0) { if (argc < 5) { usage(); return 2; } return cmd_file_list_abs_filter(argv[2], argv[3], argv[4], argc >= 6 ? argv[5] : "-"); }
    if (strcmp(argv[1], "selected-list") == 0) { if (argc < 6) { usage(); return 2; } return cmd_selected_list(argv[2], argv[3], argv[4], argv[5]); }
    if (strcmp(argv[1], "apk-size-map") == 0) { if (argc < 4) { usage(); return 2; } return cmd_apk_size_map(argv[2], argv[3]); }
    if (strcmp(argv[1], "backup-prescan-summary") == 0) { if (argc < 10) { usage(); return 2; } return cmd_backup_prescan_summary(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]); }
    if (strcmp(argv[1], "backup-root-index") == 0) { if (argc < 4) { usage(); return 2; } return cmd_backup_root_index(argv[2], argv[3], argc >= 5 ? argv[4] : "3"); }
    if (strcmp(argv[1], "storage-summary") == 0) return cmd_storage_summary(argv[2]);
    if (strcmp(argv[1], "checksum-list") == 0) { if (argc < 4) { usage(); return 2; } return cmd_checksum_list(argv[2], argv[3]); }
    if (strcmp(argv[1], "manifest-verify") == 0) { if (argc < 4) { usage(); return 2; } return cmd_manifest_verify(argv[2], argv[3]); }
    if (strcmp(argv[1], "run-tmpdir-facts") == 0) { if (argc < 4) { usage(); return 2; } return cmd_run_tmpdir_facts(argv[2], argv[3], argc >= 5 ? argv[4] : ".speedbackup_run_"); }
    if (strcmp(argv[1], "zst-file-facts") == 0) return cmd_zst_file_facts(argv[2]);
    usage();
    return 2;
}
