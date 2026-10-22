// Frozen pre-C01c3b implementation; controlled resize used only as an oracle.
static long long legacyImageSad(const Mat &img, const Mat &templ,
                                    int x0, int y0, int x1, int y1,
                                    int step, int *bestX, int *bestY)
{
    auto nativeBudget = TLinkCurrentNativeBudget();
    const int w = templ.cols;
    const int h = templ.rows;

    long long bestSad = LLONG_MAX;
    int bx = 0;
    int by = 0;

    if (step <= 0) step = 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    const int maxX = img.cols - w;
    const int maxY = img.rows - h;
    if (x1 > maxX) x1 = maxX;
    if (y1 > maxY) y1 = maxY;
    if (x0 > x1 || y0 > y1) {
        if (bestX) *bestX = 0;
        if (bestY) *bestY = 0;
        return bestSad;
    }

    for (int y = y0; y <= y1; y += step) {
        if (nativeBudget && nativeBudget->stopped()) return LLONG_MAX;
        for (int x = x0; x <= x1; x += step) {
            long long sad = 0;
            for (int ty = 0; ty < h; ty++) {
                if ((ty & 31) == 0 && nativeBudget && nativeBudget->stopped()) return LLONG_MAX;
                const unsigned char *imgRow = img.ptr<unsigned char>(y + ty) + x;
                const unsigned char *tRow = templ.ptr<unsigned char>(ty);
                for (int tx = 0; tx < w; tx++) {
                    sad += (long long)abs((int)imgRow[tx] - (int)tRow[tx]);
                }
                if (sad >= bestSad) {
                    break;
                }
            }
            if (sad < bestSad) {
                bestSad = sad;
                bx = x;
                by = y;
            }
        }
    }

    if (bestX) *bestX = bx;
    if (bestY) *bestY = by;
    return bestSad;
}

static BOOL legacyImageFind(const Mat &img, const Mat &templ,
                              double acceptable,
                              float scaleMin, float scaleMax, float scaleStep,
                              int pixelSkip,
                              int *outX, int *outY, int *outW, int *outH,
                              double *outScore)
{
    if (outX) *outX = -1;
    if (outY) *outY = -1;
    if (outW) *outW = 0;
    if (outH) *outH = 0;
    if (outScore) *outScore = 0;

    if (img.empty() || templ.empty()) {
        return false;
    }

    float r = 1.0f;
    long long pixels = (long long)img.cols * (long long)img.rows;
    if (pixels > 600000) {
        r = 0.5f;
    }

    Mat imgWork = img;
    if (r != 1.0f) {
        cv::resize(img, imgWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
    }

    int coarseStep = pixelSkip + 1;
    if (coarseStep < 4) coarseStep = 4;

    double bestOverallScore = -1.0;
    int bestX = -1, bestY = -1, bestW = 0, bestH = 0;

    if (scaleStep <= 0.0f) {
        scaleStep = 0.1f;
    }
    if (scaleMax < scaleMin) {
        float tmp = scaleMax;
        scaleMax = scaleMin;
        scaleMin = tmp;
    }

    for (float s = scaleMax; s >= scaleMin - 0.0001f; s -= scaleStep) {
        if (TLinkNativeStopped()) return false;
        Mat templScaled;
        if (fabsf(s - 1.0f) < 0.0001f) {
            templScaled = templ;
        } else {
            int interp = s < 1.0f ? cv::INTER_AREA : cv::INTER_LINEAR;
            cv::resize(templ, templScaled, cv::Size(0, 0), s, s, interp);
        }
        if (templScaled.empty()) {
            continue;
        }
        Mat templWork = templScaled;
        if (r != 1.0f) {
            cv::resize(templScaled, templWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
        }

        if (templWork.cols <= 0 || templWork.rows <= 0 ||
            templWork.cols > imgWork.cols || templWork.rows > imgWork.rows) {
            continue;
        }

        int bx = 0, by = 0;
        long long bestSad = legacyImageSad(imgWork, templWork,
                                               0, 0,
                                               imgWork.cols - templWork.cols,
                                               imgWork.rows - templWork.rows,
                                               coarseStep,
                                               &bx, &by);

        int refineRadius = coarseStep * 2;
        int rbx = bx, rby = by;
        long long refinedSad = legacyImageSad(imgWork, templWork,
                                                   bx - refineRadius, by - refineRadius,
                                                   bx + refineRadius, by + refineRadius,
                                                   1,
                                                   &rbx, &rby);
        if (refinedSad < bestSad) {
            bestSad = refinedSad;
            bx = rbx;
            by = rby;
        }

        const long long denom = 255LL * (long long)templWork.cols * (long long)templWork.rows;
        double score = (denom > 0) ? (1.0 - ((double)bestSad / (double)denom)) : 0.0;
        if (score > bestOverallScore) {
            bestOverallScore = score;
            bestX = bx;
            bestY = by;
            bestW = templWork.cols;
            bestH = templWork.rows;
        }

        if (score >= acceptable) {
            const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
            if (outX) *outX = (int)round(bx * inv);
            if (outY) *outY = (int)round(by * inv);
            if (outW) *outW = (int)round(templWork.cols * inv);
            if (outH) *outH = (int)round(templWork.rows * inv);
            if (outScore) *outScore = score;
            return true;
        }
    }

    if (bestX >= 0 && bestY >= 0 && bestW > 0 && bestH > 0) {
        const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
        if (outX) *outX = (int)round(bestX * inv);
        if (outY) *outY = (int)round(bestY * inv);
        if (outW) *outW = (int)round(bestW * inv);
        if (outH) *outH = (int)round(bestH * inv);
    }
    if (outScore) *outScore = (bestOverallScore < 0.0) ? 0.0 : bestOverallScore;
    return false;
}

