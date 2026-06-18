import type { GameState, PafwState } from '../sim/types';
import { BUILDINGS, type BuildingDef } from '../data/buildings';
import { SHIP_CLASSES, type ShipClassId } from '../data/ships';
import { MISSILE_TYPES, type MissileTypeId } from '../data/missiles';
import { ORES, type OreId } from '../data/ores';
import { defOf, storageCapacity, requiredCentres, countMedicalCentres, countSecurityCentres } from '../sim/colony';
import { fmtCredits, pct } from './format';

export type FleetOrderMode = 'move' | 'attackAsteroid' | 'intercept' | 'sentry' | null;

export interface PanelCtx {
  onBuild(colonyId: string, buildingId: string): void;
  onBuildShip(colonyId: string, shipClassId: ShipClassId): void;
  onSetSiloType(colonyId: string, siloUid: string, type: MissileTypeId): void;
  onFireMissiles(colonyId: string, type: MissileTypeId, count: number, targetColonyId: string): void;
  onFoundColony(fleetId: string, colonists: number): void;
  onArmOrder(mode: FleetOrderMode): void;
  onSetRetreat(fleetId: string, pct: number): void;
  onSetBudget(alloc: GameState['budgetAllocation']): void;
  onTogglePanelMode(): void;
  pendingOrderMode: FleetOrderMode;
  panelMode: 'select' | 'budget';
}

function pafwPill(state: PafwState): string {
  return `<span class="pill ${state}">${state}</span>`;
}

function hpBar(hp: number, maxHp: number): string {
  const p = maxHp > 0 ? (hp / maxHp) * 100 : 0;
  return `<div class="barWrap"><div class="bar hp${p < 35 ? ' low' : ''}" style="width:${p}%"></div></div>`;
}

function buildingRows(colony: GameState['colonies'][string]): string {
  const counts = new Map<string, { count: number; hp: number; maxHp: number }>();
  for (const b of colony.buildings) {
    const e = counts.get(b.defId) ?? { count: 0, hp: 0, maxHp: 0 };
    e.count++; e.hp += b.hp; e.maxHp += b.maxHp;
    counts.set(b.defId, e);
  }
  let rows = '';
  for (const [defId, e] of counts) {
    const name = BUILDINGS[defId]?.name ?? defId;
    rows += `<div class="bldRow"><span class="name">${name} x${e.count}</span>${hpBar(e.hp, e.maxHp)}</div>`;
  }
  for (const order of colony.constructionQueue) {
    rows += `<div class="bldRow"><span class="meta">building ${BUILDINGS[order.buildingDefId].name}… ${order.daysRemaining}d</span></div>`;
  }
  return rows || '<div class="meta">No buildings yet.</div>';
}

function buildMenu(state: GameState, colonyId: string): string {
  const colony = state.colonies[colonyId];
  let html = '<div class="buildList">';
  for (const def of Object.values(BUILDINGS) as BuildingDef[]) {
    const countOfType = colony.buildings.filter((b) => b.defId === def.id).length
      + colony.constructionQueue.filter((o) => o.buildingDefId === def.id).length;
    const maxed = def.maxPerColony ? countOfType >= def.maxPerColony : false;
    const missingReq = def.requires ? !colony.buildings.some((b) => b.defId === def.requires) : false;
    const oreStr = Object.entries(def.costOre ?? {}).map(([o, n]) => `${n} ${ORES[o as OreId].name}`).join(', ');
    html += `<button data-build="${def.id}" ${maxed || missingReq ? 'disabled' : ''} title="${missingReq ? 'requires ' + BUILDINGS[def.requires!].name : ''}">
      ${def.name}<small>${fmtCredits(def.costCredits)} CR${oreStr ? ' + ' + oreStr : ''}</small>
    </button>`;
  }
  html += '</div>';
  return html;
}

