#include "SocketServer.h"
#include <string.h>

int notifyClient(UInt8* msg, CFWriteStreamRef client)
{
    if (client == 0 || msg == NULL)
    {
        return -1;
    }

    const UInt8 *cursor = msg;
    CFIndex remaining = (CFIndex)strlen((char*)msg);
    CFIndex total = remaining;
    while (remaining > 0)
    {
        CFIndex wrote = CFWriteStreamWrite(client, cursor, remaining);
        if (wrote <= 0)
        {
            return -1;
        }
        cursor += wrote;
        remaining -= wrote;
    }
    return (int)total;
}
