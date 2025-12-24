/// Central, canonical payment plan definitions and helpers.
///
/// Goal: avoid scattered hardcoded plan names/aliases across the app.
class PlanMeta {
  final String id;
  final String displayName;
  final int priceHuf;
  final int subscriptionDays;

  const PlanMeta({
    required this.id,
    required this.displayName,
    required this.priceHuf,
    required this.subscriptionDays,
  });
}

// Canonical plan IDs (do not rename: backward compatibility with stored data).
const String kPlanIdMonthlyPremiumPrepaid = 'monthly_premium_prepaid';
const String kPlanIdMonthlyWeb = 'monthly_web';

// Canonical display name (user-facing + billing).
const String kPlanNameLexgo30DayOpen = 'LexGO 30 day open';

// Alias -> canonical mapping.
const Map<String, String> kCanonicalPlanId = {
  kPlanIdMonthlyWeb: kPlanIdMonthlyPremiumPrepaid,
  kPlanIdMonthlyPremiumPrepaid: kPlanIdMonthlyPremiumPrepaid,
};

/// Returns the canonical planId for any known alias.
String canonicalPlanId(String rawPlanId) {
  return kCanonicalPlanId[rawPlanId] ?? rawPlanId;
}

/// Plan catalog.
///
/// Note: we keep both IDs here for display convenience; canonicalization is
/// still preferred for storage/processing.
const Map<String, PlanMeta> kPaymentPlans = {
  kPlanIdMonthlyPremiumPrepaid: PlanMeta(
    id: kPlanIdMonthlyPremiumPrepaid,
    displayName: kPlanNameLexgo30DayOpen,
    priceHuf: 4350,
    subscriptionDays: 30,
  ),
  kPlanIdMonthlyWeb: PlanMeta(
    id: kPlanIdMonthlyWeb,
    displayName: kPlanNameLexgo30DayOpen,
    priceHuf: 4350,
    subscriptionDays: 30,
  ),
};

PlanMeta? paymentPlanMeta(String planId) => kPaymentPlans[planId];

/// Returns the user-facing plan name for a given planId (supports aliases).
String displayPlanName(String planId) {
  final canonical = canonicalPlanId(planId);
  return paymentPlanMeta(canonical)?.displayName ?? planId;
}
