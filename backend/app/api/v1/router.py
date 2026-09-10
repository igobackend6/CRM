from fastapi import APIRouter

from app.api.v1.ai_insights import router as ai_insights_router
from app.api.v1.auth import router as auth_router
from app.api.v1.calls import router as calls_router
from app.api.v1.custom_fields import router as custom_fields_router
from app.api.v1.customers import router as customers_router
from app.api.v1.dashboard import router as dashboard_router
from app.api.v1.documents import router as documents_router
from app.api.v1.followups import router as followups_router
from app.api.v1.leads import router as leads_router
from app.api.v1.message_templates import router as message_templates_router
from app.api.v1.messages import router as messages_router
from app.api.v1.notifications import router as notifications_router
from app.api.v1.rechurn import router as rechurn_router
from app.api.v1.reports import router as reports_router

# Versioned API surface. CRM endpoints (leads, calls, followups, ...) are
# added in their respective later phases and registered here. `auth` is
# an exception, included in Phase 3: it's identity/session foundation
# (proving JWT verification works end-to-end), not a CRM feature.
api_v1_router = APIRouter()
api_v1_router.include_router(auth_router)
api_v1_router.include_router(leads_router)
api_v1_router.include_router(followups_router)
api_v1_router.include_router(customers_router)
api_v1_router.include_router(calls_router)
api_v1_router.include_router(notifications_router)
api_v1_router.include_router(dashboard_router)
api_v1_router.include_router(messages_router)
api_v1_router.include_router(rechurn_router)
api_v1_router.include_router(ai_insights_router)
api_v1_router.include_router(documents_router)
api_v1_router.include_router(message_templates_router)
api_v1_router.include_router(reports_router)
api_v1_router.include_router(custom_fields_router)
