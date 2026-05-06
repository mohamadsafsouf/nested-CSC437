from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from app.api.dependencies import get_bearer_token, get_event_service, get_supabase_auth_service
from app.schemas.event import (
    CameraEventCreateRequest,
    CameraEventCreateResponse,
    CameraEventHistoryResponse,
    LocalCriticalCameraEventRequest,
    SimulatedCameraNetworkActivityRequest,
    SimulatedCameraNetworkActivityResponse,
)
from app.services.event_service import EventService
from app.services.supabase_auth_service import SupabaseAuthService

router = APIRouter(prefix="/events", tags=["events"])


@router.post("/simulated-camera-network-activity", response_model=SimulatedCameraNetworkActivityResponse)
async def simulate_camera_network_activity(
    request: SimulatedCameraNetworkActivityRequest,
    event_service: Annotated[EventService, Depends(get_event_service)],
) -> SimulatedCameraNetworkActivityResponse:
    return event_service.score_simulated_camera_network_activity(request)


@router.post("/local-critical-camera-test", response_model=CameraEventCreateResponse)
async def local_critical_camera_test(
    request: LocalCriticalCameraEventRequest,
    http_request: Request,
    event_service: Annotated[EventService, Depends(get_event_service)],
) -> CameraEventCreateResponse:
    client_host = http_request.client.host if http_request.client else ""
    if client_host not in {"127.0.0.1", "::1", "localhost"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Local critical camera testing is only available from this Mac.",
        )
    return await event_service.create_local_critical_camera_event(request)


@router.post("/camera", response_model=CameraEventCreateResponse)
async def create_camera_event(
    request: CameraEventCreateRequest,
    access_token: Annotated[str, Depends(get_bearer_token)],
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
    event_service: Annotated[EventService, Depends(get_event_service)],
) -> CameraEventCreateResponse:
    user = await auth_service.get_user(access_token)
    return await event_service.create_camera_event(user=user, request=request)


@router.get("/camera", response_model=CameraEventHistoryResponse)
async def list_camera_events(
    access_token: Annotated[str, Depends(get_bearer_token)],
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
    event_service: Annotated[EventService, Depends(get_event_service)],
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> CameraEventHistoryResponse:
    user = await auth_service.get_user(access_token)
    return await event_service.list_camera_events(user=user, limit=limit)
