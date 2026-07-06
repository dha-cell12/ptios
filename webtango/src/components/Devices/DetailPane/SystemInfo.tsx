import { useState, useEffect } from 'react';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';

type Props = {
  serial: string;
};

export function SystemInfo({ serial }: Props) {
  const [ip, setIp] = useState<string>('-');
  const [arch, setArch] = useState<string>('arm64');
  const [osVersion, setOsVersion] = useState<string>('Android OS');
  const [model, setModel] = useState<string>('Device');

  useEffect(() => {
    let active = true;
    const adb = getAdbConnection(serial);
    if (!adb) return;

    const fetchInfo = async () => {
      try {
        const [ipOut, archOut, versionOut, modelOut] = await Promise.all([
          adb.createSocket('shell:ip route get 8.8.8.8').then(async s => {
            const chunks = [];
            for await (const c of s.readable) chunks.push(c);
            return new TextDecoder().decode(Buffer.concat(chunks));
          }).catch(() => ''),
          adb.getProp('ro.product.cpu.abi').catch(() => 'arm64'),
          adb.getProp('ro.build.version.release').catch(() => 'Android OS'),
          adb.getProp('ro.product.model').catch(() => 'Device'),
        ]);

        if (!active) return;

        if (ipOut) {
          const match = ipOut.match(/src\s+([0-9\.]+)/);
          if (match && match[1]) {
            setIp(match[1]);
          }
        }
        setArch(archOut);
        setOsVersion(`Android ${versionOut}`);
        setModel(modelOut);

      } catch (e) {
        console.warn(`[SystemInfo] Failed to fetch info for ${serial}`, e);
      }
    };
    fetchInfo();

    return () => { active = false; };
  }, [serial]);

  return (
    <div className="collapsible-section open">
      <div className="collapsible-header">
        <span>System Info</span>
        <span className="collapse-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-chevron-down"><path d="m6 9 6 6 6-6"/></svg>
        </span>
      </div>
      <div className="collapsible-content">
        <div className="info-list-grid">
          <div className="info-item">
            <div className="info-label-group">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-usb"><circle cx="12" cy="6" r="1"/><path d="M12 2v20"/><path d="M12 12c-2.071 0-3.75-1.679-3.75-3.75V6.5h1.5"/><path d="M12 14c2.071 0 3.75 1.679 3.75 3.75V19h-1.5"/></svg>
              <span className="info-label">Connection</span>
            </div>
            <span className="info-value">USB</span>
          </div>
          <div className="info-item">
            <div className="info-label-group">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-cpu"><rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="M9 1v3"/><path d="M15 1v3"/><path d="M9 20v3"/><path d="M15 20v3"/><path d="M20 9h3"/><path d="M20 15h3"/><path d="M1 9h3"/><path d="M1 15h3"/></svg>
              <span className="info-label">Arch</span>
            </div>
            <span className="info-value font-mono">{arch}</span>
          </div>
          <div className="info-item">
            <div className="info-label-group">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-wifi"><path d="M12 20h.01"/><path d="M8.5 16.5a5 5 0 0 1 7 0"/><path d="M5 13a10 10 0 0 1 14 0"/><path d="M1.5 9.5a15 15 0 0 1 21 0"/></svg>
              <span className="info-label">IP Address</span>
            </div>
            <span className="info-value font-mono">{ip}</span>
          </div>
          <div className="info-item">
            <div className="info-label-group">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-settings"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.1a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>
              <span className="info-label">OS Version</span>
            </div>
            <span className="info-value">{osVersion}</span>
          </div>
          <div className="info-item full-width-info pt-2 border-t">
            <div className="info-label-group">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-refresh-cw"><path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/><path d="M16 16h5v5"/></svg>
              <span className="info-label">Serial Number</span>
            </div>
            <span className="info-value font-mono truncate">{serial}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
