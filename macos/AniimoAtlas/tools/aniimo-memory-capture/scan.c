#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_region.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    CHUNK_BYTES = 1024 * 1024,
    OVERLAP_BYTES = 64,
    MIN_BASE64_BYTES = 16,
    MAX_BASE64_BYTES = 36,
    MAX_RESULTS = 100000,
};

typedef struct {
    uint64_t hash;
    mach_vm_address_t address;
    char encoded[MAX_BASE64_BYTES + 1];
} SeenResult;

static SeenResult results[MAX_RESULTS];
static size_t result_count = 0;

static uint16_t read_u16(const uint8_t *bytes, size_t offset) {
    return (uint16_t)bytes[offset] | ((uint16_t)bytes[offset + 1] << 8);
}

static int16_t read_i16(const uint8_t *bytes, size_t offset) {
    return (int16_t)read_u16(bytes, offset);
}

static uint32_t read_u32(const uint8_t *bytes, size_t offset) {
    return (uint32_t)bytes[offset]
        | ((uint32_t)bytes[offset + 1] << 8)
        | ((uint32_t)bytes[offset + 2] << 16)
        | ((uint32_t)bytes[offset + 3] << 24);
}

static bool is_base64_char(uint8_t value) {
    return (value >= 'A' && value <= 'Z')
        || (value >= 'a' && value <= 'z')
        || (value >= '0' && value <= '9')
        || value == '+' || value == '/' || value == '=';
}

static int base64_value(uint8_t value) {
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '+') return 62;
    if (value == '/') return 63;
    return -1;
}

static bool decode_base64(const uint8_t *input, size_t length, uint8_t *output, size_t *output_length) {
    if (length % 4 != 0 || length < MIN_BASE64_BYTES || length > MAX_BASE64_BYTES) return false;
    size_t padding = 0;
    if (length && input[length - 1] == '=') padding++;
    if (length > 1 && input[length - 2] == '=') padding++;
    for (size_t index = 0; index + padding < length; index++) {
        if (input[index] == '=' || base64_value(input[index]) < 0) return false;
    }
    for (size_t index = length - padding; index < length; index++) {
        if (input[index] != '=') return false;
    }

    size_t out = 0;
    for (size_t index = 0; index < length; index += 4) {
        int a = base64_value(input[index]);
        int b = base64_value(input[index + 1]);
        int c = input[index + 2] == '=' ? 0 : base64_value(input[index + 2]);
        int d = input[index + 3] == '=' ? 0 : base64_value(input[index + 3]);
        if (a < 0 || b < 0 || c < 0 || d < 0) return false;
        uint32_t triple = ((uint32_t)a << 18) | ((uint32_t)b << 12) | ((uint32_t)c << 6) | (uint32_t)d;
        output[out++] = (triple >> 16) & 0xff;
        if (input[index + 2] != '=') output[out++] = (triple >> 8) & 0xff;
        if (input[index + 3] != '=') output[out++] = triple & 0xff;
    }
    *output_length = out;
    return true;
}

static bool decode_ornament(const uint8_t *bytes, size_t length, uint16_t *flags_out, uint32_t *home_id_out,
                            int16_t position[3], uint16_t rotation[3], uint16_t scale[3],
                            uint16_t *trash_out, uint8_t *area_out, bool *electric_out) {
    if (length < 12 || length > 27) return false;
    uint16_t flags = read_u16(bytes, 0);
    const uint16_t known_flags = 0x07ff;
    if ((flags & ~known_flags) != 0 || ((flags & 0x0004) && (flags & 0x0008))) return false;

    size_t expected = 12;
    if (flags & 0x0001) expected += 2;
    if (flags & 0x0002) expected += 4;
    if (flags & 0x0004) expected += 2;
    else if (flags & 0x0008) expected += 6;
    if (flags & 0x0010) expected += 2;
    if (flags & 0x0400) expected += 1;
    if (length != expected) return false;

    uint32_t home_id = read_u32(bytes, 2);
    if (home_id == 0) return false;
    position[0] = read_i16(bytes, 6);
    position[1] = read_i16(bytes, 8);
    position[2] = read_i16(bytes, 10);
    rotation[0] = rotation[1] = rotation[2] = 0;
    scale[0] = scale[1] = scale[2] = 1000;
    uint16_t trash = 0;
    size_t cursor = 12;
    if (flags & 0x0001) {
        rotation[1] = read_u16(bytes, cursor);
        cursor += 2;
    }
    if (flags & 0x0002) {
        rotation[0] = read_u16(bytes, cursor);
        rotation[2] = read_u16(bytes, cursor + 2);
        cursor += 4;
    }
    if (flags & 0x0004) {
        scale[0] = scale[1] = scale[2] = read_u16(bytes, cursor);
        cursor += 2;
    } else if (flags & 0x0008) {
        scale[0] = read_u16(bytes, cursor);
        scale[1] = read_u16(bytes, cursor + 2);
        scale[2] = read_u16(bytes, cursor + 4);
        cursor += 6;
    }
    if (flags & 0x0010) {
        trash = read_u16(bytes, cursor);
        cursor += 2;
    }
    uint8_t area = (flags >> 6) & 0x0f;
    if (flags & 0x0400) area = bytes[cursor];

    *flags_out = flags;
    *home_id_out = home_id;
    *trash_out = trash;
    *area_out = area;
    *electric_out = (flags & 0x0020) != 0;
    return true;
}

