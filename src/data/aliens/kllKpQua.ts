import type { AlienRaceDef } from './raceTypes';
import { KLL_KP_QUA_CLUSTERS, SURVIVAL_CRITICAL } from './alienBuildings';

// Race #1: Kll-Kp-Qua — the documented "easiest" default opponent.
// Radiation-immune hive insects; weak missile stockpiles (capped at 5/type);
// slow, predictable scouting; the intended first-contact race.
export const KLL_KP_QUA: AlienRaceDef = {
  id: 'kll_kp_qua',
  name: 'Kll-Kp-Qua',
  implemented: true,
  radiationImmune: true,
  needsAirWater: false,
  popGrowthPerDay: 5,
  popDeclinePerDayWithoutFood: 1,
  buildClusterIntervalDays: 60,
  buildClusters: KLL_KP_QUA_CLUSTERS,
  survivalCriticalBuildings: SURVIVAL_CRITICAL,
  colonizeIntervalDays: 200,
  colonizeChance: 1.0,
  colonyShipColonistCapacity: 200,
  colonyOperationalDelayDays: 40,
  missileBuildIntervalDays: 25,
  missileCapPerType: 5,
  missileWeights: {
    explosive: 39,
    area_explosive: 28,
    scatter: 12,
    napalm: 7,
    virus: 6,
    bioweapon: 5,
    nuclear: 3,
  },
  missileSensorRange: 16,
  retaliationMaxMissiles: 8,
  retaliationDelayDaysPerColony: 12,
  scoutIntervalDays: 70,
  shipClasses: [
    { id: 'kkq_scout', name: 'Kll-Kp-Qua Scout', hardpoints: 0, weapons: [], armor: 10, buildDays: 15 },
    { id: 'kkq_stinger', name: 'Kll-Kp-Qua Stinger', hardpoints: 1, weapons: ['laser'], armor: 17, buildDays: 25 },
    { id: 'kkq_swarmer', name: 'Kll-Kp-Qua Swarmer', hardpoints: 2, weapons: ['laser', 'plasma_cannon'], armor: 24, buildDays: 35 },
    { id: 'kkq_lancer', name: 'Kll-Kp-Qua Lancer', hardpoints: 2, weapons: ['plasma_cannon', 'plasma_cannon'], armor: 31, buildDays: 45 },
    { id: 'kkq_warrior', name: 'Kll-Kp-Qua Warrior', hardpoints: 3, weapons: ['plasma_cannon', 'photon_cannon', 'laser'], armor: 38, buildDays: 55 },
    { id: 'kkq_brood_carrier', name: 'Kll-Kp-Qua Brood Carrier', hardpoints: 0, weapons: [], armor: 45, buildDays: 65 },
    { id: 'kkq_hive_destroyer', name: 'Kll-Kp-Qua Hive Destroyer', hardpoints: 4, weapons: ['photon_cannon', 'photon_cannon', 'plasma_cannon', 'laser'], armor: 52, buildDays: 80 },
    { id: 'kkq_battleship', name: 'Kll-Kp-Qua Battleship', hardpoints: 6, weapons: ['photon_cannon', 'photon_cannon', 'plasma_cannon', 'plasma_cannon', 'laser', 'deflector'], armor: 60, buildDays: 95 },
  ],
};
