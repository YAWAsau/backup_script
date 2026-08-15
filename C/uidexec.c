#define _GNU_SOURCE

#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define UIDEXEC_VERSION "1.0.0-android28-r28c-dyn16k-relroguard-r238"

static int debug_enabled(void) {
    const char *debug = getenv("UIDEXEC_DEBUG");
    return debug != NULL && strcmp(debug, "0") != 0 && debug[0] != '\0';
}

static long parse_long(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;

    long v = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || v < 0) {
        fprintf(stderr, "bad %s: %s\n", name, s != NULL ? s : "(null)");
        exit(2);
    }

    return v;
}

static void die(const char *msg) {
    fprintf(stderr, "%s: %s\n", msg, strerror(errno));
    exit(1);
}

static void die_msg(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

static void debug_log(const char *msg) {
    if (debug_enabled()) {
        fprintf(stderr, "%s\n", msg);
    }
}

static void usage(const char *prog) {
    fprintf(stderr,
        "usage:\n"
        "  %s <uid> <gid> <android_data_dir> -- <cmd> [args...]\n"
        "  %s <uid> <gid> <android_data_dir> <classpath> <cmd> [args...]  # legacy\n"
        "  %s <uid> <gid> <android_data_dir> --classpath <classpath> -- <cmd> [args...]\n",
        prog, prog, prog);
}

static void make_tmpdir(const char *android_data, uid_t uid, gid_t gid) {
    char tmpdir[PATH_MAX];
    int n = snprintf(tmpdir, sizeof(tmpdir), "%s/tmp", android_data);
    if (n < 0 || (size_t)n >= sizeof(tmpdir)) {
        die_msg("TMPDIR path too long");
    }

    if (mkdir(tmpdir, 0700) != 0 && errno != EEXIST) {
        die("mkdir TMPDIR");
    }

    /*
     * Best effort: uidexec normally starts as root, but do not make old
     * caller environments fail merely because ownership/mode cannot be
     * adjusted on a special directory.
     */
    if (chown(tmpdir, uid, gid) != 0 && debug_enabled()) {
        fprintf(stderr, "warn: chown TMPDIR failed: %s\n", strerror(errno));
    }

    if (chmod(tmpdir, 0700) != 0 && debug_enabled()) {
        fprintf(stderr, "warn: chmod TMPDIR failed: %s\n", strerror(errno));
    }

    if (setenv("TMPDIR", tmpdir, 1) != 0) {
        die("setenv TMPDIR");
    }
}

static void harden_process(void) {
    umask(0077);

#ifdef PR_SET_DUMPABLE
    if (prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0) {
        debug_log("warn: PR_SET_DUMPABLE failed");
    }
#endif
}

static void drop_identity(uid_t uid, gid_t gid) {
    gid_t groups[1];
    groups[0] = gid;

    /* Preserve the original behavior: keep exactly the target primary GID as supplementary group. */
    if (setgroups(1, groups) != 0) {
        die("setgroups");
    }

    if (setresgid(gid, gid, gid) != 0) {
        die("setresgid");
    }

    if (setresuid(uid, uid, uid) != 0) {
        die("setresuid");
    }

    uid_t ruid = (uid_t)-1;
    uid_t euid = (uid_t)-1;
    uid_t suid = (uid_t)-1;
    gid_t rgid = (gid_t)-1;
    gid_t egid = (gid_t)-1;
    gid_t sgid = (gid_t)-1;

    if (getresuid(&ruid, &euid, &suid) != 0) {
        die("getresuid");
    }
    if (getresgid(&rgid, &egid, &sgid) != 0) {
        die("getresgid");
    }

    if (ruid != uid || euid != uid || suid != uid || rgid != gid || egid != gid || sgid != gid) {
        fprintf(stderr,
                "identity mismatch: uid=%ld/%ld/%ld expected=%ld gid=%ld/%ld/%ld expected=%ld\n",
                (long)ruid, (long)euid, (long)suid, (long)uid,
                (long)rgid, (long)egid, (long)sgid, (long)gid);
        exit(1);
    }
}

int main(int argc, char **argv) {
    if (argc == 2 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "version") == 0)) {
        printf("uidexec %s\n", UIDEXEC_VERSION);
        return 0;
    }

    if (argc < 6) {
        usage(argv[0]);
        return 2;
    }

    uid_t uid = (uid_t)parse_long(argv[1], "uid");
    gid_t gid = (gid_t)parse_long(argv[2], "gid");
    const char *android_data = argv[3];

    if (android_data == NULL || android_data[0] == '\0') {
        die_msg("bad android_data_dir");
    }

    const char *classpath = NULL;
    int cmd_index = -1;

    /*
     * Supported formats:
     *
     * New no-classpath mode:
     *   uidexec <uid> <gid> <android_data_dir> -- <cmd> [args...]
     *
     * New explicit classpath mode:
     *   uidexec <uid> <gid> <android_data_dir> --classpath <classpath> -- <cmd> [args...]
     *
     * Legacy mode:
     *   uidexec <uid> <gid> <android_data_dir> <classpath> <cmd> [args...]
     */
    if (strcmp(argv[4], "--") == 0) {
        cmd_index = 5;
    } else if (strcmp(argv[4], "--classpath") == 0) {
        if (argc < 8) {
            usage(argv[0]);
            return 2;
        }

        classpath = argv[5];

        if (strcmp(argv[6], "--") == 0) {
            cmd_index = 7;
        } else {
            /* Also tolerate: uidexec uid gid data --classpath classes.dex app_process ... */
            cmd_index = 6;
        }
    } else {
        /* Legacy compatibility: argv[4] = classpath, argv[5] = command */
        classpath = argv[4];
        cmd_index = 5;
    }

    if (cmd_index < 0 || cmd_index >= argc || argv[cmd_index] == NULL) {
        usage(argv[0]);
        return 2;
    }

    harden_process();

    if (setenv("ANDROID_DATA", android_data, 1) != 0) {
        die("setenv ANDROID_DATA");
    }

    if (classpath != NULL && classpath[0] != '\0') {
        if (setenv("CLASSPATH", classpath, 1) != 0) {
            die("setenv CLASSPATH");
        }
    } else {
        unsetenv("CLASSPATH");
    }

    make_tmpdir(android_data, uid, gid);

    /*
     * Keep existing PATH if caller already supplied one.
     * Otherwise set a sane Android default.
     */
    setenv(
        "PATH",
        "/system/bin:/system/xbin:/vendor/bin:/product/bin:/apex/com.android.runtime/bin",
        0
    );

    drop_identity(uid, gid);

    if (debug_enabled()) {
        fprintf(stderr, "running as uid=%d gid=%d\n", getuid(), getgid());
    }

    execvp(argv[cmd_index], &argv[cmd_index]);
    die("execvp");
    return 1;
}
