#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define VERSION "unixsock 2.1.0-stream-framed"
#define COPY_BUFFER_SIZE (128 * 1024)
#define HEADER_LINE_MAX 4096

static int read_header_line(int fd, char *buffer, size_t capacity, size_t *length_out);

static void usage(FILE *out) {
    fprintf(out,
            "%s\n"
            "Usage:\n"
            "  unixsock relay-unix <socketPath> [--header-file <path>]\n"
            "  unixsock relay-tcp <host> <port> [--header-file <path>]\n"
            "\n"
            "stdin is copied to the socket. At stdin EOF the write side is half-closed,\n"
            "while the socket response continues to stdout. With --header-file, the first\n"
            "two newline-terminated response lines are written to that file and only the\n"
            "remaining binary body is written to stdout. The second header line may be\n"
            "an exact byte count, -1 (raw until EOF), or -2 (daemon chunk framing).\n",
            VERSION);
}

static int write_all(int fd, const void *buffer, size_t length) {
    const uint8_t *p = (const uint8_t *)buffer;
    while (length > 0) {
        ssize_t n = write(fd, p, length);
        if (n > 0) {
            p += (size_t)n;
            length -= (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        return -1;
    }
    return 0;
}

static int copy_fd(int input_fd, int output_fd, int ignore_epipe) {
    uint8_t *buffer = (uint8_t *)malloc(COPY_BUFFER_SIZE);
    if (buffer == NULL) return -1;

    int result = 0;
    for (;;) {
        ssize_t n = read(input_fd, buffer, COPY_BUFFER_SIZE);
        if (n == 0) break;
        if (n < 0) {
            if (errno == EINTR) continue;
            result = -1;
            break;
        }
        size_t offset = 0;
        while (offset < (size_t)n) {
            ssize_t written = write(output_fd, buffer + offset, (size_t)n - offset);
            if (written > 0) {
                offset += (size_t)written;
                continue;
            }
            if (written < 0 && errno == EINTR) continue;
            if (written < 0 && errno == EPIPE && ignore_epipe) {
                result = 1;
            } else {
                result = -1;
            }
            free(buffer);
            return result;
        }
    }

    free(buffer);
    return result;
}

static int write_stdout(const uint8_t *buffer, size_t length, int *consumer_closed) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t n = write(STDOUT_FILENO, buffer + offset, length - offset);
        if (n > 0) {
            offset += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && errno == EPIPE) {
            *consumer_closed = 1;
            return 1;
        }
        return -1;
    }
    return 0;
}

static int copy_exact_response(int input_fd, uint64_t expected, int *consumer_closed) {
    uint8_t *buffer = (uint8_t *)malloc(COPY_BUFFER_SIZE);
    if (buffer == NULL) return -1;

    uint64_t remaining = expected;
    int result = 0;
    while (remaining > 0) {
        size_t want = remaining < COPY_BUFFER_SIZE ? (size_t)remaining : COPY_BUFFER_SIZE;
        ssize_t n = read(input_fd, buffer, want);
        if (n == 0) {
            errno = EPROTO;
            result = -1;
            break;
        }
        if (n < 0) {
            if (errno == EINTR) continue;
            result = -1;
            break;
        }
        int write_result = write_stdout(buffer, (size_t)n, consumer_closed);
        if (write_result != 0) {
            result = write_result;
            break;
        }
        remaining -= (uint64_t)n;
    }

    free(buffer);
    return result;
}

static int read_exact_discard_or_stdout(int input_fd, uint64_t length, int *consumer_closed) {
    return copy_exact_response(input_fd, length, consumer_closed);
}

