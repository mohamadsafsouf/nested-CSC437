from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class ProtectionActionRequest(BaseModel):
    event_id: UUID
    device_id: Optional[UUID] = None
    app_name: str = Field(min_length=1, max_length=200)
    process_id: Optional[int] = None
    action: str = Field(pattern="^(none|warnOnly|closeBrowserTab|terminateProcess|requestManualReview|openPrivacySettings)$")
    result: str = Field(min_length=1, max_length=120)
    confidence: str = Field(pattern="^(confirmed|likely|uncertain)$")
    timestamp: datetime
    report_path: Optional[str] = Field(default=None, max_length=500)


class ProtectionActionResponse(BaseModel):
    id: UUID
    synced: bool
