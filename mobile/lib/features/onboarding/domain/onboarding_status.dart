/// Whether this install has already shown the intro slides.
///
/// `loading` exists because the answer lives in secure storage (async) —
/// the router shows the splash until it is known, so a returning user
/// never sees the slides flash before the login screen.
enum OnboardingStatus { loading, unseen, seen }
