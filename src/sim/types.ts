import type { OreId } from '../data/ores';
import type { MissileTypeId } from '../data/missiles';
import type { ShipInstance, FleetOrder } from '../data/ships';

export const TICKS_PER_DAY = 4;
export const DAYS_PER_YEAR = 360;

export interface AsteroidPoint { x: number; y: number }

export interface Asteroid {
  id: string;
  name: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  shape: AsteroidPoint[]; // irregular polygon, local coords
  ore: Partial<Record<OreId, number>>; // remaining unmined deposits
  colonyId: string | null;
  isHome: boolean;
  layoutIndex: number;
}

export interface BuildingInstance {
  uid: string;
  defId: string;
  hp: number;
  maxHp: number;
  powered: boolean;
  minerTargetOre?: OreId;
  mineProgressDays: number;
  secondGen: boolean;
  fireProgressDays: number;
  optimized: boolean;
  active: boolean; // gravity nullifier / asteroid engines toggle state
  selectedMissileType?: MissileTypeId;
}

export interface ConstructionOrder {
  uid: string;
  buildingDefId: string;
  daysRemaining: number;
}

export interface ShipBuildOrder {
  uid: string;
  shipClassId: string;
  daysRemaining: number;
}

export type PafwState = 'surplus' | 'deficiency' | 'critical';

export interface Colony {
  id: string;
  asteroidId: string;
  owner: 'player' | string;
  buildings: BuildingInstance[];
  constructionQueue: ConstructionOrder[];
  shipBuildQueue: ShipBuildOrder[];
  population: number;
  foodStock: number;
  airStock: number;
  waterStock: number;
  oreStock: Partial<Record<OreId, number>>;
  missileStock: Partial<Record<MissileTypeId, number>>;
  missileBuildProgressDays: number;
  radiationPercent: number;
  unrest: number;
  powerState: PafwState;
  airState: PafwState;
  foodState: PafwState;
  waterState: PafwState;
  virusOutbreak: boolean;
  founded: boolean;
  // Alien-only fields
  alienRaceId?: string;
  alienBuildClusterProgressDays?: number;
  alienColonizeProgressDays?: number;
  alienScoutProgressDays?: number;
  alienOperationalInDays?: number; // counts down after colony ship arrival
  alienShipBuildProgressDays?: number;
  alienAttackProgressDays?: number;
}

export interface Fleet {
  id: string;
  owner: 'player' | string;
  shipIds: string[];
  order: FleetOrder;
  targetAsteroidId: string | null;
  currentAsteroidId: string | null; // set once arrived; null while in transit
  retreatThresholdPct: number; // 0-100
  x: number;
  y: number;
}

export interface MissileSalvo {
  id: string;
  ownerId: 'player' | string;
  targetColonyId: string;
  missileType: import('../data/missiles').MissileTypeId;
  count: number;
  arrivalDay: number;
}

export interface BudgetAllocation {
  reserve: number;
  construction: number;
  vehicles: number;
  intelligence: number;
  missiles: number;
}

export interface BudgetPools {
  construction: number;
  vehicles: number;
  intelligence: number;
  missiles: number;
}

export interface IntelRecord {
  asteroidId: string;
  level: 'none' | 'scout' | 'spysat';
  lastUpdatedDay: number;
}

export interface LogEntry {
  day: number;
  text: string;
}

export interface GameState {
  rngSeed: number;
  day: number; // fractional, advances by 1/TICKS_PER_DAY per tick
  tickCounter: number;
  year: number;
  paused: boolean;
  speed: number; // ticks processed per real frame batch
  credits: number;
  budgetAllocation: BudgetAllocation;
  budgetPools: BudgetPools;
  orePrices: Partial<Record<OreId, number>>;
  asteroids: Record<string, Asteroid>;
  colonies: Record<string, Colony>;
  ships: Record<string, ShipInstance>;
  fleets: Record<string, Fleet>;
  missilesInFlight: MissileSalvo[];
  intel: Record<string, IntelRecord>;
  activeAlienRaceIds: string[];
  log: LogEntry[];
  selectedAsteroidId: string | null;
  selectedFleetId: string | null;
  gameOver: 'won' | 'lost' | null;
}
