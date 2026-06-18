import type { GameState, Colony, Asteroid, BuildingInstance } from './types';
import type { AlienRaceDef } from '../data/aliens/raceTypes';
import { ALIEN_RACES } from '../data/aliens';
import { KLL_KP_QUA_BUILDINGS, SURVIVAL_CRITICAL } from '../data/aliens/alienBuildings';
import type { Rng } from './rng';
import { nextUid, createColony } from './colony';
import { createAlienHomeAsteroid } from './asteroidField';
import { spawnShip, issueFleetOrder, mergeFleetInto } from './fleet';
import { MISSILE_TYPES } from '../data/missiles';

// Only Kll-Kp-Qua ships/buildings exist today; this map lets dailyTickAlienColony
// stay race-agnostic once more races' building/ship tables are added.
const RACE_BUILDINGS: Record<string, typeof KLL_KP_QUA_BUILDINGS> = {
  kll_kp_qua: KLL_KP_QUA_BUILDINGS,
};

function alienDefOf(raceId: string, defId: string) {
  return RACE_BUILDINGS[raceId]?.[defId];
}

export function foundAlienColony(colony: Colony, raceId: string) {
  colony.founded = true;
  colony.alienRaceId = raceId;
  colony.alienBuildClusterProgressDays = 0;
  colony.alienColonizeProgressDays = 0;
  colony.alienScoutProgressDays = 0;
  colony.population = 50;
  const defs = RACE_BUILDINGS[raceId];
  const mk = (defId: string): BuildingInstance => ({
    uid: nextUid('bld'), defId, hp: defs[defId].hp, maxHp: defs[defId].hp, powered: true, mineProgressDays: 0,
    secondGen: false, fireProgressDays: 0, optimized: false, active: true,
  });
  // Pre-build survival-critical infra so the colony doesn't starve before the
  // build-cluster system (which only fires every buildClusterIntervalDays) can react.
  colony.buildings.push(mk('queens_chamber'), mk('hive_chamber'), ...SURVIVAL_CRITICAL.map(mk));
}

function countAlienBuilding(colony: Colony, defId: string): number {
  return colony.buildings.filter((b) => b.defId === defId && b.hp > 0).length;
}

