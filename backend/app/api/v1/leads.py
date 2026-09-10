from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission, require_workspace_member
from app.schemas.assignment import AllocationOut, AssignmentRequest
from app.schemas.calls import CallOut
from app.schemas.data_ops import (
    BulkLeadAction,
    BulkLeadActionRequest,
    BulkLeadActionResponse,
    LeadImportRequest,
    LeadImportResponse,
)
from app.schemas.customer360 import NoteCreate, TimelineResponse
from app.schemas.followups import FollowUpOut
from app.schemas.leads import (
    InteractionOut,
    LeadCreate,
    LeadListResponse,
    LeadOut,
    LeadSourceOut,
    LeadStatusOut,
    LeadTagAttach,
    LeadUpdate,
    MemberSummary,
    TagCreate,
    TagOut,
)
from app.schemas.pipeline import LeadStatusChange, PipelineResponse
from app.security import authorization as authz
from app.security.permissions import Permission
from app.services.calls import CallService
from app.services.customer360 import CustomerService
from app.services.followups import FollowUpService
from app.services.leads import LeadService

# Phase 13's bulk endpoint gates on whichever permission its *action*
# actually needs (assign -> leads.assign, change_status/update-shaped ->
# leads.update, delete -> leads.delete) — the same permission each
# action's own single-lead endpoint already requires above. The action
# only becomes known once the body is parsed, so this can't be a
# `Depends(require_permission(...))` on the route signature the way
# every other route here does it; the route below calls
# `authz.require_permission()` directly instead; see require_workspace_member's
# note.
_BULK_ACTION_PERMISSIONS = {
    BulkLeadAction.ASSIGN: Permission.LEADS_ASSIGN,
    BulkLeadAction.UNASSIGN: Permission.LEADS_ASSIGN,
    BulkLeadAction.CHANGE_STATUS: Permission.LEADS_UPDATE,
    BulkLeadAction.DELETE: Permission.LEADS_DELETE,
}

# Nested under /workspaces/{workspace_id}/... (rather than the flat
# /api/v1/leads the Phase 5 prompt's "suggested" surface sketches) so
# every route can reuse api/dependencies.py's existing
# require_permission()/require_workspace_member() dependency factories,
# which resolve `workspace_id` from the path — see Phase 3's auth
# foundation. This is the same "never trust workspace_id from the
# client without server/database validation" rule Phase 5 §9 asks for:
# the id in the URL is only ever used after has_permission()/
# is_workspace_member() have verified it against real membership rows.
router = APIRouter(tags=["leads"])


def _service(client: Client) -> LeadService:
    return LeadService(client)


@router.get("/workspaces/{workspace_id}/leads", response_model=LeadListResponse)
async def list_leads(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    search: str | None = Query(default=None, max_length=200),
    status_id: UUID | None = Query(default=None),
    # Phase 14 §"Advanced Lead Search, Filters & Saved Views" — the same
    # workspace-scoped listing query, just with more optional narrowing
    # params; see LeadService.list_leads for the per-id workspace
    # validation each of these gets before it reaches the query.
    source_id: UUID | None = Query(default=None),
    assigned_member_id: UUID | None = Query(default=None),
    priority: str | None = Query(default=None, max_length=20),
    is_customer: bool | None = Query(default=None),
    created_from: datetime | None = Query(default=None),
    created_to: datetime | None = Query(default=None),
    tag_id: UUID | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> LeadListResponse:
    items, total = _service(client).list_leads(
        workspace_id,
        search=search,
        status_id=status_id,
        source_id=source_id,
        assigned_member_id=assigned_member_id,
        priority=priority,
        is_customer=is_customer,
        created_from=created_from,
        created_to=created_to,
        tag_id=tag_id,
        limit=limit,
        offset=offset,
    )
    return LeadListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/pipeline", response_model=PipelineResponse)
async def get_pipeline(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    search: str | None = Query(default=None, max_length=200),
    assigned_member_id: UUID | None = Query(default=None),
    source_id: UUID | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> PipelineResponse:
    """Phase 12 — leads grouped by the workspace's own `lead_statuses`
    (never a hardcoded status list/order). Gated on leads.read, same as
    `list_leads` — the pipeline is just another view over the same
    leads a permitted member can already list."""
    columns = _service(client).list_pipeline(
        workspace_id,
        search=search,
        assigned_member_id=assigned_member_id,
        source_id=source_id,
        limit=limit,
        offset=offset,
    )
    return PipelineResponse(columns=columns, limit=limit, offset=offset)


@router.post("/workspaces/{workspace_id}/leads/bulk", response_model=BulkLeadActionResponse)
async def bulk_lead_action(
    workspace_id: UUID,
    body: BulkLeadActionRequest,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> BulkLeadActionResponse:
    """Phase 13 §"Bulk Actions". Gated on plain membership at the route
    signature (like `list_lead_statuses`/`list_members` above), then
    re-gated on the specific permission `body.action` actually needs
    (see `_BULK_ACTION_PERMISSIONS`) — the same has_permission() RPC
    every other route's `require_permission()` dependency calls, just
    invoked after the body is parsed instead of before. Delegates every
    write to `LeadService.bulk_update_leads`, which itself only calls
    the existing single-lead assign/status/delete service methods."""
    permission = _BULK_ACTION_PERMISSIONS[body.action]
    authz.require_permission(client, workspace_id, permission)

    results = _service(client).bulk_update_leads(
        workspace_id,
        body.lead_ids,
        body.action.value,
        member_id=body.member_id,
        status_id=body.status_id,
    )
    succeeded = sum(1 for r in results if r["success"])
    return BulkLeadActionResponse(
        action=body.action,
        total=len(results),
        succeeded=succeeded,
        failed=len(results) - succeeded,
        results=results,
    )


@router.post("/workspaces/{workspace_id}/leads/import", response_model=LeadImportResponse)
async def import_leads(
    workspace_id: UUID,
    body: LeadImportRequest,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_CREATE))],
) -> LeadImportResponse:
    """Phase 13 §"CSV Import". Gated on leads.create — importing is
    fundamentally a batch of lead creations, so it requires the same
    permission `create_lead` above does, not a new import-specific one."""
    result = _service(client).import_leads_csv(workspace_id, body.csv_content)
    return LeadImportResponse(**result)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}", response_model=LeadOut)
