// SpeedBackup speedscan r238-api28-r28c-relroguard
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
//   speedscan has-files ROOT           # exit 0 and print 1 when regular file exists, else 1/0
//   speedscan manifest ROOT OUT        # recursive manifest
//   speedscan scan-summary ROOT [MANIFEST_OUT|-] # one walk: size/files/dirs/hasFiles/maxMtime + optional manifest, no hash
//   speedscan path-audit ROOT LIST      # facts-only symlink/root escape/mount-cross audit, no hash
//   speedscan label-audit ROOT [MAX_ROWS] # quick SELinux/xattr ownership audit, no hash
//   speedscan facts ROOT [MANIFEST_OUT|-] # unified summary+manifest facts, no hash

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
#include <dirent.h>
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

static void usage(void) {
    fprintf(stderr, "speedscan r238-api28-r28c-relroguard\n");
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
    fprintf(stderr, "  speedscan has-files ROOT\n");
    fprintf(stderr, "  speedscan manifest ROOT OUT\n");
    fprintf(stderr, "  speedscan scan-summary ROOT [MANIFEST_OUT|-]\n");
    fprintf(stderr, "  speedscan path-audit ROOT LIST\n");
    fprintf(stderr, "  speedscan label-audit ROOT [MAX_ROWS]\n");
    fprintf(stderr, "  speedscan facts ROOT [FACTS_OUT|-]\n");
}

int main(int argc, char **argv) {
    if (argc >= 2 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "version") == 0)) {
        printf("speedscan r238-api28-r28c-relroguard\n");
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
    if (strcmp(argv[1], "has-files") == 0) return cmd_has_files(argv[2]);
    if (strcmp(argv[1], "manifest") == 0) { if (argc < 4) { usage(); return 2; } return cmd_manifest(argv[2], argv[3]); }
    if (strcmp(argv[1], "scan-summary") == 0) return cmd_scan_summary(argv[2], argc >= 4 ? argv[3] : "-");
    if (strcmp(argv[1], "path-audit") == 0) { if (argc < 4) { usage(); return 2; } return cmd_path_audit(argv[2], argv[3]); }
    if (strcmp(argv[1], "label-audit") == 0) return cmd_label_audit(argv[2], argc >= 4 ? argv[3] : "4096");
    if (strcmp(argv[1], "facts") == 0) return cmd_facts(argv[2], argc >= 4 ? argv[3] : "-");
    usage();
    return 2;
}
