import { useState, useEffect } from 'react';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';

type Props = {
  serial: string;
};

export function Resources({ serial }: Props) {
  const [battery, setBattery] = useState<number>(0);
  const [storagePerc, setStoragePerc] = useState<number>(0);
  const [storageText, setStorageText] = useState<string>('-- GB');

  useEffect(() => {
    let active = true;
    const adb = getAdbConnection(serial);
    if (!adb) return;

    const fetchRes = async () => {
      try {
        const [batOut, dfOut] = await Promise.all([
          adb.createSocket('shell:dumpsys battery').then(async s => {
            const chunks = [];
            for await (const c of s.readable) chunks.push(c);
            return new TextDecoder().decode(Buffer.concat(chunks));
          }).catch(() => ''),
          adb.createSocket('shell:df /data').then(async s => {
            const chunks = [];
            for await (const c of s.readable) chunks.push(c);
            return new TextDecoder().decode(Buffer.concat(chunks));
          }).catch(() => '')
        ]);

        if (!active) return;

        if (batOut) {
          const match = batOut.match(/level:\s*(\d+)/);
          if (match && match[1]) {
            setBattery(parseInt(match[1], 10));
          }
        }

        if (dfOut) {
          const lines = dfOut.split('\n');
          if (lines.length > 1) {
            const parts = lines[1].trim().split(/\s+/);
            if (parts.length >= 5) {
              const totalK = parseInt(parts[1], 10);
              const usedK = parseInt(parts[2], 10);
              if (totalK > 0) {
                const perc = Math.round((usedK / totalK) * 100);
                setStoragePerc(perc);
                const totalG = (totalK / 1024 / 1024).toFixed(1);
                const usedG = (usedK / 1024 / 1024).toFixed(1);
                setStorageText(`${usedG} / ${totalG} GB`);
              }
            }
          }
        }

      } catch (e) {
        console.warn(`[Resources] Failed to fetch resources for ${serial}`, e);
      }
    };
    fetchRes();

    // Optionally set up a polling interval
    const interval = setInterval(fetchRes, 10000);
    return () => { active = false; clearInterval(interval); };
  }, [serial]);

  return (
    <div className="collapsible-section open">
      <div className="collapsible-header">
        <span>Resources</span>
        <span className="collapse-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-chevron-down"><path d="m6 9 6 6 6-6"/></svg>
        </span>
      </div>
      <div className="collapsible-content space-y-4">
        <div className="resource-row">
          <div className="resource-info">
            <span className="res-label">
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-battery"><rect width="16" height="10" x="2" y="7" rx="2" ry="2"/><line x1="22" x2="22" y1="11" y2="13"/></svg>
              Battery Level
            </span>
            <span className="res-value">{battery}%</span>
          </div>
          <div className="progress-bar-wrapper">
            <div className="progress-bar-bg">
              <div className={`progress-bar-fill ${battery > 20 ? 'progress-bar-fill-success' : 'progress-bar-fill-warning'}`} style={{ width: `${battery}%` }}></div>
            </div>
          </div>
        </div>

        <div className="resource-row">
          <div className="resource-info">
            <span className="res-label">
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-hard-drive"><rect width="20" height="8" x="2" y="14" rx="2"/><path d="M2 14v-4a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v4"/><line x1="6" x2="6" y1="18" y2="18"/><line x1="10" x2="10" y1="18" y2="18"/></svg>
              Storage Space
            </span>
            <span className="res-value">{storageText}</span>
          </div>
          <div className="progress-bar-wrapper">
            <div className="progress-bar-bg">
              <div className="progress-bar-fill" style={{ width: `${storagePerc}%` }}></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
