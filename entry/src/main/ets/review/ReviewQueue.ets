import { newCard, reviewCard, ReviewCard } from './Review';

// 书房管家·复习队列：圈选提问的问答沉淀为测验卡，SM-2 排期。
// 纯逻辑；持久化（review.json）在视图层。

export interface QuizCard {
  id: string;
  bookTitle: string;
  page: number;
  question: string;
  answer: string;
  card: ReviewCard;
}

export class ReviewQueue {
  private cards: Map<string, QuizCard> = new Map();

  load(cards: Array<QuizCard>): void {
    this.cards = new Map();
    for (const c of cards) {
      this.cards.set(c.id, c);
    }
  }

  all(): Array<QuizCard> {
    const out: Array<QuizCard> = [];
    for (const c of this.cards.values()) {
      out.push(c);
    }
    return out;
  }

  count(): number {
    return this.cards.size;
  }

  addQuiz(id: string, bookTitle: string, page: number, question: string, answer: string,
    now: number): QuizCard {
    const existing = this.cards.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const card: QuizCard = {
      id: id,
      bookTitle: bookTitle,
      page: page,
      question: question,
      answer: answer,
      card: newCard(now)
    };
    this.cards.set(id, card);
    return card;
  }

  due(now: number): Array<QuizCard> {
    const out: Array<QuizCard> = [];
    for (const c of this.cards.values()) {
      if (c.card.dueAt <= now) {
        out.push(c);
      }
    }
    out.sort((a, b) => a.card.dueAt - b.card.dueAt);
    return out;
  }

  dueCount(now: number): number {
    return this.due(now).length;
  }

  grade(id: string, quality: number, now: number): void {
    const c = this.cards.get(id);
    if (c === undefined) {
      return;
    }
    c.card = reviewCard(c.card, quality, now);
  }
}
