import { BUILDINGS, POWER_PRIORITY, type BuildingDef } from '../data/buildings';
import { ORES, MINER_DEFS, type OreId } from '../data/ores';
import type { Asteroid, BuildingInstance, Colony, PafwState } from './types';
import type { Rng } from './rng';
import type { GameState } from './types';

let uidCounter = 1;
export function nextUid(prefix: string) {
  return `${prefix}_${uidCounter++}`;
}

export function defOf(b: BuildingInstance): BuildingDef {
  return BUILDINGS[b.defId];
}

export function createColony(id: string, asteroidId: string, owner: string): Colony {
  return {
    id, asteroidId, owner,
    buildings: [],
    constructionQueue: [],
    shipBuildQueue: [],
    population: 0,
    foodStock: 0, airStock: 0, waterStock: 0,
    oreStock: {},
    missileStock: {},
    missileBuildProgressDays: 0,
    radiationPercent: 0,
    unrest: 0,
    powerState: 'surplus', airState: 'surplus', foodState: 'surplus', waterState: 'surplus',
    virusOutbreak: false,
    founded: false,
  };
}

function makeBuilding(defId: string): BuildingInstance {
  const def = BUILDINGS[defId];
  return {
    uid: nextUid('bld'), defId, hp: def.hp, maxHp: def.hp, powered: true, mineProgressDays: 0,
    secondGen: false, fireProgressDays: 0, optimized: false, active: true,
  };
}

// New colonies ship with enough PAFW reserves (matching the 5x-population storage cap)
// to survive until life support is built; starterInfra additionally pre-builds the
// core survival buildings, used for the player's already-established home base.
export function foundColony(colony: Colony, startingColonists: number, starterInfra = false) {
  colony.founded = true;
  colony.population = startingColonists;
  colony.buildings.push(makeBuilding('command_centre'), makeBuilding('living_quarters'));
  colony.airStock = colony.foodStock = colony.waterStock = startingColonists * 5;
  if (starterInfra) {
    colony.buildings.push(
      makeBuilding('solar_generator'), makeBuilding('life_support'),
      makeBuilding('hydroponics'), makeBuilding('hydration_plant'),
    );
  }
}

function storageCapacity(colony: Colony): number {
  let cap = 200; // base capacity even with no storage buildings
  for (const b of colony.buildings) {
    const def = defOf(b);
    if (def.category === 'storage' && b.powered) cap += def.capacity ?? 0;
  }
  return cap;
}

function applyPowerPriority(colony: Colony, asteroid: Asteroid) {
  const consumers: BuildingInstance[] = [];
  let production = 0;
  // Powerplants always run; output is 32MW per unit of unmined Asteros
  // present on the asteroid (documented), capped at 10 units worth, with a
  // 0.25-unit trickle floor so a colony never goes to absolute zero power.
  for (const b of colony.buildings) {
    const def = defOf(b);
    if (def.category === 'power') {
      b.powered = true;
      const asteros = Math.min(asteroid.ore.asteros ?? 0, 10);
      production += def.outputPerDay! * Math.max(asteros, 0.25);
    } else {
      consumers.push(b);
    }
  }

  let consumption = consumers.reduce((s, b) => s + defOf(b).powerConsumption, 0);

  if (consumption <= production) {
    for (const b of consumers) b.powered = true;
    colony.powerState = 'surplus';
    return;
  }

  colony.powerState = consumption - production > production ? 'critical' : 'deficiency';
  // Shed load category by category in documented priority order until balanced.
  for (const b of consumers) b.powered = true;
  for (const category of POWER_PRIORITY) {
    if (consumption <= production) break;
    for (const b of consumers) {
      if (consumption <= production) break;
      const def = defOf(b);
      if (def.category === category && b.powered) {
        b.powered = false;
        consumption -= def.powerConsumption;
      }
    }
  }
}

