from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID
from pydantic import BaseModel, Field


class CameraApplicationPayload(BaseModel):
    display_name: str = Field(min_length=1, max_length=200)
    bundle_identifier: Optional[str] = Field(default=None, max_length=200)
    process_id: Optional[int] = Field(default=None, ge=0)
    signing_team_id: Optional[str] = Field(default=None, max_length=80)
    is_trusted: bool = False
    is_known: bool = False


class CameraEventCreateRequest(BaseModel):
    client_event_id: UUID
    device_id: UUID
    event_type: str = Field(pattern="^(camera_session|permission_change|network_activity|simulation)$")
    camera_status: str = Field(pattern="^(started|ended|active|permission_only|unknown)$")
    permission_status: str = Field(pattern="^(authorized|denied|restricted|not_determined|unknown)$")
    occurred_at: datetime
    collected_at: datetime
    application: CameraApplicationPayload
    session_id: Optional[UUID] = None
    duration_seconds: Optional[float] = Field(default=None, ge=0)
    activation_count_recent_window: int = Field(default=0, ge=0)
    recent_window_seconds: int = Field(default=600, ge=1)
    is_background_access: bool = False
    is_repeated_short_activation: bool = False
    network_upload_after_camera: bool = False
    network_window_seconds: int = Field(default=30, ge=1)
    is_simulated: bool = False
    simulation_label: Optional[str] = Field(default=None, max_length=120)
    observed_website_url: Optional[str] = Field(default=None, max_length=500)
    observed_website_host: Optional[str] = Field(default=None, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=500)


class ThreatScoreResponse(BaseModel):
    anomaly_score: float
    contextual_score: float
    threat_probability: float
    threat_level: str


class CameraEventCreateResponse(BaseModel):
    id: UUID
    client_event_id: UUID
    saved: bool
    score: ThreatScoreResponse


class CameraEventHistoryItem(BaseModel):
    id: UUID
    client_event_id: UUID
    occurred_at: datetime
    camera_status: str
    notes: Optional[str] = None
    application_display_name: Optional[str] = None
    observed_process_id: Optional[int] = None
    observed_bundle_identifier: Optional[str] = None
    observed_website_url: Optional[str] = None
    observed_website_host: Optional[str] = None
    source_device_id: Optional[UUID] = None
    source_device_name: Optional[str] = None
    source_device_type: Optional[str] = None
    source_device_os: Optional[str] = None
    protection_action: Optional[str] = None
    protection_result: Optional[str] = None
    protection_confidence: Optional[str] = None
    score: Optional[ThreatScoreResponse] = None


class CameraEventHistoryResponse(BaseModel):
    events: List[CameraEventHistoryItem]


class SimulatedCameraNetworkActivityRequest(BaseModel):
    event_type: str = Field(pattern="^simulated_camera_network_activity$")
    app_name: str = Field(default="UnknownCameraClient", min_length=1, max_length=200)
    dummy_upload: bool = True
    payload: str = Field(default="test_only_no_camera_media", max_length=200)
    duration_seconds: float = Field(default=3.0, ge=0)
    activation_count_recent_window: int = Field(default=1, ge=0)


class SimulatedCameraNetworkActivityResponse(BaseModel):
    detected: bool
    reason: str
    threat_level: str
    score: ThreatScoreResponse
    received_metadata: Dict[str, Any]


class LocalCriticalCameraEventRequest(BaseModel):
    app_name: str = Field(default="UnknownCameraClient", min_length=1, max_length=200)
    bundle_identifier: Optional[str] = Field(default=None, max_length=200)
    process_id: Optional[int] = Field(default=None, ge=0)
    duration_seconds: float = Field(default=3.0, ge=0)
    activation_count_recent_window: int = Field(default=3, ge=1)
