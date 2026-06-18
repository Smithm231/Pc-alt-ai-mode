import type { Rng } from './rng';
import type { Asteroid, AsteroidPoint } from './types';
import { ORES, ORE_IDS, HOME_ASTEROID_ORE, type OreId } from '../data/ores';

export const ASTEROID_LAYOUT_COUNT = 24;
export const FIELD_SIZE = 4000;

function makeShape(rng: Rng, radius: number, irregular: boolean): AsteroidPoint[] {
  const pts: AsteroidPoint[] = [];
  const sides = rng.int(7, 11);
  for (let i = 0; i < sides; i++) {
    const angle = (i / sides) * Math.PI * 2;
    const wobble = irregular ? rng.next() * 0.5 + 0.7 : rng.next() * 0.2 + 0.85;
    pts.push({ x: Math.cos(angle) * radius * wobble, y: Math.sin(angle) * radius * wobble });
  }
  return pts;
}

function rollOreDeposits(rng: Rng): Partial<Record<OreId, number>> {
  const ore: Partial<Record<OreId, number>> = {};
  for (const id of ORE_IDS) {
    const def = ORES[id];
    if (rng.chance(def.spawnChance)) {
      // Higher-rank (rarer) ores naturally deposit in smaller quantities.
      const base = Math.max(20, Math.round(300 / def.rank));
      ore[id] = rng.int(Math.round(base * 0.5), base);
    }
  }
  return ore;
}

let nextId = 1;
function genId(prefix: string) {
  return `${prefix}_${nextId++}`;
}

export function createHomeAsteroid(rng: Rng, x: number, y: number, layoutIndex: number): Asteroid {
  return {
    id: genId('ast'),
    name: 'Sol Base',
    x, y, vx: 0, vy: 0,
    radius: 70,
    shape: makeShape(rng, 70, false),
    ore: { ...HOME_ASTEROID_ORE },
    colonyId: null,
    isHome: true,
    layoutIndex,
  };
}

export function createAlienHomeAsteroid(rng: Rng, x: number, y: number, layoutIndex: number, name: string): Asteroid {
  return {
    id: genId('ast'),
    name,
    x, y, vx: 0, vy: 0,
    radius: 70,
    shape: makeShape(rng, 70, false),
    ore: rollOreDeposits(rng),
    colonyId: null,
    isHome: true,
    layoutIndex,
  };
}

export function createFieldAsteroid(rng: Rng, layoutIndex: number, usedLayouts: Set<number>): Asteroid {
  let li = layoutIndex;
  while (usedLayouts.has(li)) li = (li + 1) % ASTEROID_LAYOUT_COUNT;
  usedLayouts.add(li);
  const irregular = [13, 15, 18, 23].includes(li);
  const radius = rng.int(35, 65);
  const speed = rng.int(2, 5);
  const angle = rng.next() * Math.PI * 2;
  return {
    id: genId('ast'),
    name: `Asteroid ${li}`,
    x: rng.int(0, FIELD_SIZE),
    y: rng.int(0, FIELD_SIZE),
    vx: Math.cos(angle) * speed,
    vy: Math.sin(angle) * speed,
    radius,
    shape: makeShape(rng, radius, irregular),
    ore: rollOreDeposits(rng),
    colonyId: null,
    isHome: false,
    layoutIndex: li,
  };
}

export function generateField(rng: Rng, fieldAsteroidCount: number): { asteroids: Asteroid[]; usedLayouts: Set<number> } {
  const usedLayouts = new Set<number>();
  const asteroids: Asteroid[] = [];
  for (let i = 0; i < fieldAsteroidCount; i++) {
    asteroids.push(createFieldAsteroid(rng, rng.int(0, ASTEROID_LAYOUT_COUNT - 1), usedLayouts));
  }
  return { asteroids, usedLayouts };
}

export function stepAsteroidDrift(a: Asteroid, dtDays: number) {
  if (a.isHome) return;
  a.x += a.vx * dtDays;
  a.y += a.vy * dtDays;
  if (a.x < 0 || a.x > FIELD_SIZE) a.vx *= -1;
  if (a.y < 0 || a.y > FIELD_SIZE) a.vy *= -1;
  a.x = Math.max(0, Math.min(FIELD_SIZE, a.x));
  a.y = Math.max(0, Math.min(FIELD_SIZE, a.y));
}
