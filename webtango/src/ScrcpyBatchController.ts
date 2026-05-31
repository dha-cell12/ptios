import { ScrcpyControlMessageWriter } from "@yume-chan/scrcpy";

/**
 * Helper to inject KeyCode using Atomic Batch Write (Down + Up in one packet).
 * This acts as a workaround for the Sequential Write Hang issue encountered
 * on some Scrcpy connections (like WebSocket bridges).
 */
export class ScrcpyBatchController {
    /**
     * Injects a key code by sending DOWN and UP events in a single atomic write.
     * @param controller The Scrcpy controller instance
     * @param keyCode The Android KeyCode (number)
     * @param timeoutMs Safety timeout to prevent promise hanging (default 300ms)
     */
    static async injectKey(
        controller: ScrcpyControlMessageWriter,
        keyCode: number,
        timeoutMs: number = 300
    ): Promise<void> {
        try {
            // 14 bytes for Down + 14 bytes for Up = 28 bytes total
            const batchMsg = new Uint8Array(28);

            // --- Message 1: DOWN ---
            // Format: Type(1) + Action(1) + KeyCode(4) + Repeat(4) + MetaState(4)
            batchMsg[0] = 0; // Type: InjectKeyCode
            batchMsg[1] = 0; // Action: Down
            const view = new DataView(batchMsg.buffer);
            view.setUint32(2, keyCode, false); // KeyCode (Big Endian)
            view.setUint32(6, 0, false);       // Repeat: 0
            view.setUint32(10, 0, false);      // MetaState: 0

            // --- Message 2: UP ---
            // Offset 14
            batchMsg[14] = 0; // Type: InjectKeyCode
            batchMsg[15] = 1; // Action: Up
            view.setUint32(16, keyCode, false); // KeyCode
            view.setUint32(20, 0, false);       // Repeat
            view.setUint32(24, 0, false);       // MetaState

            // Send ATOMICALLY with safety timeout
            // Using Promise.race to ensure we don't hang if server doesn't ACK quickly
            const result = await Promise.race([
                controller.write(batchMsg),
                new Promise(resolve => setTimeout(() => resolve('timeout'), timeoutMs))
            ]);

            if (result === 'timeout') {
                console.debug(`[ScrcpyBatch] Key ${keyCode} write timed out (likely sent)`);
            }
        } catch (err) {
            console.error(`[ScrcpyBatch] Failed to inject key ${keyCode}:`, err);
            throw err; // Re-throw to let caller decide fallback
        }
    }
}
