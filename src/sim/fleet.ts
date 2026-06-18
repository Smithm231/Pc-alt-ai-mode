import type { GameState, Fleet } from './types';
import { SHIP_CLASSES, type ShipClassId, type ShipInstance } from '../data/ships';
import { ALIEN_RACES } from '../data/aliens';
import { nextUid } from './colony';
import { TICKS_PER_DAY } from './types';
import { MISSILE_TYPES, type MissileTypeId } from '../data/missiles';

const FLEET_SPEED_PER_TICK = 6;
const ARRIVAL_THRESHOLD = 40;

export function spawnShip(state: GameState, owner: string, classId: ShipClassId, atAsteroidId: string): string {
  const playerDef = SHIP_CLASSES[classId];
  const alienDef = playerDef ? null : ALIEN_RACES[owner]?.shipClasses.find((c) => c.id === classId);
  const ast = state.asteroids[atAsteroidId];
  const id = nextUid('ship');
  const armor = playerDef ? playerDef.armor : alienDef!.armor;
  const hardpoints = playerDef ? playerDef.hardpoints : alienDef!.hardpoints;
  const ship: ShipInstance = {
    id, classId, owner, hp: armor, maxHp: armor,
    hardpointWeapons: alienDef ? [...alienDef.weapons] : new Array(hardpoints).fill(null),
    hardpointCooldowns: new Array(hardpoints).fill(0),
    disabledUntilTick: 0,
    x: ast.x, y: ast.y, vx: 0, vy: 0,
    targetAsteroidId: null,
    fleetId: '',
  };
  state.ships[id] = ship;
  const fleetId = nextUid('fleet');
  const fleet: Fleet = {
    id: fleetId, owner, shipIds: [id], order: 'sentry',
    targetAsteroidId: atAsteroidId, currentAsteroidId: atAsteroidId,
    retreatThresholdPct: 25, x: ast.x, y: ast.y,
  };
  ship.fleetId = fleetId;
  state.fleets[fleetId] = fleet;
  return fleetId;
}

export function mergeFleetInto(state: GameState, sourceFleetId: string, destFleetId: string) {
  const src = state.fleets[sourceFleetId];
  const dest = state.fleets[destFleetId];
  if (!src || !dest) return;
  for (const sid of src.shipIds) {
    state.ships[sid].fleetId = destFleetId;
    dest.shipIds.push(sid);
  }
  delete state.fleets[sourceFleetId];
}

export function issueFleetOrder(state: GameState, fleetId: string, order: Fleet['order'], targetAsteroidId: string) {
  const fleet = state.fleets[fleetId];
  if (!fleet) return;
  fleet.order = order;
  fleet.targetAsteroidId = targetAsteroidId;
  fleet.currentAsteroidId = fleet.currentAsteroidId === targetAsteroidId ? targetAsteroidId : null;
}

export function fleetTotalHpPct(state: GameState, fleet: Fleet): number {
  let hp = 0, maxHp = 0;
  for (const sid of fleet.shipIds) {
    const s = state.ships[sid];
    if (!s) continue;
    hp += s.hp; maxHp += s.maxHp;
  }
  return maxHp === 0 ? 0 : (hp / maxHp) * 100;
}

export function tickFleetMovement(state: GameState, dtTicks: number) {
  for (const fleet of Object.values(state.fleets)) {
    if (fleet.shipIds.length === 0) { delete state.fleets[fleet.id]; continue; }

    if (fleet.retreatThresholdPct > 0 && fleetTotalHpPct(state, fleet) <= fleet.retreatThresholdPct && fleet.order !== 'move') {
      const homeId = Object.values(state.asteroids).find((a) => a.isHome && a.colonyId && state.colonies[a.colonyId]?.owner === fleet.owner)?.id;
      if (homeId) {
        fleet.order = 'move';
        fleet.targetAsteroidId = homeId;
        fleet.currentAsteroidId = null;
      }
    }

    if (!fleet.targetAsteroidId) continue;
    const target = state.asteroids[fleet.targetAsteroidId];
    if (!target) continue;
    if (fleet.currentAsteroidId === fleet.targetAsteroidId) {
      fleet.x = target.x; fleet.y = target.y;
      continue;
    }
    const dx = target.x - fleet.x, dy = target.y - fleet.y;
    const dist = Math.hypot(dx, dy);
    if (dist <= ARRIVAL_THRESHOLD) {
      fleet.currentAsteroidId = fleet.targetAsteroidId;
      fleet.x = target.x; fleet.y = target.y;
    } else {
      const step = FLEET_SPEED_PER_TICK * dtTicks;
      fleet.x += (dx / dist) * step;
      fleet.y += (dy / dist) * step;
    }
    for (const sid of fleet.shipIds) {
      const s = state.ships[sid];
      if (s) { s.x = fleet.x; s.y = fleet.y; }
    }
  }
}

export function launchMissileSalvo(
  state: GameState, ownerId: string, targetColonyId: string, missileType: MissileTypeId, count: number,
) {
  const def = MISSILE_TYPES[missileType];
  state.missilesInFlight.push({
    id: nextUid('salvo'), ownerId, targetColonyId, missileType, count,
    arrivalDay: state.day + def.travelDays,
  });
}

export const FLEET_TICKS_PER_DAY = TICKS_PER_DAY;
