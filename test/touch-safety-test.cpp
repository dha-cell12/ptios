// Compiles both production touch injectors against a retain-counted HID test double.
// This checks our ownership bookkeeping; private-API retain semantics still need device validation.
#include <cassert>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif
#include "../shared/TLinkTouchPayload.h"

using UInt8 = uint8_t;
#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2
#define MAX_FINGER_INDEX kTLinkTouchMaxFingerCount
#define NOT_VALID 0
#define VALID 1
#define VALID_AT_NEXT_APPEND 2
#define EVENT_VALID_INDEX 0
#define EVENT_TYPE_INDEX 1
#define EVENT_X_INDEX 2
#define EVENT_Y_INDEX 3
static int eventsToAppend[MAX_FINGER_INDEX][4];
static float device_screen_width = 1000;
static float device_screen_height = 2000;
static const int kCFAllocatorDefault = 0;

struct Sample { int type; int index; float x; float y; };
struct Event {
    int refs = 1;
    Sample sample = {};
    std::vector<Event *> children;
};
using IOHIDEventRef = Event *;
static int liveEvents = 0;
static int createAttempts = 0;
static int failAt = -1;
static int dispatchCount = 0;
static std::vector<Sample> lastFrame;
static uint64_t mach_absolute_time() { return 0; }
static Event *createEvent() {
    if (++createAttempts == failAt) return nullptr;
    ++liveEvents;
    return new Event;
}
template <typename... Args> static Event *IOHIDEventCreateDigitizerEvent(Args...) { return createEvent(); }
static Event *IOHIDEventCreateDigitizerFingerEvent(int, uint64_t, int index, int, int mask,
                                                  float x, float y, float, float, float, int, int, int) {
    Event *event = createEvent();
    if (event) event->sample = {mask == 3 ? TOUCH_DOWN : (mask == 4 ? TOUCH_MOVE : TOUCH_UP), index, x, y};
    return event;
}
static void IOHIDEventSetFloatValue(Event *event, int, float) { assert(event && event->refs > 0); }
static void IOHIDEventSetIntegerValue(Event *event, int, int) { assert(event && event->refs > 0); }
static void IOHIDEventAppendEvent(Event *parent, Event *child) {
    assert(parent && child && child->refs == 1);
    ++child->refs;
    parent->children.push_back(child);
}
static void CFRelease(Event *event) {
    assert(event && event->refs > 0);
    if (--event->refs == 0) {
        for (auto *child : event->children) CFRelease(child);
        --liveEvents;
        delete event;
    }
}
static void postIOHIDEvent(Event *event) {
    lastFrame.clear();
    for (const auto *child : event->children) {
        assert(child->refs == 1); // Parent owns the only remaining reference at dispatch.
        lastFrame.push_back(child->sample);
    }
    ++dispatchCount;
}

#ifdef TLINK_TEST_TROLLSTORE
#define POC_TOUCH_UP TOUCH_UP
#define POC_TOUCH_DOWN TOUCH_DOWN
#define POC_TOUCH_MOVE TOUCH_MOVE
#define sScreenWidth device_screen_width
#define sScreenHeight device_screen_height
#define sEventsToAppend eventsToAppend
#define POCPostEvent postIOHIDEvent
#define POCPerformTouchFromRawData performTouchFromRawData
#endif
#include "TouchInjectionUnderTest.inc"
#ifndef TLINK_TEST_TROLLSTORE
using CGFloat = double;
struct CGPoint {CGFloat x, y;};
static std::atomic<uint64_t> sTLinkZoomFrameCount{0};
#include "TaskTouchHelpersUnderTest.inc"
#endif

