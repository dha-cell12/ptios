// Executes the production HID ownership functions and slot guard, with a fake run loop/client.
// UIKit rendering and actual main-thread scheduling still require the iOS build/device checks.
#include <cassert>
#include <cstdint>
#include <climits>
#include <cstdio>
#include <initializer_list>
#include "../shared/TLinkTouchPayload.h"

struct Client;
using IOHIDEventSystemClientRef = Client *;
using IOHIDEventQueueRef = void *;
using IOHIDEventRef = void *;
using IOHIDEventSystemClientEventCallback = void (*)(void *, void *, IOHIDEventQueueRef, IOHIDEventRef);
static const int kCFAllocatorDefault = 0;
static const int kCFRunLoopCommonModes = 7;
static int CFRunLoopGetMain() { return 42; }

#include "IndicatorGlobalsUnderTest.inc"
static bool zx_indicatorAcceptsCallback(void *refcon);
static int deliveries = 0;
static void IOHIDEventCallbackForTouchIndicator(void *, void *refcon, IOHIDEventQueueRef, IOHIDEventRef) {
    if (zx_indicatorAcceptsCallback(refcon)) ++deliveries;
}

struct Client {
    bool registered = false;
    bool scheduled = false;
    int runLoop = 0;
    int mode = 0;
    void *refcon = nullptr;
    IOHIDEventSystemClientEventCallback callback = nullptr;
};
static int liveClients = 0;
static int creates = 0;
static int unregisters = 0;
static int unschedules = 0;
static int releases = 0;
static bool failCreate = false;
static Client *IOHIDEventSystemClientCreate(int) {
    ++creates;
    if (failCreate) return nullptr;
    assert(liveClients == 0);
    ++liveClients;
    return new Client;
}
static void IOHIDEventSystemClientRegisterEventCallback(Client *client, IOHIDEventSystemClientEventCallback callback,
                                                        void *, void *refcon) {
    assert(client && !client->registered && refcon != nullptr);
    assert(indicatorState == TLinkIndicatorStarting && !zx_indicatorAcceptsCallback(refcon));
    client->registered = true;
    client->callback = callback;
    client->refcon = refcon;
}
static void IOHIDEventSystemClientScheduleWithRunLoop(Client *client, int loop, int mode) {
    assert(client && client->registered && !client->scheduled);
    assert(loop == CFRunLoopGetMain() && mode == kCFRunLoopCommonModes);
    client->scheduled = true;
    client->runLoop = loop;
    client->mode = mode;
    const int before = deliveries;
    client->callback(nullptr, client->refcon, nullptr, nullptr);
    assert(deliveries == before); // Starting sessions cannot deliver events yet.
}
static void IOHIDEventSystemClientUnregisterEventCallback(Client *client) {
    assert(client && client->registered && indicatorState == TLinkIndicatorStopping);
    const int before = deliveries;
    client->callback(nullptr, client->refcon, nullptr, nullptr);
    assert(deliveries == before); // A callback queued during stop is rejected.
    client->registered = false;
    ++unregisters;
}
static void IOHIDEventSystemClientUnscheduleWithRunLoop(Client *client, int loop, int mode) {
    assert(client && !client->registered && client->scheduled);
    assert(loop == client->runLoop && mode == client->mode);
    client->scheduled = false;
    ++unschedules;
}
static void CFRelease(Client *client) {
    assert(client && !client->registered && !client->scheduled && indicatorState == TLinkIndicatorStopping);
    assert(liveClients == 1);
    --liveClients;
    ++releases;
    delete client;
}

#include "IndicatorCoreUnderTest.inc"

static void start() {
    assert(indicatorState == TLinkIndicatorStopped);
    indicatorState = TLinkIndicatorStarting;
    assert(zx_indicatorStartClientOnMain());
    assert(indicatorState == TLinkIndicatorRunning && liveClients == 1);
}
static void testSlots() {
    for (int i = 0; i < 20; i++) assert(zx_indicatorValidFingerIndex(i));
    for (int i : {-1, -20, 20, 21, INT_MIN, INT_MAX}) assert(!zx_indicatorValidFingerIndex(i));
}
static void testLifecycle() {
    zx_indicatorStopClientOnMain();
    assert(indicatorState == TLinkIndicatorStopped && liveClients == 0);
    assert(creates == 0 && releases == 0);
    start();
    void *oldRefcon = ioHIDEventSystemClient->refcon;
    auto callback = ioHIDEventSystemClient->callback;
    callback(nullptr, oldRefcon, nullptr, nullptr);
    assert(deliveries == 1);
    const int before = creates;
    assert(!zx_indicatorStartClientOnMain()); // Duplicate start must not allocate/replace the client.
    assert(creates == before && liveClients == 1 && ioHIDEventSystemClient->refcon == oldRefcon);
    zx_indicatorStopClientOnMain();
    assert(!ioHIDEventSystemClient && liveClients == 0);
    assert(unregisters == 1 && unschedules == 1 && releases == 1);
    callback(nullptr, oldRefcon, nullptr, nullptr);
    assert(deliveries == 1);
    zx_indicatorStopClientOnMain(); // Idempotent stop cannot release twice or stop the shared run loop.
    assert(releases == 1);
    start();
    void *newRefcon = ioHIDEventSystemClient->refcon;
    assert(oldRefcon != newRefcon);
    callback(nullptr, oldRefcon, nullptr, nullptr);
    assert(deliveries == 1); // Old session cannot update the new window.
    callback(nullptr, newRefcon, nullptr, nullptr);
    assert(deliveries == 2);
    zx_indicatorStopClientOnMain();
}
static void testFailure() {
    indicatorState = TLinkIndicatorStarting;
    failCreate = true;
    const int before = releases;
    assert(!zx_indicatorStartClientOnMain());
    assert(ioHIDEventSystemClient == nullptr && liveClients == 0);
    zx_indicatorStopClientOnMain(); // Same cleanup used by configuration/window/client start failures.
    assert(indicatorState == TLinkIndicatorStopped && releases == before);
    failCreate = false;
    start(); // Failure must not strand the state in Starting.
    zx_indicatorStopClientOnMain();
}
static void testRepeatedStarts() {
    for (int i = 0; i < 10000; i++) {
        start();
        assert(!zx_indicatorStartClientOnMain());
        zx_indicatorStopClientOnMain();
        assert(liveClients == 0 && ioHIDEventSystemClient == nullptr);
    }
    assert(unregisters == unschedules && unschedules == releases);
    assert(creates == releases + 1); // Exactly one deliberately failed creation.
}
int main() {
    testSlots();
    testLifecycle();
    testFailure();
    testRepeatedStarts();
    std::puts("Indicator safety OK: slots 0..19, duplicate start, failure recovery, stale callbacks, 10k balanced client lifecycles");
}
