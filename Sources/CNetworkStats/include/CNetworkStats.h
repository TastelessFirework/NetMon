#ifndef CNetworkStats_h
#define CNetworkStats_h

#include <stdint.h>

typedef struct nm_interface_counters {
    uint64_t received_bytes;
    uint64_t transmitted_bytes;
    int is_up;
    int is_running;
} nm_interface_counters;

/// Reads Darwin's 64-bit per-interface counters through NET_RT_IFLIST2.
/// Returns 0 on success or an errno-compatible value on failure.
int nm_read_interface_counters(const char *interface_name,
                               nm_interface_counters *result);

#endif