function lifeSupportTick(
  colony: Colony,
  category: 'lifeSupportAir' | 'lifeSupportFood' | 'lifeSupportWater',
  stockKey: 'airStock' | 'foodStock' | 'waterStock',
): { state: PafwState; deaths: number } {
  let production = 0;
  for (const b of colony.buildings) {
    const def = defOf(b);
    if (def.category === category && b.powered) production += def.outputPerDay ?? 0;
  }
  const demand = colony.population;
  const cap = colony.population * 5;
  const available = production + colony[stockKey];

  if (production >= demand) {
    colony[stockKey] = Math.min(cap, colony[stockKey] + (production - demand));
    return { state: 'surplus', deaths: 0 };
  }
  if (available >= demand) {
    colony[stockKey] = available - demand;
    return { state: 'deficiency', deaths: 0 };
  }
  colony[stockKey] = 0;
  const shortfall = demand - available;
  let deaths = 0;
  if (category === 'lifeSupportAir') deaths = shortfall;
  else if (category === 'lifeSupportFood') deaths = Math.floor(shortfall / 10) + 1;
  else deaths = Math.floor(shortfall / 5) + 1;
  return { state: 'critical', deaths: Math.min(deaths, colony.population) };
}

function radiationLossChancePct(rad: number): number {
  const pts: [number, number][] = [[0, 1], [10, 11], [50, 18], [90, 51], [100, 100]];
  if (rad <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1];
    const [x1, y1] = pts[i];
    if (rad <= x1) return y0 + ((rad - x0) / (x1 - x0)) * (y1 - y0);
  }
  return 100;
}

function updateRadiation(colony: Colony, asteroid: Asteroid) {
  let raw = 0;
  for (const id of Object.keys(asteroid.ore) as OreId[]) {
    const def = ORES[id];
    if (def.radiationUnit) raw += (asteroid.ore[id]! / def.radiationUnit) * 10;
  }
  raw = Math.min(100, raw);
  let filters = 0;
  for (const b of colony.buildings) {
    if (defOf(b).category === 'decon' && b.powered) filters++;
  }
  const reduced = raw * Math.pow(1 - 0.30, filters);
  colony.radiationPercent = Math.max(0, Math.min(100, reduced));
}

function countMedicalCentres(colony: Colony): number {
  return colony.buildings.filter((b) => defOf(b).category === 'medical' && b.powered).length;
}
function countSecurityCentres(colony: Colony): number {
  return colony.buildings.filter((b) => defOf(b).category === 'security' && b.powered).length;
}

function requiredCentres(population: number): number {
  return Math.max(0, Math.ceil((population - 50) / 100));
}

function mineTick(colony: Colony, asteroid: Asteroid) {
  const cap = storageCapacity(colony);
  let totalOre = Object.values(colony.oreStock).reduce((s, v) => s + (v ?? 0), 0);
  for (const b of colony.buildings) {
    const def = defOf(b);
    if (def.category !== 'mining' || !b.powered) continue;
    if (totalOre >= cap) continue;
    const minerType = def.id === 'mine' ? 'mine' : def.id === 'deep_bore_mine' ? 'deepBoreMine' : 'seismicPenetrator';
    if (!b.minerTargetOre) {
      const candidate = (Object.keys(asteroid.ore) as OreId[]).find(
        (id) => ORES[id].minerType === minerType && (asteroid.ore[id] ?? 0) > 0,
      );
      if (!candidate) continue;
      b.minerTargetOre = candidate;
    }
    const remaining = asteroid.ore[b.minerTargetOre] ?? 0;
    if (remaining <= 0) { b.minerTargetOre = undefined; continue; }
    const minerDef = MINER_DEFS[minerType];
    const cycle = b.secondGen ? minerDef.cycleDays2ndGen : minerDef.cycleDays;
    b.mineProgressDays += 1;
    if (b.mineProgressDays >= cycle) {
      b.mineProgressDays -= cycle;
      asteroid.ore[b.minerTargetOre] = remaining - 1;
      colony.oreStock[b.minerTargetOre] = (colony.oreStock[b.minerTargetOre] ?? 0) + 1;
      totalOre++;
    }
  }
}

function exportOreTick(colony: Colony, state: GameState) {
  const storageFacilities = colony.buildings.filter((b) => defOf(b).category === 'storage' && b.powered).length;
  const ratePerOre = 20 + 10 * storageFacilities;
  for (const id of Object.keys(colony.oreStock) as OreId[]) {
    const have = colony.oreStock[id] ?? 0;
    if (have <= 0) continue;
    const sell = Math.min(have, ratePerOre);
    const price = state.orePrices[id] ?? ORES[id].minPrice;
    state.credits += sell * price;
    colony.oreStock[id] = have - sell;
  }
}

