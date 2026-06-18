import type { MissileTypeId } from '../missiles';

export interface AlienShipClassDef {
  id: string;
  name: string;
  hardpoints: number;
  weapons: string[]; // weapon ids equipped, length === hardpoints
  armor: number;
  buildDays: number;
}

export interface AlienRaceDef {
  id: string;
  name: string;
  implemented: boolean;
  radiationImmune: boolean;
  needsAirWater: boolean;
  popGrowthPerDay: number;
  popDeclinePerDayWithoutFood: number;
  buildClusterIntervalDays: number;
  buildClusters: string[][];
  survivalCriticalBuildings: string[];
  colonizeIntervalDays: number;
  colonizeChance: number;
  colonyShipColonistCapacity: number;
  colonyOperationalDelayDays: number;
  missileBuildIntervalDays: number;
  missileCapPerType: number;
  missileWeights: Partial<Record<MissileTypeId, number>>;
  missileSensorRange: number;
  retaliationMaxMissiles: number;
  retaliationDelayDaysPerColony: number;
  scoutIntervalDays: number;
  shipClasses: AlienShipClassDef[];
}
