// Alien colonies do not use credits; everything is gated by time, matching
// the documented behaviour ("randomly selecting from building clusters
// without requiring currency or resources"). This is a separate, smaller
// building set from the player's, since each race's hive-biology differs.
export type AlienBuildingCategory =
  | 'core' | 'power' | 'food' | 'housing' | 'mining' | 'turret' | 'missileSilo' | 'hibernation';

export interface AlienBuildingDef {
  id: string;
  name: string;
  category: AlienBuildingCategory;
  buildDays: number;
  hp: number;
  damage?: number;
  fireEveryDays?: number;
  capacity?: number;
}

export const KLL_KP_QUA_BUILDINGS: Record<string, AlienBuildingDef> = {
  queens_chamber: { id: 'queens_chamber', name: "Queen's Chamber", category: 'core', buildDays: 40, hp: 100 },
  power_converter: { id: 'power_converter', name: 'Power Converter', category: 'power', buildDays: 14, hp: 35 },
  protein_plant: { id: 'protein_plant', name: 'Protein Plant', category: 'food', buildDays: 14, hp: 35 },
  hive_chamber: { id: 'hive_chamber', name: 'Hive Chamber', category: 'housing', buildDays: 12, hp: 50, capacity: 50 },
  bore_drone_nest: { id: 'bore_drone_nest', name: 'Bore Drone Nest', category: 'mining', buildDays: 16, hp: 30 },
  spike_turret: { id: 'spike_turret', name: 'Spike Turret', category: 'turret', buildDays: 10, hp: 25, damage: 5, fireEveryDays: 5 },
  missile_hatchery: { id: 'missile_hatchery', name: 'Missile Hatchery', category: 'missileSilo', buildDays: 18, hp: 35 },
  hibernation_hive: { id: 'hibernation_hive', name: 'Hibernation Hive', category: 'hibernation', buildDays: 20, hp: 40, capacity: 600 },
};

/** The 7 build clusters the AI randomly samples from every buildClusterIntervalDays. */
export const KLL_KP_QUA_CLUSTERS: string[][] = [
  ['protein_plant'],
  ['power_converter'],
  ['hive_chamber'],
  ['bore_drone_nest'],
  ['spike_turret', 'spike_turret'],
  ['missile_hatchery'],
  ['hibernation_hive'],
];

export const SURVIVAL_CRITICAL = ['protein_plant', 'power_converter'];
