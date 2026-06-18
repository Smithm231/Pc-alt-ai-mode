import type { GameState } from './types';
import { BUILDINGS } from '../data/buildings';
import { SHIP_CLASSES, type ShipClassId } from '../data/ships';
import { MISSILE_TYPES, type MissileTypeId } from '../data/missiles';
import { ORES, type OreId } from '../data/ores';
import { nextUid, foundColony } from './colony';
import { launchMissileSalvo, issueFleetOrder } from './fleet';
import type { Fleet, Colony } from './types';

export interface ActionResult { ok: boolean; reason?: string }

function spend(state: GameState, pool: keyof GameState['budgetPools'] | null, amount: number): boolean {
  if (pool) {
    const available = state.budgetPools[pool];
    if (available >= amount) { state.budgetPools[pool] -= amount; return true; }
    const shortfall = amount - available;
    if (state.credits < shortfall) return false;
    state.credits -= shortfall;
    state.budgetPools[pool] = 0;
    return true;
  }
  if (state.credits < amount) return false;
  state.credits -= amount;
  return true;
}

export function queueBuilding(state: GameState, colonyId: string, buildingDefId: string): ActionResult {
  const colony = state.colonies[colonyId];
  const def = BUILDINGS[buildingDefId];
  if (!colony || !def) return { ok: false, reason: 'unknown building or colony' };
  if (colony.owner !== 'player') return { ok: false, reason: 'not your colony' };
  if (def.requires && !colony.buildings.some((b) => b.defId === def.requires)) {
    return { ok: false, reason: `requires ${BUILDINGS[def.requires].name}` };
  }
  if (def.maxPerColony) {
    const countOfType = colony.buildings.filter((b) => b.defId === buildingDefId).length
      + colony.constructionQueue.filter((o) => o.buildingDefId === buildingDefId).length;
    if (countOfType >= def.maxPerColony) return { ok: false, reason: 'max reached' };
  }
  for (const [oreId, amount] of Object.entries(def.costOre ?? {})) {
    if ((colony.oreStock[oreId as OreId] ?? 0) < amount!) {
      return { ok: false, reason: `not enough ${ORES[oreId as OreId].name}` };
    }
  }
  if (!spend(state, 'construction', def.costCredits)) return { ok: false, reason: 'insufficient credits' };
  for (const [oreId, amount] of Object.entries(def.costOre ?? {})) {
    colony.oreStock[oreId as OreId]! -= amount!;
  }
  colony.constructionQueue.push({ uid: nextUid('order'), buildingDefId, daysRemaining: def.buildDays });
  return { ok: true };
}

export function queueShip(state: GameState, colonyId: string, shipClassId: ShipClassId): ActionResult {
  const colony = state.colonies[colonyId];
  const def = SHIP_CLASSES[shipClassId];
  if (!colony || !def) return { ok: false, reason: 'unknown ship or colony' };
  if (colony.owner !== 'player') return { ok: false, reason: 'not your colony' };
  const yardCategory = def.yard;
  const hasYard = colony.buildings.some((b) => BUILDINGS[b.defId].category === yardCategory && b.powered);
  if (!hasYard) return { ok: false, reason: `requires a powered ${yardCategory === 'shipyardSmall' ? 'Construction Yard' : 'Orbital Space Dock'}` };
  for (const [oreId, amount] of Object.entries(def.costOre ?? {})) {
    if ((colony.oreStock[oreId as OreId] ?? 0) < amount!) return { ok: false, reason: `not enough ${ORES[oreId as OreId].name}` };
  }
  if (!spend(state, 'vehicles', def.costCredits)) return { ok: false, reason: 'insufficient credits' };
  for (const [oreId, amount] of Object.entries(def.costOre ?? {})) {
    colony.oreStock[oreId as OreId]! -= amount!;
  }
  colony.shipBuildQueue.push({ uid: nextUid('order'), shipClassId, daysRemaining: def.buildDays });
  return { ok: true };
}

export function setSiloMissileType(state: GameState, colonyId: string, siloUid: string, type: MissileTypeId): ActionResult {
  const colony = state.colonies[colonyId];
  const silo = colony?.buildings.find((b) => b.uid === siloUid);
  if (!silo) return { ok: false, reason: 'no such silo' };
  silo.selectedMissileType = type;
  return { ok: true };
}

export function fireMissiles(
  state: GameState, colonyId: string, missileType: MissileTypeId, count: number, targetColonyId: string,
): ActionResult {
  const colony = state.colonies[colonyId];
  if (!colony) return { ok: false, reason: 'no such colony' };
  const have = colony.missileStock[missileType] ?? 0;
  if (have < count || count <= 0) return { ok: false, reason: 'not enough missiles' };
  colony.missileStock[missileType] = have - count;
  launchMissileSalvo(state, colony.owner, targetColonyId, missileType, count);
  return { ok: true };
}

export function deployTransporterColony(state: GameState, fleetId: string, colonists: number): ActionResult {
  const fleet = state.fleets[fleetId];
  if (!fleet) return { ok: false, reason: 'no such fleet' };
  if (fleet.owner !== 'player') return { ok: false, reason: 'not your fleet' };
  const shipId = fleet.shipIds.find((id) => state.ships[id]?.classId === 'transporter');
  const ship = shipId ? state.ships[shipId] : null;
  if (!ship || !fleet.currentAsteroidId) return { ok: false, reason: 'no transporter at an asteroid' };
  const asteroid = state.asteroids[fleet.currentAsteroidId];
  if (asteroid.colonyId) return { ok: false, reason: 'asteroid already colonized' };
  if (colonists > 200 || colonists <= 0) return { ok: false, reason: 'invalid colonist count' };

  const id = nextUid('colony');
  const newColony: Colony = {
    id, asteroidId: asteroid.id, owner: 'player', buildings: [], constructionQueue: [], shipBuildQueue: [],
    population: 0, foodStock: 0, airStock: 0, waterStock: 0, oreStock: {}, missileStock: {},
    missileBuildProgressDays: 0, radiationPercent: 0, unrest: 0,
    powerState: 'surplus', airState: 'surplus', foodState: 'surplus', waterState: 'surplus',
    virusOutbreak: false, founded: false,
  };
  state.colonies[id] = newColony;
  asteroid.colonyId = id;
  foundColony(newColony, colonists);
  delete state.ships[shipId!];
  fleet.shipIds = fleet.shipIds.filter((sid) => sid !== shipId);
  if (fleet.shipIds.length === 0) delete state.fleets[fleetId];
  return { ok: true };
}

export function setFleetOrderAction(state: GameState, fleetId: string, order: Fleet['order'], targetAsteroidId: string): ActionResult {
  issueFleetOrder(state, fleetId, order, targetAsteroidId);
  return { ok: true };
}

export function setRetreatThreshold(state: GameState, fleetId: string, pct: number): ActionResult {
  const fleet = state.fleets[fleetId];
  if (!fleet) return { ok: false, reason: 'no such fleet' };
  fleet.retreatThresholdPct = Math.max(0, Math.min(100, pct));
  return { ok: true };
}

export function setBudgetAllocation(state: GameState, allocation: GameState['budgetAllocation']): ActionResult {
  state.budgetAllocation = allocation;
  return { ok: true };
}

export { MISSILE_TYPES };
