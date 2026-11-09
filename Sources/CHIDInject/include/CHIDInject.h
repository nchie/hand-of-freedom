// The only place IOHIDPostEvent appears. Relative injection through the HID system, the way a real
// mouse reports: the window server computes the cursor itself and honours a game's cursor lock.
#ifndef CHIDINJECT_H
#define CHIDINJECT_H

#include <stdint.h>

/// Opens the HID system connection. Returns a kern_return_t, 0 on success.
int32_t hid_open(void);
void hid_close(void);
/// button: 0 left, 1 right, 2 middle. down: 1 press, 0 release.
int32_t hid_post_button(int button, int down);
/// Relative motion. held: 0/1/2 for a drag of that button, -1 for a plain move.
int32_t hid_post_move(int dx, int dy, int held);
/// Vertical scroll in lines; positive scrolls up.
int32_t hid_post_scroll(int ticks);

#endif
