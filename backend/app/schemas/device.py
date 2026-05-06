from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel, Field


class DeviceRegisterRequest(BaseModel):
    client_device_id: str = Field(min_length=1, max_length=200)
    display_name: str = Field(min_length=1, max_length=200)
    device_type_key: str = Field(default="macos", min_length=1, max_length=40)
    os_name: str = Field(min_length=1, max_length=80)
    os_version: str = Field(min_length=1, max_length=120)
    model_name: Optional[str] = Field(default=None, max_length=160)


class DeviceResponse(BaseModel):
    id: UUID
    client_device_id: str
    display_name: str
    device_type_key: str
    os_name: str
    os_version: str
    model_name: Optional[str] = None
    last_seen_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
