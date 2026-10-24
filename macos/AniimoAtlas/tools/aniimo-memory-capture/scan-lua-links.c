#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

enum { CHUNK_BYTES = 1024 * 1024, MAX_TARGETS = 256, MAX_HEADER_OFFSET = 64,
       MAX_LINK_TARGETS = MAX_TARGETS * (MAX_HEADER_OFFSET + 1) };
static const uint64_t POINTER_MASK = (1ULL << 47) - 1;

typedef struct { uint64_t pointer; size_t original_index; size_t header_offset; } Target;

static int compare_target(const void *left, const void *right) {
    const Target *a = left;
    const Target *b = right;
    return a->pointer < b->pointer ? -1 : a->pointer > b->pointer;
}

static const Target *find_target(const Target *targets, size_t count, uint64_t pointer) {
    size_t low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (targets[middle].pointer < pointer) low = middle + 1;
        else high = middle;
    }
    return low < count && targets[low].pointer == pointer ? &targets[low] : NULL;
}

static uint64_t read_u64(const uint8_t *bytes) {
    uint64_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static bool exact_positive_integer_double(uint64_t raw, uint64_t *output) {
    double value = 0;
    memcpy(&value, &raw, sizeof(value));
    if (!isfinite(value) || value < 1 || value > 9007199254740991.0 || floor(value) != value) {
        return false;
    }
    *output = (uint64_t)value;
    return true;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc - 2 > MAX_TARGETS) {
        fprintf(stderr, "usage: %s PID CONTENT_ADDRESS_HEX...\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    long pid_value = strtol(argv[1], &end, 10);
    if (!end || *end || pid_value <= 0) return 2;
    size_t content_count = (size_t)argc - 2;
    size_t target_count = content_count * (MAX_HEADER_OFFSET + 1);
    Target targets[MAX_LINK_TARGETS];
    for (size_t index = 0; index < content_count; index++) {
        uint64_t content = strtoull(argv[index + 2], &end, 16);
        if (!end || *end || content < MAX_HEADER_OFFSET) return 2;
        for (size_t header = 0; header <= MAX_HEADER_OFFSET; header++) {
            targets[index * (MAX_HEADER_OFFSET + 1) + header] =
                (Target){content - header, index, header};
        }
    }
    qsort(targets, target_count, sizeof(Target), compare_target);

    task_t task = MACH_PORT_NULL;
    kern_return_t result = task_for_pid(mach_task_self(), (pid_t)pid_value, &task);
    if (result != KERN_SUCCESS) {
        fprintf(stderr, "cannot inspect process: %s\n", mach_error_string(result));
        return 1;
    }
    uint8_t *buffer = malloc(CHUNK_BYTES);
    if (!buffer) return 1;
    mach_vm_address_t address = 0;
    uint64_t scanned = 0, regions = 0;
    size_t matches = 0;
    while (true) {
        mach_vm_size_t region_size = 0;
        vm_region_basic_info_data_64_t info = {0};
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        mach_vm_address_t region_address = address;
        result = mach_vm_region(task, &region_address, &region_size, VM_REGION_BASIC_INFO_64,
                                (vm_region_info_t)&info, &count, &object);
        if (result != KERN_SUCCESS) break;
        address = region_address + region_size;
        if (!(info.protection & VM_PROT_READ) || !(info.protection & VM_PROT_WRITE)) continue;
        regions++;
        for (mach_vm_size_t chunk = 0; chunk < region_size; chunk += CHUNK_BYTES) {
            mach_vm_size_t wanted = region_size - chunk;
            if (wanted > CHUNK_BYTES) wanted = CHUNK_BYTES;
            mach_vm_size_t received = 0;
            result = mach_vm_read_overwrite(task, region_address + chunk, wanted,
                                            (mach_vm_address_t)buffer, &received);
            if (result != KERN_SUCCESS || received < 8) continue;
            scanned += received;
            for (size_t offset = 0; offset + 8 <= received; offset += 8) {
                uint64_t raw = read_u64(buffer + offset);
                uint64_t pointer = raw & POINTER_MASK;
                const Target *target = find_target(targets, target_count, pointer);
                if (!target) continue;
                uint64_t instance_id = 0;
                bool has_instance_id = offset + 16 <= received
                    && exact_positive_integer_double(read_u64(buffer + offset + 8), &instance_id);
                printf("0x%llx target=%zu header=%zu object=0x%llx raw=0x%016llx tag=0x%04llx",
                       region_address + chunk + offset, target->original_index,
                       target->header_offset, target->pointer, raw, raw >> 47);
                if (has_instance_id) printf(" instance_candidate=%llu", instance_id);
                putchar('\n');
                matches++;
            }
        }
    }
    fprintf(stderr, "scanned_bytes=%llu regions=%llu contents=%zu link_targets=%zu references=%zu\n",
            scanned, regions, content_count, target_count, matches);
    free(buffer);
    return 0;
}
