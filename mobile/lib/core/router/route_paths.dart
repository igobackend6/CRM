class RoutePaths {
  RoutePaths._();

  static const String root = '/';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String workspace = '/workspace';
  static const String app = '/app';

  // Phase 5 — Lead Management.
  static const String leads = '/app/leads';
  static const String leadCreate = '/app/leads/create';
  static String leadDetail(String id) => '/app/leads/$id';
  static String leadEdit(String id) => '/app/leads/$id/edit';

  // Phase 12 — Lead Pipeline & Sales Funnel.
  static const String pipeline = '/app/pipeline';

  // Phase 7 — Follow-Up & Task Management.
  static const String followUps = '/app/follow-ups';
  static const String followUpCreate = '/app/follow-ups/create';
  static String followUpDetail(String id) => '/app/follow-ups/$id';
  static String followUpEdit(String id) => '/app/follow-ups/$id/edit';

  /// `/app/follow-ups/create` needs to know which lead it's for — there
  /// is no lead picker in this phase (§13's minimalism), so creation is
  /// only reachable from a lead's own follow-up section, which passes
  /// leadId as a query parameter.
  static String followUpCreateForLead(String leadId) => '/app/follow-ups/create?leadId=$leadId';

  // Phase 8 — Customer 360 & Unified Interaction Timeline. `id` is an
  // existing leads.id (a customer IS a lead with is_customer=true) —
  // there is no separate customer id space. `customers` itself (no id)
  // used to have no screen at all; the bottom nav's Customers tab
  // (below) now gives it one, still just a placeholder pending the real
  // list.
  static const String customers = '/app/customers';
  static String customerDetail(String id) => '/app/customers/$id';

  // Bottom nav (Runo-reference footer, docs/design/design-tokens.md) —
  // Home/Allocations reuse existing routes (app shell, leads); Customers
  // above and Menu here are new landing points the footer needed.
  static const String menu = '/app/menu';

  // The bottom nav's center call FAB (docs/design/design-tokens.md) —
  // a full-screen dialer, matching the reference's own full-screen (no
  // bottom bar) treatment, so declared outside the StatefulShellRoute
  // like Calls/Reports below rather than nested in a branch.
  static const String dialer = '/app/dialer';

  // Phase 9 — Calling & Call Log Foundation.
  static const String calls = '/app/calls';
  static const String callCreate = '/app/calls/create';
  static String callDetail(String id) => '/app/calls/$id';

  /// `/app/calls/create` needs to know which lead it's for — same
  /// minimalism as follow-ups' create route (no lead picker this
  /// phase): creation is only reachable from a lead's own Calls
  /// section, which passes leadId as a query parameter.
  static String callCreateForLead(String leadId) => '/app/calls/create?leadId=$leadId';

  /// "View all calls" from a lead's Calls section (§6) — the same
  /// `/app/calls` screen, server-side filtered to one lead.
  static String callsForLead(String leadId) => '/app/calls?leadId=$leadId';

  // Phase 10 — Notifications & Activity Alerts. No detail/create routes:
  // a notification isn't its own entity to browse — tapping one
  // navigates straight to the existing lead/follow-up/call/customer
  // screen it refers to (§4), reusing the routes above rather than
  // adding a second detail screen.
  static const String notifications = '/app/notifications';

  // Phase 16 — Internal CRM Messaging & Conversation Foundation. No
  // create route: a conversation is always get-or-created from a lead's
  // "Messages" entry point (MessagesEntryButton), never picked from a
  // standalone form — same minimalism as calls'/follow-ups' create
  // routes (no lead picker), just via a GET instead of a form screen.
  static const String messages = '/app/messages';
  static String messageDetail(String conversationId) => '/app/messages/$conversationId';

  // Phase 19 — Rechurn / Re-engagement. No detail/create route: the
  // queue is a filtered view over existing leads, and every action
  // (call, follow-up, status change, Customer 360) reuses an existing
  // detail/create route above rather than a rechurn-specific one.
  static const String rechurn = '/app/rechurn';

  // Phase 21A — Secure Lead Documents + WhatsApp Templates. Documents
  // themselves have no route of their own (they're a section embedded
  // in Lead Detail/Customer 360, like AI insights); message templates
  // are workspace-level configuration, reachable from the WhatsApp send
  // sheet's "Manage templates" action.
  static const String messageTemplates = '/app/message-templates';

  // Phase 21C — Complete Reports & Analytics. One screen with its own
  // internal Personal/Team/Pipeline tabs (see ReportsScreen) rather than
  // three separate routes — there is no per-report deep-link need (no
  // notification or external link ever points at a specific report tab).
  static const String reports = '/app/reports';
}
