import type { GameState } from './types';
import type { ShipInstance } from '../data/ships';
import { WEAPONS } from '../data/weapons';
import { MISSILE_TYPES } from '../data/missiles';
import { BUILDINGS } from '../data/buildings';
import { defOf } from './colony';
import type { Rng } from './rng';

function shipsAt(state: GameState, asteroidId: string, owner?: string): ShipInstance[] {
  return Object.values(state.ships).filter((s) => {
    const fleet = state.fleets[s.fleetId];
    return fleet && fleet.currentAsteroidId === asteroidId && (owner === undefined || s.owner === owner);
  });
}

function applyDamageToShip(target: ShipInstance, dmg: number) {
  // Deflector hardpoint halves all incoming damage (rounded down, min 1 if any dmg).
  const hasDeflector = target.hardpointWeapons.includes('deflector');
  let final = hasDeflector ? Math.max(1, Math.floor(dmg / 2)) : dmg;
  target.hp = Math.max(0, target.hp - final);
}

/** Resolves ship-vs-ship hardpoint combat for all asteroids with opposing fleets present. */
export function tickShipCombat(state: GameState, rng: Rng, currentTick: number) {
  const byAsteroid = new Map<string, ShipInstance[]>();
  for (const s of Object.values(state.ships)) {
    const fleet = state.fleets[s.fleetId];
    if (!fleet || !fleet.currentAsteroidId) continue;
    const arr = byAsteroid.get(fleet.currentAsteroidId) ?? [];
    arr.push(s);
    byAsteroid.set(fleet.currentAsteroidId, arr);
  }

  for (const [, ships] of byAsteroid) {
    const owners = new Set(ships.map((s) => s.owner));
    if (owners.size < 2) continue; // no opposing forces here

    for (const ship of ships) {
      if (ship.disabledUntilTick > currentTick) continue;
      const enemies = ships.filter((s) => s.owner !== ship.owner && s.hp > 0);
      if (enemies.length === 0) continue;

      ship.hardpointWeapons.forEach((weaponId, idx) => {
        if (!weaponId) return;
        const weapon = WEAPONS[weaponId as keyof typeof WEAPONS];
        if (!weapon || !weapon.offensive) return;
        if (ship.hardpointCooldowns[idx] > 0) { ship.hardpointCooldowns[idx]--; return; }
        ship.hardpointCooldowns[idx] = weapon.cooldownTicks;

        if (!rng.chance(weapon.hitChance)) return;
        const hitCount = weapon.areaEffect ? Math.min(4, enemies.length) : 1;
        const targetList: ShipInstance[] = [];
        const pool = [...enemies];
        for (let i = 0; i < hitCount && pool.length > 0; i++) {
          const idx = rng.int(0, pool.length - 1);
          targetList.push(pool.splice(idx, 1)[0]);
        }
        for (const t of targetList) {
          if (weapon.disableTicks) {
            t.disabledUntilTick = currentTick + weapon.disableTicks;
          } else {
            applyDamageToShip(t, weapon.damage);
          }
        }
      });
    }
    for (const s of ships) {
      if (s.hp <= 0) delete state.ships[s.id];
    }
    for (const fleet of Object.values(state.fleets)) {
      fleet.shipIds = fleet.shipIds.filter((id) => state.ships[id]);
    }
  }
}

/** Daily turret defense: colony turrets fire on any enemy ships present at the asteroid. */
export function dailyTurretDefense(state: GameState, rng: Rng) {
  for (const colony of Object.values(state.colonies)) {
    if (!colony.founded) continue;
    const enemyShips = shipsAt(state, colony.asteroidId).filter((s) => s.owner !== colony.owner);
    if (enemyShips.length === 0) continue;
    for (const b of colony.buildings) {
      const def = defOf(b);
      if (def.category !== 'turret' || !b.powered || b.hp <= 0) continue;
      b.fireProgressDays += 1;
      if (b.fireProgressDays < (def.fireEveryDays ?? 5)) continue;
      b.fireProgressDays = 0;
      const target = rng.pick(enemyShips);
      const dmg = b.optimized ? (def.damageOptimized ?? def.damage ?? 0) : (def.damage ?? 0);
      applyDamageToShip(target, dmg);
    }
    for (const s of enemyShips) if (s.hp <= 0) delete state.ships[s.id];
    for (const fleet of Object.values(state.fleets)) {
      fleet.shipIds = fleet.shipIds.filter((id) => state.ships[id]);
    }
  }
}

function antiMissileInterceptChance(colony: GameState['colonies'][string]): number {
  const pods = colony.buildings.filter((b) => defOf(b).category === 'antiMissile' && b.powered && b.hp > 0);
  if (pods.length === 0) return 0;
  const def = BUILDINGS.anti_missile_pod;
  const chance = def.interceptBase! + def.interceptPerPod! * (pods.length - 1);
  return Math.min(def.interceptCap!, chance);
}

/** Resolves missile salvos that have reached their arrival day. */
export function resolveMissileArrivals(state: GameState, rng: Rng) {
  const remaining = [];
  for (const salvo of state.missilesInFlight) {
    if (salvo.arrivalDay > state.day) { remaining.push(salvo); continue; }
    const colony = state.colonies[salvo.targetColonyId];
    if (!colony || colony.population <= 0) continue;
    const def = MISSILE_TYPES[salvo.missileType];
    const intercept = antiMissileInterceptChance(colony);

    let survivors = 0;
    for (let i = 0; i < salvo.count; i++) if (!rng.chance(intercept)) survivors++;
    if (survivors === 0) continue;

    if (def.populationCasualties) {
      colony.population = Math.max(0, colony.population - def.populationCasualties * survivors);
    }
    if (def.triggersVirus) colony.virusOutbreak = true;
    if (def.radiationIncrease) colony.radiationPercent = Math.min(100, colony.radiationPercent + def.radiationIncrease * survivors);
    if (def.buildingDamage > 0) {
      const alive = colony.buildings.filter((b) => b.hp > 0 && defOf(b).id !== 'cpu');
      for (let i = 0; i < survivors; i++) {
        const hits = Math.min(def.targetsHit, alive.length);
        for (let h = 0; h < hits; h++) {
          const target = rng.pick(alive);
          target.hp = Math.max(0, target.hp - def.buildingDamage);
        }
      }
      colony.buildings = colony.buildings.filter((b) => b.hp > 0);
    }
  }
  state.missilesInFlight = remaining;
}
