from typing import Annotated
from fastapi import APIRouter, Depends, status
from app.api.dependencies import get_bearer_token, get_supabase_auth_service
from app.schemas.auth import (
    AuthResponse,
    AuthUser,
    ConfirmSessionRequest,
    RefreshTokenRequest,
    ResendConfirmationRequest,
    SignInRequest,
    SignOutRequest,
    SignUpRequest,
)
from app.services.supabase_auth_service import SupabaseAuthService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/sign-up", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def sign_up(
    request: SignUpRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> AuthResponse:
    return await auth_service.sign_up(
        email=str(request.email),
        password=request.password,
        display_name=request.display_name,
    )


@router.post("/sign-in", response_model=AuthResponse)
async def sign_in(
    request: SignInRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> AuthResponse:
    return await auth_service.sign_in(email=str(request.email), password=request.password)


@router.post("/refresh", response_model=AuthResponse)
async def refresh_session(
    request: RefreshTokenRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> AuthResponse:
    return await auth_service.refresh(refresh_token=request.refresh_token)


@router.post("/confirm-session", response_model=AuthResponse)
async def confirm_session(
    request: ConfirmSessionRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> AuthResponse:
    return await auth_service.confirm_session(
        access_token=request.access_token,
        refresh_token=request.refresh_token,
        token_type=request.token_type,
        expires_in=request.expires_in,
        expires_at=request.expires_at,
    )


@router.post("/resend-confirmation")
async def resend_confirmation(
    request: ResendConfirmationRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> dict[str, str]:
    return await auth_service.resend_confirmation(email=str(request.email))


@router.get("/me", response_model=AuthUser)
async def get_current_user(
    access_token: Annotated[str, Depends(get_bearer_token)],
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> AuthUser:
    return await auth_service.get_user(access_token=access_token)


@router.post("/sign-out")
async def sign_out(
    request: SignOutRequest,
    auth_service: Annotated[SupabaseAuthService, Depends(get_supabase_auth_service)],
) -> dict[str, str]:
    return await auth_service.sign_out(access_token=request.access_token)
