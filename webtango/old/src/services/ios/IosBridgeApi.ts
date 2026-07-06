import { deriveBridgeBases } from '../bridgeBase';
import type { UnifiedDevice } from '../deviceRegistry';

export type RtcIceConfig = {
  iceServers: RTCIceServer[];
  iceTransportPolicy?: RTCIceTransportPolicy;
};

export async function fetchUnifiedDevices(bridgeWsUrl: string): Promise<UnifiedDevice[]> {
  const { httpBase } = deriveBridgeBases(bridgeWsUrl);
  const resp = await fetch(`${httpBase}/devices`, { cache: 'no-store' });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return (await resp.json()) as UnifiedDevice[];
}

export async function fetchRtcIceConfig(bridgeWsUrl: string, forceRelay = false): Promise<RtcIceConfig> {
  const { httpBase } = deriveBridgeBases(bridgeWsUrl);
  try {
    const url = `${httpBase}/rtc/config${forceRelay ? '?forceRelay=1' : ''}`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const cfg = await resp.json();
    const iceServers = Array.isArray(cfg.iceServers) ? cfg.iceServers : [];
    const policy = cfg.iceTransportPolicy === 'relay' ? 'relay' : 'all';
    return { iceServers, iceTransportPolicy: policy };
  } catch (e) {
    console.warn('[ios-bridge-api] rtc/config unavailable, using defaults', e);
    return { iceServers: [], iceTransportPolicy: forceRelay ? 'relay' : 'all' };
  }
}

export function buildIosStreamUrls(bridgeWsUrl: string, deviceId: string) {
  const { httpBase, wsBase } = deriveBridgeBases(bridgeWsUrl);
  const encoded = encodeURIComponent(deviceId);
  return {
    httpBase,
    wsBase,
    h264: `${wsBase}/ios/${encoded}/h264`,
    h264Worker: `${wsBase}/ios/${encoded}/h264-worker`,
    stream: `${wsBase}/ios/${encoded}/stream`,
    streamEco: `${wsBase}/ios/${encoded}/stream-eco`,
    tlinkauto: `${wsBase}/ios/${encoded}/tlinkauto`,
    rtcOffer: `${httpBase}/ios/${encoded}/rtc/offer`,
    rtcClose: `${httpBase}/ios/${encoded}/rtc/close`,
  };
}
