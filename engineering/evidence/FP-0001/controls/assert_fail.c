/* Negative control: the c-abi gate flags must keep assert() active. */
#include <assert.h>

int main(void) {
    assert(0);
    return 0;
}
