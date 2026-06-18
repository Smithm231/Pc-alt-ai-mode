// Ore tiers and pricing, derived from documented K240 mechanics:
// - Selenium: price range 20-115 CR
// - Nexos: price range 100,000-498,400 CR
// - Prices recalculate on day 1 of every in-game year (360 days)
// - price = minPrice + variance * rand(0..249)
// Intermediate ore tiers are interpolated geometrically between these two
// documented endpoints to keep the 10-ore economy internally consistent.

export type OreId =
  | 'selenium'
  | 'asteros'
  | 'barium'
  | 'crystalite'
  | 'quazinc'
  | 'bytanium'
  | 'korellium'
  | 'dragonium'
  | 'traxium'
  | 'nexos';

export type MinerType = 'mine' | 'deepBoreMine' | 'seismicPenetrator';

export interface OreDef {
  id: OreId;
  name: string;
  rank: number; // 1 (common) .. 10 (rarest)
  minPrice: number;
  priceVariance: number;
  spawnChance: number; // chance an asteroid generates a deposit of this ore
  minerType: MinerType;
  /** Contributes to colony radiation: 10% per `radiationUnit` units unmined. */
  radiationUnit?: number;
}

const RANKS = 10;
const SELENIUM_MIN = 20;
const NEXOS_MIN = 100_000;
const SELENIUM_VAR = (115 - 20) / 249;
const NEXOS_VAR = (498_400 - 100_000) / 249;

const priceRatio = Math.pow(NEXOS_MIN / SELENIUM_MIN, 1 / (RANKS - 1));
const varRatio = Math.pow(NEXOS_VAR / SELENIUM_VAR, 1 / (RANKS - 1));

function tierPrice(rank: number) {
  return SELENIUM_MIN * Math.pow(priceRatio, rank - 1);
}
function tierVariance(rank: number) {
  return SELENIUM_VAR * Math.pow(varRatio, rank - 1);
}

interface OreSeed {
  id: OreId;
  name: string;
  rank: number;
  minerType: MinerType;
  spawnChance: number;
  radiationUnit?: number;
}

const SEEDS: OreSeed[] = [
  { id: 'selenium', name: 'Selenium', rank: 1, minerType: 'mine', spawnChance: 0.8 },
  { id: 'asteros', name: 'Asteros', rank: 2, minerType: 'mine', spawnChance: 0.8, radiationUnit: 100 },
  { id: 'barium', name: 'Barium', rank: 3, minerType: 'mine', spawnChance: 0.8 },
  { id: 'crystalite', name: 'Crystalite', rank: 4, minerType: 'mine', spawnChance: 0.8 },
  { id: 'quazinc', name: 'Quazinc', rank: 5, minerType: 'deepBoreMine', spawnChance: 0.6 },
  { id: 'bytanium', name: 'Bytanium', rank: 6, minerType: 'deepBoreMine', spawnChance: 0.6 },
  { id: 'korellium', name: 'Korellium', rank: 7, minerType: 'deepBoreMine', spawnChance: 0.5 },
  { id: 'dragonium', name: 'Dragonium', rank: 8, minerType: 'deepBoreMine', spawnChance: 0.5 },
  { id: 'traxium', name: 'Traxium', rank: 9, minerType: 'seismicPenetrator', spawnChance: 0.3, radiationUnit: 2 },
  { id: 'nexos', name: 'Nexos', rank: 10, minerType: 'seismicPenetrator', spawnChance: 0.2, radiationUnit: 1 },
];

export const ORES: Record<OreId, OreDef> = Object.fromEntries(
  SEEDS.map((s) => [
    s.id,
    {
      ...s,
      minPrice: Math.round(tierPrice(s.rank)),
      priceVariance: tierVariance(s.rank),
    },
  ]),
) as Record<OreId, OreDef>;

export const ORE_IDS = SEEDS.map((s) => s.id);

export const HOME_ASTEROID_ORE: Partial<Record<OreId, number>> = {
  selenium: 250,
  asteros: 300,
};

export function rollOrePrice(ore: OreDef, rng: { int(min: number, max: number): number }): number {
  return Math.round(ore.minPrice + ore.priceVariance * rng.int(0, 249));
}

export const MINER_DEFS: Record<MinerType, { name: string; cycleDays: number; cycleDays2ndGen: number; workers: number }> = {
  mine: { name: 'Mine', cycleDays: 4, cycleDays2ndGen: 2, workers: 8 },
  deepBoreMine: { name: 'Deep Bore Mine', cycleDays: 16, cycleDays2ndGen: 8, workers: 8 },
  seismicPenetrator: { name: 'Seismic Penetrator', cycleDays: 16, cycleDays2ndGen: 16, workers: 8 },
};