static int consume_crlf(int fd) {
    uint8_t pair[2];
    size_t offset = 0;
    while (offset < sizeof(pair)) {
        ssize_t n = read(fd, pair + offset, sizeof(pair) - offset);
        if (n > 0) {
            offset += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        errno = EPROTO;
        return -1;
    }
    if (pair[0] != '\r' || pair[1] != '\n') {
        errno = EPROTO;
        return -1;
    }
    return 0;
}

static int relay_daemon_chunks(int fd, int *consumer_closed) {
    char line[HEADER_LINE_MAX];
    size_t line_length = 0;

    for (;;) {
        if (read_header_line(fd, line, sizeof(line), &line_length) != 0) return -1;
        char *extension = strchr(line, ';');
        if (extension != NULL) *extension = '\0';
        errno = 0;
        char *end = NULL;
        unsigned long long chunk_size = strtoull(line, &end, 16);
        if (errno != 0 || end == line || *end != '\0') {
            errno = EPROTO;
            return -1;
        }
        if (chunk_size == 0) {
            if (read_header_line(fd, line, sizeof(line), &line_length) != 0 || line_length != 0) {
                errno = EPROTO;
                return -1;
            }
            return 0;
        }
        int copy_result = read_exact_discard_or_stdout(fd, (uint64_t)chunk_size, consumer_closed);
        if (copy_result != 0) return copy_result;
        if (consume_crlf(fd) != 0) return -1;
    }
}

static int parse_body_mode(const char *line, long long *value_out) {
    if (line == NULL || *line == '\0') return -1;
    errno = 0;
    char *end = NULL;
    long long value = strtoll(line, &end, 10);
    if (errno != 0 || end == line || *end != '\0' || value < -2) return -1;
    *value_out = value;
    return 0;
}

static int read_header_line(int fd, char *buffer, size_t capacity, size_t *length_out) {
    size_t length = 0;
    if (capacity == 0) return -1;

    while (length + 1 < capacity) {
        uint8_t byte;
        ssize_t n = read(fd, &byte, 1);
        if (n == 0) { errno = EPROTO; return -1; }
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (byte == '\n') {
            buffer[length] = '\0';
            if (length > 0 && buffer[length - 1] == '\r') {
                buffer[--length] = '\0';
            }
            *length_out = length;
            return 0;
        }
        buffer[length++] = (char)byte;
    }

    errno = EMSGSIZE;
    return -1;
}

static int write_response_header_file(const char *path,
                                      const char *line1,
                                      size_t length1,
                                      const char *line2,
                                      size_t length2) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) return -1;

    int result = 0;
    if (fchmod(fd, 0600) != 0 ||
        write_all(fd, line1, length1) != 0 ||
        write_all(fd, "\n", 1) != 0 ||
        write_all(fd, line2, length2) != 0 ||
        write_all(fd, "\n", 1) != 0) {
        result = -1;
    }
    if (close(fd) != 0 && result == 0) result = -1;
    return result;
}

static int connect_unix_socket(const char *path) {
    if (path == NULL || path[0] != '/') {
        errno = EINVAL;
        return -1;
    }

    size_t length = strlen(path);
    struct sockaddr_un address;
    if (length >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;

    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, length + 1);

    socklen_t address_length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + length + 1);
    if (connect(fd, (struct sockaddr *)&address, address_length) != 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    return fd;
}

