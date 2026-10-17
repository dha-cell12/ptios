// Frozen at 1b4b382; regression oracle for coarse/refined SAD.
static long long legacyTemplateSad(const Mat &img, const Mat &templ,
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
