#include "fairpane.h"
#include <assert.h>
#include <stddef.h>

_Static_assert(sizeof(uint32_t) == 4, "A 32-bit uint32_t is required");
_Static_assert(offsetof(fp_capabilities, abi_revision) == 4, "Unexpected revision offset");
_Static_assert(offsetof(fp_capabilities, feature_bits) == 8, "Unexpected feature offset");
_Static_assert(sizeof(fp_capabilities) == 16, "Unexpected capability structure size");

int main(void) {
    fp_capabilities result = {19, 23, 42};
    assert(fp_abi_revision() == 0);
    assert(fp_query_capabilities(NULL, sizeof(result)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_query_capabilities(&result, sizeof(result) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(result.struct_size == 19 && result.abi_revision == 23 && result.feature_bits == 42);
    assert(fp_query_capabilities(&result, sizeof(result)) == FP_STATUS_OK);
    assert(result.struct_size == sizeof(result));
    assert(result.abi_revision == 0 && result.feature_bits == 0);
    return 0;
}
