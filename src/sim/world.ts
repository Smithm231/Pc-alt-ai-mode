import { Rng } from './rng';
import type { GameState, Fleet } from './types';
import { TICKS_PER_DAY } from './types';
import { generateField, createHomeAsteroid, createAlienHomeAsteroid, FIELD_SIZE } from './asteroidField';
import { stepAsteroidDrift } from './asteroidField';
import { createColony, foundColony, dailyTickPlayerColony, nextUid } from './colony';
import { foundAlienColony, dailyTickAlienColony, triggerRetaliation } from './alienAI';
import { spawnShip, tickFleetMovement } from './fleet';
import { tickShipCombat, dailyTurretDefense, resolveMissileArrivals } from './combat';
import { maybeRerollPrices, applyBudgetAllocation, rollAllOrePrices } from './economy';
import { ALIEN_RACES, IMPLEMENTED_RACE_IDS } from '../data/aliens';

const FIELD_ASTEROID_COUNT = 18;
const STARTING_CREDITS = 400_000;

export function initGame(seed: number): GameState {
  const rng = new Rng(seed);
  const state: GameState = {
    rngSeed: seed,
    day: 0,
    tickCounter: 0,
    year: 0,
    paused: false,
    speed: 1,
    credits: STARTING_CREDITS,
    budgetAllocation: { reserve: 40, construction: 25, vehicles: 20, intelligence: 5, missiles: 10 },
    budgetPools: { construction: 0, vehicles: 0, intelligence: 0, missiles: 0 },
    orePrices: rollAllOrePrices(rng),
    asteroids: {},
    colonies: {},
    ships: {},
    fleets: {},
    missilesInFlight: [],
    intel: {},
    activeAlienRaceIds: IMPLEMENTED_RACE_IDS.slice(0, 1),
    log: [],
    selectedAsteroidId: null,
    selectedFleetId: null,
    gameOver: null,
  };

  const home = createHomeAsteroid(rng, FIELD_SIZE * 0.15, FIELD_SIZE * 0.5, 0);
  state.asteroids[home.id] = home;

  const alienRaceId = state.activeAlienRaceIds[0];
  const alienHome = createAlienHomeAsteroid(rng, FIELD_SIZE * 0.85, FIELD_SIZE * 0.5, 1, `${ALIEN_RACES[alienRaceId].name} Hive`);
  state.asteroids[alienHome.id] = alienHome;

  const { asteroids: field } = generateField(rng, FIELD_ASTEROID_COUNT);
  for (const a of field) state.asteroids[a.id] = a;

  const playerColony = createColony(nextUid('colony'), home.id, 'player');
  state.colonies[playerColony.id] = playerColony;
  home.colonyId = playerColony.id;
  foundColony(playerColony, 50, true);

  const alienOwnerId = alienRaceId;
  const alienColony = createColony(nextUid('colony'), alienHome.id, alienOwnerId);
  foundAlienColony(alienColony, alienRaceId);
  state.colonies[alienColony.id] = alienColony;
  alienHome.colonyId = alienColony.id;

  spawnShip(state, 'player', 'transporter', home.id);

  state.log.push({ day: 0, text: `Sector K240 colonized. First contact: ${ALIEN_RACES[alienRaceId].name}.` });

  return state;
}

function runDailyEvents(state: GameState, rng: Rng) {
  for (const asteroid of Object.values(state.asteroids)) stepAsteroidDrift(asteroid, 1);

  maybeRerollPrices(state, rng);

  const incomeBefore = state.credits;
  for (const colony of Object.values(state.colonies)) {
    const asteroid = state.asteroids[colony.asteroidId];
    if (!asteroid) continue;
    if (colony.owner === 'player') dailyTickPlayerColony(colony, asteroid, state, rng);
    else dailyTickAlienColony(colony, asteroid, state, rng);
  }
  const dailyIncome = Math.max(0, state.credits - incomeBefore);
  applyBudgetAllocation(state, dailyIncome);

  for (const colony of Object.values(state.colonies)) {
    if (colony.owner !== 'player') continue;
    for (const order of [...colony.shipBuildQueue]) {
      order.daysRemaining -= 1;
      if (order.daysRemaining <= 0) {
        spawnShip(state, 'player', order.shipClassId as any, colony.asteroidId);
        colony.shipBuildQueue = colony.shipBuildQueue.filter((o) => o.uid !== order.uid);
      }
    }
  }

  dailyTurretDefense(state, rng);
  resolveMissileArrivals(state, rng);

  for (const colony of Object.values(state.colonies)) {
    if (colony.owner === 'player' || !colony.alienRaceId) continue;
    const asteroid = state.asteroids[colony.asteroidId];
    if (!asteroid) continue;
    const sensorRange = ALIEN_RACES[colony.alienRaceId].missileSensorRange;
    const incoming = state.missilesInFlight.some((m) => m.targetColonyId === colony.id && m.ownerId === 'player');
    if (incoming && sensorRange > 0) triggerRetaliation(state, colony.owner, colony.alienRaceId);
  }

  checkGameOver(state);
  state.year = Math.floor(state.day / 360);
}

function checkGameOver(state: GameState) {
  if (state.gameOver) return;
  const playerAlive = Object.values(state.colonies).some((c) => c.owner === 'player' && c.founded && c.population > 0);
  const playerHasShips = Object.values(state.ships).some((s) => s.owner === 'player');
  if (!playerAlive && !playerHasShips) {
    state.gameOver = 'lost';
    return;
  }
  const aliensAlive = Object.values(state.colonies).some(
    (c) => c.owner !== 'player' && c.founded && c.population > 0,
  );
  if (!aliensAlive && Object.keys(state.colonies).some((id) => state.colonies[id].owner !== 'player')) {
    state.gameOver = 'won';
  }
}

export function tick(state: GameState, rng: Rng) {
  if (state.gameOver || state.paused) return;
  const prevDayFloor = Math.floor(state.day);
  state.tickCounter += 1;
  state.day += 1 / TICKS_PER_DAY;

  tickFleetMovement(state, 1);
  tickShipCombat(state, rng, state.tickCounter);

  const newDayFloor = Math.floor(state.day);
  if (newDayFloor > prevDayFloor) {
    runDailyEvents(state, rng);
  }
}

export function findFleetAt(state: GameState, fleetId: string): Fleet | undefined {
  return state.fleets[fleetId];
}
