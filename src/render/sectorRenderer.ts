import type { GameState, Asteroid, Fleet } from '../sim/types';
import { FIELD_SIZE } from '../sim/asteroidField';

export interface Camera { x: number; y: number; zoom: number }

export function createCamera(): Camera {
  return { x: FIELD_SIZE / 2, y: FIELD_SIZE / 2, zoom: 0.5 };
}

function worldToScreen(cam: Camera, canvas: HTMLCanvasElement, x: number, y: number) {
  return {
    x: (x - cam.x) * cam.zoom + canvas.width / 2,
    y: (y - cam.y) * cam.zoom + canvas.height / 2,
  };
}

export function screenToWorld(cam: Camera, canvas: HTMLCanvasElement, sx: number, sy: number) {
  return {
    x: (sx - canvas.width / 2) / cam.zoom + cam.x,
    y: (sy - canvas.height / 2) / cam.zoom + cam.y,
  };
}

function ownerColor(owner: string): string {
  if (owner === 'player') return '#4fd1ff';
  return '#ff6b6b';
}

export function render(
  ctx: CanvasRenderingContext2D, canvas: HTMLCanvasElement, state: GameState, cam: Camera,
) {
  ctx.fillStyle = '#030407';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // starfield
  ctx.fillStyle = '#1a2236';
  for (let i = 0; i < 120; i++) {
    const sx = (i * 137.5) % canvas.width;
    const sy = (i * 91.3 + i * 13) % canvas.height;
    ctx.fillRect(sx, sy, 1, 1);
  }

  for (const a of Object.values(state.asteroids)) drawAsteroid(ctx, canvas, cam, state, a);
  for (const f of Object.values(state.fleets)) drawFleet(ctx, canvas, cam, state, f);
}

function drawAsteroid(
  ctx: CanvasRenderingContext2D, canvas: HTMLCanvasElement, cam: Camera, state: GameState, a: Asteroid,
) {
  const p = worldToScreen(cam, canvas, a.x, a.y);
  if (p.x < -100 || p.x > canvas.width + 100 || p.y < -100 || p.y > canvas.height + 100) return;

  const colony = a.colonyId ? state.colonies[a.colonyId] : null;
  const isSelected = state.selectedAsteroidId === a.id;

  ctx.beginPath();
  a.shape.forEach((pt, i) => {
    const x = p.x + pt.x * cam.zoom;
    const y = p.y + pt.y * cam.zoom;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.closePath();
  ctx.fillStyle = colony ? (colony.owner === 'player' ? 'rgba(79,209,255,.18)' : 'rgba(255,107,107,.18)') : '#3a3326';
  ctx.fill();
  ctx.strokeStyle = isSelected ? '#fff' : colony ? ownerColor(colony.owner) : '#5a5040';
  ctx.lineWidth = isSelected ? 2.5 : 1.2;
  ctx.stroke();

  if (cam.zoom > 0.25) {
    ctx.fillStyle = '#aab4c8';
    ctx.font = '11px sans-serif';
    ctx.fillText(a.isHome ? a.name : `#${a.layoutIndex}`, p.x + a.radius * cam.zoom + 4, p.y);
  }
}

function drawFleet(
  ctx: CanvasRenderingContext2D, canvas: HTMLCanvasElement, cam: Camera, state: GameState, f: Fleet,
) {
  if (f.shipIds.length === 0) return;
  const p = worldToScreen(cam, canvas, f.x, f.y);
  if (p.x < -50 || p.x > canvas.width + 50 || p.y < -50 || p.y > canvas.height + 50) return;
  const isSelected = state.selectedFleetId === f.id;

  ctx.save();
  ctx.translate(p.x, p.y);
  ctx.fillStyle = ownerColor(f.owner);
  ctx.beginPath();
  ctx.moveTo(0, -7);
  ctx.lineTo(6, 6);
  ctx.lineTo(-6, 6);
  ctx.closePath();
  ctx.fill();
  if (isSelected) {
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }
  ctx.restore();

  ctx.fillStyle = '#cdd6e8';
  ctx.font = '10px sans-serif';
  ctx.fillText(`${f.shipIds.length}`, p.x + 8, p.y + 3);
}

export function pickAsteroidAt(state: GameState, cam: Camera, canvas: HTMLCanvasElement, sx: number, sy: number): string | null {
  const w = screenToWorld(cam, canvas, sx, sy);
  let best: { id: string; d: number } | null = null;
  for (const a of Object.values(state.asteroids)) {
    const d = Math.hypot(a.x - w.x, a.y - w.y);
    if (d <= a.radius + 10 && (!best || d < best.d)) best = { id: a.id, d };
  }
  return best?.id ?? null;
}

export function pickFleetAt(state: GameState, cam: Camera, canvas: HTMLCanvasElement, sx: number, sy: number): string | null {
  const w = screenToWorld(cam, canvas, sx, sy);
  let best: { id: string; d: number } | null = null;
  for (const f of Object.values(state.fleets)) {
    if (f.shipIds.length === 0) continue;
    const d = Math.hypot(f.x - w.x, f.y - w.y);
    if (d <= 14 / cam.zoom && (!best || d < best.d)) best = { id: f.id, d };
  }
  return best?.id ?? null;
}
