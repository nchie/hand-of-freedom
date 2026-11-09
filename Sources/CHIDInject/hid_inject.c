#pragma clang diagnostic ignored "-Wdeprecated-declarations"   // IOHIDPostEvent: deprecated, still the only usable path
#include "CHIDInject.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <string.h>

static io_connect_t gConn = 0;

int32_t hid_open(void) {
    if (gConn) return KERN_SUCCESS;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!svc) return KERN_FAILURE;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), kIOHIDParamConnectType, &gConn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) gConn = 0;
    return kr;
}

void hid_close(void) {
    if (gConn) { IOServiceClose(gConn); gConn = 0; }
}

static int32_t post(UInt32 type, NXEventData *ev, IOOptionBits options) {
    if (!gConn) return KERN_INVALID_CAPABILITY;
    IOGPoint loc = {0, 0};
    return IOHIDPostEvent(gConn, type, loc, ev, kNXEventDataVersion, 0, options);
}

int32_t hid_post_button(int button, int down) {
    NXEventData ev;
    memset(&ev, 0, sizeof ev);
    ev.mouse.buttonNumber = (UInt8)button;
    ev.mouse.click = 1;
    ev.mouse.pressure = down ? 255 : 0;
    ev.mouse.subType = NX_SUBTYPE_DEFAULT;
    UInt32 type;
    switch (button) {
    case 0: type = down ? NX_LMOUSEDOWN : NX_LMOUSEUP; break;
    case 1: type = down ? NX_RMOUSEDOWN : NX_RMOUSEUP; break;
    default: type = down ? NX_OMOUSEDOWN : NX_OMOUSEUP; break;
    }
    return post(type, &ev, 0);
}

int32_t hid_post_move(int dx, int dy, int held) {
    NXEventData ev;
    memset(&ev, 0, sizeof ev);
    ev.mouseMove.dx = dx;
    ev.mouseMove.dy = dy;
    ev.mouseMove.subType = NX_SUBTYPE_DEFAULT;
    UInt32 type;
    switch (held) {
    case 0: type = NX_LMOUSEDRAGGED; break;
    case 1: type = NX_RMOUSEDRAGGED; break;
    case 2: type = NX_OMOUSEDRAGGED; break;
    default: type = NX_MOUSEMOVED; break;
    }
    return post(type, &ev, kIOHIDSetRelativeCursorPosition);
}

int32_t hid_post_scroll(int ticks) {
    NXEventData ev;
    memset(&ev, 0, sizeof ev);
    ev.scrollWheel.deltaAxis1 = (SInt16)ticks;
    ev.scrollWheel.fixedDeltaAxis1 = ticks * 65536;     // 16.16 fixed point
    ev.scrollWheel.pointDeltaAxis1 = ticks * 10;        // one line is about ten points
    return post(NX_SCROLLWHEELMOVED, &ev, 0);
}
