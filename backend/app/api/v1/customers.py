from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.api.dependencies import require_permission
from app.schemas.customer360 import DocumentListResponse, NoteCreate, TimelineResponse
from app.schemas.followups import FollowUpOut
from app.schemas.leads import InteractionOut, LeadOut
from app.security.permissions import Permission
from app.services.customer360 import CustomerService

# Phase 8 — Customer 360 & Unified Interaction Timeline. Nested under
# /workspaces/{workspace_id}/customers/{customer_id}/... (§9's suggested
# surface) rather than reusing /leads/{lead_id}/... — `customer_id` IS a
# `leads.id` (§"Customer model": no separate customers table), but a
# distinct URL namespace makes the is_customer requirement explicit at
# the route level and matches the phase's own suggested API surface.
# Every route below is gated on Permission.LEADS_READ (or LEADS_UPDATE
# for the note-creation write), the same permission the underlying lead
# is already gated on elsewhere (leads.py) — Customer 360 is not a
# separate permission domain, it's a different view of the same lead
# data, so it reuses the same RBAC checks rather than inventing new
# permission codes not present in the seeded catalog
# (supabase/migrations/000013_reference_data.sql).
router = APIRouter(tags=["customers"])


def _service(client: Client) -> CustomerService:
    return CustomerService(client)


@router.get("/workspaces/{workspace_id}/customers/{customer_id}", response_model=LeadOut)
async def get_customer(
    workspace_id: UUID,
    customer_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> LeadOut:
    """Customer Profile (§2). Returns the existing LeadOut shape — 404s
    if the lead doesn't exist, isn't visible to this caller, or exists
    but is_customer is false (see CustomerService._require_customer)."""
    return _service(client).get_customer(workspace_id, customer_id)


@router.get("/workspaces/{workspace_id}/customers/{customer_id}/timeline", response_model=TimelineResponse)
async def get_customer_timeline(
    workspace_id: UUID,
    customer_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    limit: int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
) -> TimelineResponse:
    """Unified, paginated, chronologically-ordered timeline (§3/§10)."""
    items, total = _service(client).get_timeline(workspace_id, customer_id, limit=limit, offset=offset)
    return TimelineResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/customers/{customer_id}/documents", response_model=DocumentListResponse)
async def list_customer_documents(
    workspace_id: UUID,
    customer_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> DocumentListResponse:
    items, total = _service(client).list_documents(workspace_id, customer_id, limit=limit, offset=offset)
    return DocumentListResponse(items=items, total=total, limit=limit, offset=offset)


@router.get("/workspaces/{workspace_id}/customers/{customer_id}/follow-ups", response_model=list[FollowUpOut])
async def list_customer_follow_ups(
    workspace_id: UUID,
    customer_id: UUID,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_READ))],
) -> list[FollowUpOut]:
    """Reuses Phase 7's FollowUpService unchanged (§2 "Reuse Phase 7
    follow-up functionality... do not duplicate follow-up state") — this
    route only adds the is_customer requirement on top."""
    return _service(client).list_follow_ups(workspace_id, customer_id)


@router.post("/workspaces/{workspace_id}/customers/{customer_id}/notes", response_model=InteractionOut, status_code=201)
async def create_customer_note(
    workspace_id: UUID,
    customer_id: UUID,
    body: NoteCreate,
    client: Annotated[Client, Depends(require_permission(Permission.LEADS_UPDATE))],
) -> InteractionOut:
    """§7's minimum note-creation capability. Gated on leads.update
    (not leads.read, since this is a write) — the same permission
    attach_lead_tag/detach_lead_tag use for a write on a lead-nested
    resource (leads.py); `interactions_insert` RLS itself is actually
    looser (visibility-only, no permission-code check at all), so this
    is an intentionally stricter, defense-in-depth API-layer gate, not a
    mismatch that would block anyone RLS would otherwise allow through
    from actually inserting."""
    return _service(client).create_note(workspace_id, customer_id, body.text)
