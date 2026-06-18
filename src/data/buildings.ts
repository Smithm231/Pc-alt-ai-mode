import type { OreId } from './ores';

export type BuildingCategory =
  | 'core'
  | 'housing'
  | 'power'
  | 'lifeSupportAir'
  | 'lifeSupportFood'
  | 'lifeSupportWater'
  | 'mining'
  | 'storage'
  | 'security'
  | 'medical'
  | 'decon'
  | 'turret'
  | 'antiMissile'
  | 'screen'
  | 'missileSilo'
  | 'repair'
  | 'shipyardSmall'
  | 'shipyardLarge'
  | 'landingPad'
  | 'asteroidEngines'
  | 'gravityNullifier';

export interface BuildingDef {
  id: string;
  name: string;
  category: BuildingCategory;
  costCredits: number;
  costOre?: Partial<Record<OreId, number>>;
  hp: number;
  powerConsumption: number;
  workers: number;
  buildDays: number;
  requires?: string; // building id prerequisite
  maxPerColony?: number;
  // Category-specific numeric payloads, interpreted by sim/colony.ts
  capacity?: number; // housing pop, storage ore units, etc.
  outputPerDay?: number; // life support units/day at full pop coverage
  damage?: number;
  damageOptimized?: number;
  fireEveryDays?: number;
  interceptBase?: number;
  interceptPerPod?: number;
  interceptCap?: number;
  radiationReduction?: number; // multiplicative fraction removed while active
  protected?: boolean;
}