async def get_lead(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> LeadOut:
    return _service(client).get_lead(workspace_id, lead_id)


@router.post("/workspaces/{workspace_id}/leads", response_model=LeadOut, status_code=201)
async def create_lead(
    workspace_id: UUID,
    body: LeadCreate,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_CREATE))],
) -> LeadOut:
    return _service(client).create_lead(workspace_id, body.model_dump())


@router.patch("/workspaces/{workspace_id}/leads/{lead_id}", response_model=LeadOut)
async def update_lead(
    workspace_id: UUID,
    lead_id: UUID,
    body: LeadUpdate,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> LeadOut:
    return _service(client).update_lead(workspace_id, lead_id, body.model_dump(exclude_unset=True))


@router.patch("/workspaces/{workspace_id}/leads/{lead_id}/status", response_model=LeadOut)
async def change_lead_status(
    workspace_id: UUID,
    lead_id: UUID,
    body: LeadStatusChange,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> LeadOut:
    """Phase 12's minimal pipeline status-change action — same
    leads.update permission as the general `update_lead` PATCH above (a
    status change is a lead update), and internally delegates to
    `LeadService.update_lead` so there is exactly one code path that
    writes `leads.status_id` (see LeadService.change_lead_status)."""
    return _service(client).change_lead_status(workspace_id, lead_id, body.status_id)


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/convert", response_model=LeadOut)
async def convert_lead_to_customer(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> LeadOut:
    """Phase 18 — dedicated Lead -> Customer conversion action. Gated on
    leads.update (the same permission `update_lead`/`change_lead_status`
    above use, not a new permission — converting is fundamentally an
    update to the lead), and `leads_update` RLS
    (000014_rls_policies.sql) remains the final enforcement layer, same
    as every other write on this router. No request body: there is
    nothing for the client to supply — the server derives the actor and
    resolves everything else from the existing lead row."""
    return _service(client).convert_to_customer(workspace_id, lead_id)


@router.delete("/workspaces/{workspace_id}/leads/{lead_id}", status_code=204)
async def delete_lead(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_DELETE))],
) -> None:
    _service(client).delete_lead(workspace_id, lead_id)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/interactions", response_model=list[InteractionOut])
