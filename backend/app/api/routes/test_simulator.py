"""Test-only HTTP endpoints for the CamGuard Web Attack Simulator (local dev).

The browser cannot POST camera media here; only metadata is accepted. Disable or
proxy-guard in production if this module is not desired.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(tags=["test-simulator"])


class DummyUploadRequest(BaseModel):
    simulation: bool = True
    test_type: str = Field(..., max_length=120)
    message: str = Field(..., max_length=500)
    timestamp: Optional[str] = None


@router.post("/api/test/dummy-upload")
async def dummy_upload(payload: DummyUploadRequest) -> dict:
    return {
        "saved": True,
        "received_at": datetime.now(timezone.utc).isoformat(),
        "simulation": payload.simulation,
        "test_type": payload.test_type,
        "note": "No camera media was uploaded. Metadata-only test.",
    }
