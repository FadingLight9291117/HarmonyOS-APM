export function humanizeDuration(ms: number | undefined): string {
  if (ms == null) return '0ms';
  if (ms < 1000) return `${ms}ms`;
  const seconds = ms / 1000;
  if (seconds < 60) return `${seconds.toFixed(2)}s`;
  const minutes = Math.floor(seconds / 60);
  const remSec = seconds - minutes * 60;
  return `${minutes}m ${remSec.toFixed(2)}s`;
}
