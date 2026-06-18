export function fmtCredits(n: number): string {
  return Math.round(n).toLocaleString('en-US');
}

export function fmtDay(day: number): { year: number; dayOfYear: number } {
  const year = Math.floor(day / 360);
  const dayOfYear = Math.floor(day % 360);
  return { year, dayOfYear };
}

export function pct(n: number): string {
  return `${Math.round(n)}%`;
}
