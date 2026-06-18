import { ZxTouchWsClient } from '../ZxTouchWsClient';

export class ZxTouchDeviceSdk {
  private client: ZxTouchWsClient;

  constructor(wsBase: string, deviceId: string) {
    this.client = new ZxTouchWsClient(`${wsBase}/ios/${encodeURIComponent(deviceId)}/zxtouch`);
  }

  async waitOpen(timeoutMs = 1500) {
    await this.client.waitOpen(timeoutMs);
  }

  close() {
    this.client.close();
  }

  async tap(x: number, y: number, holdMs = 60) {
    await this.waitOpen();
    this.client.touch(1, 1, x, y);
    await sleep(holdMs);
    this.client.touch(0, 1, x, y);
  }

  async swipe(x1: number, y1: number, x2: number, y2: number, durationMs = 300) {
    await this.waitOpen();
    const steps = Math.max(2, Math.ceil(durationMs / 16));
    this.client.touch(1, 1, x1, y1);
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      this.client.tryTouchMove(1, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      await sleep(durationMs / steps);
    }
    this.client.touch(0, 1, x2, y2);
  }

  async getScreenSize() {
    await this.waitOpen();
    return this.client.getScreenSize();
  }

  async screenshot(path: string, region?: RegionTuple): Promise<string> {
    await this.waitOpen();
    const response = region
      ? await this.client.request(29, 1, path, region[0], region[1], region[2], region[3])
      : await this.client.request(29, 1, path);
    if (!response.ok || response.parts.length < 1) {
      throw new Error(response.raw || 'screenshot failed');
    }
    return response.parts[0];
  }

  async pickColor(x: number, y: number): Promise<PickedColor> {
    await this.waitOpen();
    const response = await this.client.request(23, Math.round(x), Math.round(y));
    if (!response.ok || response.parts.length < 3) {
      throw new Error(response.raw || 'pickColor failed');
    }

    const red = clampColor(Number(response.parts[0]));
    const green = clampColor(Number(response.parts[1]));
    const blue = clampColor(Number(response.parts[2]));
    return {
      red,
      green,
      blue,
      hex: rgbToHex(red, green, blue),
    };
  }

  async colorEquals(x: number, y: number, hex: string, tolerance = 10): Promise<boolean> {
    const color = await this.pickColor(x, y);
    const expected = hexToRgb(hex);
    return (
      Math.abs(color.red - expected.red) <= tolerance &&
      Math.abs(color.green - expected.green) <= tolerance &&
      Math.abs(color.blue - expected.blue) <= tolerance
    );
  }

  async openImage(path: string): Promise<ImageObjectRef> {
    await this.waitOpen();
    const response = await this.client.request(48, 2, path);
    if (!response.ok || response.parts.length < 3) {
      throw new Error(response.raw || 'openImage failed');
    }
    return {
      id: Number(response.parts[0]),
      width: Number(response.parts[1]),
      height: Number(response.parts[2]),
      path,
    };
  }

  async captureImage(region: RegionTuple): Promise<ImageObjectRef> {
    await this.waitOpen();
    const response = await this.client.request(48, 1, region[0], region[1], region[2], region[3]);
    if (!response.ok || response.parts.length < 3) {
      throw new Error(response.raw || 'captureImage failed');
    }
    return {
      id: Number(response.parts[0]),
      width: Number(response.parts[1]),
      height: Number(response.parts[2]),
      region,
    };
  }

  async releaseImage(image: ImageObjectRef | number): Promise<void> {
    const imageId = typeof image === 'number' ? image : image.id;
    await this.waitOpen();
    const response = await this.client.request(48, 3, imageId);
    if (!response.ok) throw new Error(response.raw || 'releaseImage failed');
  }

  async findImage(imagePath: string, options: FindImageOptions = {}): Promise<FindImageResult> {
    const image = await this.openImage(imagePath);
    try {
      return await this.findImageObject(image, options);
    } finally {
      await this.releaseImage(image).catch(() => {});
    }
  }

  async findImageObject(image: ImageObjectRef | number, options: FindImageOptions = {}): Promise<FindImageResult> {
    await this.waitOpen();
    const imageId = typeof image === 'number' ? image : image.id;
    const region = options.region || [0, 0, 0, 0];
    const response = await this.client.request(
      49,
      imageId,
      region[0],
      region[1],
      region[2],
      region[3],
      options.acceptable ?? 0.8,
      options.scaleMin ?? 0.2,
      options.scaleMax ?? 1.0,
      options.scaleStep ?? 0.1,
      options.pixelSkip ?? 0,
    );
    if (!response.ok || response.parts.length < 7) {
      throw new Error(response.raw || 'findImageObject failed');
    }
    return {
      x: Number(response.parts[0]),
      y: Number(response.parts[1]),
      width: Number(response.parts[2]),
      height: Number(response.parts[3]),
      centerX: Number(response.parts[4]),
      centerY: Number(response.parts[5]),
      score: Number(response.parts[6]),
    };
  }

