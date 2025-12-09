export function humanizeBytes(bytes: number): string {
  if (bytes === 0) return '0B';
  const abs = Math.abs(bytes);
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx = 0;
  let val = abs;
  while (val >= 1024 && idx < units.length - 1) { val = val / 1024; idx++; }
  const sign = bytes < 0 ? '-' : '';
  const formatted = idx === 0 ? `${Math.round(val)}` : `${val.toFixed(2)}`;
  return `${sign}${formatted}${units[idx]}`;
}
