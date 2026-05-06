import logging
from typing import Any, Dict, Optional
from uuid import UUID
import httpx
from fastapi import HTTPException, status
from app.core.config import Settings
from app.schemas.auth import AuthResponse, AuthSession, AuthUser, SupabaseAuthPayload

logger = logging.getLogger(__name__)


class SupabaseAuthService:
    def __init__(self, settings: Settings):
        self.settings = settings

    async def sign_up(self, email: str, password: str, display_name: str) -> AuthResponse:
        payload = {
            "email": email,
            "password": password,
            "data": {"display_name": display_name},
        }
        data = await self._request("POST", "/signup", json=payload)
        response = self._parse_auth_response(data)

        await self._upsert_profile(
            access_token=response.session.access_token if response.session else None,
            user_id=response.user.id,
            display_name=display_name,
        )

        return response

    async def sign_in(self, email: str, password: str) -> AuthResponse:
        data = await self._request(
            "POST",
            "/token?grant_type=password",
            json={"email": email, "password": password},
        )
        response = self._parse_auth_response(data)

        if response.session is not None:
            await self._upsert_profile(
                access_token=response.session.access_token,
                user_id=response.user.id,
                display_name=response.user.display_name or email.split("@")[0],
            )

        return response

    async def refresh(self, refresh_token: str) -> AuthResponse:
        data = await self._request(
            "POST",
            "/token?grant_type=refresh_token",
            json={"refresh_token": refresh_token},
        )
        return self._parse_auth_response(data)

    async def confirm_session(
        self,
        access_token: str,
        refresh_token: str,
        token_type: str,
        expires_in: Optional[int],
        expires_at: Optional[int],
    ) -> AuthResponse:
        user = await self.get_user(access_token=access_token)
        await self._upsert_profile(
            access_token=access_token,
            user_id=user.id,
            display_name=user.display_name or (user.email.split("@")[0] if user.email else "CamGuard User"),
        )
        return AuthResponse(
            user=user,
            session=AuthSession(
                access_token=access_token,
                refresh_token=refresh_token,
                token_type=token_type or "bearer",
                expires_in=expires_in,
                expires_at=expires_at,
            ),
        )

    async def resend_confirmation(self, email: str) -> Dict[str, str]:
        payload: Dict[str, Any] = {"type": "signup", "email": email}
        if self.settings.auth_email_redirect_to:
            payload["options"] = {"email_redirect_to": self.settings.auth_email_redirect_to}

        await self._request("POST", "/resend", json=payload)
        return {"status": "confirmation_email_sent"}

    async def get_user(self, access_token: str) -> AuthUser:
        data = await self._request("GET", "/user", access_token=access_token)
        return self._parse_user(data)

    async def sign_out(self, access_token: str) -> dict[str, str]:
        await self._request("POST", "/logout", access_token=access_token)
        return {"status": "signed_out"}

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json: Optional[Dict[str, Any]] = None,
        access_token: Optional[str] = None,
    ) -> Dict[str, Any]:
        headers = {
            "apikey": self.settings.supabase_publishable_key,
            "Content-Type": "application/json",
        }
        if access_token:
            headers["Authorization"] = f"Bearer {access_token}"

        url = f"{self.settings.supabase_auth_url}{path}"
        try:
            async with httpx.AsyncClient(timeout=self.settings.request_timeout_seconds) as client:
                response = await client.request(method, url, headers=headers, json=json)
        except httpx.RequestError as exc:
            logger.exception("Supabase Auth request failed")
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Authentication service is unavailable.",
            ) from exc

        if response.status_code >= 400:
            logger.warning("Supabase Auth rejected request with status %s", response.status_code)
            raise HTTPException(
                status_code=self._map_status_code(response.status_code),
                detail=self._extract_error(response),
            )

        if not response.content:
            return {}
        return response.json()

    async def _upsert_profile(self, access_token: Optional[str], user_id: UUID, display_name: str) -> None:
        auth_token = access_token or self.settings.supabase_secret_key
        api_key = self.settings.supabase_secret_key if access_token is None else self.settings.supabase_publishable_key
        if not auth_token or not api_key:
            logger.warning("Skipping profile upsert because no Supabase auth token is available")
            return

        headers = {
            "apikey": api_key,
            "Authorization": f"Bearer {auth_token}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        }
        payload = {"id": str(user_id), "display_name": display_name}

        try:
            async with httpx.AsyncClient(timeout=self.settings.request_timeout_seconds) as client:
                response = await client.post(
                    f"{self.settings.supabase_rest_url}/users",
                    headers=headers,
                    json=payload,
                )
        except httpx.RequestError:
            logger.exception("Failed to upsert Supabase profile")
            return

        if response.status_code >= 400:
            # Auth can still succeed if profile sync fails; callers should not lose the session.
            logger.warning("Profile upsert failed with status %s", response.status_code)

    def _parse_auth_response(self, data: dict[str, Any]) -> AuthResponse:
        payload = SupabaseAuthPayload.model_validate(data)
        user_payload = payload.user or data.get("user")
        if not user_payload and data.get("id"):
            # Supabase signup can return the user object directly when email
            # confirmation is enabled and no session is issued yet.
            user_payload = data
        if not user_payload:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Authentication response did not include a user.",
            )

        session_payload = payload.session or data
        session = self._parse_session(session_payload)
        return AuthResponse(user=self._parse_user(user_payload), session=session)

    def _parse_user(self, data: dict[str, Any]) -> AuthUser:
        metadata = data.get("user_metadata") or data.get("raw_user_meta_data") or {}
        return AuthUser(
            id=UUID(str(data["id"])),
            email=data.get("email"),
            display_name=metadata.get("display_name"),
            created_at=data.get("created_at"),
        )

    def _parse_session(self, data: Dict[str, Any]) -> Optional[AuthSession]:
        access_token = data.get("access_token")
        refresh_token = data.get("refresh_token")
        if not access_token or not refresh_token:
            return None

        return AuthSession(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type=data.get("token_type") or "bearer",
            expires_in=data.get("expires_in"),
            expires_at=data.get("expires_at"),
        )

    def _extract_error(self, response: httpx.Response) -> str:
        try:
            data = response.json()
        except ValueError:
            return "Authentication request failed."
        return data.get("msg") or data.get("message") or data.get("error_description") or "Authentication request failed."

    def _map_status_code(self, status_code: int) -> int:
        if status_code in {400, 401, 403, 404, 409, 422, 429}:
            return status_code
        return status.HTTP_502_BAD_GATEWAY
