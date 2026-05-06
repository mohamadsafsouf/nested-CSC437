import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
from urllib.parse import quote, urlparse
from uuid import UUID, uuid4
import httpx
from fastapi import HTTPException, status
from app.core.config import Settings
from app.schemas.auth import AuthUser
from app.schemas.event import (
    CameraEventCreateRequest,
    CameraEventCreateResponse,
    CameraEventHistoryItem,
    CameraEventHistoryResponse,
    SimulatedCameraNetworkActivityRequest,
    SimulatedCameraNetworkActivityResponse,
    ThreatScoreResponse,
    LocalCriticalCameraEventRequest,
)
from app.services.tcb_ad_service import TCBADFeatures, TCBADService

logger = logging.getLogger(__name__)


class EventService:
    def __init__(self, settings: Settings, tcb_ad_service: Optional[TCBADService] = None):
        self.settings = settings
        self.tcb_ad_service = tcb_ad_service or TCBADService()

    def score_simulated_camera_network_activity(
        self,
        request: SimulatedCameraNetworkActivityRequest,
    ) -> SimulatedCameraNetworkActivityResponse:
        features = TCBADFeatures(
            access_time_hour=13.0,
            duration_seconds=request.duration_seconds,
            activation_frequency=max(request.activation_count_recent_window, 1),
            background_access=False,
            unknown_or_untrusted=True,
            network_upload_after_camera=request.dummy_upload,
            permission_changed_recently=False,
            repeated_short_activation=request.duration_seconds < 5,
        )
        score = self.tcb_ad_service.score(features)

        return SimulatedCameraNetworkActivityResponse(
            detected=request.dummy_upload,
            reason="Camera access followed by network activity",
            threat_level=score.threat_level_key,
            score=ThreatScoreResponse(
                anomaly_score=score.anomaly_score,
                contextual_score=score.contextual_score,
                threat_probability=score.threat_probability,
                threat_level=score.threat_level_key,
            ),
            received_metadata={
                "event_type": request.event_type,
                "app_name": request.app_name,
                "dummy_upload": request.dummy_upload,
                "payload": request.payload,
                "camera_media_received": False,
            },
        )

    async def create_local_critical_camera_event(
        self,
        request: LocalCriticalCameraEventRequest,
    ) -> CameraEventCreateResponse:
        self._require_service_role()
        device = await self._latest_registered_macos_device()
        now = datetime.now(timezone.utc)
        user = AuthUser(id=UUID(str(device["user_id"])))
        return await self.create_camera_event(
            user=user,
            request=CameraEventCreateRequest(
                client_event_id=uuid4(),
                device_id=UUID(str(device["id"])),
                event_type="camera_session",
                camera_status="ended",
                permission_status="authorized",
                occurred_at=now,
                collected_at=now,
                application={
                    "display_name": request.app_name,
                    "bundle_identifier": request.bundle_identifier,
                    "process_id": request.process_id,
                    "signing_team_id": None,
                    "is_trusted": False,
                    "is_known": False,
                },
                duration_seconds=request.duration_seconds,
                activation_count_recent_window=max(request.activation_count_recent_window, 3),
                recent_window_seconds=600,
                is_background_access=False,
                is_repeated_short_activation=True,
                network_upload_after_camera=True,
                network_window_seconds=30,
                is_simulated=True,
                simulation_label="local_critical_camera_network_test",
                notes="Local critical test metadata: camera use followed by test-only network activity. No camera media included.",
            ),
        )

    async def create_camera_event(
        self,
        user: AuthUser,
        request: CameraEventCreateRequest,
    ) -> CameraEventCreateResponse:
        self._require_service_role()
        device = await self._get_owned_device(user.id, request.device_id)
        event_type_id = await self._lookup_id("event_types", request.event_type)
        permission_status_id = await self._lookup_id("permission_statuses", request.permission_status)
        application_id = await self._upsert_application(
            device_type_id=int(device["device_type_id"]),
            display_name=request.application.display_name,
            bundle_identifier=request.application.bundle_identifier,
            signing_team_id=request.application.signing_team_id,
        )
        source_key = self._source_key_for_request(request)
        source_context = await self._same_source_context(user.id, request)
        same_source_count = max(source_context["recent_count"] + 1, 1)
        same_source_network_count = source_context["network_upload_count"] + int(request.network_upload_after_camera)
        current_short_activation = (request.duration_seconds or 0.0) < 5
        repeated_short_activation = (
            request.is_repeated_short_activation
            or (source_context["short_activation_count"] + int(current_short_activation)) >= 3
        )
        activation_frequency = max(request.activation_count_recent_window, same_source_count)
        network_upload_after_camera = request.network_upload_after_camera or source_context["network_upload_count"] > 0

        features = TCBADFeatures(
            access_time_hour=self._hour_fraction(request.occurred_at),
            duration_seconds=request.duration_seconds or 0.0,
            activation_frequency=activation_frequency,
            background_access=request.is_background_access,
            unknown_or_untrusted=(not request.application.is_known) or (not request.application.is_trusted),
            network_upload_after_camera=network_upload_after_camera,
            permission_changed_recently=request.event_type == "permission_change",
            repeated_short_activation=repeated_short_activation,
            same_source_recent_count=same_source_count,
            same_source_network_upload_count=same_source_network_count,
        )
        score = self.tcb_ad_service.score(features)

        event_payload = {
            "user_id": str(user.id),
            "device_id": str(request.device_id),
            "application_id": application_id,
            "event_type_id": event_type_id,
            "permission_status_id": permission_status_id,
            "client_event_id": str(request.client_event_id),
            "session_id": str(request.session_id) if request.session_id else None,
            "occurred_at": request.occurred_at.isoformat(),
            "collected_at": request.collected_at.isoformat(),
            "camera_status": request.camera_status,
            "duration_seconds": request.duration_seconds,
            "activation_count_recent_window": activation_frequency,
            "recent_window_seconds": request.recent_window_seconds,
            "observed_app_name": request.application.display_name,
            "observed_process_id": request.application.process_id,
            "observed_bundle_identifier": request.application.bundle_identifier,
            "is_background_access": request.is_background_access,
            "is_repeated_short_activation": repeated_short_activation,
            "is_unknown_application": not request.application.is_known,
            "is_untrusted_application": not request.application.is_trusted,
            "permission_changed_recently": request.event_type == "permission_change",
            "network_upload_after_camera": network_upload_after_camera,
            "network_window_seconds": request.network_window_seconds,
            "is_simulated": request.is_simulated,
            "simulation_label": request.simulation_label,
            "observed_website_url": request.observed_website_url,
            "observed_website_host": request.observed_website_host,
            "source_key": source_key or None,
            "notes": request.notes,
        }
        try:
            event_rows = await self._insert_camera_event(event_payload)
        except HTTPException:
            legacy_payload = dict(event_payload)
            legacy_payload.pop("observed_website_url", None)
            legacy_payload.pop("observed_website_host", None)
            legacy_payload.pop("source_key", None)
            logger.warning("Retrying camera event save without source-context columns. Apply latest Supabase migrations.")
            event_rows = await self._insert_camera_event(legacy_payload)
        if not event_rows:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Camera event save returned no rows.")

        camera_event_id = str(event_rows[0]["id"])
        threat_level_id = await self._lookup_id("threat_levels", score.threat_level_key)
        await self._service_rest_request(
            "POST",
            "/threat_scores?on_conflict=camera_event_id",
            json={
                "user_id": str(user.id),
                "camera_event_id": camera_event_id,
                "threat_level_id": threat_level_id,
                "anomaly_score": round(score.anomaly_score, 6),
                "contextual_score": round(score.contextual_score, 6),
                "threat_probability": round(score.threat_probability, 6),
                "feature_access_time_hour": round(features.access_time_hour, 4),
                "feature_duration_seconds": round(features.duration_seconds, 3),
                "feature_activation_frequency": features.activation_frequency,
                "feature_background_access": features.background_access,
                "feature_unknown_or_untrusted": features.unknown_or_untrusted,
                "feature_network_upload_after_camera": features.network_upload_after_camera,
                "feature_permission_changed_recently": features.permission_changed_recently,
                "feature_repeated_short_activation": features.repeated_short_activation,
                "scoring_version": "tcb-ad-1",
            },
            prefer="resolution=merge-duplicates,return=minimal",
        )

        return CameraEventCreateResponse(
            id=UUID(camera_event_id),
            client_event_id=request.client_event_id,
            saved=True,
            score=ThreatScoreResponse(
                anomaly_score=score.anomaly_score,
                contextual_score=score.contextual_score,
                threat_probability=score.threat_probability,
                threat_level=score.threat_level_key,
            ),
        )

    async def _insert_camera_event(self, event_payload: Dict[str, Any]) -> Any:
        return await self._service_rest_request(
            "POST",
            "/camera_events?on_conflict=device_id,client_event_id&select=id,client_event_id",
            json=event_payload,
            prefer="resolution=merge-duplicates,return=representation",
        )

    async def list_camera_events(self, user: AuthUser, limit: int = 50) -> CameraEventHistoryResponse:
        self._require_service_role()
        safe_limit = max(1, min(limit, 100))
        rows = await self._service_rest_request(
            "GET",
            "/camera_events"
            "?select=id,client_event_id,occurred_at,camera_status,notes,"
            "observed_app_name,observed_process_id,observed_bundle_identifier,"
            "applications(display_name),"
            "devices(id,display_name,device_types(key),operating_systems(name,version)),"
            "protection_actions(action,result,confidence),"
            "threat_scores(anomaly_score,contextual_score,threat_probability,threat_levels(key))"
            f"&user_id=eq.{user.id}&order=occurred_at.desc&limit={safe_limit}",
        )
        return CameraEventHistoryResponse(events=[self._parse_history_item(row) for row in rows])

    async def _same_source_context(self, user_id: UUID, request: CameraEventCreateRequest) -> Dict[str, int]:
        source_key = self._source_key_for_request(request)
        if not source_key:
            return {"recent_count": 0, "short_activation_count": 0, "network_upload_count": 0}

        window_start = request.occurred_at.astimezone(timezone.utc) - timedelta(seconds=request.recent_window_seconds)
        rows = await self._service_rest_request(
            "GET",
            "/camera_events"
            "?select=client_event_id,occurred_at,camera_status,duration_seconds,"
            "activation_count_recent_window,is_repeated_short_activation,network_upload_after_camera,"
            "observed_app_name,observed_bundle_identifier,notes"
            f"&user_id=eq.{user_id}"
            f"&occurred_at=gte.{quote(window_start.isoformat(), safe='')}"
            "&order=occurred_at.desc&limit=100",
        )

        recent_count = 0
        short_activation_count = 0
        network_upload_count = 0
        for row in rows:
            if str(row.get("client_event_id")) == str(request.client_event_id):
                continue
            if not self._row_matches_source(row, source_key):
                continue
            recent_count += 1
            duration = row.get("duration_seconds")
            is_short = bool(row.get("is_repeated_short_activation"))
            if duration is not None:
                try:
                    is_short = is_short or float(duration) < 5
                except (TypeError, ValueError):
                    pass
            if is_short:
                short_activation_count += 1
            if row.get("network_upload_after_camera"):
                network_upload_count += 1

        return {
            "recent_count": recent_count,
            "short_activation_count": short_activation_count,
            "network_upload_count": network_upload_count,
        }

    def _source_key_for_request(self, request: CameraEventCreateRequest) -> str:
        return (
            self._normalize_source(request.observed_website_host)
            or self._normalize_source(self._host_from_url(request.observed_website_url))
            or self._normalize_source(request.application.bundle_identifier)
            or self._normalize_source(request.application.display_name)
        )

    def _row_matches_source(self, row: Dict[str, Any], source_key: str) -> bool:
        candidates = [
            self._normalize_source(row.get("observed_bundle_identifier")),
            self._normalize_source(row.get("observed_app_name")),
            self._normalize_source(self._website_host_from_notes(row.get("notes"))),
        ]
        if source_key in candidates:
            return True

        observed_name = self._normalize_source(row.get("observed_app_name"))
        return bool(observed_name and source_key and source_key in observed_name)

    def _normalize_source(self, value: Optional[str]) -> str:
        if not value:
            return ""
        normalized = value.strip().lower()
        if normalized.startswith("http://") or normalized.startswith("https://"):
            normalized = self._host_from_url(normalized) or normalized
        if normalized.startswith("www."):
            normalized = normalized[4:]
        normalized = normalized.split("/", 1)[0].strip()
        if normalized == "127.0.0.1":
            return "localhost"
        return normalized

    def _host_from_url(self, value: Optional[str]) -> str:
        if not value:
            return ""
        parsed = urlparse(value if "://" in value else f"https://{value}")
        return parsed.hostname or ""

    def _website_host_from_notes(self, notes: Optional[str]) -> str:
        if not notes or "URL:" not in notes:
            return ""
        possible_url = notes.rsplit("URL:", 1)[-1].strip()
        return self._host_from_url(possible_url)

    async def _get_owned_device(self, user_id: UUID, device_id: UUID) -> Dict[str, Any]:
        rows = await self._service_rest_request(
            "GET",
            f"/devices?id=eq.{device_id}&user_id=eq.{user_id}&select=id,device_type_id&limit=1",
        )
        if not rows:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device is not registered for this account.")
        return rows[0]

    async def _latest_registered_macos_device(self) -> Dict[str, Any]:
        rows = await self._service_rest_request(
            "GET",
            "/devices?select=id,user_id,device_type_id,device_types(key)"
            "&order=last_seen_at.desc.nullslast&limit=20",
        )
        for row in rows:
            device_type = row.get("device_types") or {}
            if device_type.get("key") == "macos":
                return row
        if rows:
            return rows[0]
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No registered device is available for local critical testing.")

    async def _lookup_id(self, table: str, key: str) -> int:
        rows = await self._service_rest_request("GET", f"/{table}?key=eq.{key}&select=id&limit=1")
        if not rows:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Missing lookup key: {table}.{key}")
        return int(rows[0]["id"])

    async def _upsert_application(
        self,
        device_type_id: int,
        display_name: str,
        bundle_identifier: Optional[str],
        signing_team_id: Optional[str],
    ) -> Optional[str]:
        if not bundle_identifier:
            return None

        encoded_bundle_identifier = quote(bundle_identifier, safe="")
        existing_rows = await self._service_rest_request(
            "GET",
            f"/applications?device_type_id=eq.{device_type_id}"
            f"&bundle_identifier=eq.{encoded_bundle_identifier}"
            "&select=id&limit=1",
        )
        if existing_rows:
            return str(existing_rows[0]["id"])

        rows = await self._service_rest_request(
            "POST",
            "/applications?select=id",
            json={
                "device_type_id": device_type_id,
                "display_name": display_name,
                "bundle_identifier": bundle_identifier,
                "signing_team_id": signing_team_id,
            },
            prefer="return=representation",
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
            logger.exception("Supabase event request failed")
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Event service is unavailable.") from exc

        if response.status_code >= 400:
            logger.warning("Supabase event request failed with status %s: %s", response.status_code, response.text)
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Camera event save failed.")

        if not response.content:
            return []
        return response.json()

    def _require_service_role(self) -> None:
        if not self.settings.supabase_secret_key:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Event service is not configured.")

    def _hour_fraction(self, value) -> float:
        utc_value = value.astimezone(timezone.utc)
        return utc_value.hour + (utc_value.minute / 60.0) + (utc_value.second / 3600.0)

    def _parse_history_item(self, row: Dict[str, Any]) -> CameraEventHistoryItem:
        application = row.get("applications") or {}
        device = row.get("devices") or {}
        device_type = device.get("device_types") or {}
        operating_system = device.get("operating_systems") or {}
        protection_action = self._first_or_object(row.get("protection_actions"))
        score_payload = self._first_or_object(row.get("threat_scores"))
        threat_level_payload = self._first_or_object((score_payload or {}).get("threat_levels")) if score_payload else None
        score = None
        if score_payload:
            score = ThreatScoreResponse(
                anomaly_score=float(score_payload["anomaly_score"]),
                contextual_score=float(score_payload["contextual_score"]),
                threat_probability=float(score_payload["threat_probability"]),
                threat_level=(threat_level_payload or {}).get("key") or "normal",
            )

        return CameraEventHistoryItem(
            id=UUID(str(row["id"])),
            client_event_id=UUID(str(row["client_event_id"])),
            occurred_at=row["occurred_at"],
            camera_status=row["camera_status"],
            notes=row.get("notes"),
            application_display_name=application.get("display_name") or row.get("observed_app_name"),
            observed_process_id=row.get("observed_process_id"),
            observed_bundle_identifier=row.get("observed_bundle_identifier"),
            observed_website_url=row.get("observed_website_url") or self._website_url_from_notes(row.get("notes")),
            observed_website_host=row.get("observed_website_host") or self._website_host_from_notes(row.get("notes")),
            source_device_id=UUID(str(device["id"])) if device.get("id") else None,
            source_device_name=device.get("display_name"),
            source_device_type=device_type.get("key"),
            source_device_os=(
                f"{operating_system.get('name')} {operating_system.get('version')}"
                if operating_system.get("name") and operating_system.get("version")
                else None
            ),
            protection_action=protection_action.get("action") if protection_action else None,
            protection_result=protection_action.get("result") if protection_action else None,
            protection_confidence=protection_action.get("confidence") if protection_action else None,
            score=score,
        )

    def _first_or_object(self, value: Any) -> Optional[Dict[str, Any]]:
        if isinstance(value, list):
            return value[0] if value else None
        if isinstance(value, dict):
            return value
        return None

    def _website_url_from_notes(self, notes: Optional[str]) -> str:
        if not notes or "URL:" not in notes:
            return ""
        return notes.rsplit("URL:", 1)[-1].strip()
