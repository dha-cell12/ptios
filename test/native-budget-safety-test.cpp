#include "../shared/TLinkNativeTouchRequest.h"
#include "../shared/TLinkGestureTiming.h"
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkTemplatePolicy.h"
#include "../shared/TLinkModernImagePolicy.h"
#include <cassert>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <functional>
TLinkNativeBudgetPtr nativeBudgetFromPeer();
struct Mat {
    int cols, rows;
    std::vector<unsigned char> bytes;
    Mat() : cols(0), rows(0) {}
    bool empty() const { return bytes.empty(); }
    Mat(int c, int r, unsigned char value) : cols(c), rows(r), bytes(size_t(c) * size_t(r), value) {}
    template<class T> const T *ptr(int row) const { return reinterpret_cast<const T *>(bytes.data() + size_t(row) * size_t(cols)); }
};
static int cvRound(double value){return int(std::nearbyint(value));}
#include "ImageSadUnderTest.inc"
#include "TemplateSadUnderTest.inc"
// Image.h undefines these OpenCV-conflicting macros. Compile the full scale helper
// under the same condition, with only unit-scale/small-buffer fixtures below.
#undef NO
#undef YES
using BOOL = bool;
namespace cv {
    struct Size { Size(int, int) {} };
    enum { INTER_AREA, INTER_LINEAR };
    static void resize(const Mat &, Mat &, Size, double, double, int) {
        assert(false && "fixture unexpectedly requested OpenCV resize");
    }
}
#include "ImageScaleUnderTest.inc"

