from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.v1.router import api_v1_router
from app.core.config import get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, get_logger
from app.core.rate_limit import RateLimitMiddleware
from app.schemas.common import HealthResponse
from app.workers import scheduler

configure_logging()
logger = get_logger(__name__)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Sales CRM API (environment=%s)", settings.environment)
    scheduler.start()
    yield
    scheduler.shutdown()


app = FastAPI(
    title="Sales CRM API",
    version="0.1.0",
    lifespan=lifespan,
    # Phase 21 §"Secrets"/hardening: interactive API docs expose the full
    # route/schema surface with no authentication of their own — harmless
    # reconnaissance value against an API where every real endpoint still
    # enforces JWT + permission checks underneath, but disabling them in
    # production is a standard, free reduction in attack-surface visibility.
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

register_exception_handlers(app)
app.add_middleware(RateLimitMiddleware)
app.include_router(api_v1_router, prefix=settings.api_v1_prefix)


@app.get("/health", response_model=HealthResponse, tags=["health"])
async def health() -> HealthResponse:
    return HealthResponse(status="ok")
