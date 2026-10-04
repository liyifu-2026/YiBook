// SM-2 复习调度（书房管家的排期引擎；FSRS 端口留给优化路径，接口保持一致）。
// quality: 0-2 = 没记住（重学），3 = 想起来了但费劲，4 = 记得，5 = 秒答。

export interface ReviewCard {
  ease: number;
  intervalDays: number;
  reps: number;
  dueAt: number;
}

const DAY = 86400000;
const EASE_MIN = 1.3;

export function newCard(now: number): ReviewCard {
  const c: ReviewCard = { ease: 2.5, intervalDays: 0, reps: 0, dueAt: now };
  return c;
}

export function reviewCard(card: ReviewCard, quality: number, now: number): ReviewCard {
  let ease = card.ease;
  let reps = card.reps;
  let intervalDays: number;
  if (quality < 3) {
    ease = Math.max(EASE_MIN, ease - 0.2);
    reps = 0;
    intervalDays = 1;
  } else {
    ease = Math.max(EASE_MIN, ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)));
    reps = reps + 1;
    if (reps === 1) {
      intervalDays = 1;
    } else if (reps === 2) {
      intervalDays = 6;
    } else {
      intervalDays = Math.round(card.intervalDays * ease);
    }
  }
  const c: ReviewCard = {
    ease: ease,
    intervalDays: intervalDays,
    reps: reps,
    dueAt: now + intervalDays * DAY
  };
  return c;
}