static uint64_t fnv1a(const uint8_t *bytes, size_t length) {
    uint64_t hash = 1469598103934665603ULL;
    for (size_t index = 0; index < length; index++) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static bool remember_result(const uint8_t *encoded, size_t length, mach_vm_address_t address) {
    uint64_t hash = fnv1a(encoded, length);
    for (size_t index = 0; index < result_count; index++) {
        if (results[index].address == address && results[index].hash == hash && strlen(results[index].encoded) == length
            && memcmp(results[index].encoded, encoded, length) == 0) return false;
    }
    if (result_count >= MAX_RESULTS) return false;
    results[result_count].hash = hash;
    results[result_count].address = address;
    memcpy(results[result_count].encoded, encoded, length);
    results[result_count].encoded[length] = '\0';
    result_count++;
    return true;
}

static void scan_buffer(const uint8_t *buffer, size_t length, mach_vm_address_t base_address) {
    size_t index = 0;
    while (index < length) {
        if (!is_base64_char(buffer[index])) { index++; continue; }
        size_t start = index;
        while (index < length && is_base64_char(buffer[index])) index++;
        size_t token_length = index - start;
        if (token_length < MIN_BASE64_BYTES || token_length > MAX_BASE64_BYTES || token_length % 4 != 0) continue;

        uint8_t decoded[32];
        size_t decoded_length = 0;
        if (!decode_base64(buffer + start, token_length, decoded, &decoded_length)) continue;
        uint16_t flags, rotation[3], scale[3], trash;
        uint32_t home_id;
        int16_t position[3];
        uint8_t area;
        bool electric;
        if (!decode_ornament(decoded, decoded_length, &flags, &home_id, position, rotation, scale,
                             &trash, &area, &electric)) continue;
        // The same encoded record may exist in a serialized buffer and as a
        // Lua TString. Preserve distinct addresses so ownership resolution can
        // follow the actual table value, not just the first textual copy.
        if (!remember_result(buffer + start, token_length, base_address + start)) continue;
        printf("{\"encoded\":\"%.*s\",\"address\":\"0x%llx\",\"flags\":%u,\"homeId\":%u,"
               "\"position\":[%d,%d,%d],\"rotation\":[%u,%u,%u],"
               "\"scale\":[%u,%u,%u],\"trashId\":%u,\"areaId\":%u,\"electricMode\":%s}\n",
               (int)token_length, buffer + start, base_address + start, flags, home_id,
               position[0], position[1], position[2], rotation[0], rotation[1], rotation[2],
               scale[0], scale[1], scale[2], trash, area, electric ? "true" : "false");
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s PID\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    long pid_value = strtol(argv[1], &end, 10);
    if (!end || *end != '\0' || pid_value <= 0) {
        fprintf(stderr, "invalid PID\n");
        return 2;
    }

    task_t task = MACH_PORT_NULL;
    kern_return_t result = task_for_pid(mach_task_self(), (pid_t)pid_value, &task);
    if (result != KERN_SUCCESS) {
        fprintf(stderr, "cannot inspect process: %s\n", mach_error_string(result));
        return 1;
    }

    uint8_t *buffer = malloc(CHUNK_BYTES + OVERLAP_BYTES);
    if (!buffer) return 1;
    mach_vm_address_t address = 0;
    uint64_t scanned = 0;
    uint64_t regions = 0;

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

        size_t carry = 0;
        for (mach_vm_size_t offset = 0; offset < region_size; offset += CHUNK_BYTES) {
            mach_vm_size_t wanted = region_size - offset;
            if (wanted > CHUNK_BYTES) wanted = CHUNK_BYTES;
            mach_vm_size_t received = 0;
            result = mach_vm_read_overwrite(task, region_address + offset, wanted,
                                            (mach_vm_address_t)(buffer + carry), &received);
            if (result != KERN_SUCCESS || received == 0) { carry = 0; continue; }
            mach_vm_address_t buffer_address = region_address + offset - carry;
            scan_buffer(buffer, carry + (size_t)received, buffer_address);
            scanned += received;
            size_t available = carry + (size_t)received;
            carry = available < OVERLAP_BYTES ? available : OVERLAP_BYTES;
            memmove(buffer, buffer + available - carry, carry);
        }
    }

    fprintf(stderr, "scanned_bytes=%llu readable_writable_regions=%llu record_copies=%zu result_limit=%u\n",
            scanned, regions, result_count, MAX_RESULTS);
    free(buffer);
    return 0;
}
