# 07 — AI Architecture (Phase 23, post core-stability)

AI is implemented only after core CRM + calling (Phases 1–22) are stable — this document defines the target shape so later phases don't require re-architecture, not something built now.

## 1. Ownership

Python backend owns **all** AI orchestration. Flutter is a consumer of AI *results* only — it never calls an AI provider directly and never holds an AI provider key.

## 2. Pipeline

```
Call ends -> call_recordings row (status: ready, if recording succeeded)
  -> background worker picks up recording
    -> transcription (AI provider, via backend integrations/ai/)
      -> transcript stored (Storage or DB text column, workspace-scoped)
        -> summary generation
        -> sentiment analysis
        -> action-item extraction
        -> call scoring / quality analysis
      -> results written to a call-analysis table (added in Phase 23, not before)
      -> notification: "AI summary ready for call with {lead}"
```

Every stage is independently retriable and independently nullable — a transcription failure doesn't block summary-of-notes-only fallback where feasible, and never blocks core call logging (which already happened in Phase 9-21).

## 3. Planned Capabilities

- Call transcription
- Call summary
- Sentiment
- Action items
- Call scoring / quality analysis
- AI assistant (chat-style, scoped to a rep's own leads/calls — permission-checked like any other data access)
- Lead insights
- Follow-up suggestions

## 4. Architecture Constraints Carried Forward From Now

- AI results are always additive/advisory — never silently overwrite rep-entered data (e.g., an AI-suggested follow-up is a suggestion the rep accepts, not an auto-created follow-up without confirmation, unless a future workspace setting explicitly opts in).
- All AI processing happens in background workers (Phase 3 architecture), never synchronously in a request.
- AI provider key(s) live only in backend `.env`/secret store.
- Any AI-generated content stored in the DB remains workspace-scoped and RLS-protected like any other CRM data — no shared/global AI cache across tenants.