export const BUILDINGS: Record<string, BuildingDef> = {
  command_centre: {
    id: 'command_centre', name: 'Command Centre', category: 'core',
    costCredits: 50_000, hp: 60, powerConsumption: 5, workers: 8, buildDays: 20,
    maxPerColony: 1,
  },
  cpu: {
    id: 'cpu', name: 'CPU', category: 'core',
    costCredits: 20_000, hp: 40, powerConsumption: 3, workers: 0, buildDays: 10,
    maxPerColony: 1,
  },
  living_quarters: {
    id: 'living_quarters', name: 'Living Quarters', category: 'housing',
    costCredits: 10_000, costOre: { crystalite: 20 }, hp: 50, powerConsumption: 2, workers: 0,
    buildDays: 12, capacity: 50,
  },
  protected_resiblock: {
    id: 'protected_resiblock', name: 'Protected Resiblock', category: 'housing',
    costCredits: 22_000, costOre: { crystalite: 40, barium: 20 }, hp: 80, powerConsumption: 3, workers: 0,
    buildDays: 18, capacity: 50, protected: true,
  },
  solar_generator: {
    id: 'solar_generator', name: 'Powerplant', category: 'power',
    costCredits: 30_000, hp: 40, powerConsumption: 0, workers: 0, buildDays: 16,
    outputPerDay: 32, // MW per unmined unit of Asteros present, capped by deposit
  },
  protected_solar_matrix: {
    id: 'protected_solar_matrix', name: 'Protected Solar Matrix', category: 'power',
    costCredits: 48_000, hp: 70, powerConsumption: 0, workers: 0, buildDays: 22,
    outputPerDay: 32, protected: true,
  },
  hydroponics: {
    id: 'hydroponics', name: 'Hydroponics', category: 'lifeSupportFood',
    costCredits: 15_000, hp: 35, powerConsumption: 4, workers: 0, buildDays: 14, outputPerDay: 50,
  },
  life_support: {
    id: 'life_support', name: 'Life Support', category: 'lifeSupportAir',
    costCredits: 15_000, hp: 35, powerConsumption: 4, workers: 0, buildDays: 14, outputPerDay: 50,
  },
  protected_environment_control: {
    id: 'protected_environment_control', name: 'Protected Environment Control', category: 'lifeSupportAir',
    costCredits: 28_000, hp: 60, powerConsumption: 5, workers: 0, buildDays: 18, outputPerDay: 50, protected: true,
  },
  hydration_plant: {
    id: 'hydration_plant', name: 'Hydration Plant', category: 'lifeSupportWater',
    costCredits: 15_000, hp: 35, powerConsumption: 4, workers: 0, buildDays: 14, outputPerDay: 50,
  },
  mine: {
    id: 'mine', name: 'Mine', category: 'mining',
    costCredits: 12_000, hp: 30, powerConsumption: 3, workers: 8, buildDays: 10,
  },
  deep_bore_mine: {
    id: 'deep_bore_mine', name: 'Deep Bore Mine', category: 'mining',
    costCredits: 28_000, hp: 35, powerConsumption: 6, workers: 8, buildDays: 20,
  },
  seismic_penetrator: {
    id: 'seismic_penetrator', name: 'Seismic Penetrator', category: 'mining',
    costCredits: 60_000, hp: 40, powerConsumption: 10, workers: 8, buildDays: 30,
  },
  storage_facility: {
    id: 'storage_facility', name: 'Storage Facility', category: 'storage',
    costCredits: 8_000, hp: 30, powerConsumption: 1, workers: 0, buildDays: 8, capacity: 500,
  },
  security_centre: {
    id: 'security_centre', name: 'Security Centre', category: 'security',
    costCredits: 18_000, hp: 30, powerConsumption: 3, workers: 0, buildDays: 12, capacity: 100,
  },
  medical_centre: {
    id: 'medical_centre', name: 'Medical Centre', category: 'medical',
    costCredits: 22_000, hp: 30, powerConsumption: 4, workers: 0, buildDays: 14,
    radiationReduction: 0.10, capacity: 100,
  },
  decontamination_filter: {
    id: 'decontamination_filter', name: 'Decontamination Filter', category: 'decon',
    costCredits: 25_000, hp: 30, powerConsumption: 5, workers: 0, buildDays: 16, radiationReduction: 0.30,
  },
  laser_turret: {
    id: 'laser_turret', name: 'Laser Turret', category: 'turret',
    costCredits: 9_000, hp: 25, powerConsumption: 2, workers: 0, buildDays: 8,
    damage: 2, damageOptimized: 4, fireEveryDays: 5,
  },
  plasma_turret: {
    id: 'plasma_turret', name: 'Plasma Turret', category: 'turret',
    costCredits: 20_000, hp: 30, powerConsumption: 4, workers: 0, buildDays: 14,
    damage: 5, damageOptimized: 10, fireEveryDays: 5,
  },
  photon_turret: {
    id: 'photon_turret', name: 'Photon Turret', category: 'turret',
    costCredits: 40_000, hp: 35, powerConsumption: 6, workers: 0, buildDays: 20,
    damage: 8, damageOptimized: 16, fireEveryDays: 5,
  },
  anti_missile_pod: {
    id: 'anti_missile_pod', name: 'Anti-Missile Pod', category: 'antiMissile',
    costCredits: 15_000, hp: 20, powerConsumption: 2, workers: 0, buildDays: 10,
    interceptBase: 0.21, interceptPerPod: 0.02, interceptCap: 0.71,
  },
  screen_generator: {
    id: 'screen_generator', name: 'Screen Generator', category: 'screen',
    costCredits: 50_000, hp: 40, powerConsumption: 8, workers: 0, buildDays: 25,
    maxPerColony: 1, damage: 50, // damage field reused as % reduction (50%)
  },
  missile_silo: {
    id: 'missile_silo', name: 'Missile Silo', category: 'missileSilo',
    costCredits: 35_000, hp: 35, powerConsumption: 5, workers: 8, buildDays: 18,
  },
  repair_facility: {
    id: 'repair_facility', name: 'Repair Facility', category: 'repair',
    costCredits: 30_000, hp: 30, powerConsumption: 4, workers: 0, buildDays: 16,
  },
  construction_yard: {
    id: 'construction_yard', name: 'Construction Yard', category: 'shipyardSmall',
    costCredits: 40_000, hp: 35, powerConsumption: 5, workers: 8, buildDays: 22, maxPerColony: 64,
  },
  space_dock: {
    id: 'space_dock', name: 'Orbital Space Dock', category: 'shipyardLarge',
    costCredits: 120_000, hp: 60, powerConsumption: 10, workers: 8, buildDays: 35,
    requires: 'command_centre',
  },
  landing_pad: {
    id: 'landing_pad', name: 'Landing Pad', category: 'landingPad',
    costCredits: 6_000, hp: 20, powerConsumption: 1, workers: 0, buildDays: 6,
  },
  asteroid_engines: {
    id: 'asteroid_engines', name: 'Asteroid Engines', category: 'asteroidEngines',
    costCredits: 80_000, hp: 30, powerConsumption: 7, workers: 0, buildDays: 30, maxPerColony: 1,
  },
  gravity_nullifier: {
    id: 'gravity_nullifier', name: 'Gravity Nullifier', category: 'gravityNullifier',
    costCredits: 45_000, hp: 30, powerConsumption: 6, workers: 0, buildDays: 20, maxPerColony: 1,
  },
};

export const BUILDING_IDS = Object.keys(BUILDINGS);

/** Power fails in this order (first to last) when supply is insufficient. */
export const POWER_PRIORITY: BuildingCategory[] = [
  'asteroidEngines',
  'gravityNullifier',
  'shipyardLarge',
  'shipyardSmall',
  'missileSilo',
  'turret',
  'antiMissile',
  'screen',
  'mining',
  'decon',
  'medical',
  'repair',
  'security',
  'storage',
  'landingPad',
  'lifeSupportWater',
  'lifeSupportFood',
  'lifeSupportAir',
  'housing',
  'power',
  'core',
];
