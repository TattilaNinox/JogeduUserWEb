// LexGO payment plan definitions (isolated from legacy functions).
// Keep plan IDs unchanged for backward compatibility with stored data.

const DEFAULT_PLAN_NAME = 'LexGO 30 day open';

const PAYMENT_PLANS = {
  monthly_premium_prepaid: {
    name: DEFAULT_PLAN_NAME,
    price: 4350,
    description: 'Teljes hozzáférés minden funkcióhoz',
    subscriptionDays: 30,
  },
  // legacy alias accepted for backwards compatibility (still maps to canonical)
  monthly_web: {
    name: DEFAULT_PLAN_NAME,
    price: 4350,
    description: 'Teljes hozzáférés minden funkcióhoz',
    subscriptionDays: 30,
  },
};

const CANONICAL_PLAN_ID = {
  monthly_web: 'monthly_premium_prepaid',
  monthly_premium_prepaid: 'monthly_premium_prepaid',
};

module.exports = {
  DEFAULT_PLAN_NAME,
  PAYMENT_PLANS,
  CANONICAL_PLAN_ID,
};


