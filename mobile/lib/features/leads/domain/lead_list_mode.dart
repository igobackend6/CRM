/// Which of the two tabs a `LeadListScreen` is serving.
///
/// * [allocations] — every lead the member can see: a plain "Allocations" title with a search icon.
/// * [customers] — only leads converted to customers, with the full header (status selector, search,
///   filters, pipeline board, more) that used to be on Allocations.
enum LeadListMode { allocations, customers }