function pickShipClassForColony(race: AlienRaceDef, population: number) {
  const tiers = race.shipClasses;
  if (population < 60) return tiers[Math.min(1, tiers.length - 1)];
  if (population < 120) return tiers[Math.min(3, tiers.length - 1)];
  return tiers[rng_int(4, tiers.length - 1)];
}
// Small local helper kept free of an Rng instance for the deterministic tier pick above.
function rng_int(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function findUnclaimedAsteroid(state: GameState): Asteroid | null {
  const candidates = Object.values(state.asteroids).filter((a) => !a.colonyId && !a.isHome);
  return candidates.length ? candidates[Math.floor(Math.random() * candidates.length)] : null;
}

function nearestPlayerAsteroidId(state: GameState, from: Asteroid): string | null {
  let best: { id: string; d: number } | null = null;
  for (const c of Object.values(state.colonies)) {
    if (c.owner !== 'player' || !c.founded) continue;
    const a = state.asteroids[c.asteroidId];
    if (!a) continue;
    const d = Math.hypot(a.x - from.x, a.y - from.y);
    if (!best || d < best.d) best = { id: a.id, d };
  }
  return best?.id ?? null;
}

export function dailyTickAlienColony(colony: Colony, asteroid: Asteroid, state: GameState, rng: Rng) {
  const race = ALIEN_RACES[colony.alienRaceId!];
  if (!race || colony.population <= 0) return;

  const hasFood = countAlienBuilding(colony, 'protein_plant') > 0;
  if (hasFood) colony.population += race.popGrowthPerDay;
  else colony.population = Math.max(0, colony.population - race.popDeclinePerDayWithoutFood);

  // Build clusters
  colony.alienBuildClusterProgressDays = (colony.alienBuildClusterProgressDays ?? 0) + 1;
  if (colony.alienBuildClusterProgressDays >= race.buildClusterIntervalDays) {
    colony.alienBuildClusterProgressDays = 0;
    const missingCritical = SURVIVAL_CRITICAL.filter((id) => countAlienBuilding(colony, id) === 0);
    const cluster = missingCritical.length > 0
      ? [missingCritical[0]]
      : race.buildClusters[rng.int(0, race.buildClusters.length - 1)];
    for (const buildingId of cluster) {
      const def = alienDefOf(colony.alienRaceId!, buildingId);
      if (!def) continue;
      colony.buildings.push({
        uid: nextUid('bld'), defId: buildingId, hp: def.hp, maxHp: def.hp, powered: true,
        mineProgressDays: 0, secondGen: false, fireProgressDays: 0, optimized: false, active: true,
      });
    }
  }

  // Missile production
  colony.missileBuildProgressDays += 1;
  if (colony.missileBuildProgressDays >= race.missileBuildIntervalDays) {
    colony.missileBuildProgressDays = 0;
    const entries = Object.entries(race.missileWeights) as [string, number][];
    const type = rng.weighted(entries.map(([k, w]) => [k, w] as const)) as keyof typeof colony.missileStock;
    const have = colony.missileStock[type] ?? 0;
    if (have < race.missileCapPerType) colony.missileStock[type] = have + 1;
  }

  // Colonization
  colony.alienColonizeProgressDays = (colony.alienColonizeProgressDays ?? 0) + 1;
  if (colony.alienColonizeProgressDays >= race.colonizeIntervalDays && rng.chance(race.colonizeChance)) {
    colony.alienColonizeProgressDays = 0;
    const target = findUnclaimedAsteroid(state);
    if (target) {
      const newColony = createColony(nextUid('colony'), target.id, colony.owner);
      foundAlienColony(newColony, colony.alienRaceId!);
      newColony.population = Math.min(race.colonyShipColonistCapacity, 50);
      state.colonies[newColony.id] = newColony;
      target.colonyId = newColony.id;
    }
  }

  // Scouting
  colony.alienScoutProgressDays = (colony.alienScoutProgressDays ?? 0) + 1;
  if (colony.alienScoutProgressDays >= race.scoutIntervalDays) {
    colony.alienScoutProgressDays = 0;
    const scoutClass = race.shipClasses[0];
    const fleetId = spawnShip(state, colony.owner, scoutClass.id as any, asteroid.id);
    const dest = nearestPlayerAsteroidId(state, asteroid);
    if (dest) issueFleetOrder(state, fleetId, 'move', dest);
  }

  // Combat ship production
  colony.alienShipBuildProgressDays = (colony.alienShipBuildProgressDays ?? 0) + 1;
  const targetClass = pickShipClassForColony(race, colony.population);
  if (colony.alienShipBuildProgressDays >= targetClass.buildDays) {
    colony.alienShipBuildProgressDays = 0;
    const fleetId = spawnShip(state, colony.owner, targetClass.id as any, asteroid.id);
    const ship = state.ships[state.fleets[fleetId].shipIds[0]];
    targetClass.weapons.forEach((w, i) => { ship.hardpointWeapons[i] = w; });
    const homeFleet = Object.values(state.fleets).find(
      (f) => f.owner === colony.owner && f.currentAsteroidId === asteroid.id && f.id !== fleetId && f.order === 'sentry',
    );
    if (homeFleet) mergeFleetInto(state, fleetId, homeFleet.id);
  }

  // Send an attack wing toward the nearest player colony once enough ships have massed.
  colony.alienAttackProgressDays = (colony.alienAttackProgressDays ?? 0) + 1;
  if (colony.alienAttackProgressDays >= 90) {
    colony.alienAttackProgressDays = 0;
    const homeFleet = Object.values(state.fleets).find(
      (f) => f.owner === colony.owner && f.currentAsteroidId === asteroid.id && f.order === 'sentry' && f.shipIds.length >= 3,
    );
    if (homeFleet) {
      const dest = nearestPlayerAsteroidId(state, asteroid);
      if (dest) issueFleetOrder(state, homeFleet.id, 'attackAsteroid', dest);
    }
  }
}

/** Called when a colony belonging to this race is struck by missiles, per documented retaliation behaviour. */
export function triggerRetaliation(state: GameState, alienOwnerId: string, raceId: string) {
  const race = ALIEN_RACES[raceId];
  const alienColonies = Object.values(state.colonies).filter((c) => c.owner === alienOwnerId && c.founded);
  const playerHome = Object.values(state.colonies).find((c) => c.owner === 'player' && c.founded);
  if (!playerHome || alienColonies.length === 0) return;
  const delayDays = race.retaliationDelayDaysPerColony * alienColonies.length;
  const source = alienColonies[Math.floor(Math.random() * alienColonies.length)];
  const stock = Object.entries(source.missileStock) as [keyof typeof source.missileStock, number][];
  let remaining = race.retaliationMaxMissiles;
  for (const [type, count] of stock) {
    if (remaining <= 0) break;
    const fire = Math.min(count, remaining);
    if (fire <= 0) continue;
    source.missileStock[type] = count - fire;
    remaining -= fire;
    state.missilesInFlight.push({
      id: nextUid('salvo'), ownerId: alienOwnerId, targetColonyId: playerHome.id,
      missileType: type, count: fire, arrivalDay: state.day + delayDays + MISSILE_TYPES[type].travelDays,
    });
  }
}

export { createAlienHomeAsteroid };
