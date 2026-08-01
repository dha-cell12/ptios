import { TLinkautoWsClient } from '../TLinkautoWsClient';

export type ZoomOptions = {
  durationMs?: number;
  fingerCount?: 2 | 3;
  steps?: number;
  angleDegrees?: number;
  baseFinger?: number;
};

export class TLinkautoDeviceSdk {
  private client: TLinkautoWsClient;
  private screenScale: number | null = null;
  private coordinateScale: number | null = null;

  constructor(wsBase: string, deviceId: string) {
    this.client = new TLinkautoWsClient(`${wsBase}/ios/${encodeURIComponent(deviceId)}/tlinkauto`);
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

  async zoom(centerX: number, centerY: number, startRadius: number, endRadius: number, options: ZoomOptions = {}) {
    await this.waitOpen();
    const durationMs = options.durationMs ?? 300;
    const response = await this.client.requestWithTimeout(
      64,
      Math.max(3000, durationMs + 2000),
      'zoom',
      centerX,
      centerY,
      startRadius,
      endRadius,
      durationMs,
      options.fingerCount ?? 2,
      options.steps ?? 20,
      options.angleDegrees ?? 0,
      options.baseFinger ?? 0,
    );
    if (!response.ok) throw new Error(response.raw || 'zoom failed');
  }

  async getScreenSize() {
    await this.waitOpen();
    return this.client.getScreenSize();
  }

  async getScreenScale() {
    await this.waitOpen();
    return this.client.getScreenScale();
  }

  async getCoordinateDiagnostics(): Promise<CoordinateDiagnostics> {
    await this.waitOpen();
    const [screenSize, screenScale] = await Promise.all([this.getScreenSize(), this.getScreenScale()]);
    const frame = await this.captureFrame({ gray: true, bgra: false, ttlMs: 1000 });
    try {
      const coordScale = await this.getNativeScaleForSize(frame.width, frame.height, false);
      this.coordinateScale = coordScale;
      return {
        screenSize,
        screenScale: screenScale || 1,
        frameWidth: frame.width,
        frameHeight: frame.height,
        frameScale: frame.scale,
        coordScale,
      };
    } finally {
      await this.releaseFrame(frame).catch(() => {});
    }
  }

  async screenshot(path: string, region?: RegionTuple): Promise<string> {
    await this.waitOpen();
    const nativeRegion = region ? await this.toNativeRegion(region) : undefined;
    const response = region
      ? await this.client.request(29, 1, path, nativeRegion![0], nativeRegion![1], nativeRegion![2], nativeRegion![3])
      : await this.client.request(29, 1, path);
    if (!response.ok || response.parts.length < 1) {
      throw new Error(response.raw || 'screenshot failed');
    }
    return response.parts[0];
  }

  async pickColor(x: number, y: number): Promise<PickedColor> {
    await this.waitOpen();
    const scale = await this.getNativeScale();
    const response = await this.client.request(23, Math.round(x * scale), Math.round(y * scale));
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
    const scale = await this.getNativeScale();
    const response = await this.client.request(48, 2, path);
    if (!response.ok || response.parts.length < 3) {
      throw new Error(response.raw || 'openImage failed');
    }
    return {
      id: Number(response.parts[0]),
      width: this.fromNativeLength(Number(response.parts[1]), scale),
      height: this.fromNativeLength(Number(response.parts[2]), scale),
      path,
    };
  }

  async captureImage(region: RegionTuple): Promise<ImageObjectRef> {
    await this.waitOpen();
    const scale = await this.getNativeScale();
    const nativeRegion = this.scaleRegion(region, scale);
    const response = await this.client.request(48, 1, nativeRegion[0], nativeRegion[1], nativeRegion[2], nativeRegion[3]);
    if (!response.ok || response.parts.length < 3) {
      throw new Error(response.raw || 'captureImage failed');
    }
    return {
      id: Number(response.parts[0]),
      width: this.fromNativeLength(Number(response.parts[1]), scale),
      height: this.fromNativeLength(Number(response.parts[2]), scale),
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
    const scale = await this.getNativeScale();
    const imageId = typeof image === 'number' ? image : image.id;
    const region = this.scaleRegion(options.region || [0, 0, 0, 0], scale);
    const response = await this.client.request(
      49,
      imageId,
      region[0],
      region[1],
      region[2],
      region[3],
      options.acceptable ?? 0.9,
      options.scaleMin ?? 1.0,
      options.scaleMax ?? 1.0,
      options.scaleStep ?? 0.1,
      options.pixelSkip ?? 0,
    );
    if (!response.ok || response.parts.length < 7) {
      throw new Error(response.raw || 'findImageObject failed');
    }
    const x = this.fromNativeCoord(Number(response.parts[0]), scale);
    const y = this.fromNativeCoord(Number(response.parts[1]), scale);
    const width = this.fromNativeLength(Number(response.parts[2]), scale);
    const height = this.fromNativeLength(Number(response.parts[3]), scale);
    const centerX = this.fromNativeCoord(Number(response.parts[4]), scale);
    const centerY = this.fromNativeCoord(Number(response.parts[5]), scale);
    const score = Number(response.parts[6]);
    return {
      found: x >= 0 && y >= 0 && width > 0 && height > 0,
      x,
      y,
      width,
      height,
      centerX,
      centerY,
      score,
      native: {
        region,
        result: response.parts.slice(0, 7),
        coordScale: scale,
      },
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
    return {
      id: Number(response.parts[0]),
      width: Number(response.parts[1]) || undefined,
      height: Number(response.parts[2]) || undefined,
      scale: Number(response.parts[4]) || undefined,
    };
  }

  async releaseFrame(frame: FrameRef | number): Promise<void> {
    const frameId = typeof frame === 'number' ? frame : frame.id;
    await this.waitOpen();
    const response = await this.client.request(67, frameId);
    if (!response.ok) throw new Error(response.raw || 'releaseFrame failed');
  }

  async ocr(options: OcrOptions): Promise<OcrResult> {
    const frame = await this.captureFrame({ gray: true, ttlMs: options.ttlMs ?? 1000 });
    const coordScale = await this.getNativeScaleForSize(frame.width, frame.height);
    const region = this.scaleRegion(options.region, coordScale);
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
        'pixel',
        options.maxAgeMs ?? 1000,
      );
      if (!response.ok) throw new Error(formatOcrError(response.parts, response.raw));
      return parseOcrResponse(response.parts, {
        inputRegion: options.region,
        nativeRegion: region,
        coordScale,
        frame,
      });
    } finally {
      await this.releaseFrame(frame).catch(() => {});
    }
  }

  async request(task: number, ...args: Array<string | number>) {
    return this.client.request(task, ...args);
  }

  private async getNativeScale() {
    if (this.coordinateScale && this.coordinateScale > 0) return this.coordinateScale;
    const frame = await this.captureFrame({ gray: true, bgra: false, ttlMs: 1000 });
    try {
      this.coordinateScale = await this.getNativeScaleForSize(frame.width, frame.height, false);
      return this.coordinateScale;
    } finally {
      await this.releaseFrame(frame).catch(() => {});
    }
  }

  private async getNativeScaleForSize(nativeWidth?: number, nativeHeight?: number, allowFallbackFrame = true) {
    const size = await this.getScreenSize();
    if (!size || !nativeWidth || !nativeHeight) {
      if (allowFallbackFrame) return this.getNativeScale();
      const fallbackScale = await this.getScreenScale();
      this.screenScale = fallbackScale && fallbackScale > 0 ? fallbackScale : 1;
      return this.screenScale;
    }

    const widthRatio = nativeWidth / size.width;
    const heightRatio = nativeHeight / size.height;
    if (isNear(widthRatio, 1) && isNear(heightRatio, 1)) return 1;

    const scale = await this.getScreenScale();
    this.screenScale = scale && scale > 0 ? scale : 1;
    if (isNear(widthRatio, this.screenScale) && isNear(heightRatio, this.screenScale)) return this.screenScale;

    const ratio = (widthRatio + heightRatio) / 2;
    return Number.isFinite(ratio) && ratio > 0 ? ratio : this.screenScale;
  }

  private async toNativeRegion(region: RegionTuple) {
    return this.scaleRegion(region, await this.getNativeScale());
  }

  private scaleRegion(region: RegionTuple, scale: number): RegionTuple {
    return [
      Math.round(region[0] * scale),
      Math.round(region[1] * scale),
      Math.round(region[2] * scale),
      Math.round(region[3] * scale),
    ];
  }

  private fromNativeCoord(value: number, scale: number) {
    if (value < 0) return value;
    return roundCoord(value / scale);
  }

  private fromNativeLength(value: number, scale: number) {
    if (value <= 0) return value;
    return roundCoord(value / scale);
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
  found: boolean;
  x: number;
  y: number;
  width: number;
  height: number;
  centerX: number;
  centerY: number;
  score: number;
  native?: {
    region: RegionTuple;
    result: string[];
    coordScale: number;
  };
};

export type CoordinateDiagnostics = {
  screenSize: { width: number; height: number } | null;
  screenScale: number;
  frameWidth?: number;
  frameHeight?: number;
  frameScale?: number;
  coordScale: number;
};

export type CaptureFrameOptions = {
  gray?: boolean;
  bgra?: boolean;
  ttlMs?: number;
};

export type FrameRef = {
  id: number;
  width?: number;
  height?: number;
  scale?: number;
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
  confidence?: number;
  frameAgeMs?: number;
  ocrMs?: number;
  preprocessMs?: number;
  totalMs?: number;
  diagnostics?: {
    inputRegion: RegionTuple;
    nativeRegion: RegionTuple;
    coordScale: number;
    frame: FrameRef;
  };
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

function roundCoord(value: number) {
  return Math.round(value * 100) / 100;
}

function isNear(value: number, target: number) {
  return Math.abs(value - target) < 0.05;
}

function parseOcrResponse(parts: string[], diagnostics?: OcrResult['diagnostics']): OcrResult {
  const joined = parts.join(';;');
  try {
    const decoded = decodeBase64Utf8(parts[0] || '');
    return {
      text: decoded,
      raw: parts,
      confidence: optionalNumber(parts[1]),
      frameAgeMs: optionalNumber(parts[2]),
      ocrMs: optionalNumber(parts[3]),
      preprocessMs: optionalNumber(parts[4]),
      totalMs: optionalNumber(parts[5]),
      diagnostics,
    };
  } catch {}
  return { text: joined, raw: parts, diagnostics };
}

function optionalNumber(value: string | undefined) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function formatOcrError(parts: string[], raw: string) {
  if (parts.length >= 2) {
    try {
      const detail = decodeBase64Utf8(parts[1]);
      return detail ? `OCR ${parts[0]}: ${detail}` : `OCR ${parts[0]}`;
    } catch {}
  }
  return raw || 'ocr failed';
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