const MISSILE_SILO_CYCLE_DAYS = 8;
const PLAYER_MISSILE_CAP_PER_TYPE = 20;

function missileSiloTick(colony: Colony) {
  const silos = colony.buildings.filter((b) => defOf(b).category === 'missileSilo' && b.powered && b.hp > 0);
  for (const silo of silos) {
    if (!silo.selectedMissileType) continue;
    silo.fireProgressDays += 1;
    if (silo.fireProgressDays < MISSILE_SILO_CYCLE_DAYS) continue;
    silo.fireProgressDays = 0;
    const have = colony.missileStock[silo.selectedMissileType] ?? 0;
    if (have < PLAYER_MISSILE_CAP_PER_TYPE) colony.missileStock[silo.selectedMissileType] = have + 1;
  }
}

function repairTick(colony: Colony) {
  const repairFacilities = colony.buildings.filter((b) => defOf(b).category === 'repair' && b.powered).length;
  if (repairFacilities === 0) return;
  for (const b of colony.buildings) {
    if (b.hp < b.maxHp) b.hp = Math.min(b.maxHp, b.hp + repairFacilities);
  }
}

function constructionTick(colony: Colony) {
  for (const order of [...colony.constructionQueue]) {
    order.daysRemaining -= 1;
    if (order.daysRemaining <= 0) {
      const def = BUILDINGS[order.buildingDefId];
      colony.buildings.push({
        uid: nextUid('bld'), defId: def.id, hp: def.hp, maxHp: def.hp, powered: true,
        mineProgressDays: 0, secondGen: false, fireProgressDays: 0, optimized: false, active: true,
      });
      colony.constructionQueue = colony.constructionQueue.filter((o) => o.uid !== order.uid);
    }
  }
}

export function populationTick(colony: Colony, rng: Rng, deaths: number) {
  colony.population = Math.max(0, colony.population - deaths);
  if (colony.population <= 0) return;
  if (rng.chance(0.40)) colony.population += 1;
  if (rng.chance(0.10)) colony.population = Math.max(0, colony.population - 1);
}

export function dailyTickPlayerColony(colony: Colony, asteroid: Asteroid, state: GameState, rng: Rng) {
  if (!colony.founded || colony.population <= 0) return;

  applyPowerPriority(colony, asteroid);
  updateRadiation(colony, asteroid);

  const air = lifeSupportTick(colony, 'lifeSupportAir', 'airStock');
  const food = lifeSupportTick(colony, 'lifeSupportFood', 'foodStock');
  const water = lifeSupportTick(colony, 'lifeSupportWater', 'waterStock');
  colony.airState = air.state; colony.foodState = food.state; colony.waterState = water.state;
  let deaths = air.deaths + food.deaths + water.deaths;

  if ([air.state, food.state, water.state].filter((s) => s === 'critical').length > 0) {
    colony.unrest += 2 * [air.state, food.state, water.state].filter((s) => s === 'critical').length;
  }

  const medCentres = countMedicalCentres(colony);
  const effectiveRad = colony.radiationPercent * Math.pow(1 - 0.10, medCentres);
  if (rng.chance(radiationLossChancePct(effectiveRad) / 100)) {
    deaths += effectiveRad >= 90 ? rng.int(1, 3) : 1;
  }

  if (colony.virusOutbreak) {
    const needed = requiredCentres(colony.population);
    if (medCentres >= needed && needed > 0) colony.virusOutbreak = false;
    else deaths += 2;
  }

  const secNeeded = requiredCentres(colony.population);
  const secHave = countSecurityCentres(colony);
  if (secHave < secNeeded) colony.unrest += (secNeeded - secHave);
  else colony.unrest = Math.max(0, colony.unrest - 1);

  if (colony.unrest >= 100) {
    deaths += Math.ceil(colony.population * 0.05);
    colony.unrest -= 50;
  }

  populationTick(colony, rng, deaths);

  mineTick(colony, asteroid);
  if (colony.owner === 'player') {
    exportOreTick(colony, state);
    state.credits += 100 + colony.population * 2;
  }
  missileSiloTick(colony);
  repairTick(colony);
  constructionTick(colony);
}

export { storageCapacity, requiredCentres, countMedicalCentres, countSecurityCentres };
