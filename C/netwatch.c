/*
 * netwatch.c - Minimal Android/Linux rtnetlink event watcher
 *
 * Subscribes to:
 *   RTMGRP_LINK
 *   RTMGRP_IPV4_IFADDR
 *
 * No timers, no polling, no wake locks. The process blocks in recv()
 * until the kernel reports a link or IPv4 address event.
 *
 * SPDX-License-Identifier: MIT
 */

#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <linux/if_addr.h>
#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define NETWATCH_VERSION "1.2.0-android23-r25c-static-16k"
#define RECEIVE_BUFFER_SIZE (64U * 1024U)

static volatile sig_atomic_t g_stop_requested = 0;

static void handle_signal(int signo) {
    (void)signo;
    g_stop_requested = 1;
}

static int install_signal_handlers(void) {
    const int signals[] = {SIGINT, SIGTERM, SIGHUP};
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0; /* Keep recv() interruptible. */

    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) {
        if (sigaction(signals[i], &action, NULL) != 0) {
            return -1;
        }
    }
    return 0;
}

static const char *message_type_name(uint16_t type) {
    switch (type) {
        case RTM_NEWLINK:
            return "LINK_NEW";
        case RTM_DELLINK:
            return "LINK_DEL";
        case RTM_NEWADDR:
            return "ADDR_NEW";
        case RTM_DELADDR:
            return "ADDR_DEL";
        default:
            return "UNKNOWN";
    }
}

static void resolve_interface_name(unsigned int index,
                                   char *name,
                                   size_t name_size) {
    if (name == NULL || name_size == 0U) {
        return;
    }

    name[0] = '\0';
    if (if_indextoname(index, name) == NULL) {
        (void)snprintf(name, name_size, "if%u", index);
    }
}

static void parse_link_name(const struct nlmsghdr *header,
                            const struct ifinfomsg *info,
                            char *name,
                            size_t name_size) {
    int attribute_length;
    struct rtattr *attribute;

    resolve_interface_name((unsigned int)info->ifi_index, name, name_size);

    attribute_length = IFLA_PAYLOAD(header);
    for (attribute = IFLA_RTA(info);
         RTA_OK(attribute, attribute_length);
         attribute = RTA_NEXT(attribute, attribute_length)) {
        if (attribute->rta_type == IFLA_IFNAME) {
            const char *source = (const char *)RTA_DATA(attribute);
            const size_t payload = (size_t)RTA_PAYLOAD(attribute);

            if (payload > 0U) {
                const size_t copy_length =
                    payload < (name_size - 1U) ? payload : (name_size - 1U);
                memcpy(name, source, copy_length);
                name[copy_length] = '\0';
            }
            break;
        }
    }
}

static void print_link_event(const struct nlmsghdr *header) {
    const struct ifinfomsg *info;
    char interface_name[IF_NAMESIZE];

    if (NLMSG_PAYLOAD(header, 0) < sizeof(*info)) {
        return;
    }

    info = (const struct ifinfomsg *)NLMSG_DATA(header);
    parse_link_name(header, info, interface_name, sizeof(interface_name));

    printf("%s ifindex=%d ifname=%s flags=0x%x change=0x%x\n",
           message_type_name(header->nlmsg_type),
           info->ifi_index,
           interface_name,
           info->ifi_flags,
           info->ifi_change);
}

static void parse_ipv4_address(const struct nlmsghdr *header,
                               const struct ifaddrmsg *info,
                               char *address,
                               size_t address_size) {
    int attribute_length;
    struct rtattr *attribute;
    const void *candidate = NULL;

    if (address == NULL || address_size == 0U) {
        return;
    }
    address[0] = '\0';

    attribute_length = IFA_PAYLOAD(header);
    for (attribute = IFA_RTA(info);
         RTA_OK(attribute, attribute_length);
         attribute = RTA_NEXT(attribute, attribute_length)) {
        if (attribute->rta_type == IFA_LOCAL) {
            candidate = RTA_DATA(attribute);
            break;
        }
        if (attribute->rta_type == IFA_ADDRESS && candidate == NULL) {
            candidate = RTA_DATA(attribute);
        }
    }

    if (candidate != NULL) {
        if (inet_ntop(AF_INET, candidate, address, (socklen_t)address_size) == NULL) {
            address[0] = '\0';
        }
    }
}

static void print_address_event(const struct nlmsghdr *header) {
    const struct ifaddrmsg *info;
    char interface_name[IF_NAMESIZE];
    char address[INET_ADDRSTRLEN];

    if (NLMSG_PAYLOAD(header, 0) < sizeof(*info)) {
        return;
    }

    info = (const struct ifaddrmsg *)NLMSG_DATA(header);
    if (info->ifa_family != AF_INET) {
        return;
    }

    resolve_interface_name(info->ifa_index, interface_name, sizeof(interface_name));
    parse_ipv4_address(header, info, address, sizeof(address));

    printf("%s ifindex=%u ifname=%s address=%s prefixlen=%u scope=%u flags=0x%x\n",
           message_type_name(header->nlmsg_type),
           info->ifa_index,
           interface_name,
           address[0] != '\0' ? address : "-",
           info->ifa_prefixlen,
           info->ifa_scope,
           info->ifa_flags);
}