static TLinkNativeBudgetPtr makeBudget(std::shared_ptr<TLinkNativeCancellation> token = {}, double timeout = 0,
                                      size_t cap = 1024, bool cleanup = false) {
    return std::make_shared<TLinkNativeBudget>(token, TLinkNativeDeadline(timeout), cap, cleanup, true);
}
static int append(const TLinkNativeBudgetPtr &b, const std::string &s) {
    return b->appendCString(reinterpret_cast<const uint8_t *>(s.c_str()));
}
static void testTypedTouchCompatibility() {
    assert(TLinkNativeTouchTask(TLinkNativeTouchKind::Tap)==62 && TLinkNativeTouchTask(TLinkNativeTouchKind::Swipe)==63);
    assert(TLinkNativeTouchTask(TLinkNativeTouchKind::Gesture)==64 && TLinkNativeTouchTask(TLinkNativeTouchKind::Zoom)==64);
    assert(TLinkNativeTouchTask(static_cast<TLinkNativeTouchKind>(9))==0);
    TLinkNativeTouchRequest request;assert(request.durationMs==50 && request.finger==0 && request.steps==0);
    for(double value:{-1e308,-1e30,-9999.9,-0.005,-0.0,0.005,0.945,0.95,1.005,1234.89,9999.89,9999.9,1e30,1e308}){
        char legacy[384];std::snprintf(legacy,sizeof(legacy),"%.2f",value);
        const double expected=double(std::strtof(legacy,nullptr));
        size_t bytes=0;const double actual=TLinkNativeTouchJSCoordinate(value,&bytes);
        assert(actual==expected && std::signbit(actual)==std::signbit(expected) && bytes==std::strlen(legacy));
        const double wide=TLinkNativeTouchJSZoomNumber(value);
        assert(wide==std::strtod(legacy,nullptr) && std::signbit(wide)==std::signbit(expected));
    }
    uint32_t random=719;
    for(int i=0;i<100000;++i){
        random=random*1664525U+1013904223U;
        const double value=(double(random)-2147483648.0)/997.0;
        char legacy[384];std::snprintf(legacy,sizeof(legacy),"%.2f",value);
        size_t bytes=0;assert(TLinkNativeTouchJSCoordinate(value,&bytes)==double(std::strtof(legacy,nullptr)) && bytes==std::strlen(legacy));
        assert(TLinkNativeTouchJSZoomNumber(value)==std::strtod(legacy,nullptr));
    }
    for(double value:{-100.0,0.0,0.5,1.5,2.5,15.5,16.5,59999.5,60000.0,1e30}){
        const double clamped=value<0?0:(value>60000?60000:value);
        char legacy[32];std::snprintf(legacy,sizeof(legacy),"%.0f",clamped);
        assert(TLinkNativeTouchJSDuration(value)==std::strtol(legacy,nullptr,10));
    }
    assert(std::isnan(TLinkNativeTouchJSCoordinate(NAN)) && std::isinf(TLinkNativeTouchJSCoordinate(INFINITY)));
    assert(TLinkNativeTouchJSDuration(NAN)==-1 && TLinkNativeTouchJSDuration(INFINITY)==-1);
    for(int number:{INT_MIN,-100,-1,0,1,19,60000,INT_MAX}){
        char legacy[32];std::snprintf(legacy,sizeof(legacy),"%d",number);assert(TLinkNativeTouchIntegerBytes(number)==std::strlen(legacy));
        const size_t cap=8192-6-std::strlen(legacy)-3;
        assert(TLinkNativeGestureInputFits(cap,number,300));assert(!TLinkNativeGestureInputFits(cap+1,number,300));
    }
    assert(!TLinkNativeGestureInputFits(SIZE_MAX,19,60000));
    char tiny[1];assert(!TLinkNativeTouchDecimal(tiny,sizeof(tiny),2,123));
    puts("Typed touch request passed: task allowlist, 100k legacy decimal float/double/byte cases, signed zero/overflow, gesture input cap and duration clamp/rounding.");
}
static void testGestureTimeline() {
    for (unsigned intervals = 1; intervals <= 512; ++intervals) {
        const uint64_t duration = 60000000001ULL, start = 700;
        TLinkGestureTimeline timeline(start, duration);uint64_t previous = start;
        for (unsigned step = 0; step <= intervals; ++step) {
            const auto target = timeline.target(step, intervals);
            assert(target >= previous && target == start + duration * step / intervals);
            assert(timeline.remaining(target, step, intervals) == 0);
            assert(timeline.remaining(target + 1, step, intervals) == 0);
            assert(timeline.remaining(target - 1, step, intervals) == 1);
            previous = target;
        }
        assert(timeline.target(intervals, intervals) == start + duration);
    }
    assert(TLinkGestureTimeline(10, 0).target(1, 1) == 10);
    assert(TLinkGestureTimeline(10, UINT64_MAX).target(UINT32_MAX, UINT32_MAX) == UINT64_MAX);
    assert(TLinkGestureTimeline(0, UINT64_MAX).target(UINT32_MAX, UINT32_MAX) == UINT64_MAX);
    assert(TLinkGestureTimeline(15, 20).target(99, 2) == 35 && TLinkGestureTimeline(15, 20).target(1, 0) == 15);
    // Synthetic 7 ms frame work + 2 ms oversleep does not accumulate across
    // ten 10 ms targets; endpoint stays at 102 ms rather than 190 ms.
    TLinkGestureTimeline timeline(0, 100000000);uint64_t clock = 7000000;
    for (unsigned step = 1; step <= 10; ++step) {
        clock += timeline.remaining(clock, step, 10) + 2000000;
        assert(clock == uint64_t(step) * 10000000 + 2000000);clock += 7000000;
    }
    assert(timeline.remaining(200000000, 1, 10) == 0);
    auto token = std::make_shared<TLinkNativeCancellation>();token->cancel();
    {TLinkNativeBudgetScope scope(makeBudget(token));assert(!timeline.wait(0, 1));}
    auto expired = std::make_shared<TLinkNativeBudget>(nullptr, TLinkNativeNowNs() - 1, 64);
    {TLinkNativeBudgetScope scope(expired);assert(!timeline.wait(0, 1));}
    puts("Gesture timing policy passed: 1..512 intervals, exact endpoint/remainder, overflow, consumed frame work/oversleep and overdue cancellation/deadline.");
}
int main() {
    testTypedTouchCompatibility();
    testGestureTimeline();
    auto b = makeBudget({}, 0, 1024);
    assert(b->response().capacity() == 0);
    assert(append(b, "0;;") == 3);
    assert(append(b, std::string(1021, 'x')) == 1021);
    assert(b->response().size() == 1024 && b->response().capacity() <= 1024);
    assert(append(b, "") == 0 && !b->stopped());
    assert(append(b, "x") == -1 && b->reason() == TLinkNativeStop::OutputLimit);
    assert(append(b, "") == -1 && b->response().size() == 1024);
    b = makeBudget({}, 0, 13);
    assert(append(b, "0;;") == 3);
    assert(append(b, "01234567890") == -1 && b->response().size() == 3); // reject whole chunk
    b = makeBudget({}, 0, 1024 * 1024);
    for (int i = 0; i < 4096; ++i) {
        assert(append(b, std::string(256, 'a')) == 256);
        assert(b->response().size() <= b->outputLimit() && b->response().capacity() <= b->outputLimit());
    }
    assert(!b->outputAllowed(1));
    // The sink reads at most remaining+1 bytes even when no NUL appears in that range.
    b = makeBudget({}, 0, 1);
    const uint8_t nonterminated[2] = {'x', 'y'};
    assert(b->appendCString(nonterminated) == -1 && b->response().empty());
    assert(TLinkNativeDeadline(0) == 0 && TLinkNativeDeadline(-1) == 0);
    assert(TLinkNativeDeadline(std::numeric_limits<double>::infinity()) == uint64_t(INT64_MAX));
    assert(TLinkNativeDeadline(std::numeric_limits<double>::quiet_NaN()) == 0);
    auto token = std::make_shared<TLinkNativeCancellation>();
    auto outer = makeBudget(token);
    {
        TLinkNativeBudgetScope scope(outer);
        assert(nativeBudgetFromPeer() == outer);
        { TLinkNativeBudgetScope nested(b); assert(nativeBudgetFromPeer() == b); }
        assert(nativeBudgetFromPeer() == outer);
        std::thread worker([&] {
            assert(!nativeBudgetFromPeer());
            { TLinkNativeBudgetScope transferred(outer); assert(nativeBudgetFromPeer() == outer); }
            assert(!nativeBudgetFromPeer());
        }); worker.join();
    }
    assert(!TLinkCurrentNativeBudget());
    // Exercise cancellation before entry and while waiting, including the check/wait race.
    for (int i = 0; i < 200; ++i) {
        auto cancel = std::make_shared<TLinkNativeCancellation>();
        auto waiting = makeBudget(cancel);
        std::atomic_bool entered{false};
        const auto start = TLinkNativeClock::now();
        std::thread worker([&] { entered.store(true); assert(!waiting->waitNs(60000000000ULL)); });
        while (!entered.load()) std::this_thread::yield();
        cancel->cancel(); worker.join();
        assert(TLinkNativeClock::now() - start < std::chrono::seconds(2));
        assert(waiting->reason() == TLinkNativeStop::Cancelled);
    }
    b = makeBudget({}, 0.02);
    auto start = TLinkNativeClock::now();
    assert(!b->waitNs(60000000000ULL) && b->reason() == TLinkNativeStop::Deadline);
    assert(TLinkNativeClock::now() - start < std::chrono::seconds(2));
    assert(b->remainingSeconds(3) == 0);
    token->cancel();
    auto cleanup = makeBudget(token, 0.001, 8, true);
    assert(cleanup->waitNs(2000000) && !cleanup->stopped());
    assert(append(cleanup, "12345678") == 8 && append(cleanup, "x") == -1);
    // Compile and run both actual production SAD functions with a minimal pixel-buffer double.
    using Sad = long long (*)(const Mat &, const Mat &, int, int, int, int, int, int *, int *);
    for (Sad sad : {imageSadUnderTest, templateSadUnderTest}) {
        Mat image(8, 8, 10), templ(2, 2, 10); int x = -1, y = -1;
        assert(sad(image, templ, 0, 0, 7, 7, 1, &x, &y) == 0 && x == 0 && y == 0);
        { TLinkNativeBudgetScope scope(makeBudget(token)); assert(sad(image, templ, 0, 0, 7, 7, 1, &x, &y) == LLONG_MAX); }
        Mat large(2048, 2048, 0), largeTemplate(1024, 1024, 255);
        auto deadline = makeBudget({}, 0.01);
        { TLinkNativeBudgetScope scope(deadline);
          start = TLinkNativeClock::now();
          assert(sad(large, largeTemplate, 0, 0, 1024, 1024, 1, &x, &y) == LLONG_MAX);
          assert(deadline->reason() == TLinkNativeStop::Deadline);
          assert(TLinkNativeClock::now() - start < std::chrono::seconds(2)); }
        auto cancel = std::make_shared<TLinkNativeCancellation>();
        auto running = makeBudget(cancel);
        std::thread canceller([&] { std::this_thread::sleep_for(std::chrono::milliseconds(10)); cancel->cancel(); });
        { TLinkNativeBudgetScope scope(running); assert(sad(large, largeTemplate, 0, 0, 1024, 1024, 1, &x, &y) == LLONG_MAX); }
        canceller.join();
    }
    // Exercise the actual scale-loop cancellation branch, preserving empty outputs.
    Mat smallImage(8, 8, 10), smallTemplate(2, 2, 10);
    int x = 99, y = 99, w = 99, h = 99; double score = 99;
    {
        TLinkNativeBudgetScope scope(makeBudget(token));
        assert(!zx_findTemplateSAD(smallImage, smallTemplate, 0.95, 1, 1, 1, 0, &x, &y, &w, &h, &score));
        assert(x == -1 && y == -1 && w == 0 && h == 0 && score == 0);
    }
    assert(zx_findTemplateSAD(smallImage, smallTemplate, 0.95, 1, 1, 1, 0, &x, &y, &w, &h, &score));
    assert(x == 0 && y == 0 && w == 2 && h == 2 && score == 1);
    Mat different(2, 2, 255);
    assert(!zx_findTemplateSAD(smallImage, different, 0.95, 1, 1, 1, 0, &x, &y, &w, &h, &score));
    Mat empty;
    assert(!zx_findTemplateSAD(smallImage, empty, 0.95, 1, 1, 1, 0, &x, &y, &w, &h, &score));
    std::puts("Native budget: bounded 1MiB sink, 200 cancel races, deadlines, cleanup, cross-TU/worker scopes both production SAD loops and macro-independent scale cancellation passed.");
}
