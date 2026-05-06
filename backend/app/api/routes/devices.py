from typing import Annotated, List
from fastapi import APIRouter, Depends
from app.api.dependencies import get_bearer_token, get_device_service, get_supabase_auth_service
from app.schemas.device import DeviceRegisterRequest, DeviceResponse
from app.services.device_service import DeviceService
from app.services.supabase_auth_service import SupabaseAuthService

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", response_model=DeviceResponse)
async def register_device(
    request: DeviceRegisterRequest,
    access_token: Annotated[str, Depends(get_bearer_token)],
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
    device_service: Annotated[DeviceService, Depends(get_device_service)],
) -> DeviceResponse:
    user = await auth_service.get_user(access_token)
    return await device_service.register_device(access_token=access_token, user=user, request=request)


@router.get("", response_model=List[DeviceResponse])
async def list_devices(
    access_token: Annotated[str, Depends(get_bearer_token)],
    device_service: Annotated[DeviceService, Depends(get_device_service)],
) -> List[DeviceResponse]:
    return await device_service.list_devices(access_token=access_token)
