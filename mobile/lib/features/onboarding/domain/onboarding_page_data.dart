/// Which animated illustration a slide shows. Kept as an enum (not a
/// widget) so the slide copy stays plain data that is easy to test.
enum OnboardingIllustrationType { hub, analytics, timeline, followUps, team }

class OnboardingPageData {
  const OnboardingPageData({required this.title, required this.subtitle, required this.illustration});

  final String title;
  final String subtitle;
  final OnboardingIllustrationType illustration;
}

/// The intro slides, in order. Copy only describes what the app does
/// today (see PROJECT_ANALYSIS.md §4) — no promises about features
/// that are not built yet.
const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    title: 'Sales CRM in One App',
    subtitle: 'Leads, calls, follow-ups and customers together in one easy-to-use app',
    illustration: OnboardingIllustrationType.hub,
  ),
  OnboardingPageData(
    title: 'Real-Time Call Analytics',
    subtitle: 'Turn every call into insight with talk time, call trends and conversions at a glance',
    illustration: OnboardingIllustrationType.analytics,
  ),
  OnboardingPageData(
    title: 'Complete Interaction History',
    subtitle: 'Every call, WhatsApp message and note for a customer in a single timeline',
    illustration: OnboardingIllustrationType.timeline,
  ),
  OnboardingPageData(
    title: 'Follow-ups That Get Done',
    subtitle: 'Schedule follow-ups and log the call outcome the moment a call ends',
    illustration: OnboardingIllustrationType.followUps,
  ),
  OnboardingPageData(
    title: 'Track Team Activity',
    subtitle: 'Keep track of talk, idle, break and login time at your fingertips',
    illustration: OnboardingIllustrationType.team,
  ),
];
