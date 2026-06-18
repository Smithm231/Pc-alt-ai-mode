import { ORES, ORE_IDS, rollOrePrice } from '../data/ores';
import type { Rng } from './rng';
import type { GameState } from './types';

export function rollAllOrePrices(rng: Rng): Record<string, number> {
  const prices: Record<string, number> = {};
  for (const id of ORE_IDS) prices[id] = rollOrePrice(ORES[id], rng);
  return prices;
}

/** Prices recalculate on day 1 of every in-game year. */
export function maybeRerollPrices(state: GameState, rng: Rng) {
  const dayOfYear = Math.floor(state.day) % 360;
  if (dayOfYear === 0) {
    state.orePrices = rollAllOrePrices(rng);
  }
}

/** Top up the four spending pools from the day's income, per budget sliders. */
export function applyBudgetAllocation(state: GameState, dailyIncome: number) {
  const a = state.budgetAllocation;
  const total = a.reserve + a.construction + a.vehicles + a.intelligence + a.missiles;
  if (total <= 0) return;
  state.budgetPools.construction += dailyIncome * (a.construction / total);
  state.budgetPools.vehicles += dailyIncome * (a.vehicles / total);
  state.budgetPools.intelligence += dailyIncome * (a.intelligence / total);
  state.budgetPools.missiles += dailyIncome * (a.missiles / total);
}