  async captureFrame(options: CaptureFrameOptions = {}): Promise<FrameRef> {
    await this.waitOpen();
    const response = await this.client.request(
      66,
      options.gray ? 1 : 0,
      options.bgra ? 1 : 0,
      options.ttlMs ?? 1000,
    );
    if (!response.ok || response.parts.length < 1) {
      throw new Error(response.raw || 'captureFrame failed');
    }
    return { id: Number(response.parts[0]) };
  }

  async releaseFrame(frame: FrameRef | number): Promise<void> {
    const frameId = typeof frame === 'number' ? frame : frame.id;
    await this.waitOpen();
    const response = await this.client.request(67, frameId);
    if (!response.ok) throw new Error(response.raw || 'releaseFrame failed');
  }

  async ocr(options: OcrOptions): Promise<OcrResult> {
    const region = options.region;
    const frame = await this.captureFrame({ gray: true, ttlMs: options.ttlMs ?? 1000 });
    try {
      const response = await this.client.request(
        91,
        frame.id,
        region[0],
        region[1],
        region[2],
        region[3],
        options.lang ?? 'vie',
        options.oem ?? 1,
        options.psm ?? 7,
        encodeBase64Utf8(options.whitelist ?? ''),
        options.scaleUp ?? 2,
        options.thresholdMode ?? 0,
        options.coord ?? 'pixel',
        options.maxAgeMs ?? 1000,
      );
      if (!response.ok) throw new Error(response.raw || 'ocr failed');
      return parseOcrResponse(response.parts);
    } finally {
      await this.releaseFrame(frame).catch(() => {});
    }
  }

  async request(task: number, ...args: Array<string | number>) {
    return this.client.request(task, ...args);
  }
}

export type PickedColor = {
  red: number;
  green: number;
  blue: number;
  hex: string;
};

export type RegionTuple = [number, number, number, number];

export type ImageObjectRef = {
  id: number;
  width: number;
  height: number;
  path?: string;
  region?: RegionTuple;
};

export type FindImageOptions = {
  region?: RegionTuple;
  acceptable?: number;
  scaleMin?: number;
  scaleMax?: number;
  scaleStep?: number;
  pixelSkip?: number;
};

export type FindImageResult = {
  x: number;
  y: number;
  width: number;
  height: number;
  centerX: number;
  centerY: number;
  score: number;
};

export type CaptureFrameOptions = {
  gray?: boolean;
  bgra?: boolean;
  ttlMs?: number;
};

export type FrameRef = {
  id: number;
};

export type OcrOptions = {
  region: [number, number, number, number];
  lang?: string;
  oem?: number;
  psm?: number;
  whitelist?: string;
  scaleUp?: number;
  thresholdMode?: number;
  coord?: 'pixel' | 'point';
  maxAgeMs?: number;
  ttlMs?: number;
};

export type OcrResult = {
  text: string;
  raw: string[];
};

export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) return Promise.reject(new DOMException('Aborted', 'AbortError'));
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(new DOMException('Aborted', 'AbortError'));
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

export function rgbToHex(red: number, green: number, blue: number): string {
  return `#${toHex(red)}${toHex(green)}${toHex(blue)}`;
}

export function hexToRgb(hex: string): { red: number; green: number; blue: number } {
  const normalized = hex.trim().replace(/^#/, '');
  if (!/^[0-9a-fA-F]{6}$/.test(normalized)) throw new Error(`Invalid hex color: ${hex}`);
  return {
    red: parseInt(normalized.slice(0, 2), 16),
    green: parseInt(normalized.slice(2, 4), 16),
    blue: parseInt(normalized.slice(4, 6), 16),
  };
}

function clampColor(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(255, Math.round(value)));
}

function toHex(value: number): string {
  return clampColor(value).toString(16).padStart(2, '0').toUpperCase();
}

function parseOcrResponse(parts: string[]): OcrResult {
  const joined = parts.join(';;');
  try {
    const decoded = decodeBase64Utf8(parts[0] || '');
    return { text: decoded, raw: parts };
  } catch {}
  return { text: joined, raw: parts };
}

function encodeBase64Utf8(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function decodeBase64Utf8(base64: string): string {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder('utf-8').decode(bytes);
}
