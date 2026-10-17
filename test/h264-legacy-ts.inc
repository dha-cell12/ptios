// Frozen TS wire oracle from a54251b; only name and send sink renamed.
static bool legacyWriteTSPackets(int fd,
                           uint16_t pid,
                           const uint8_t *payload,
                           size_t len,
                           bool start,
                           bool addPCR,
                           uint64_t pts90k,
                           uint8_t *cc) {
    size_t off = 0;

    while (off < len) {
        uint8_t pkt[188] = {0};
        bool first = start && (off == 0);
        bool pcrHere = addPCR && first;

        pkt[0] = 0x47;
        pkt[1] = (uint8_t)(((first ? 0x40 : 0x00) | ((pid >> 8) & 0x1F)));
        pkt[2] = (uint8_t)(pid & 0xFF);
        pkt[3] = (uint8_t)(*cc & 0x0F);
        *cc = (uint8_t)((*cc + 1) & 0x0F);

        const size_t payloadMax = 184;
        size_t remain = len - off;
        size_t copy = (remain < payloadMax) ? remain : payloadMax;

        if (pcrHere || copy < payloadMax) {
            pkt[3] |= 0x30; // adaptation + payload
            uint8_t *ad = pkt + 4;
            size_t ai = 2;

            ad[1] = pcrHere ? 0x10 : 0x00; // PCR flag

            if (pcrHere) {
                // PCR_base = pts90k (90kHz). PCR_ext = 0.
                uint64_t base = pts90k & ((1ULL << 33) - 1);
                ad[2] = (uint8_t)((base >> 25) & 0xFF);
                ad[3] = (uint8_t)((base >> 17) & 0xFF);
                ad[4] = (uint8_t)((base >> 9) & 0xFF);
                ad[5] = (uint8_t)((base >> 1) & 0xFF);
                ad[6] = (uint8_t)(((base & 1) << 7) | 0x7E);
                ad[7] = 0x00;
                ai = 8;
            }

            size_t payloadRoom = payloadMax - ai;
            if (copy > payloadRoom) {
                copy = payloadRoom;
            }
            size_t adaptLen = ai - 1;
            size_t stuff = payloadMax - (ai + copy);
            adaptLen += stuff;

            ad[0] = (uint8_t)adaptLen;
            memset(ad + ai, 0xFF, stuff);

            memcpy(pkt + 4 + 1 + adaptLen, payload + off, copy);
        } else {
            pkt[3] |= 0x10; // payload only
            memcpy(pkt + 4, payload + off, copy);
        }

        if (!legacySendAll(fd, pkt, 188)) return false;
        off += copy;
    }

    return true;
}
