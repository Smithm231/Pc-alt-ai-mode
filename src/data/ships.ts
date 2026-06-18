import type { OreId } from './ores';

export type ShipClassId =
  | 'scout_ship'
  | 'assault_fighter'
  | 'combat_eagle'
  | 'transporter'
  | 'destructor'
  | 'terminator'
  | 'mobile_space_dock'
  | 'fleet_battleship';

export type Yard = 'shipyardSmall' | 'shipyardLarge';

export interface ShipClassDef {
  id: ShipClassId;
  name: string;
  yard: Yard;
  hardpoints: number;
  armor: number;
  buildDays: number;
  costCredits: number;
  costOre?: Partial<Record<OreId, number>>;
  cargoColonists?: number;
  cargoOre?: number;
  sensorRange?: number; // for scouts
  role: 'recon' | 'combat' | 'colonize' | 'construct';
}

export const SHIP_CLASSES: Record<ShipClassId, ShipClassDef> = {
  scout_ship: {
    id: 'scout_ship', name: 'Scout Ship', yard: 'shipyardSmall',
    hardpoints: 0, armor: 10, buildDays: 15, costCredits: 20_000,
    sensorRange: 24, role: 'recon',
  },
  assault_fighter: {
    id: 'assault_fighter', name: 'Assault Fighter', yard: 'shipyardSmall',
    hardpoints: 1, armor: 15, buildDays: 20, costCredits: 35_000, role: 'combat',
  },
  combat_eagle: {
    id: 'combat_eagle', name: 'Combat Eagle', yard: 'shipyardSmall',
    hardpoints: 2, armor: 20, buildDays: 28, costCredits: 60_000, role: 'combat',
  },
  transporter: {
    id: 'transporter', name: 'Transporter', yard: 'shipyardLarge',
    hardpoints: 0, armor: 25, buildDays: 25, costCredits: 50_000,
    cargoColonists: 200, cargoOre: 500, role: 'colonize',
  },
  destructor: {
    id: 'destructor', name: 'Destructor', yard: 'shipyardLarge',
    hardpoints: 3, armor: 35, buildDays: 45, costCredits: 110_000, role: 'combat',
  },
  terminator: {
    id: 'terminator', name: 'Terminator', yard: 'shipyardLarge',
    hardpoints: 4, armor: 45, buildDays: 60, costCredits: 160_000, role: 'combat',
  },
  mobile_space_dock: {
    id: 'mobile_space_dock', name: 'Space Dock', yard: 'shipyardLarge',
    hardpoints: 2, armor: 50, buildDays: 80, costCredits: 250_000, role: 'construct',
  },
  fleet_battleship: {
    id: 'fleet_battleship', name: 'Fleet Battleship', yard: 'shipyardLarge',
    hardpoints: 6, armor: 60, buildDays: 95, costCredits: 320_000, role: 'combat',
  },
};

export const SHIP_CLASS_IDS = Object.keys(SHIP_CLASSES) as ShipClassId[];

export type FleetOrder = 'move' | 'attackAsteroid' | 'intercept' | 'sentry';

export interface ShipInstance {
  id: string;
  classId: ShipClassId;
  owner: 'player' | string; // alien race id
  hp: number;
  maxHp: number;
  hardpointWeapons: (string | null)[]; // weapon id per slot
  hardpointCooldowns: number[];
  disabledUntilTick: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  targetAsteroidId: string | null;
  fleetId: string;
}
