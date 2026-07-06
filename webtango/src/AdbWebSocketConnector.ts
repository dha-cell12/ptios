import { AdbServerClient } from "@yume-chan/adb";
import { MaybeConsumable } from "@yume-chan/stream-extra";

/**
 * WebSocket connector for AdbServerClient.
 * Implements the ServerConnector interface to work with bridge-rs.
 */
export class AdbWebSocketConnector implements AdbServerClient.ServerConnector {
    private url: string;

    constructor(url: string) {
        this.url = url;
    }

    async connect(options?: AdbServerClient.ServerConnectionOptions): Promise<AdbServerClient.ServerConnection> {
        console.debug('[AdbWebSocketConnector] Connecting to:', this.url);

        return new Promise((resolve, reject) => {
            const socket = new WebSocket(this.url);
            socket.binaryType = "arraybuffer";

            console.debug('[AdbWebSocketConnector] WebSocket created, waiting for connection...');

            socket.onopen = () => {
                console.debug('[AdbWebSocketConnector] ✅ WebSocket connected successfully');

                // Create readable stream from WebSocket messages
                const readable = new ReadableStream<Uint8Array>({
                    start(controller) {
                        socket.onmessage = ({ data }) => {
                            const bytes = new Uint8Array(data as ArrayBuffer);
                            // Verbose logging removed for performance
                            // console.debug('[AdbWebSocketConnector] ⬇️ Received', bytes.length, 'bytes');
                            controller.enqueue(bytes);
                        };

                        socket.onclose = (event) => {
                            console.debug('[AdbWebSocketConnector] ❌ WebSocket closed:', event.code, event.reason);
                            try {
                                controller.close();
                            } catch (e) {
                                // Stream might already be errored, ignore
                            }
                        };

                        socket.onerror = (e) => {
                            console.error('[AdbWebSocketConnector] ❌ WebSocket error:', e);
                            controller.error(e);
                        };
                    },
                });

                // Create writable stream to send data via WebSocket
                const writable = new WritableStream<MaybeConsumable<Uint8Array>>({
                    async write(chunk) {
                        const bytes = chunk instanceof Uint8Array ? chunk : chunk.value;
                        // Verbose logging removed for performance
                        // console.debug('[AdbWebSocketConnector] ⬆️ Sending', bytes.length, 'bytes');

                        // Backpressure control: Wait if buffer is full
                        if (socket.bufferedAmount > 1024 * 1024) { // 1MB Limit
                            await new Promise<void>(resolve => {
                                const check = () => {
                                    if (socket.readyState !== WebSocket.OPEN) {
                                        resolve();
                                        return;
                                    }
                                    if (socket.bufferedAmount < 512 * 1024) { // Drain to 512KB
                                        resolve();
                                    } else {
                                        setTimeout(check, 50);
                                    }
                                };
                                check();
                            });
                        }

                        socket.send(bytes);
                    },
                    close() {
                        console.debug('[AdbWebSocketConnector] Closing writable stream');
                        socket.close();
                    },
                });

                // Keepalive mechanism for Cloudflare Tunnel
                // Send ping every 30 seconds to prevent timeout
                let keepaliveInterval: number | undefined = window.setInterval(() => {
                    if (socket.readyState === WebSocket.OPEN) {
                        // Send empty message as keepalive
                        // ADB protocol ignores zero-length messages
                        socket.send(new Uint8Array(0));
                        console.debug('[AdbWebSocketConnector] 💓 Keepalive ping sent');
                    } else {
                        // Clear interval if socket is closed
                        if (keepaliveInterval) {
                            clearInterval(keepaliveInterval);
                            keepaliveInterval = undefined;
                        }
                    }
                }, 30000); // 30 seconds

                const connection: AdbServerClient.ServerConnection = {
                    readable: readable as any,
                    writable: writable as any,
                    get closed() {
                        return new Promise<undefined>((resolve) => {
                            if (socket.readyState === WebSocket.CLOSED) {
                                resolve(undefined);
                            } else {
                                socket.addEventListener('close', () => resolve(undefined), { once: true });
                            }
                        });
                    },
                    close() {
                        console.debug('[AdbWebSocketConnector] Closing connection');
                        // Clear keepalive interval
                        if (keepaliveInterval) {
                            clearInterval(keepaliveInterval);
                            keepaliveInterval = undefined;
                        }
                        socket.close();
                    },
                };

                console.debug('[AdbWebSocketConnector] ✅ Connection initialized');
                resolve(connection);
            };

            socket.onerror = (e) => {
                console.error('[AdbWebSocketConnector] ❌ WebSocket connection error:', e);
                reject(new Error('WebSocket connection failed'));
            };

            socket.onclose = (event) => {
                if (event.code !== 1000) {
                    console.error('[AdbWebSocketConnector] ❌ WebSocket closed before connection:', event.code, event.reason);
                    reject(new Error(`WebSocket closed: ${event.code} ${event.reason}`));
                }
            };
        });
    }

    // Reverse tunnel methods - implement for scrcpy support
    async addReverseTunnel(handler: any, address?: string): Promise<string> {
        // For scrcpy, address is typically "localabstract:scrcpy"
        // The handler will be called when incoming connections arrive
        console.log('[AdbWebSocketConnector] Adding reverse tunnel:', address);

        // For WebSocket-based ADB, reverse tunnels work differently
        // The ADB server protocol will handle the actual tunneling
        // We just need to return the address
        return address || 'localabstract:scrcpy';
    }

    async removeReverseTunnel(address: string): Promise<void> {
        console.log('[AdbWebSocketConnector] Removing reverse tunnel:', address);
        // Cleanup handled by ADB server protocol
    }

    async clearReverseTunnels(): Promise<void> {
        console.log('[AdbWebSocketConnector] Clearing all reverse tunnels');
        // Cleanup handled by ADB server protocol
    }
}
