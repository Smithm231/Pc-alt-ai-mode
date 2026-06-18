import './style.css';
import { Rng } from './sim/rng';
import { initGame, tick } from './sim/world';
import { createCamera, render, pickAsteroidAt, pickFleetAt } from './render/sectorRenderer';
import { renderSidePanel, type FleetOrderMode, type PanelCtx } from './ui/sidePanel';
import { fmtCredits, fmtDay } from './ui/format';
import {
  queueBuilding, queueShip, setSiloMissileType, fireMissiles, deployTransporterColony,
  setFleetOrderAction, setRetreatThreshold, setBudgetAllocation,
} from './sim/actions';

const app = document.getElementById('app')!;
app.innerHTML = `
  <div id="hud">
    <span class="stat">K240</span>
    <span class="stat">Credits: <b id="hudCredits"></b></span>
    <span class="stat">Day <b id="hudDay"></b>, Year <b id="hudYear"></b></span>
    <button id="pauseBtn"></button>
    <button id="speed1">1x</button>
    <button id="speed2">2x</button>
    <button id="speed4">4x</button>
    <span class="stat" id="hudHint" style="margin-left:auto;color:var(--dim)">Click an asteroid or fleet to inspect it. Scroll to zoom, drag to pan.</span>
  </div>
  <div id="main">
    <canvas id="sectorCanvas"></canvas>
    <div id="sidePanel"></div>
  </div>
  <div id="gameOverBanner" class="hidden"></div>
`;

const canvas = document.getElementById('sectorCanvas') as HTMLCanvasElement;
const ctx2d = canvas.getContext('2d')!;
const sidePanelEl = document.getElementById('sidePanel')!;
const gameOverEl = document.getElementById('gameOverBanner')!;

function resize() {
  canvas.width = canvas.clientWidth;
  canvas.height = canvas.clientHeight;
}
window.addEventListener('resize', resize);

const seed = Date.now() & 0xffffffff;
const rng = new Rng(seed);
const state = initGame(seed);
const cam = createCamera();

let panelMode: 'select' | 'budget' = 'select';
let pendingOrderMode: FleetOrderMode = null;

let dragging = false;
let dragStart = { x: 0, y: 0 };
let camStart = { x: 0, y: 0 };

canvas.addEventListener('mousedown', (e) => {
  dragging = true;
  dragStart = { x: e.clientX, y: e.clientY };
  camStart = { x: cam.x, y: cam.y };
});
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => {
  if (!dragging) return;
  cam.x = camStart.x - (e.clientX - dragStart.x) / cam.zoom;
  cam.y = camStart.y - (e.clientY - dragStart.y) / cam.zoom;
});
canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  cam.zoom = Math.max(0.08, Math.min(2.5, cam.zoom * (e.deltaY < 0 ? 1.1 : 0.9)));
}, { passive: false });

canvas.addEventListener('click', (e) => {
  const rect = canvas.getBoundingClientRect();
  const sx = e.clientX - rect.left, sy = e.clientY - rect.top;

  if (pendingOrderMode && state.selectedFleetId) {
    const targetId = pickAsteroidAt(state, cam, canvas, sx, sy);
    if (targetId) {
      setFleetOrderAction(state, state.selectedFleetId, pendingOrderMode, targetId);
      pendingOrderMode = null;
      refreshPanel();
      return;
    }
  }

  const fleetId = pickFleetAt(state, cam, canvas, sx, sy);
  if (fleetId) {
    state.selectedFleetId = fleetId;
    state.selectedAsteroidId = null;
    panelMode = 'select';
    refreshPanel();
    return;
  }
  const asteroidId = pickAsteroidAt(state, cam, canvas, sx, sy);
  if (asteroidId) {
    state.selectedAsteroidId = asteroidId;
    state.selectedFleetId = null;
    panelMode = 'select';
    refreshPanel();
  }
});

const panelCtx: PanelCtx = {
  onBuild: (colonyId, buildingId) => { queueBuilding(state, colonyId, buildingId); refreshPanel(); },
  onBuildShip: (colonyId, shipClassId) => { queueShip(state, colonyId, shipClassId); refreshPanel(); },
  onSetSiloType: (colonyId, siloUid, type) => { setSiloMissileType(state, colonyId, siloUid, type); refreshPanel(); },
  onFireMissiles: (colonyId, type, count, targetColonyId) => { fireMissiles(state, colonyId, type, count, targetColonyId); refreshPanel(); },
  onFoundColony: (fleetId, colonists) => { deployTransporterColony(state, fleetId, colonists); refreshPanel(); },
  onArmOrder: (mode) => { pendingOrderMode = pendingOrderMode === mode ? null : mode; refreshPanel(); },
  onSetRetreat: (fleetId, p) => { setRetreatThreshold(state, fleetId, p); refreshPanel(); },
  onSetBudget: (alloc) => { setBudgetAllocation(state, alloc); refreshPanel(); },
  onTogglePanelMode: () => { panelMode = panelMode === 'select' ? 'budget' : 'select'; refreshPanel(); },
  get pendingOrderMode() { return pendingOrderMode; },
  get panelMode() { return panelMode; },
};

function refreshPanel() {
  renderSidePanel(sidePanelEl, state, panelCtx);
}

function refreshHud() {
  document.getElementById('hudCredits')!.textContent = fmtCredits(state.credits);
  const { year, dayOfYear } = fmtDay(state.day);
  document.getElementById('hudDay')!.textContent = String(dayOfYear);
  document.getElementById('hudYear')!.textContent = String(year);
  document.getElementById('pauseBtn')!.textContent = state.paused ? 'Resume' : 'Pause';
  for (const n of [1, 2, 4]) {
    document.getElementById(`speed${n}`)!.classList.toggle('active', state.speed === n);
  }
  if (state.gameOver) {
    gameOverEl.classList.remove('hidden');
    gameOverEl.textContent = state.gameOver === 'won' ? 'VICTORY — SECTOR K240 SECURED' : 'DEFEAT — COLONY LOST';
  }
}

document.getElementById('pauseBtn')!.addEventListener('click', () => { state.paused = !state.paused; });
document.getElementById('speed1')!.addEventListener('click', () => { state.speed = 1; });
document.getElementById('speed2')!.addEventListener('click', () => { state.speed = 2; });
document.getElementById('speed4')!.addEventListener('click', () => { state.speed = 4; });

resize();
refreshPanel();

const TICK_INTERVAL_MS = 250;
let acc = 0;
let last = performance.now();

function frame(now: number) {
  const dt = now - last;
  last = now;
  acc += dt;
  const interval = TICK_INTERVAL_MS / Math.max(1, state.speed);
  let ticked = false;
  while (acc >= interval) {
    acc -= interval;
    tick(state, rng);
    ticked = true;
  }
  render(ctx2d, canvas, state, cam);
  refreshHud();
  if (ticked) refreshPanel();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
