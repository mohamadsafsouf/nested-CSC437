import logging
from typing import Any, Dict, Optional
from uuid import UUID
import httpx
from fastapi import HTTPException, status
from app.core.config import Settings
from app.schemas.auth import AuthUser
from app.schemas.protection import ProtectionActionRequest, ProtectionActionResponse

logger = logging.getLogger(__name__)


class ProtectionService:
    def __init__(self, settings: Settings):
        self.settings = settings

    async def create_protection_action(
        self,
        user: AuthUser,
        request: ProtectionActionRequest,
    ) -> ProtectionActionResponse:
        if not self.settings.supabase_secret_key:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Protection service is not configured.")

        camera_event_id = await self._camera_event_id_for_client_event(user.id, request.event_id)
        rows = await self._service_rest_request(
            "POST",
            "/protection_actions?select=id",
            json={
                "user_id": str(user.id),
                "device_id": str(request.device_id) if request.device_id else None,
                "camera_event_id": camera_event_id,
                "client_event_id": str(request.event_id),
                "app_name": request.app_name,
                "process_id": request.process_id,
                "action": request.action,
                "result": request.result,
                "confidence": request.confidence,
                "report_path": request.report_path,
                "occurred_at": request.timestamp.isoformat(),
            },
            prefer="return=representation",
        )
        if not rows:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Protection action sync returned no rows.")
        return ProtectionActionResponse(id=UUID(str(rows[0]["id"])), synced=True)

    async def _camera_event_id_for_client_event(self, user_id: UUID, client_event_id: UUID) -> Optional[str]:
        rows = await self._service_rest_request(
            "GET",
            f"/camera_events?user_id=eq.{user_id}&client_event_id=eq.{client_event_id}&select=id&limit=1",
        )
        return str(rows[0]["id"]) if rows else None

    async def _service_rest_request(
        self,
        method: str,
        path: str,
        json: Optional[Dict[str, Any]] = None,
        prefer: Optional[str] = None,
    ) -> Any:
        headers = {
            "apikey": self.settings.supabase_secret_key,
            "Authorization": f"Bearer {self.settings.supabase_secret_key}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer

        try:
            async with httpx.AsyncClient(timeout=self.settings.request_timeout_seconds) as client:
                response = await client.request(
                    method,
                    f"{self.settings.supabase_rest_url}{path}",
                    headers=headers,
                    json=json,
                )
        except httpx.RequestError as exc:
            logger.exception("Supabase protection action request failed")
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Protection service is unavailable.") from exc

        if response.status_code >= 400:
            logger.warning("Protection sync failed with status %s: %s", response.status_code, response.text)
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Protection action sync failed.")

        if not response.content:
            return []
        return response.json()
