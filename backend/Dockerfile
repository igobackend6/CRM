# Sales CRM API (FastAPI). Built and run by deploy/docker-compose.yml.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app

# Never run as root inside the container.
RUN useradd --system --no-create-home crm && chown -R crm /srv
USER crm

EXPOSE 8000

# One worker on purpose: the reminder scheduler (APScheduler) and the rate limiter live inside the
# process, so a second worker would run every scheduled job twice. One worker is plenty for a small
# team; scale the server up before adding workers (and move the scheduler out first).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--proxy-headers", "--forwarded-allow-ips", "*"]
