#include "AllocCounter.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>

// Not in the public headers, but exported by libsystem_malloc and used by malloc stack logging.
typedef void(malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result,
                              uint32_t num_hot_frames_to_skip);
extern malloc_logger_t *malloc_logger;

#define MALLOC_LOG_TYPE_ALLOCATE 2

static _Atomic(pthread_t) target;
static atomic_long count;

static void logger(uint32_t type, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t result, uint32_t skip) {
    (void)a1; (void)a2; (void)a3; (void)result; (void)skip;
    if ((type & MALLOC_LOG_TYPE_ALLOCATE) && pthread_equal(pthread_self(), atomic_load(&target))) {
        atomic_fetch_add(&count, 1);
    }
}

void alloc_counter_start(void) {
    atomic_store(&count, 0);
    atomic_store(&target, pthread_self());
    malloc_logger = logger;
}

long alloc_counter_stop(void) {
    malloc_logger = 0;
    atomic_store(&target, (pthread_t)0);
    return atomic_load(&count);
}
