/*
 * propwait.c - Blocking Android system property waiter
 * SPDX-License-Identifier: MIT
 */
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/system_properties.h>

#define PROPWAIT_VERSION "1.0.1-android23-r25c-static16k"

/*
 * Android 6.0 already provides these bionic symbols, but the modern NDK
 * public header intentionally omits their declarations because they are
 * legacy/deprecated property APIs. Declare the exact C ABI explicitly.
 */
extern uint32_t __system_property_area_serial(void);
extern uint32_t __system_property_wait_any(uint32_t old_serial);
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

static int read_property(const char *name, char value[PROP_VALUE_MAX]) {
    const int length = __system_property_get(name, value);
    if (length < 0) { value[0] = '\0'; return -1; }
    return length;
}

static bool matches(const char *mode, const char *value,
                    const char *expected, const char *initial) {
    if (strcmp(mode, "equals") == 0) return strcmp(value, expected) == 0;
    if (strcmp(mode, "exists") == 0) return value[0] != '\0';
    if (strcmp(mode, "change") == 0) return strcmp(value, initial) != 0;
    return false;
}

static int wait_property(const char *mode, const char *name,
                         const char *expected) {
    char initial[PROP_VALUE_MAX];
    char value[PROP_VALUE_MAX];

    if (read_property(name, initial) < 0) {
        perror("propwait: property read"); return 1;
    }

    for (;;) {
        const uint32_t serial = __system_property_area_serial();
        if (read_property(name, value) < 0) {
            perror("propwait: property read"); return 1;
        }
        if (matches(mode, value, expected, initial)) {
            printf("MATCH name=%s value=%s\n", name, value);
            return 0;
        }
        if (g_stop) return 130;
        (void)__system_property_wait_any(serial);
        if (g_stop) return 130;
    }
}

static void print_help(const char *program) {
    printf("用法:\n  %s equals NAME VALUE\n  %s exists NAME\n"
           "  %s change NAME\n  %s get NAME\n\n",
           program, program, program, program);
    puts("範例：propwait equals sys.boot_completed 1");
    puts("使用 bionic property wait，不執行 getprop+sleep 輪詢。");
}

int main(int argc, char **argv) {
    char value[PROP_VALUE_MAX];
    if (install_signals() != 0) { perror("propwait: sigaction"); return 1; }

    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        printf("propwait %s\n", PROPWAIT_VERSION); return 0;
    }
    if (argc == 2 && (strcmp(argv[1], "--help") == 0 ||
                      strcmp(argv[1], "-h") == 0)) {
        print_help(argv[0]); return 0;
    }
    if (argc == 3 && strcmp(argv[1], "get") == 0) {
        if (read_property(argv[2], value) < 0) {
            perror("propwait: property read"); return 1;
        }
        puts(value); return 0;
    }
    if (argc == 3 && strcmp(argv[1], "exists") == 0)
        return wait_property("exists", argv[2], "");
    if (argc == 3 && strcmp(argv[1], "change") == 0)
        return wait_property("change", argv[2], "");
    if (argc == 4 && strcmp(argv[1], "equals") == 0)
        return wait_property("equals", argv[2], argv[3]);

    print_help(argv[0]);
    return 2;
}