static int process_netlink_buffer(void *buffer, ssize_t received_length) {
    size_t remaining;
    struct nlmsghdr *header;

    if (buffer == NULL || received_length <= 0) {
        return 0;
    }

    remaining = (size_t)received_length;
    header = (struct nlmsghdr *)buffer;

    while (remaining >= sizeof(*header)) {
        const size_t message_length = (size_t)header->nlmsg_len;
        const size_t aligned_length = (size_t)NLMSG_ALIGN(header->nlmsg_len);

        if (message_length < sizeof(*header) ||
            message_length > remaining ||
            aligned_length > remaining) {
            fputs("netwatch: malformed netlink message\n", stderr);
            return -1;
        }

        switch (header->nlmsg_type) {
            case NLMSG_NOOP:
            case NLMSG_DONE:
                break;

            case NLMSG_OVERRUN:
                puts("NETLINK_OVERRUN");
                break;

            case NLMSG_ERROR: {
                const struct nlmsgerr *error_message;

                if (NLMSG_PAYLOAD(header, 0) < sizeof(*error_message)) {
                    fputs("netwatch: malformed NLMSG_ERROR\n", stderr);
                    return -1;
                }

                error_message =
                    (const struct nlmsgerr *)NLMSG_DATA(header);
                if (error_message->error != 0) {
                    errno = -error_message->error;
                    perror("netwatch: netlink error");
                    return -1;
                }
                break;
            }

            case RTM_NEWLINK:
            case RTM_DELLINK:
                print_link_event(header);
                break;

            case RTM_NEWADDR:
            case RTM_DELADDR:
                print_address_event(header);
                break;

            default:
                break;
        }

        remaining -= aligned_length;
        header = (struct nlmsghdr *)((unsigned char *)header + aligned_length);
    }

    if (remaining != 0U) {
        fputs("netwatch: trailing bytes in netlink buffer\n", stderr);
        return -1;
    }

    return 0;
}

static int run_watcher(void) {
    int socket_fd;
    int receive_buffer_bytes = 256 * 1024;
    struct sockaddr_nl local_address;
    unsigned char buffer[RECEIVE_BUFFER_SIZE];

    socket_fd = socket(AF_NETLINK,
                       SOCK_RAW | SOCK_CLOEXEC,
                       NETLINK_ROUTE);
    if (socket_fd < 0) {
        perror("netwatch: socket");
        return 1;
    }

    (void)setsockopt(socket_fd,
                     SOL_SOCKET,
                     SO_RCVBUF,
                     &receive_buffer_bytes,
                     sizeof(receive_buffer_bytes));

    memset(&local_address, 0, sizeof(local_address));
    local_address.nl_family = AF_NETLINK;
    local_address.nl_pid = (uint32_t)getpid();
    local_address.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR;

    if (bind(socket_fd,
             (const struct sockaddr *)&local_address,
             sizeof(local_address)) != 0) {
        perror("netwatch: bind");
        close(socket_fd);
        return 1;
    }

    setvbuf(stdout, NULL, _IOLBF, 0);

    while (!g_stop_requested) {
        const ssize_t received_length =
            recv(socket_fd, buffer, sizeof(buffer), 0);

        if (received_length < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("netwatch: recv");
            close(socket_fd);
            return 1;
        }

        if (received_length == 0) {
            continue;
        }

        if (process_netlink_buffer(buffer, received_length) != 0) {
            close(socket_fd);
            return 1;
        }
    }

    close(socket_fd);
    return 0;
}

static void print_help(const char *program_name) {
    printf("用法: %s [--help|--version]\n", program_name);
    puts("監看 Linux/Android 介面與 IPv4 位址的 rtnetlink 事件。");
    puts("閒置時阻塞在 recv()，不使用定時器、輪詢或 WakeLock。");
}

int main(int argc, char **argv) {
    if (argc > 2) {
        print_help(argv[0]);
        return 2;
    }

    if (argc == 2) {
        if (strcmp(argv[1], "--version") == 0) {
            printf("netwatch %s\n", NETWATCH_VERSION);
            return 0;
        }
        if (strcmp(argv[1], "--help") == 0 ||
            strcmp(argv[1], "-h") == 0) {
            print_help(argv[0]);
            return 0;
        }

        fprintf(stderr, "netwatch: 未知參數: %s\n", argv[1]);
        print_help(argv[0]);
        return 2;
    }

    if (install_signal_handlers() != 0) {
        perror("netwatch: sigaction");
        return 1;
    }

    return run_watcher();
}
