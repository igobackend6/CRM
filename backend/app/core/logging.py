import logging
import sys

from app.core.config import get_settings


def configure_logging() -> None:
    """Centralized logging setup. Never log request bodies, tokens, API
    keys, or other sensitive values — call sites are responsible for only
    passing safe, structured context into log calls.
    """
    settings = get_settings()
    logging.basicConfig(
        level=settings.log_level.upper(),
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        stream=sys.stdout,
    )


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
