"""Vercel entry point: exposes the FastAPI app (app/main.py) as a serverless function.

Vercel routes every request here (see vercel.json); nothing else in the backend changes. Run
locally exactly as before: `uvicorn app.main:app`.
"""
from app.main import app  # noqa: F401  (Vercel looks for a module-level `app`)
