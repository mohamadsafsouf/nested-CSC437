import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from uuid import UUID
import httpx
from fastapi import HTTPException, status
from app.core.config import Settings
from app.schemas.auth import AuthUser
from app.schemas.device import DeviceRegisterRequest, DeviceResponse

logger = logging.getLogger(__name__)


class DeviceService:
    def __init__(self, settings: Settings):
        self.settings = settings

    async def register_device(
        self,
        access_token: str,
        user: AuthUser,
        request: DeviceRegisterRequest,
    ) -> DeviceResponse:
        device_type_id = await self._get_device_type_id(access_token, request.device_type_key)
        operating_system_id = await self._upsert_operating_system(
            device_type_id=device_type_id,
            os_name=request.os_name,
            os_version=request.os_version,
        )
        payload = {
            "user_id": str(user.id),
            "device_type_id": device_type_id,
            "operating_system_id": operating_system_id,
            "client_device_id": request.client_device_id,
            "display_name": request.display_name,
            "model_name": request.model_name,
            "last_seen_at": datetime.now(timezone.utc).isoformat(),
        }

        rows = await self._rest_request(
            access_token,
            "POST",
            "/devices?on_conflict=user_id,client_device_id&select=*,device_types(key),operating_systems(name,version)",
            json=payload,
            prefer="resolution=merge-duplicates,return=representation",
        )
        if not rows:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Device registration returned no rows.")

        return self._parse_device(rows[0], request.os_name, request.os_version)

    async def list_devices(self, access_token: str) -> List[DeviceResponse]:
        rows = await self._rest_request(
            access_token,
            "GET",
            "/devices?select=*,device_types(key),operating_systems(name,version)&order=last_seen_at.desc.nullslast",
        )
        return [self._parse_device(row) for row in rows]

    async def _get_device_type_id(self, access_token: str, key: str) -> int:
        rows = await self._rest_request(
            access_token,
            "GET",
            f"/device_types?key=eq.{key}&select=id&limit=1",
        )
        if not rows:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Missing device type: {key}")
        return int(rows[0]["id"])

    async def _upsert_operating_system(self, device_type_id: int, os_name: str, os_version: str) -> str:
        if not self.settings.supabase_secret_key:
            logger.error("SUPABASE_SECRET_KEY is required for operating system sync.")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Device service is not configured.")

        rows = await self._service_rest_request(
            "POST",
            "/operating_systems?on_conflict=device_type_id,name,version&select=id",
            json={"device_type_id": device_type_id, "name": os_name, "version": os_version},
            prefer="resolution=merge-duplicates,return=representation",
        )
        if not rows:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Operating system sync returned no rows.")
        return str(rows[0]["id"])

    async def _rest_request(
        self,
        access_token: str,
        method: str,
        path: str,
        json: Optional[Dict[str, Any]] = None,
        prefer: Optional[str] = None,
    ) -> Any:
        headers = {
            "apikey": self.settings.supabase_publishable_key,
            "Authorization": f"Bearer {access_token}",
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
            logger.exception("Supabase device request failed")
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Device service is unavailable.") from exc

        if response.status_code >= 400:
            logger.warning("Supabase device request failed with status %s: %s", response.status_code, response.text)
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Device request failed.")

        if not response.content:
            return []
        return response.json()

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
            logger.exception("Supabase service-role device request failed")
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Device service is unavailable.") from exc

        if response.status_code >= 400:
            logger.warning("Supabase service-role device request failed with status %s: %s", response.status_code, response.text)
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Device request failed.")

        if not response.content:
            return []
        return response.json()

    def _parse_device(
        self,
        row: Dict[str, Any],
        fallback_os_name: str = "macOS",
        fallback_os_version: str = "Unknown",
    ) -> DeviceResponse:
        device_type = row.get("device_types") or {}
        operating_system = row.get("operating_systems") or {}
        return DeviceResponse(
            id=UUID(str(row["id"])),
            client_device_id=row["client_device_id"],
            display_name=row["display_name"],
            device_type_key=device_type.get("key") or "macos",
            os_name=operating_system.get("name") or fallback_os_name,
            os_version=operating_system.get("version") or fallback_os_version,
            model_name=row.get("model_name"),
            last_seen_at=row.get("last_seen_at"),
            created_at=row.get("created_at"),
            updated_at=row.get("updated_at"),
        )
