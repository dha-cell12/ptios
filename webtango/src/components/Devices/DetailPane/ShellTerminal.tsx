import { useEffect, useRef, useState } from 'react';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';

type Props = {
  serial: string;
};

export function ShellTerminal({ serial }: Props) {
  const terminalRef = useRef<HTMLDivElement>(null);
  const [TerminalClass, setTerminalClass] = useState<any>(null);
  const [FitAddonClass, setFitAddonClass] = useState<any>(null);
  const xtermInstance = useRef<any>(null);
  const shellSocket = useRef<any>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    // Lazy load xterm
    let active = true;
    Promise.all([
      import('xterm').then(m => m.Terminal),
      import('xterm-addon-fit').then(m => m.FitAddon)
    ]).then(([Term, FitAddon]) => {
      if (!active) return;
      import('xterm/css/xterm.css'); // Import styles
      setTerminalClass(() => Term);
      setFitAddonClass(() => FitAddon);
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!TerminalClass || !FitAddonClass || !terminalRef.current) return;

    const term = new TerminalClass({
      cursorBlink: true,
      fontFamily: '"JetBrains Mono", monospace',
      fontSize: 13,
      theme: {
        background: '#1e293b',
        foreground: '#f8fafc',
      }
    });
    const fitAddon = new FitAddonClass();
    term.loadAddon(fitAddon);

    term.open(terminalRef.current);
    fitAddon.fit();
    xtermInstance.current = term;

    const resizeObserver = new ResizeObserver(() => fitAddon.fit());
    resizeObserver.observe(terminalRef.current);

    const initShell = async () => {
      const adb = getAdbConnection(serial);
      if (!adb) {
        term.writeln('\r\n\x1b[31m[Error] Device not connected\x1b[0m');
        return;
      }
      try {
        const shell = await adb.subprocess.shell();
        shellSocket.current = shell;
        setIsReady(true);

        const writer = shell.stdin.getWriter();
        term.onData((data: string) => {
          writer.write(data);
        });

        // Read output
        for await (const data of shell.stdout) {
          term.write(new Uint8Array(data));
        }

      } catch (e) {
        term.writeln(`\r\n\x1b[31m[Error] ${e}\x1b[0m`);
      }
    };

    initShell();

    return () => {
      resizeObserver.disconnect();
      shellSocket.current?.kill?.();
      term.dispose();
      setIsReady(false);
    };
  }, [TerminalClass, FitAddonClass, serial]);

  return (
    <div className="shell-terminal-wrapper" style={{ display: 'block' }}>
      <div className="shell-header">
        <span>ADB Shell</span>
        {!isReady && <span style={{ marginLeft: 8, fontSize: 11, color: '#94a3b8' }}>Connecting...</span>}
      </div>
      <div 
        ref={terminalRef} 
        style={{ width: '100%', height: '250px', backgroundColor: '#1e293b', padding: '8px' }} 
      />
    </div>
  );
}