function shipMenu(state: GameState, colonyId: string): string {
  const colony = state.colonies[colonyId];
  const yards = new Set(colony.buildings.filter((b) => BUILDINGS[b.defId].category.startsWith('shipyard') && b.powered).map((b) => BUILDINGS[b.defId].category));
  let html = '<div class="shipList">';
  for (const def of Object.values(SHIP_CLASSES)) {
    const available = yards.has(def.yard);
    html += `<button data-ship="${def.id}" ${available ? '' : 'disabled'} title="${available ? '' : 'requires yard'}">
      ${def.name} (${def.hardpoints}hp/${def.armor}armor)<small>${fmtCredits(def.costCredits)} CR</small>
    </button>`;
  }
  html += '</div>';
  if (colony.shipBuildQueue.length) {
    html += '<div class="meta">';
    for (const o of colony.shipBuildQueue) html += `<div class="bldRow"><span class="meta">${SHIP_CLASSES[o.shipClassId as ShipClassId].name}… ${o.daysRemaining}d</span></div>`;
    html += '</div>';
  }
  return html;
}

function missilePanel(state: GameState, colonyId: string): string {
  const colony = state.colonies[colonyId];
  const silos = colony.buildings.filter((b) => defOf(b).category === 'missileSilo');
  if (silos.length === 0) return '<div class="meta">No missile silos.</div>';
  let html = '';
  for (const silo of silos) {
    html += `<div class="row"><span>Silo ${silo.uid.slice(-4)}</span>
      <select data-silo="${silo.uid}">
        ${Object.values(MISSILE_TYPES).map((m) => `<option value="${m.id}" ${silo.selectedMissileType === m.id ? 'selected' : ''}>${m.name}</option>`).join('')}
      </select></div>`;
  }
  html += '<h3>Stockpile</h3>';
  for (const [type, n] of Object.entries(colony.missileStock)) {
    if (!n) continue;
    html += `<div class="row"><span>${MISSILE_TYPES[type as MissileTypeId].name}</span><span>${n}</span></div>`;
  }
  const enemyColonies = Object.values(state.colonies).filter((c) => c.owner !== colony.owner && c.founded);
  if (enemyColonies.length > 0) {
    html += `<div class="row">
      <select id="missileTargetSelect">${enemyColonies.map((c) => `<option value="${c.id}">${state.asteroids[c.asteroidId]?.name ?? c.id}</option>`).join('')}</select>
      <select id="missileFireType">${Object.values(MISSILE_TYPES).map((m) => `<option value="${m.id}">${m.name}</option>`).join('')}</select>
      <input id="missileFireCount" type="number" min="1" value="1" style="width:40px" />
      <button id="missileFireBtn">Fire</button>
    </div>`;
  }
  return html;
}

