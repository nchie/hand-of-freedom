#include "CMultitouchSupport.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef void *MTDeviceRef;
typedef void (*MTRefconCallback)(MTDeviceRef, MTTouch *, size_t, double, size_t, void *);

static CFMutableArrayRef (*pCreateList)(void);
static void (*pRegisterWithRefcon)(MTDeviceRef, MTRefconCallback, void *);
static void (*pUnregister)(MTDeviceRef, MTRefconCallback);
static void (*pStart)(MTDeviceRef, int);
static void (*pStop)(MTDeviceRef);
static _Bool (*pIsBuiltIn)(MTDeviceRef);

static CFMutableArrayRef gDevices;

#define MAX_DEVICES 8
typedef struct { mt_frame_fn fn; void *refcon; int started; } Slot;
static Slot gSlots[MAX_DEVICES];

int mt_load(char *err, size_t errlen) {
    static int loaded = 0;
    if (loaded) return 0;
    void *lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) { snprintf(err, errlen, "dlopen MultitouchSupport: %s", dlerror()); return -1; }
#define SYM(var, name) do { var = dlsym(lib, name); if (!var) { snprintf(err, errlen, "missing symbol %s", name); return -1; } } while (0)
    SYM(pCreateList, "MTDeviceCreateList");
    SYM(pRegisterWithRefcon, "MTRegisterContactFrameCallbackWithRefcon");
    SYM(pUnregister, "MTUnregisterContactFrameCallback");
    SYM(pStart, "MTDeviceStart");
    SYM(pStop, "MTDeviceStop");
    SYM(pIsBuiltIn, "MTDeviceIsBuiltIn");
#undef SYM
    loaded = 1;
    return 0;
}

int mt_enumerate(void) {
    if (gDevices) { CFRelease(gDevices); gDevices = NULL; }
    gDevices = pCreateList ? pCreateList() : NULL;
    return gDevices ? (int)CFArrayGetCount(gDevices) : 0;
}

static MTDeviceRef device(int index) {
    if (!gDevices || index < 0 || index >= CFArrayGetCount(gDevices) || index >= MAX_DEVICES) return NULL;
    return (MTDeviceRef)CFArrayGetValueAtIndex(gDevices, index);
}

int mt_device_is_builtin(int index) {
    MTDeviceRef d = device(index);
    return d && pIsBuiltIn(d) ? 1 : 0;
}

static void trampoline(MTDeviceRef dev, MTTouch *touches, size_t count, double timestamp, size_t frame, void *refcon) {
    (void)dev;
    Slot *slot = (Slot *)refcon;
    slot->fn(slot->refcon, touches, (int)count, timestamp, (int)frame);
}

int mt_start(int index, mt_frame_fn fn, void *refcon) {
    MTDeviceRef d = device(index);
    if (!d) return -1;
    Slot *slot = &gSlots[index];
    slot->fn = fn;
    slot->refcon = refcon;
    pRegisterWithRefcon(d, trampoline, slot);
    pStart(d, 0);
    slot->started = 1;
    return 0;
}

void mt_stop(int index) {
    MTDeviceRef d = device(index);
    if (!d || !gSlots[index].started) return;
    pUnregister(d, trampoline);
    pStop(d);
    gSlots[index].started = 0;
}