async def list_interactions(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[InteractionOut]:
    return _service(client).list_interactions(workspace_id, lead_id)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/activity", response_model=TimelineResponse)
async def get_lead_activity(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    limit: int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
) -> TimelineResponse:
    """Phase 15 §"Backend" — the unified activity feed (calls/follow-ups/
    notes/allocations/documents), generalized from Phase 8's Customer 360
    timeline to any lead, not just customers. Gated on leads.read, same
    as `list_interactions` above — this is a read view over data a
    permitted member can already see individually via the calls/
    follow-ups/interactions endpoints, not a new permission domain.
    Reuses CustomerService's aggregation (`_assemble_activity`) verbatim
    — one implementation for both this route and
    GET /customers/{id}/timeline, not a second aggregation path."""
    items, total = CustomerService(client).get_lead_activity(workspace_id, lead_id, limit=limit, offset=offset)
    return TimelineResponse(items=items, total=total, limit=limit, offset=offset)


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/notes", response_model=InteractionOut, status_code=201)
async def create_lead_note(
    workspace_id: UUID,
    lead_id: UUID,
    body: NoteCreate,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> InteractionOut:
    """Phase 15 §"Interaction / Note Creation" — the same minimum note
    capability Phase 8 gave Customer 360 (`POST /customers/{id}/notes`),
    now also reachable from Lead Detail for a lead that isn't a customer
    yet. Gated on leads.update, matching that endpoint and
    attach_lead_tag/detach_lead_tag's existing write gate on a
    lead-nested resource."""
    return CustomerService(client).create_lead_note(workspace_id, lead_id, body.text)


@router.get("/workspaces/{workspace_id}/members", response_model=list[MemberSummary])
async def list_members(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[MemberSummary]:
    """Active workspace members only (Phase 6 §3) — the assignment
    picker's candidate list. Gated on plain membership, not a specific
    permission: RLS's own workspace_members_select policy already lets
    any active member see their teammates (000014_rls_policies.sql)."""
    return _service(client).list_workspace_members(workspace_id)


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/assignment", response_model=LeadOut)
async def assign_lead(
    workspace_id: UUID,
    lead_id: UUID,
    body: AssignmentRequest,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_ASSIGN))],
) -> LeadOut:
    """Assign, reassign, or unassign (member_id omitted/null) a lead.
    Gated on leads.assign specifically — not leads.update — matching
    the RBAC catalog's dedicated permission for this action (Phase 6
    §4). See supabase/migrations/000017_lead_assignment_permission.sql
    for the matching database-level enforcement."""
    return _service(client).assign_lead(workspace_id, lead_id, body.member_id)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/allocations", response_model=list[AllocationOut])
async def list_allocations(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[AllocationOut]:
    """Gated on leads.read (same as the lead itself), not
    allocations.read — the allocations_select RLS policy already lets a
    team_mate see their own lead's history regardless of the
    allocations.* permissions (those gate allocations.manage/read
    workspace-wide, a stricter manager-only concept); gating this
    endpoint on allocations.read would hide a rep's own assignment
    history from them even though RLS would return it."""
    return _service(client).list_allocations(workspace_id, lead_id)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/follow-ups", response_model=list[FollowUpOut])
async def list_lead_follow_ups(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[FollowUpOut]:
    """Phase 7 §4's lead-specific follow-up surface, kept alongside the
    other lead-nested resources (interactions, allocations) rather than
    in api/v1/followups.py, for the same reason those are here: it's a
    property of a specific lead the caller already has open, not a
    standalone follow-up query. Gated on leads.read (matching
    interactions/allocations above), not followups.read — a viewer who
    can see the lead should see its follow-ups without needing a second,
    separate permission."""
    return FollowUpService(client).list_lead_follow_ups(workspace_id, lead_id)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/calls", response_model=list[CallOut])
async def list_lead_calls(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[CallOut]:
    """Phase 9 §8's lead-specific call surface, kept alongside the other
    lead-nested resources (interactions/allocations/follow-ups) for the
    same reason those are here: it's a property of a specific lead the
    caller already has open. Gated on leads.read (matching
    interactions/allocations/follow-ups above), not calls.read — a
    viewer who can see the lead should see its calls without needing a
    second permission; calls_select RLS still independently scopes which
    rows actually come back (manager-or-self)."""
    return CallService(client).list_lead_calls(workspace_id, lead_id)


@router.get("/workspaces/{workspace_id}/lead-statuses", response_model=list[LeadStatusOut])
async def list_lead_statuses(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[LeadStatusOut]:
    return _service(client).list_statuses(workspace_id)


@router.get("/workspaces/{workspace_id}/lead-sources", response_model=list[LeadSourceOut])
async def list_lead_sources(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[LeadSourceOut]:
    return _service(client).list_sources(workspace_id)


@router.get("/workspaces/{workspace_id}/tags", response_model=list[TagOut])
async def list_tags(
    workspace_id: UUID,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> list[TagOut]:
    return _service(client).list_tags(workspace_id)


@router.post("/workspaces/{workspace_id}/tags", response_model=TagOut, status_code=201)
async def create_tag(
    workspace_id: UUID,
    body: TagCreate,
    client: Annotated[Client, Depends(require_workspace_member)],
) -> TagOut:
    return _service(client).create_tag(workspace_id, body.name, body.color)


@router.get("/workspaces/{workspace_id}/leads/{lead_id}/tags", response_model=list[TagOut])
async def list_lead_tags(
    workspace_id: UUID,
    lead_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[TagOut]:
    return _service(client).list_lead_tags(workspace_id, lead_id)


@router.post("/workspaces/{workspace_id}/leads/{lead_id}/tags", response_model=TagOut, status_code=201)
async def attach_lead_tag(
    workspace_id: UUID,
    lead_id: UUID,
    body: LeadTagAttach,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> TagOut:
    return _service(client).attach_tag(workspace_id, lead_id, body.tag_id)


@router.delete("/workspaces/{workspace_id}/leads/{lead_id}/tags/{tag_id}", status_code=204)
async def detach_lead_tag(
    workspace_id: UUID,
    lead_id: UUID,
    tag_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> None:
    _service(client).detach_tag(workspace_id, lead_id, tag_id)
