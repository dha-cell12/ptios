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

  async getRunHistory(): Promise<RunHistorySnapshot> {
    await this.waitOpen();
    const response = await this.client.requestWithTimeout(60, 5000);
    if (!response.ok || response.parts.length < 1) {
      throw new Error(response.raw || 'run history status failed');
    }
    const status = JSON.parse(decodeBase64Utf8(response.parts[0]));
    const history = status?.run_history;
    if (!history || history.schema !== 'run_history_v1' || !Array.isArray(history.runs)) {
      throw new Error('run_history_v1 is unavailable');
    }
    return history as RunHistorySnapshot;
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

  async frontMostAppId(): Promise<string> {
    await this.waitOpen();
    const response = await this.client.request(34);
    if (!response.ok || response.parts.length < 1) {
      throw new Error(response.raw || 'frontMostAppId failed');
    }
    return response.parts[0];
  }

  async waitUntil<T>(
    predicate: (attempt: number) => T | false | null | undefined | Promise<T | false | null | undefined>,
    options: SmartWaitOptions = {},
  ): Promise<SmartWaitResult<T>> {
    return this.runWait('wait_until', predicate, options, false);
  }

  async waitForApp(bundleId: string, options: SmartWaitOptions = {}): Promise<SmartWaitResult<string>> {
    if (!bundleId) throw new Error('waitForApp requires bundleId');
    const result = await this.runWait(
      'wait_for_app',
      async () => {
        const current = await this.frontMostAppId();
        return current === bundleId ? current : false;
      },
      options,
      true,
    );
    return Object.assign(result, { bundleId });
  }

  async waitForColor(
    x: number,
    y: number,
    color: SmartWaitColor,
    options: SmartWaitOptions & { tolerance?: number } = {},
  ): Promise<SmartWaitResult<PickedColor>> {
    const expected = normalizeSmartWaitColor(color);
    const tolerance = Math.max(0, finiteNumber(options.tolerance, 0));
    const result = await this.runWait(
      'wait_for_color',
      async () => {
        const current = await this.pickColor(x, y);
        const matched =
          Math.abs(current.red - expected.red) <= tolerance &&
          Math.abs(current.green - expected.green) <= tolerance &&
          Math.abs(current.blue - expected.blue) <= tolerance;
        return matched ? current : false;
      },
      options,
      true,
    );
    return Object.assign(result, { expected, tolerance, x, y });
  }

  async waitForImage(
    imagePath: string,
    options: WaitForImageOptions = {},
  ): Promise<SmartWaitResult<FindImageResult>> {
    return this.waitForImageState(imagePath, options, true, 'wait_for_image') as Promise<SmartWaitResult<FindImageResult>>;
  }

  async waitUntilGone(
    imagePath: string,
    options: WaitForImageOptions = {},
  ): Promise<SmartWaitResult<{ gone: true; lastMatch: FindImageResult }> & { gone: boolean }> {
    const result = await this.waitForImageState(imagePath, options, false, 'wait_until_gone');
    return Object.assign(result, { found: false, gone: result.ok }) as unknown as SmartWaitResult<{
      gone: true;
      lastMatch: FindImageResult;
    }> & { gone: boolean };
  }

  async waitForText(
    text: string,
    options: WaitForTextOptions = {},
  ): Promise<SmartWaitResult<OcrResult>> {
    if (!text) throw new Error('waitForText requires non-empty text');
    const region = options.region || (await this.fullScreenRegion());
    const result = await this.runWait(
      'wait_for_text',
      async () => {
        const ocr = await this.ocr({
          region,
          lang: options.lang ?? 'eng',
          oem: options.oem,
          psm: options.psm,
          whitelist: options.whitelist,
          scaleUp: options.scaleUp,
          thresholdMode: options.thresholdMode,
          coord: options.coord,
          maxAgeMs: options.maxAgeMs,
          ttlMs: Math.max(1000, boundedInteger(options.intervalMs, 200, 20, 10000) + 500),
        });
        return smartWaitTextMatches(ocr.text, text, options) ? ocr : false;
      },
      options,
      true,
    );
    return Object.assign(result, {
      locator: {
        type: 'text',
        text,
        matchMode: options.matchMode ?? 'contains',
        caseSensitive: options.caseSensitive ?? false,
      },
    });
  }

  async tapWhenVisible(
    imagePath: string,
    options: TapWhenVisibleOptions = {},
  ): Promise<SmartWaitResult<FindImageResult> & {
    tapped: boolean;
    tapX?: number;
    tapY?: number;
  }> {
    const result = await this.waitForImage(imagePath, options);
    const output = Object.assign(result, { kind: 'tap_when_visible', tapped: false as boolean });
    if (!output.ok || !output.value) return output;
    const tapX = output.value.centerX + finiteNumber(options.offsetX, 0);
    const tapY = output.value.centerY + finiteNumber(options.offsetY, 0);
    try {
      await this.tap(tapX, tapY, options.holdMs ?? 60);
      return Object.assign(output, { tapped: true, tapX, tapY });
    } catch (error) {
      return Object.assign(output, {
        ok: false,
        tapped: false,
        tapX,
        tapY,
        lastError: smartWaitErrorText(error),
      });
    }
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

  async findImageObjectInFrame(
    frame: FrameRef | number,
    image: ImageObjectRef | number,
    options: FindImageOptions & { maxAgeMs?: number } = {},
  ): Promise<FindImageResult> {
    await this.waitOpen();
    const scale = await this.getNativeScale();
    const frameId = typeof frame === 'number' ? frame : frame.id;
    const imageId = typeof image === 'number' ? image : image.id;
    const region = this.scaleRegion(options.region || [0, 0, 0, 0], scale);
    const response = await this.client.request(
      68,
      frameId,
      imageId,
      region[0],
      region[1],
      region[2],
      region[3],
      options.acceptable ?? 0.9,
      options.scaleMin ?? 1.0,
      options.scaleMax ?? 1.0,
      options.scaleStep ?? 1.0,
      options.pixelSkip ?? 0,
      'pixel',
      options.maxAgeMs ?? 1000,
    );
    if (!response.ok || response.parts.length < 7) {
      throw new Error(response.raw || 'findImageObjectInFrame failed');
    }
    const x = this.fromNativeCoord(Number(response.parts[0]), scale);
    const y = this.fromNativeCoord(Number(response.parts[1]), scale);
    const width = this.fromNativeLength(Number(response.parts[2]), scale);
    const height = this.fromNativeLength(Number(response.parts[3]), scale);
    return {
      found: x >= 0 && y >= 0 && width > 0 && height > 0,
      x,
      y,
      width,
      height,
      centerX: this.fromNativeCoord(Number(response.parts[4]), scale),
      centerY: this.fromNativeCoord(Number(response.parts[5]), scale),
      score: Number(response.parts[6]),
      native: {
        region,
        result: response.parts.slice(0, 11),
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

  private async waitForImageState(
    imagePath: string,
    options: WaitForImageOptions,
    wantPresent: boolean,
    kind: 'wait_for_image' | 'wait_until_gone',
  ): Promise<SmartWaitResult<FindImageResult | { gone: true; lastMatch: FindImageResult }>> {
    if (!imagePath) throw new Error(`${kind} requires image path`);
    const image = await this.openImage(imagePath);
    try {
      const result = await this.runWait<FindImageResult | { gone: true; lastMatch: FindImageResult }>(
        kind,
        async () => {
          const frame = await this.captureFrame({
            gray: true,
            bgra: false,
            ttlMs: Math.max(1000, boundedInteger(options.intervalMs, 200, 20, 10000) + 500),
          });
          try {
            const match = await this.findImageObjectInFrame(frame, image, options);
            if (wantPresent ? match.found : !match.found) {
              return wantPresent ? match : { gone: true as const, lastMatch: match };
            }
            return false;
          } finally {
            await this.releaseFrame(frame).catch(() => {});
          }
        },
        options,
        true,
      );
      return Object.assign(result, { locator: { type: 'image', path: imagePath } });
    } finally {
      await this.releaseImage(image).catch(() => {});
    }
  }

  private async runWait<T>(
    kind: string,
    predicate: (attempt: number) => T | false | null | undefined | Promise<T | false | null | undefined>,
    options: SmartWaitOptions,
    visual: boolean,
  ): Promise<SmartWaitResult<T>> {
    const timeoutMs = boundedInteger(options.timeoutMs, 5000, 0, 300000);
    const intervalMs = boundedInteger(options.intervalMs, 200, 20, 10000);
    const stableFrames = boundedInteger(options.stableFrames, 1, 1, 10);
    const ignoreErrors = options.ignoreErrors ?? visual;
    const startedAt = Date.now();
    let attempts = 0;
    let stableMatches = 0;
    let lastValue: T | false | null | undefined;
    let lastError = '';

    const finish = (ok: boolean, timedOut: boolean, cancelled: boolean, value?: T): SmartWaitResult<T> => ({
      schema: 'smart_wait_result_v1',
      kind,
      ok,
      found: ok,
      timedOut,
      cancelled,
      attempts,
      elapsedMs: Math.max(0, Date.now() - startedAt),
      stableMatches,
      value,
      lastError,
    });

    while (true) {
      if (options.signal?.aborted) return finish(false, false, true);
      attempts += 1;
      try {
        const value = await predicate(attempts);
        lastValue = value;
        if (value) {
          stableMatches += 1;
          if (stableMatches >= stableFrames) return finish(true, false, false, value);
        } else {
          stableMatches = 0;
        }
      } catch (error) {
        stableMatches = 0;
        lastError = smartWaitErrorText(error);
        if (options.signal?.aborted) return finish(false, false, true);
        if (!ignoreErrors) throw error;
      }

      const elapsedMs = Date.now() - startedAt;
      if (elapsedMs >= timeoutMs) break;
      try {
        await sleep(Math.min(intervalMs, timeoutMs - elapsedMs), options.signal);
      } catch (error) {
        if (options.signal?.aborted) return finish(false, false, true);
        throw error;
      }
    }

    const result = finish(false, true, false, lastValue || undefined);
    if (options.throwOnTimeout) {
      throw Object.assign(new Error(`${kind} timed out after ${result.elapsedMs}ms`), { result });
    }
    return result;
  }

  private async fullScreenRegion(): Promise<RegionTuple> {
    const size = await this.getScreenSize();
    if (!size) throw new Error('screen size unavailable');
    return [0, 0, size.width, size.height];
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

export type FailureEvidence = {
  schema: 'failure_evidence_v1';
  run_id: string;
  captured_at_ms: number;
  error: string;
  log_tail: string[];
  log_tail_truncated: boolean;
  console_log_path: string;
  screenshot_path: string;
  screenshot_captured: boolean;
  screenshot_error: string;
  metadata_path: string;
};

export type RunHistoryRecord = {
  schema: 'run_history_v1';
  run_id: string;
  runtime: 'rootfull' | 'trollstore' | string;
  bundle_path: string;
  entry_path: string;
  state: 'running' | 'finished' | 'failed' | 'cancelled' | 'license_revoked' | string;
  started_at_ms: number;
  ended_at_ms: number;
  duration_ms: number;
  error: string;
  play_settings: Record<string, number>;
  failure_evidence: FailureEvidence | Record<string, never>;
  record_path: string;
};

export type RunHistorySnapshot = {
  schema: 'run_history_v1';
  state: 'implemented';
  root_path: string;
  retention_max_runs: number;
  failure_log_tail_max_lines: number;
  failure_error_max_characters: number;
  status_log_tail_max_lines: number;
  status_log_line_max_characters: number;
  status_error_max_characters: number;
  failure_console_read_max_bytes: number;
  total_count: number;
  failed_count: number;
  runs: RunHistoryRecord[];
};

export type SmartWaitOptions = {
  timeoutMs?: number;
  intervalMs?: number;
  stableFrames?: number;
  ignoreErrors?: boolean;
  throwOnTimeout?: boolean;
  signal?: AbortSignal;
};

export type SmartWaitResult<T> = {
  schema: 'smart_wait_result_v1';
  kind: string;
  ok: boolean;
  found: boolean;
  timedOut: boolean;
  cancelled: boolean;
  attempts: number;
  elapsedMs: number;
  stableMatches: number;
  value?: T;
  lastError: string;
  locator?: { type: string; path?: string; text?: string; matchMode?: string; caseSensitive?: boolean };
};

export type SmartWaitColor = string | [number, number, number] | {
  red?: number;
  green?: number;
  blue?: number;
  r?: number;
  g?: number;
  b?: number;
};

export type WaitForImageOptions = FindImageOptions & SmartWaitOptions & {
  maxAgeMs?: number;
};

export type WaitForTextOptions = SmartWaitOptions & Omit<OcrOptions, 'region' | 'ttlMs'> & {
  region?: RegionTuple;
  matchMode?: 'contains' | 'equals' | 'regex';
  caseSensitive?: boolean;
};

export type TapWhenVisibleOptions = WaitForImageOptions & {
  offsetX?: number;
  offsetY?: number;
  holdMs?: number;
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

function finiteNumber(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function boundedInteger(value: unknown, fallback: number, minimum: number, maximum: number) {
  return Math.max(minimum, Math.min(maximum, Math.floor(finiteNumber(value, fallback))));
}

function normalizeSmartWaitColor(color: SmartWaitColor): { red: number; green: number; blue: number } {
  if (typeof color === 'string') return hexToRgb(color);
  if (Array.isArray(color)) {
    return { red: smartWaitColorChannel(color[0]), green: smartWaitColorChannel(color[1]), blue: smartWaitColorChannel(color[2]) };
  }
  if (color && typeof color === 'object') {
    return {
      red: smartWaitColorChannel(color.red ?? color.r),
      green: smartWaitColorChannel(color.green ?? color.g),
      blue: smartWaitColorChannel(color.blue ?? color.b),
    };
  }
  throw new Error('waitForColor requires #RRGGBB or RGB object');
}

function smartWaitColorChannel(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 255) {
    throw new Error('waitForColor channels must be between 0 and 255');
  }
  return Math.round(parsed);
}

function smartWaitTextMatches(actual: string, expected: string, options: WaitForTextOptions) {
  const mode = options.matchMode ?? 'contains';
  if (mode === 'regex') return new RegExp(expected, options.caseSensitive ? '' : 'i').test(actual);
  const left = options.caseSensitive ? actual : actual.toLocaleLowerCase();
  const right = options.caseSensitive ? expected : expected.toLocaleLowerCase();
  return mode === 'equals' ? left === right : left.includes(right);
}

function smartWaitErrorText(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error || 'unknown_error');
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