function asteroidSection(state: GameState, _ctx: PanelCtx): string {
  const asteroid = state.selectedAsteroidId ? state.asteroids[state.selectedAsteroidId] : null;
  if (!asteroid) return '';
  const colony = asteroid.colonyId ? state.colonies[asteroid.colonyId] : null;
  let html = `<h2>${asteroid.name}</h2>`;
  html += '<h3>Ore Deposits</h3>';
  for (const [id, amt] of Object.entries(asteroid.ore)) {
    html += `<div class="row"><span>${ORES[id as OreId].name}</span><span>${amt} <small>(${fmtCredits(state.orePrices[id as OreId] ?? 0)} CR/u)</small></span></div>`;
  }

  if (!colony) {
    const playerFleetHere = Object.values(state.fleets).find(
      (f) => f.owner === 'player' && f.currentAsteroidId === asteroid.id
        && f.shipIds.some((sid) => state.ships[sid]?.classId === 'transporter'),
    );
    if (playerFleetHere) {
      html += `<h3>Unclaimed</h3><div class="row">
        <input id="colonistCount" type="number" min="1" max="200" value="50" style="width:60px" />
        <button id="foundColonyBtn" data-fleet="${playerFleetHere.id}">Found Colony</button>
      </div>`;
    } else {
      html += '<div class="meta">Unclaimed. Send a Transporter here.</div>';
    }
    return html;
  }

  if (colony.owner !== 'player') {
    html += `<h3>${colony.owner}</h3><div class="meta">Population ~${colony.population} (estimate). Send a Scout for full intel.</div>`;
    return html;
  }

  html += '<h3>Colony Status</h3>';
  html += `<div class="row"><span>Population</span><span>${colony.population}</span></div>`;
  html += `<div class="row"><span>Power</span>${pafwPill(colony.powerState)}</div>`;
  html += `<div class="row"><span>Air</span>${pafwPill(colony.airState)}</div>`;
  html += `<div class="row"><span>Food</span>${pafwPill(colony.foodState)}</div>`;
  html += `<div class="row"><span>Water</span>${pafwPill(colony.waterState)}</div>`;
  html += `<div class="row"><span>Radiation</span><span>${pct(colony.radiationPercent)}</span></div>`;
  html += `<div class="row"><span>Unrest</span><span>${Math.round(colony.unrest)}</span></div>`;
  html += `<div class="row"><span>Security ${countSecurityCentres(colony)}/${requiredCentres(colony.population)}</span></div>`;
  html += `<div class="row"><span>Medical ${countMedicalCentres(colony)}/${requiredCentres(colony.population)}</span></div>`;
  if (colony.virusOutbreak) html += '<div class="row"><span style="color:var(--bad)">Virus outbreak!</span></div>';

  html += '<h3>Storage</h3>';
  const cap = storageCapacity(colony);
  const used = Object.values(colony.oreStock).reduce((s, v) => s + (v ?? 0), 0);
  html += `<div class="row"><span>Ore (${used}/${cap})</span></div>`;
  for (const [id, amt] of Object.entries(colony.oreStock)) {
    if (!amt) continue;
    html += `<div class="row"><span>${ORES[id as OreId].name}</span><span>${amt}</span></div>`;
  }

  html += '<h3>Buildings</h3>' + buildingRows(colony);
  html += '<h3>Build</h3>' + buildMenu(state, colony.id);
  html += '<h3>Shipyard</h3>' + shipMenu(state, colony.id);
  html += '<h3>Missiles</h3>' + missilePanel(state, colony.id);
  return html;
}

function fleetSection(state: GameState, ctx: PanelCtx): string {
  const fleet = state.selectedFleetId ? state.fleets[state.selectedFleetId] : null;
  if (!fleet) return '';
  let html = `<h2>Fleet (${fleet.shipIds.length} ships)</h2>`;
  html += `<div class="meta">Owner: ${fleet.owner} · Order: ${fleet.order}${fleet.targetAsteroidId ? ' → ' + (state.asteroids[fleet.targetAsteroidId]?.name ?? '?') : ''}</div>`;
  for (const sid of fleet.shipIds) {
    const s = state.ships[sid];
    if (!s) continue;
    html += `<div class="bldRow"><span class="name">${s.classId}</span>${hpBar(s.hp, s.maxHp)}</div>`;
  }
  if (fleet.owner === 'player') {
    html += `<h3>Orders</h3><div class="tabs">
      <button data-order="move" class="${ctx.pendingOrderMode === 'move' ? 'active' : ''}">Move</button>
      <button data-order="attackAsteroid" class="${ctx.pendingOrderMode === 'attackAsteroid' ? 'active' : ''}">Attack</button>
      <button data-order="intercept" class="${ctx.pendingOrderMode === 'intercept' ? 'active' : ''}">Intercept</button>
    </div>
    <div class="meta">${ctx.pendingOrderMode ? 'Click an asteroid to ' + ctx.pendingOrderMode : 'Pick an order, then click an asteroid.'}</div>
    <button data-order="sentry" style="width:100%;margin-top:4px;">Sentry Here</button>
    <h3>Retreat threshold: ${fleet.retreatThresholdPct}%</h3>
    <input type="range" min="0" max="100" value="${fleet.retreatThresholdPct}" id="retreatSlider" style="width:100%" />`;
  }
  return html;
}

