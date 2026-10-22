// Frozen from 528655c pccontrol/ColorPicker.xm; valid 0/1 mode inputs only.
static inline bool legacyColorMatch(int r, int g, int b, int tr, int tg, int tb, int mode, double value)
{
    int dr = abs(r - tr);
    int dg = abs(g - tg);
    int db = abs(b - tb);
    if (mode == 1) {
        int dev = (int)value;
        return dr <= dev && dg <= dev && db <= dev;
    }
    double sim = 1.0 - ((double)dr + (double)dg + (double)db) / (3.0 * 255.0);
    return sim >= value;
}
