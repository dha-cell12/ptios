#ifndef TLINKAUTO_JS_IPC_PROTOCOL_H
#define TLINKAUTO_JS_IPC_PROTOCOL_H

#include <stdint.h>

#define TLJS_MAGIC 'TLJS'
#define TLJS_VERSION 1

typedef enum {
    TLJS_MSG_HELLO = 1,
    TLJS_MSG_HELLO_ACK,
    TLJS_MSG_START_RUN,
    TLJS_MSG_START_RESULT,
    TLJS_MSG_STOP_RUN,
    TLJS_MSG_RUN_STATE,
    TLJS_MSG_RUN_FINISHED,

    TLJS_MSG_TASK_REQUEST = 10,
    TLJS_MSG_TASK_RESPONSE,
    TLJS_MSG_TASK_CANCEL,

    TLJS_MSG_HANDLE_RELEASE = 20,
    TLJS_MSG_HANDLE_RELEASE_ALL,

    TLJS_MSG_LOG_EVENT = 30,
    TLJS_MSG_PING = 40,
    TLJS_MSG_PONG,
    TLJS_MSG_PROTOCOL_ERROR
} TLinkautoJSIPCMessageType;

#pragma pack(push, 1)
typedef struct {
    uint32_t magic;          // 'TLJS'
    uint16_t version;        // 1
    uint16_t messageType;
    uint32_t flags;
    uint64_t requestId;
    uint64_t runId;
    uint64_t generation;
    uint32_t payloadLength;
    uint32_t timeoutMs;
} TLinkautoJSIPCHeader;
#pragma pack(pop)

#endif /* TLINKAUTO_JS_IPC_PROTOCOL_H */
