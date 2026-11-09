// The only place the private MultitouchSupport framework appears.
// Layout reverse-engineered by the community (MiddleClick, OpenMultitouchSupport) and verified
// on Apple Silicon / macOS 26.
#ifndef CMULTITOUCHSUPPORT_H
#define CMULTITOUCHSUPPORT_H

#include <stddef.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;        // stable per contact while it stays on the pad
    int state;             // 0..7 lifecycle, 4 == touching
    int fingerId;
    int handId;
    MTReadout normalized;  // 0..1 across the pad, origin bottom-left
    float size;            // contact size (palms are large)
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout mm;          // physical millimetres
    int zero2[2];
    float unk2;
} MTTouch;

/// Called on the framework's callback thread for every frame of a started device.
typedef void (*mt_frame_fn)(void *refcon, const MTTouch *touches, int count, double timestamp, int frame);

/// Loads the framework once. 0 on success, -1 with a message in `err`.
int mt_load(char *err, size_t errlen);
/// (Re)creates the device list, releasing any previous one. Returns the device count.
int mt_enumerate(void);
int mt_device_is_builtin(int index);
/// Registers the callback for one device and starts it. 0 on success.
int mt_start(int index, mt_frame_fn fn, void *refcon);
/// Unregisters and stops one device. A frame already dequeued by the framework may still be delivered.
void mt_stop(int index);

#endif
