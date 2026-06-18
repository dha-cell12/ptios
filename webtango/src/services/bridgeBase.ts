export type BridgeBases = {
  httpBase: string;
  wsBase: string;
};

export function deriveBridgeBases(bridgeWsUrl: string): BridgeBases {
  const u = new URL(bridgeWsUrl);
  const httpProto = u.protocol === 'wss:' || u.protocol === 'https:' ? 'https:' : 'http:';
  const wsProto = u.protocol === 'wss:' || u.protocol === 'https:' ? 'wss:' : 'ws:';

  let basePath = u.pathname;
  basePath = basePath.replace(/\/bridge\/?$/, '');
  if (basePath.endsWith('/')) basePath = basePath.slice(0, -1);

  return {
    httpBase: `${httpProto}//${u.host}${basePath}`,
    wsBase: `${wsProto}//${u.host}${basePath}`,
  };
}

export function getBridgeEndpointValue(): string {
  const input = document.getElementById('endpoint') as HTMLInputElement | null;
  return input?.value?.trim() || 'ws://localhost:15037/bridge/';
}

export function getBridgeBasesFromPage(): BridgeBases {
  return deriveBridgeBases(getBridgeEndpointValue());
}
