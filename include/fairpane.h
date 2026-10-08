#ifndef FAIRPANE_H
#define FAIRPANE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(FAIRPANE_SHARED)
#  if defined(FAIRPANE_BUILD)
#    define FP_API __declspec(dllexport)
#  else
#    define FP_API __declspec(dllimport)
#  endif
#else
#  define FP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Experimental ABI revision zero. No stability promise exists yet. */
#define FP_STATUS_OK UINT32_C(0)
#define FP_STATUS_INVALID_ARGUMENT UINT32_C(1)

typedef struct fp_capabilities {
    uint32_t struct_size;
    uint32_t abi_revision;
    uint64_t feature_bits;
} fp_capabilities;

FP_API uint32_t fp_abi_revision(void);

/* On success, this function initializes sizeof(fp_capabilities) bytes.
 * The feature mask is zero in the bootstrap.
 * A non-null output pointer must reference a writable, aligned object.
 * On invalid size or null output, no output bytes change.
 */
FP_API uint32_t fp_query_capabilities(fp_capabilities *out, size_t out_size);

#ifdef __cplusplus
}
#endif
#endif