static std::string field(int type, int index, int x = 12345, int y = 67890) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%d%02d%05d%05d", type, index, x, y);
    return buffer;
}
static bool inject(const std::string &payload) {
    const bool result = performTouchFromRawData(reinterpret_cast<const UInt8 *>(payload.data()), payload.size());
    assert(liveEvents == 0);
    return result;
}
static void reset() {
    assert(liveEvents == 0);
    std::memset(eventsToAppend, 0, sizeof(eventsToAppend));
    lastFrame.clear();
    createAttempts = 0;
    failAt = -1;
    dispatchCount = 0;
}
static void rejected(const std::string &payload) {
    int before[MAX_FINGER_INDEX][4];
    std::memcpy(before, eventsToAppend, sizeof(before));
    const int attempts = createAttempts;
    const int dispatched = dispatchCount;
    assert(!inject(payload));
    assert(createAttempts == attempts); // Reject before creating any HID object.
    assert(dispatchCount == dispatched);
    assert(std::memcmp(before, eventsToAppend, sizeof(before)) == 0);
}

static void testValidAndState() {
    reset();
    assert(inject("1" + field(TOUCH_DOWN, 0)));
    assert(lastFrame.size() == 1 && lastFrame[0].index == 0 && lastFrame[0].type == TOUCH_DOWN);
    assert(std::fabs(lastFrame[0].x - 1.234f) < 0.000001f); // Same integer-pixel truncation as before.
    assert(std::fabs(lastFrame[0].y - 3.3945f) < 0.000001f);
    assert(inject("1" + field(TOUCH_DOWN, 19, 0, 99999) + "\r\n"));
    assert(lastFrame.size() == 2); // Newly updated finger plus unchanged active finger 0.
    assert(lastFrame[0].index == 19 && lastFrame[1].index == 0);
    assert(inject("2" + field(TOUCH_MOVE, 0) + field(TOUCH_MOVE, 19) + "\n"));
    assert(lastFrame.size() == 2);
    assert(inject("2" + field(TOUCH_UP, 0) + field(TOUCH_UP, 19) + "\r"));
    for (const auto &state : eventsToAppend) assert(state[EVENT_VALID_INDEX] == NOT_VALID);
    reset();
    std::string nine = "9";
    for (int i = 0; i < 9; i++) nine += field(TOUCH_DOWN, i);
    assert(inject(nine));
    assert(lastFrame.size() == 9);
}

static void testMalformed() {
    reset();
    assert(inject("1" + field(TOUCH_DOWN, 0)));
    rejected("");
    rejected("0");
    rejected("a" + field(TOUCH_DOWN, 0));
    rejected("2" + field(TOUCH_DOWN, 0));
    rejected("1" + field(3, 0));
    rejected("1" + field(1, 20));
    rejected("1" + field(1, 99));
    const std::string valid = "2" + field(1, 1) + field(2, 19);
    for (size_t i = 0; i < valid.size(); i++) {
        std::string bad = valid;
        bad[i] = 'x';
        rejected(bad);
        bad[i] = '\0';
        rejected(bad);
    }
    rejected(valid + "x");
    rejected(valid + std::string(1, '\0'));
    rejected(valid + "\n\n");
    rejected(valid + "\n\r");
    rejected(valid + "\r\n\n");
    rejected("1" + field(1, 0) + field(1, 1)); // Undeclared extra touch data.
    assert(!performTouchFromRawData(nullptr, 0));
    assert(!performTouchFromRawData(nullptr, 100));
    assert(!performTouchFromRawData(reinterpret_cast<const UInt8 *>(valid.data()), SIZE_MAX));
}

