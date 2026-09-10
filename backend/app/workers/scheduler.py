from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.core.logging import get_logger

logger = get_logger(__name__)

# One process-wide scheduler, started/stopped from main.py's lifespan.
# No jobs are registered in Phase 3 — the first real job (follow-up
# reminder scanning) is added in Phase 11, by calling
# scheduler.add_job(...) at import time from that feature's module, not
# by editing this file. This file only owns the scheduler's lifecycle.
scheduler = AsyncIOScheduler()


def start() -> None:
    if not scheduler.running:
        scheduler.start()
        logger.info("Background job scheduler started (%d job(s) registered).", len(scheduler.get_jobs()))


def shutdown() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Background job scheduler stopped.")
