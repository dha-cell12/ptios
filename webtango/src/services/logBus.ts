export type LogLevel = 'info' | 'warn' | 'error' | 'debug';

export type IdeLog = {
  id: number;
  time: number;
  level: LogLevel;
  source: string;
  message: string;
};

export function formatLogTime(time: number): string {
  return new Date(time).toLocaleTimeString();
}
