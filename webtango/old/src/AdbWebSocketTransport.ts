import {
    AdbPacketData,
    AdbPacketInit,
    AdbPacketSerializeStream,
    AdbDaemonConnection,
} from "@yume-chan/adb";
import {
    ReadableStream,
    WritableStream,
    ReadableWritablePair,
    BufferedReadableStream,
    Consumable,
    WrapReadableStream,
    WrapWritableStream,
} from "@yume-chan/stream-extra";
import { AdbPacketHeader } from "@yume-chan/adb";

class BufferReader {
    private buffer: Uint8Array;
    private offset: number = 0;

    constructor(buffer: Uint8Array) {
        this.buffer = buffer;
    }

    get position() {
        return this.offset;
    }

    readExactly(length: number): Uint8Array {
        if (this.offset + length > this.buffer.length) {
            throw new Error("Unexpected end of stream");
        }
        const result = this.buffer.subarray(this.offset, this.offset + length);
        this.offset += length;
        return result;
    }
}

/**
 * Creates an ADB connection over WebSocket for use with bridge-rs.
 * Bridge-rs forwards raw TCP data between WebSocket and ADB daemon,
 * so we need to parse/serialize ADB packets on the client side.
 */
export class AdbWebSocketTransport {
    static async connect(url: string): Promise<AdbDaemonConnection> {
        console.log('[AdbWebSocketTransport] Connecting to:', url);

        return new Promise((resolve, reject) => {
            const socket = new WebSocket(url);
            socket.binaryType = "arraybuffer";

            console.log('[AdbWebSocketTransport] WebSocket created, waiting for connection...');

            socket.onopen = () => {
                console.log('[AdbWebSocketTransport] ✅ WebSocket connected successfully');

                // Create raw byte stream from WebSocket
                const rawReadableSource = new ReadableStream<Uint8Array>({
                    start(controller) {
                        socket.onmessage = ({ data }) => {
                            const bytes = new Uint8Array(data as ArrayBuffer);
                            console.log('[AdbWebSocketTransport] ⬇️ Received', bytes.length, 'bytes:',
                                Array.from(bytes.slice(0, Math.min(32, bytes.length)))
                                    .map(b => b.toString(16).padStart(2, '0')).join(' '));
                            controller.enqueue(bytes);
                        };
                        socket.onclose = (event) => {
                            console.log('[AdbWebSocketTransport] ❌ WebSocket closed:', event.code, event.reason);
                            controller.close();
                        };
                        socket.onerror = (e) => {
                            console.error('[AdbWebSocketTransport] ❌ WebSocket stream error:', e);
                            controller.error(e);
                        };
                    },
                });

                // Buffer the raw stream for packet parsing
                const buffered = new BufferedReadableStream(rawReadableSource);

                // Parse ADB packets from raw stream
                const readable = new ReadableStream<AdbPacketData>({
                    async pull(controller) {
                        try {
                            console.log('[AdbWebSocketTransport] 📦 Reading ADB packet header...');
                            const headerBuffer = await buffered.readExactly(24);
                            const reader = new BufferReader(headerBuffer);
                            const header = AdbPacketHeader.deserialize(reader);

                            console.log('[AdbWebSocketTransport] 📦 Packet header:', {
                                command: '0x' + header.command.toString(16),
                                arg0: header.arg0,
                                arg1: header.arg1,
                                payloadLength: header.payloadLength
                            });

                            let payload: Uint8Array;
                            if (header.payloadLength > 0) {
                                console.log('[AdbWebSocketTransport] 📦 Reading payload:', header.payloadLength, 'bytes');
                                payload = await buffered.readExactly(header.payloadLength);
                            } else {
                                payload = new Uint8Array(0);
                            }

                            controller.enqueue({
                                command: header.command,
                                arg0: header.arg0,
                                arg1: header.arg1,
                                payload,
                            });
                        } catch (e) {
                            console.error('[AdbWebSocketTransport] ❌ Error reading packet:', e);
                            controller.close();
                        }
                    },
                });

                // Serialize ADB packets to raw bytes and send via WebSocket
                const serializer = new AdbPacketSerializeStream();
                serializer.readable.pipeTo(
                    new WritableStream({
                        write(chunk) {
                            const bytes = chunk.value;
                            console.log('[AdbWebSocketTransport] ⬆️ Sending', bytes.length, 'bytes:',
                                Array.from(bytes.slice(0, Math.min(32, bytes.length)))
                                    .map(b => b.toString(16).padStart(2, '0')).join(' '));
                            socket.send(bytes);
                        },
                    })
                );

                const connection: AdbDaemonConnection = {
                    readable,
                    writable: serializer.writable,
                };

                console.log('[AdbWebSocketTransport] ✅ Connection initialized');
                resolve(connection);
            };

            socket.onerror = (e) => {
                console.error('[AdbWebSocketTransport] ❌ WebSocket connection error:', e);
                reject(new Error('WebSocket connection failed'));
            };

            socket.onclose = (event) => {
                if (event.code !== 1000) {
                    console.error('[AdbWebSocketTransport] ❌ WebSocket closed before connection:', event.code, event.reason);
                    reject(new Error(`WebSocket closed: ${event.code} ${event.reason}`));
                }
            };
        });
    }
}
