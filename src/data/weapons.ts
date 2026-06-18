// Hardpoint weapon modules, with documented damage/hit-chance values from
// the K240 disassembly project where available.
export type WeaponId =
  | 'laser'
  | 'plasma_cannon'
  | 'photon_cannon'
  | 'ion_cannon'
  | 'disruptor'
  | 'napalm_orb'
  | 'chaos_bomb'
  | 'static_inducer'
  | 'warp_generator'
  | 'deflector';

export interface WeaponDef {
  id: WeaponId;
  name: string;
  offensive: boolean;
  damage: number;
  hitChance: number;
  areaEffect?: boolean; // hits a 2x2 cluster of targets
  damageOverTimePerDay?: number;
  damageOverTimeDays?: number;
  disableTicks?: number; // static inducer: disables target's weapons
  cooldownTicks: number; // matches documented 16-tick firing cycle
  costCredits: number;
  costOre: Partial<Record<string, number>>;
}

export const WEAPONS: Record<WeaponId, WeaponDef> = {
  laser: {
    id: 'laser', name: 'Laser', offensive: true, damage: 2, hitChance: 0.30,
    cooldownTicks: 16, costCredits: 4_000, costOre: { selenium: 10 },
  },
  plasma_cannon: {
    id: 'plasma_cannon', name: 'Plasma Cannon', offensive: true, damage: 5, hitChance: 0.30,
    cooldownTicks: 16, costCredits: 9_000, costOre: { barium: 10, quazinc: 5 },
  },
  photon_cannon: {
    id: 'photon_cannon', name: 'Photon Cannon', offensive: true, damage: 8, hitChance: 0.30,
    cooldownTicks: 16, costCredits: 16_000, costOre: { bytanium: 10, korellium: 5 },
  },
  ion_cannon: {
    id: 'ion_cannon', name: 'Ion Cannon', offensive: true, damage: 5, hitChance: 0.50,
    cooldownTicks: 16, costCredits: 14_000, costOre: { crystalite: 12 },
  },
  disruptor: {
    id: 'disruptor', name: 'Disruptor', offensive: true, damage: 5, hitChance: 0.20, areaEffect: true,
    cooldownTicks: 16, costCredits: 18_000, costOre: { dragonium: 8 },
  },
  napalm_orb: {
    id: 'napalm_orb', name: 'Napalm Orb', offensive: true, damage: 4, hitChance: 0.20,
    damageOverTimePerDay: 2, damageOverTimeDays: 5, // 4 + 2*5 = 14 total
    cooldownTicks: 16, costCredits: 20_000, costOre: { traxium: 4 },
  },
  chaos_bomb: {
    id: 'chaos_bomb', name: 'Chaos Bomb', offensive: true, damage: 14, hitChance: 0.20, areaEffect: true,
    cooldownTicks: 16, costCredits: 30_000, costOre: { nexos: 2 },
  },
  static_inducer: {
    id: 'static_inducer', name: 'Static Inducer', offensive: true, damage: 0, hitChance: 0.10,
    disableTicks: 100, cooldownTicks: 16, costCredits: 22_000, costOre: { korellium: 6 },
  },
  warp_generator: {
    id: 'warp_generator', name: 'Warp Generator', offensive: false, damage: 0, hitChance: 0.60,
    cooldownTicks: 16, costCredits: 26_000, costOre: { dragonium: 10 },
  },
  deflector: {
    id: 'deflector', name: 'Deflector', offensive: false, damage: 0, hitChance: 1,
    cooldownTicks: 16, costCredits: 28_000, costOre: { traxium: 6 },
  },
};