function budgetSection(state: GameState, _ctx: PanelCtx): string {
  const a = state.budgetAllocation;
  const fields: [keyof typeof a, string][] = [
    ['reserve', 'Reserve'], ['construction', 'Construction'], ['vehicles', 'Vehicles'],
    ['intelligence', 'Intelligence'], ['missiles', 'Missiles'],
  ];
  let html = '<h2>Budget Allocation</h2><div class="meta">Daily income is split across these pools by weight.</div>';
  for (const [key, label] of fields) {
    html += `<h3>${label}: ${a[key]}</h3><input type="range" min="0" max="100" value="${a[key]}" data-budget="${key}" style="width:100%" />`;
  }
  html += '<h3>Pools</h3>';
  html += `<div class="row"><span>Construction</span><span>${fmtCredits(state.budgetPools.construction)} CR</span></div>`;
  html += `<div class="row"><span>Vehicles</span><span>${fmtCredits(state.budgetPools.vehicles)} CR</span></div>`;
  html += `<div class="row"><span>Intelligence</span><span>${fmtCredits(state.budgetPools.intelligence)} CR</span></div>`;
  html += `<div class="row"><span>Missiles</span><span>${fmtCredits(state.budgetPools.missiles)} CR</span></div>`;
  return html;
}

export function renderSidePanel(root: HTMLElement, state: GameState, ctx: PanelCtx) {
  let html = `<button id="panelModeToggle" style="width:100%;margin-bottom:8px;">${ctx.panelMode === 'select' ? 'Open Budget Panel' : 'Back to Selection'}</button>`;
  if (ctx.panelMode === 'budget') {
    html += budgetSection(state, ctx);
  } else {
    html += asteroidSection(state, ctx) || '<div class="meta">Select an asteroid or fleet.</div>';
    html += fleetSection(state, ctx);
  }
  root.innerHTML = html;

  root.querySelector('#panelModeToggle')?.addEventListener('click', () => ctx.onTogglePanelMode());

  root.querySelectorAll<HTMLButtonElement>('[data-build]').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (state.selectedAsteroidId) {
        const colony = state.asteroids[state.selectedAsteroidId].colonyId;
        if (colony) ctx.onBuild(colony, btn.dataset.build!);
      }
    });
  });
  root.querySelectorAll<HTMLButtonElement>('[data-ship]').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (state.selectedAsteroidId) {
        const colony = state.asteroids[state.selectedAsteroidId].colonyId;
        if (colony) ctx.onBuildShip(colony, btn.dataset.ship as ShipClassId);
      }
    });
  });
  root.querySelectorAll<HTMLSelectElement>('[data-silo]').forEach((sel) => {
    sel.addEventListener('change', () => {
      if (state.selectedAsteroidId) {
        const colonyId = state.asteroids[state.selectedAsteroidId].colonyId;
        if (colonyId) ctx.onSetSiloType(colonyId, sel.dataset.silo!, sel.value as MissileTypeId);
      }
    });
  });
  root.querySelector('#missileFireBtn')?.addEventListener('click', () => {
    if (!state.selectedAsteroidId) return;
    const colonyId = state.asteroids[state.selectedAsteroidId].colonyId;
    if (!colonyId) return;
    const type = (root.querySelector('#missileFireType') as HTMLSelectElement).value as MissileTypeId;
    const count = parseInt((root.querySelector('#missileFireCount') as HTMLInputElement).value, 10);
    const target = (root.querySelector('#missileTargetSelect') as HTMLSelectElement).value;
    ctx.onFireMissiles(colonyId, type, count, target);
  });
  root.querySelector('#foundColonyBtn')?.addEventListener('click', (e) => {
    const btn = e.currentTarget as HTMLButtonElement;
    const count = parseInt((root.querySelector('#colonistCount') as HTMLInputElement).value, 10);
    ctx.onFoundColony(btn.dataset.fleet!, count);
  });
  root.querySelectorAll<HTMLButtonElement>('[data-order]').forEach((btn) => {
    btn.addEventListener('click', () => ctx.onArmOrder(btn.dataset.order as FleetOrderMode));
  });
  root.querySelector('#retreatSlider')?.addEventListener('input', (e) => {
    if (state.selectedFleetId) ctx.onSetRetreat(state.selectedFleetId, parseInt((e.target as HTMLInputElement).value, 10));
  });
  root.querySelectorAll<HTMLInputElement>('[data-budget]').forEach((slider) => {
    slider.addEventListener('input', () => {
      const alloc = { ...state.budgetAllocation };
      (alloc as any)[slider.dataset.budget!] = parseInt(slider.value, 10);
      ctx.onSetBudget(alloc);
    });
  });
}
