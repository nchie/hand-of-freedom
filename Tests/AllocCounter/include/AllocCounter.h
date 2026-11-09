// Counts heap allocations made by one thread, through libmalloc's logging hook.
// Test-only: installing the hook slows every allocation in the process while it is active.
#ifndef ALLOC_COUNTER_H
#define ALLOC_COUNTER_H

/// Starts counting allocations made by the calling thread.
void alloc_counter_start(void);
/// Stops counting and returns the number of allocations (malloc, calloc, realloc, valloc) seen.
long alloc_counter_stop(void);

#endif