static void testGuardedTruncation() {
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    const size_t page = info.dwPageSize;
    auto *memory = static_cast<UInt8 *>(VirtualAlloc(nullptr, page * 2, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    assert(memory);
    DWORD previous;
    assert(VirtualProtect(memory + page, page, PAGE_NOACCESS, &previous));
#else
    const size_t page = static_cast<size_t>(sysconf(_SC_PAGESIZE));
    auto *memory = static_cast<UInt8 *>(mmap(nullptr, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
    assert(memory != MAP_FAILED);
    assert(mprotect(memory + page, page, PROT_NONE) == 0);
#endif
    reset();
    for (int count = 1; count <= 9; count++) {
        std::string payload(1, static_cast<char>('0' + count));
        for (int i = 0; i < count; i++) payload += field(TOUCH_DOWN, i);
        for (size_t length = 0; length < payload.size(); length++) {
            UInt8 *bytes = memory + page - length; // First byte after input is unreadable, even for length=0.
            std::memcpy(bytes, payload.data(), length);
            assert(!performTouchFromRawData(bytes, length));
            assert(liveEvents == 0 && createAttempts == 0 && dispatchCount == 0);
        }
        UInt8 *bytes = memory + page - payload.size();
        std::memcpy(bytes, payload.data(), payload.size());
        assert(performTouchFromRawData(bytes, payload.size())); // No NUL terminator needed.
        assert(liveEvents == 0);
        reset();
    }
#ifdef _WIN32
    assert(VirtualFree(memory, 0, MEM_RELEASE));
#else
    assert(munmap(memory, page * 2) == 0);
#endif
}

static void testAllocationFailures() {
    // Fail parent, first child, or later child. No partial finger-state commit or leaked ownership.
    for (int failure = 1; failure <= 3; failure++) {
        reset();
        failAt = failure;
        assert(!inject("2" + field(TOUCH_DOWN, 0) + field(TOUCH_DOWN, 19)));
        assert(dispatchCount == 0);
        for (const auto &state : eventsToAppend) assert(state[EVENT_VALID_INDEX] == NOT_VALID);
    }
    reset();
    assert(inject("1" + field(TOUCH_DOWN, 0)));
    int before[MAX_FINGER_INDEX][4];
    std::memcpy(before, eventsToAppend, sizeof(before));
    failAt = createAttempts + 3; // Parent, new finger 19, then unchanged active finger 0.
    assert(!inject("1" + field(TOUCH_DOWN, 19)));
    assert(dispatchCount == 1 && std::memcmp(before, eventsToAppend, sizeof(before)) == 0);
}

static void testLongRun() {
    reset();
    assert(inject("1" + field(TOUCH_DOWN, 0)));
    const std::string move = "1" + field(TOUCH_MOVE, 0);
    for (int i = 0; i < 100000; i++) assert(inject(move));
    assert(inject("1" + field(TOUCH_UP, 0)));
    assert(dispatchCount == 100002 && liveEvents == 0);
}

#ifndef TLINK_TEST_TROLLSTORE
static void testTypedFrames() {
    reset();
    const TLinkTouchPoint valid[] = {{TOUCH_DOWN, 0, 0, 9999}, {TOUCH_MOVE, 19, 1234, 6789}};
    assert(performTouchFrame(valid, 2) && liveEvents == 0);
    int before[MAX_FINGER_INDEX][4];std::memcpy(before, eventsToAppend, sizeof(before));
    const int attempts = createAttempts, dispatched = dispatchCount;
    assert(!performTouchFrame(nullptr, 1) && !performTouchFrame(valid, 0) && !performTouchFrame(valid, -1));
    assert(!performTouchFrame(valid, 10) && !performTouchFrame(valid, INT32_MAX));
    for (const auto &bad : std::vector<TLinkTouchPoint>{{-1,0,0,0},{3,0,0,0},{1,-1,0,0},{1,20,0,0},
        {1,0,-1,0},{1,0,0,-1},{1,0,10000,0},{1,0,0,10000}}) {
        TLinkTouchPoint frame[] = {valid[0], bad};assert(!performTouchFrame(frame, 2));
    }
    assert(attempts == createAttempts && dispatched == dispatchCount && std::memcmp(before, eventsToAppend, sizeof(before)) == 0);
    // The wire injector is a thin adapter: preserve order, duplicate fingers,
    // integer-pixel quantization, active-state commit and normalized HID values.
    uint32_t random = 1979;
    const auto next = [&random]() -> uint32_t {random = random * 1664525U + 1013904223U;return random;};
    for (int trial = 0; trial < 3000; ++trial) {
        const int count = 1 + int(next() % 9);TLinkTouchPoint frame[kTLinkTouchMaxCount];std::string wire(1, char('0' + count));
        for (int i = 0; i < count; ++i) {
            int type = int(next() % 3), index = int(next() % 20), x = int(next() % 100000), y = int(next() % 100000);
            frame[i] = {type, index, x / 10, y / 10};wire += field(type, index, x, y);
        }
        reset();assert(inject(wire));const auto expected = lastFrame;
        int expectedState[MAX_FINGER_INDEX][4];std::memcpy(expectedState, eventsToAppend, sizeof(expectedState));
        reset();assert(performTouchFrame(frame, count) && liveEvents == 0 && lastFrame.size() == expected.size());
        for (size_t i = 0; i < expected.size(); ++i) {
            assert(lastFrame[i].type == expected[i].type && lastFrame[i].index == expected[i].index &&
                lastFrame[i].x == expected[i].x && lastFrame[i].y == expected[i].y);
        }
        assert(std::memcmp(expectedState, eventsToAppend, sizeof(expectedState)) == 0);
    }
    for (int failure = 1; failure <= 3; ++failure) {
        reset();failAt = failure;assert(!performTouchFrame(valid, 2) && liveEvents == 0 && dispatchCount == 0);
        for (const auto &state : eventsToAppend) assert(state[EVENT_VALID_INDEX] == NOT_VALID);
    }
    // Compile the actual Task numeric helpers on every host, including concrete
    // fixed-point boundaries and all fingers in each synchronized zoom frame.
    reset();
    zx_performSingleTouch(TOUCH_DOWN, 19, -1, 0.95);
    assert(lastFrame.size() == 1 && lastFrame[0].index == 19 && lastFrame[0].x == 0 && lastFrame[0].y == 1.0f / device_screen_height);
    zx_performSingleTouch(TOUCH_UP, 19, 1e30, 9999.89);
    assert(lastFrame[0].x == 9999.0f / device_screen_width && lastFrame[0].y == 9999.0f / device_screen_height);
    const CGPoint points[] = {{0.049, 0.95}, {1234.89, 5678.91}, {9999.9, -100}};
    zx_performTouchFrame(TOUCH_DOWN, 17, points, 3);
    assert(lastFrame.size() == 3 && sTLinkZoomFrameCount.load() == 1);
    assert(lastFrame[0].index == 17 && lastFrame[0].x == 0 && lastFrame[0].y == 1.0f / device_screen_height);
    assert(lastFrame[1].index == 18 && lastFrame[1].x == 1234.0f / device_screen_width && lastFrame[1].y == 5678.0f / device_screen_height);
    assert(lastFrame[2].index == 19 && lastFrame[2].x == 9999.0f / device_screen_width && lastFrame[2].y == 0);
    zx_performTouchFrame(TOUCH_UP, 17, points, 3);
    const int heldCount = dispatchCount;zx_performTouchFrame(TOUCH_DOWN, 0, nullptr, 2);zx_performTouchFrame(TOUCH_DOWN, 0, points, 10);
    assert(dispatchCount == heldCount && liveEvents == 0);
    reset();TLinkTouchPoint point = {TOUCH_DOWN, 19, 9999, 0};assert(performTouchFrame(&point, 1));
    point.type = TOUCH_MOVE;for (int i = 0; i < 100000; ++i) assert(performTouchFrame(&point, 1) && liveEvents == 0);
    point.type = TOUCH_UP;assert(performTouchFrame(&point, 1) && liveEvents == 0);
    puts("Typed touch passed: all-or-nothing validation, 3000 wire/HID parity frames, allocation rollback and 100k numeric frames.");
}
#endif

int main() {
    testValidAndState();
    testMalformed();
    testGuardedTruncation();
    testAllocationFailures();
    testLongRun();
#ifndef TLINK_TEST_TROLLSTORE
    testTypedFrames();
#endif
    std::puts("Touch safety OK: guarded truncation, invalid frames, 0/19 fingers, allocation rollback, 100k-frame ownership");
}
