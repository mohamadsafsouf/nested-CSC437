from typing import Annotated
from typing import Optional
from fastapi import Depends, Header, HTTPException, status
from app.core.config import Settings, get_settings
from app.services.device_service import DeviceService
from app.services.event_service import EventService
from app.services.protection_service import ProtectionService
from app.services.supabase_auth_service import SupabaseAuthService


def get_supabase_auth_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> SupabaseAuthService:
    return SupabaseAuthService(settings=settings)


def get_device_service(settings: Annotated[Settings, Depends(get_settings)]) -> DeviceService:
    return DeviceService(settings=settings)


def get_event_service(settings: Annotated[Settings, Depends(get_settings)]) -> EventService:
    return EventService(settings=settings)


def get_protection_service(settings: Annotated[Settings, Depends(get_settings)]) -> ProtectionService:
    return ProtectionService(settings=settings)


def get_bearer_token(authorization: Annotated[Optional[str], Header()] = None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header must use Bearer token.",
        )

    return token