static int connect_tcp_socket(const char *host, const char *port) {
    struct addrinfo hints;
    struct addrinfo *result = NULL;
    struct addrinfo *item;
    int fd = -1;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    int rc = getaddrinfo(host, port, &hints, &result);
    if (rc != 0) {
        fprintf(stderr, "unixsock: getaddrinfo: %s\n", gai_strerror(rc));
        return -1;
    }

    for (item = result; item != NULL; item = item->ai_next) {
        fd = socket(item->ai_family, item->ai_socktype | SOCK_CLOEXEC, item->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, item->ai_addr, item->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }

    freeaddrinfo(result);
    return fd;
}

static int parse_header_file_arg(int argc, char **argv, int start_index, const char **header_file) {
    *header_file = NULL;
    int index = start_index;
    while (index < argc) {
        if (strcmp(argv[index], "--header-file") == 0) {
            if (index + 1 >= argc || argv[index + 1][0] == '\0') return -1;
            *header_file = argv[index + 1];
            index += 2;
            continue;
        }
        return -1;
    }
    return 0;
}

static int relay_connection(int socket_fd, const char *header_file) {
    signal(SIGPIPE, SIG_IGN);

    pid_t writer_pid = fork();
    if (writer_pid < 0) {
        perror("unixsock: fork");
        close(socket_fd);
        return 4;
    }

    if (writer_pid == 0) {
        int result = copy_fd(STDIN_FILENO, socket_fd, 0);
        if (shutdown(socket_fd, SHUT_WR) != 0 && errno != ENOTCONN && errno != EPIPE) {
            result = -1;
        }
        close(socket_fd);
        _exit(result == 0 ? 0 : 4);
    }

    int response_result = 0;
    int consumer_closed = 0;
    long long body_mode = -1;

    if (header_file != NULL) {
        char line1[HEADER_LINE_MAX];
        char line2[HEADER_LINE_MAX];
        size_t length1 = 0;
        size_t length2 = 0;
        if (read_header_line(socket_fd, line1, sizeof(line1), &length1) != 0 ||
            read_header_line(socket_fd, line2, sizeof(line2), &length2) != 0) {
            fprintf(stderr, "unixsock: invalid or incomplete response header: %s\n", strerror(errno));
            response_result = -1;
        } else if (parse_body_mode(line2, &body_mode) != 0) {
            fprintf(stderr, "unixsock: invalid response body mode: %s\n", line2);
            response_result = -1;
        } else if (write_response_header_file(header_file, line1, length1, line2, length2) != 0) {
            fprintf(stderr, "unixsock: cannot write header file %s: %s\n", header_file, strerror(errno));
            response_result = -1;
        }
    }

    if (response_result == 0) {
        int copy_result;
        if (header_file == NULL || body_mode == -1) {
            copy_result = copy_fd(socket_fd, STDOUT_FILENO, 1);
        } else if (body_mode == -2) {
            copy_result = relay_daemon_chunks(socket_fd, &consumer_closed);
        } else {
            copy_result = copy_exact_response(socket_fd, (uint64_t)body_mode, &consumer_closed);
        }
        if (copy_result == 1 || consumer_closed) {
            consumer_closed = 1;
            shutdown(socket_fd, SHUT_RDWR);
        } else if (copy_result != 0) {
            fprintf(stderr, "unixsock: response copy failed: %s\n", strerror(errno));
            response_result = -1;
        }
    }

    close(socket_fd);

    int writer_status = 0;
    while (waitpid(writer_pid, &writer_status, 0) < 0) {
        if (errno == EINTR) continue;
        writer_status = -1;
        break;
    }

    if (response_result != 0) return 5;
    if (consumer_closed) return 0;
    if (writer_status == -1 || !WIFEXITED(writer_status) || WEXITSTATUS(writer_status) != 0) {
        fprintf(stderr, "unixsock: request copy failed\n");
        return 4;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "version") == 0)) {
        puts(VERSION);
        return 0;
    }
    if (argc < 3) {
        usage(stderr);
        return 2;
    }

    const char *header_file = NULL;
    int socket_fd = -1;

    if (strcmp(argv[1], "relay-unix") == 0 || strcmp(argv[1], "relay") == 0) {
        if (parse_header_file_arg(argc, argv, 3, &header_file) != 0) {
            usage(stderr);
            return 2;
        }
        socket_fd = connect_unix_socket(argv[2]);
    } else if (strcmp(argv[1], "relay-tcp") == 0) {
        if (argc < 4 || parse_header_file_arg(argc, argv, 4, &header_file) != 0) {
            usage(stderr);
            return 2;
        }
        socket_fd = connect_tcp_socket(argv[2], argv[3]);
    } else {
        usage(stderr);
        return 2;
    }

    if (socket_fd < 0) {
        fprintf(stderr, "unixsock: connect failed: %s\n", strerror(errno));
        return 3;
    }

    return relay_connection(socket_fd, header_file);
}
