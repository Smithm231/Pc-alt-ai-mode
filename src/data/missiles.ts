import type { OreId } from './ores';

export type MissileTypeId =
  | 'explosive'
  | 'area_explosive'
  | 'scatter'
  | 'napalm'
  | 'virus'
  | 'bioweapon'
  | 'nuclear';

export interface MissileTypeDef {
  id: MissileTypeId;
  name: string;
  /** Relative production weight, matching documented alien missile mix. */
  weight: number;
  buildingDamage: number;
  targetsHit: number; // how many buildings it can damage (area effects)
  populationCasualties?: number;
  radiationIncrease?: number; // flat % added to colony radiation
  triggersVirus?: boolean;
  costCredits: number;
  costOre: Partial<Record<OreId, number>>;
  travelDays: number;
}

export const MISSILE_TYPES: Record<MissileTypeId, MissileTypeDef> = {
  explosive: {
    id: 'explosive', name: 'Explosive Missile', weight: 39,
    buildingDamage: 20, targetsHit: 1,
    costCredits: 8_000, costOre: { selenium: 15 }, travelDays: 3,
  },
  area_explosive: {
    id: 'area_explosive', name: 'Area Explosive Missile', weight: 28,
    buildingDamage: 12, targetsHit: 4,
    costCredits: 14_000, costOre: { barium: 15 }, travelDays: 3,
  },
  scatter: {
    id: 'scatter', name: 'Scatter Missile', weight: 12,
    buildingDamage: 8, targetsHit: 3,
    costCredits: 12_000, costOre: { crystalite: 15 }, travelDays: 3,
  },
  napalm: {
    id: 'napalm', name: 'Napalm Missile', weight: 7,
    buildingDamage: 10, targetsHit: 1,
    costCredits: 18_000, costOre: { traxium: 5 }, travelDays: 4,
  },
  virus: {
    id: 'virus', name: 'Virus Missile', weight: 6,
    buildingDamage: 0, targetsHit: 0, triggersVirus: true,
    costCredits: 25_000, costOre: { korellium: 10 }, travelDays: 4,
  },
  bioweapon: {
    id: 'bioweapon', name: 'Bioweapon Missile', weight: 5,
    buildingDamage: 0, targetsHit: 0, populationCasualties: 10,
    costCredits: 30_000, costOre: { dragonium: 10 }, travelDays: 4,
  },
  nuclear: {
    id: 'nuclear', name: 'Nuclear Missile', weight: 3,
    buildingDamage: 40, targetsHit: 3, radiationIncrease: 15,
    costCredits: 60_000, costOre: { nexos: 3 }, travelDays: 5,
  },
};

export const MISSILE_TYPE_IDS = Object.keys(MISSILE_TYPES) as MissileTypeId[];
