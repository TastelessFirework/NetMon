#include "CNetworkStats.h"

#include <errno.h>
#include <net/if.h>
#include <net/route.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

int nm_read_interface_counters(const char *interface_name,
                               nm_interface_counters *result) {
    if (interface_name == NULL || result == NULL) {
        return EINVAL;
    }

    unsigned int interface_index = if_nametoindex(interface_name);
    if (interface_index == 0) {
        return errno == 0 ? ENOENT : errno;
    }

    int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2,
                   (int)interface_index };
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0) {
        return errno;
    }

    char *buffer = malloc(length);
    if (buffer == NULL) {
        return ENOMEM;
    }

    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) {
        int saved_errno = errno;
        free(buffer);
        return saved_errno;
    }

    int status = ENOENT;
    char *cursor = buffer;
    char *end = buffer + length;
    while (cursor + sizeof(struct if_msghdr) <= end) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (header->ifm_msglen == 0 || cursor + header->ifm_msglen > end) {
            status = EPROTO;
            break;
        }

        if (header->ifm_type == RTM_IFINFO2 &&
            header->ifm_msglen >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            if ((unsigned int)info->ifm_index == interface_index) {
                result->received_bytes = info->ifm_data.ifi_ibytes;
                result->transmitted_bytes = info->ifm_data.ifi_obytes;
                result->is_up = (info->ifm_flags & IFF_UP) != 0;
                result->is_running = (info->ifm_flags & IFF_RUNNING) != 0;
                status = 0;
                break;
            }
        }

        cursor += header->ifm_msglen;
    }

    free(buffer);
    return status;
}
