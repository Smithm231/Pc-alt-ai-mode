import type { AlienRaceDef } from './raceTypes';
import { KLL_KP_QUA } from './kllKpQua';

/**
 * Race registry. Only Kll-Kp-Qua is fully implemented; the other five
 * documented races are stubbed here with placeholder stats so the same
 * generic AlienAI controller can drive them once their data is filled in
 * (see ./kllKpQua.ts for the pattern to follow).
 */
function stub(id: string, name: string): AlienRaceDef {
  return {
    ...KLL_KP_QUA,
    id,
    name,
    implemented: false,
  };
}

export const ALIEN_RACES: Record<string, AlienRaceDef> = {
  kll_kp_qua: KLL_KP_QUA,
  ore_eaters: stub('ore_eaters', 'Ore Eaters'),
  ax_zilanths: stub('ax_zilanths', "Ax'Zilanths"),
  tylarans: stub('tylarans', 'Tylarans'),
  rigellians: stub('rigellians', 'Rigellians'),
  swixarans: stub('swixarans', 'Swixarans'),
};

export const IMPLEMENTED_RACE_IDS = Object.values(ALIEN_RACES)
  .filter((r) => r.implemented)
  .map((r) => r.id);
