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
int main() {
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
