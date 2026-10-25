#include "image-storage-fixture.h"
#include <thread>
#include <limits>
static uint64_t fixtureNow = 100;
static uint64_t zx_nowMs() { return fixtureNow; }
static bool timerAvailable = true;
static uint64_t rearmCalls=0;
static bool zx_rearmFrameExpiryLocked() { ++rearmCalls;return timerAvailable; }
#include "ImageCoreUnderTest.inc"
#include "ImageReleaseCoreUnderTest.inc"
static void numericReleaseCases(){
    for(unsigned n=0;n<10000;++n){
        auto first=frameFixture(fixtureNow,1000),second=frameFixture(fixtureNow,1000),third=frameFixture(fixtureNow,1000);
        first->ownerSessionId=third->ownerSessionId="a";second->ownerSessionId="b";
        first->ownerRunId=second->ownerRunId=third->ownerRunId="run";
        first->ownerRuntime=second->ownerRuntime=third->ownerRuntime="js";
        const uint32_t id=zx_storeFrameLocked(first);assert(id&&zx_storeFrameLocked(second)&&zx_storeFrameLocked(third));
        ZXFrameRef held=first;first.reset();second.reset();third.reset();
        TLinkNativeFrameReleaseRequest request;request.frameId=id;request.scoped=true;request.sessionId="wrong";
        uint64_t before=rearmCalls;assert(releaseStoredFrames(request)==0&&rearmCalls==before+1&&gFrameStore.size()==3);
        request.sessionId="a";request.runtime="js";request.runId="run";
        before=rearmCalls;
        if(n%2){request.all=true;assert(releaseStoredFrames(request)==2&&gFrameStore.size()==1);}
        else assert(releaseStoredFrames(request)==1&&gFrameStore.size()==2);
        assert(rearmCalls==before+1&&held->bgra[255]==42);
        request.all=true;request.scoped=false;const size_t remaining=gFrameStore.size();before=rearmCalls;
        assert(releaseStoredFrames(request)==remaining&&gFrameStore.empty()&&rearmCalls==before+1);
        assert(gImageMemory.stats().frames==256);held.reset();assert(gImageMemory.stats().total==0);
        before=rearmCalls;assert(releaseStoredFrames(request)==0&&rearmCalls==before+1);
    }
    puts("Frame release core passed: 10k actual owner/mismatch/single/scoped-all/global/empty transactions, one expiry rearm each and held-reader resource recovery.");
}
int main() {
    numericReleaseCases();
    assert(kDefaultFrameTtlMs == 1000 && kHardFrameTtlMs == 5000 && kMaxImagePixels == 16 * 1024 * 1024);
    size_t pixels = 0;
    assert(TLinkImagePixels(8192, 2048, kMaxImagePixels, &pixels) && pixels == kMaxImagePixels);
    assert(!TLinkImagePixels(0, 2, kMaxImagePixels, &pixels));
    assert(!TLinkImagePixels(SIZE_MAX, SIZE_MAX, kMaxImagePixels, &pixels));
    assert(!TLinkImagePixels(8192, 2049, kMaxImagePixels, &pixels));
    assert(!TLinkImagePixels(8193, 1, kMaxImagePixels, &pixels));
    assert(TLinkImageExpiry(UINT64_MAX - 2, 4) == UINT64_MAX);
    uint32_t lastId = INT_MAX; assert(TLinkImageNextId(lastId) == INT_MAX); assert(!TLinkImageNextId(lastId));
    lastId = 0; assert(!TLinkImageNextId(lastId));
    TLinkImageMemory budget(96, 64, 128);
    auto f = budget.reserve(TLinkImageKind::Frame, 96); assert(f);
    assert(!budget.reserve(TLinkImageKind::Frame, 1));
    assert(!budget.reserve(TLinkImageKind::Image, 33));
    auto i = budget.reserve(TLinkImageKind::Image, 32); assert(i && budget.stats().total == 128);
    auto held = f; f.reset(); assert(!budget.reserve(TLinkImageKind::Frame, 1));
    held.reset(); i.reset(); assert(budget.stats().total == 0 && budget.stats().peak == 128);
    assert(!budget.reserve(TLinkImageKind::Image, SIZE_MAX));
    { TLinkImageWork a(gImageCompute), b(gImageCompute), c(gImageCompute); assert(a && b && !c); }
    { TLinkImageWork recovered(gImageCompute); assert(recovered); }
    auto ownerFrame = frameFixture(fixtureNow, 10);
    ownerFrame->ownerSessionId = "a"; ownerFrame->ownerRunId = "b"; ownerFrame->ownerRuntime = "js";
    assert(zx_ownerMatchesFrame(*ownerFrame, "", "", ""));
    assert(zx_ownerMatchesFrame(*ownerFrame, "a", "b", "js"));
    assert(!zx_ownerMatchesFrame(*ownerFrame, "a", "other", "js"));
    assert(!zx_ownerMatchesFrame(*ownerFrame, "", "", "raw")); ownerFrame.reset();
    auto ownerImage = imageFixture(); ownerImage->ownerSessionId = "x";
    assert(zx_ownerMatchesImage(*ownerImage, "x", "", ""));
    assert(!zx_ownerMatchesImage(*ownerImage, "y", "", "")); ownerImage.reset();
    timerAvailable = false;
    auto rejected = frameFixture(fixtureNow, 10); assert(!zx_storeFrameLocked(rejected));
    rejected.reset(); assert(gImageMemory.stats().total == 0);
    timerAvailable = true;
    auto frame = frameFixture(fixtureNow, 10);
    const uint8_t *address = frame->bgra.data();
    auto id = zx_storeFrameLocked(frame); assert(id);
    ZXFrameRef snapshot = gFrameStore.at(id); frame.reset();
    assert(snapshot->bgra.data() == address && snapshot->bgra[0] == 42);
    fixtureNow += 10; zx_cleanupFramesLocked(fixtureNow); assert(gFrameStore.empty());
    assert(snapshot->bgra.data() == address && gImageMemory.stats().frames == 256);
    snapshot.reset(); assert(gImageMemory.stats().total == 0);
    // Equal-age eviction is deterministic, and held readers survive count eviction.
    auto old = zx_storeFrameLocked(frameFixture(fixtureNow, 100));
    ZXFrameRef evicted = gFrameStore.at(old);
    for (int n = 0; n < 3; ++n) assert(zx_storeFrameLocked(frameFixture(fixtureNow, 100)));
    assert(gFrameStore.size() == kMaxFrameObjects && !gFrameStore.count(old));
    assert(evicted->bgra.data() && gImageMemory.stats().frames == 4 * 256);
    gFrameStore.clear(); evicted.reset();
    std::vector<ZXImageRef> imageReaders;
    for (size_t n = 0; n < kMaxImageObjects; ++n) {
        auto image = imageFixture(); const auto *data = image->gray.data();
        const auto imageId = zx_storeImageLocked(image); assert(imageId);
        assert(gImageStore.at(imageId)->gray.data() == data);
        imageReaders.push_back(gImageStore.at(imageId));
    }
    auto extra = imageFixture(); assert(!zx_storeImageLocked(extra)); extra.reset();
    zx_cleanupFramesLocked(UINT64_MAX); assert(gImageStore.size() == 64); // Explicit image lifetime remains unchanged.
    gImageStore.clear(); assert(gImageMemory.stats().images == 64 * 64);
    imageReaders.clear(); assert(gImageMemory.stats().total == 0);
    for (int cycle = 0; cycle < 20000; ++cycle) {
        auto p = frameFixture(fixtureNow, 1); id = zx_storeFrameLocked(p); assert(id); p.reset();
        auto reader = gFrameStore.at(id); gFrameStore.erase(id);
        assert(reader->bgra[255] == 42); reader.reset();
        assert(gImageMemory.stats().total == 0);
    }
    // Ledger reservations are atomic across concurrent captures/decodes, including failures.
    TLinkImageMemory concurrent(1024, 1024, 1024);
    std::vector<std::thread> clients;
    for (int n = 0; n < 8; ++n) clients.emplace_back([&] {
        for (int cycle = 0; cycle < 10000; ++cycle) {
            auto charge = concurrent.reserve(TLinkImageKind::Frame, 256);
            auto stats = concurrent.stats(); assert(stats.total <= 1024 && stats.frames <= 1024);
        }
    });
    for (auto &client : clients) client.join();
    assert(concurrent.stats().total == 0 && concurrent.stats().peak <= 1024);
    const auto firstTime = TLinkImageNowMs(); assert(firstTime <= TLinkImageNowMs()); assert(TLinkImageNowSeconds() > 0);
    puts("Image storage passed: zero-copy publication, held readers after erase/expiry/eviction, byte/count/geometry limits, 20k lifecycles and 8 x 10k reservations.");
}
