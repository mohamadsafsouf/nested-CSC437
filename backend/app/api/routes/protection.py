from typing import Annotated
from fastapi import APIRouter, Depends
from app.api.dependencies import get_bearer_token, get_protection_service, get_supabase_auth_service
from app.schemas.protection import ProtectionActionRequest, ProtectionActionResponse
from app.services.protection_service import ProtectionService
from app.services.supabase_auth_service import SupabaseAuthService

router = APIRouter(prefix="/protection-actions", tags=["protection"])


@router.post("", response_model=ProtectionActionResponse)
async def create_protection_action(
    request: ProtectionActionRequest,
    access_token: Annotated[str, Depends(get_bearer_token)],
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
    protection_service: Annotated[ProtectionService, Depends(get_protection_service)],
) -> ProtectionActionResponse:
    user = await auth_service.get_user(access_token)
    return await protection_service.create_protection_action(user=user, request=request)
