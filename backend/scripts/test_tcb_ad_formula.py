from pathlib import Path
import sys

sys.path.append(str(Path(__file__).resolve().parents[1]))

from app.services.tcb_ad_service import TCBADFeatures, TCBADService


def assert_close(actual: float, expected: float, tolerance: float = 0.000001) -> None:
    if abs(actual - expected) > tolerance:
        raise AssertionError(f"Expected {expected}, got {actual}")


def main() -> None:
    service = TCBADService()

    normal = service.score(
        TCBADFeatures(
            access_time_hour=13,
            duration_seconds=90,
            activation_frequency=2,
            background_access=False,
            unknown_or_untrusted=False,
            network_upload_after_camera=False,
            permission_changed_recently=False,
            repeated_short_activation=False,
        )
    )
    assert_close(normal.anomaly_score, 0)
    assert_close(normal.contextual_score, 0)
    if normal.threat_level_key != "normal":
        raise AssertionError(f"Expected normal, got {normal.threat_level_key}")

    trusted_meeting = service.score(
        TCBADFeatures(
            access_time_hour=13,
            duration_seconds=120,
            activation_frequency=1,
            background_access=False,
            unknown_or_untrusted=False,
            network_upload_after_camera=False,
            permission_changed_recently=False,
            repeated_short_activation=False,
        )
    )
    if trusted_meeting.threat_level_key != "normal":
        raise AssertionError(f"Expected trusted meeting camera use to be normal, got {trusted_meeting.threat_level_key}")

    repeated_short = service.score(
        TCBADFeatures(
            access_time_hour=13,
            duration_seconds=3,
            activation_frequency=3,
            background_access=False,
            unknown_or_untrusted=True,
            network_upload_after_camera=False,
            permission_changed_recently=False,
            repeated_short_activation=True,
        )
    )
    if repeated_short.threat_level_key not in {"suspicious", "critical"}:
        raise AssertionError(f"Expected repeated short camera activations to be suspicious or critical, got {repeated_short.threat_level_key}")

    camera_network = service.score(
        TCBADFeatures(
            access_time_hour=13,
            duration_seconds=3,
            activation_frequency=1,
            background_access=False,
            unknown_or_untrusted=True,
            network_upload_after_camera=True,
            permission_changed_recently=False,
            repeated_short_activation=True,
        )
    )
    if camera_network.threat_level_key != "critical":
        raise AssertionError(f"Expected camera followed by network activity to be critical, got {camera_network.threat_level_key}")

    suspicious = service.score(
        TCBADFeatures(
            access_time_hour=3,
            duration_seconds=5,
            activation_frequency=8,
            background_access=True,
            unknown_or_untrusted=True,
            network_upload_after_camera=True,
            permission_changed_recently=True,
            repeated_short_activation=True,
        )
    )
    if suspicious.anomaly_score <= normal.anomaly_score:
        raise AssertionError("Anomalous behavior should increase Mahalanobis distance.")
    if suspicious.contextual_score <= normal.contextual_score:
        raise AssertionError("Risk flags should increase contextual suspicion score.")
    if suspicious.threat_probability <= normal.threat_probability:
        raise AssertionError("Threat probability should increase for anomalous risky behavior.")

    print("TCB-AD formula check passed")
    print(f"normal probability={normal.threat_probability:.6f}, level={normal.threat_level_key}")
    print(f"trusted meeting probability={trusted_meeting.threat_probability:.6f}, level={trusted_meeting.threat_level_key}")
    print(f"repeated short probability={repeated_short.threat_probability:.6f}, level={repeated_short.threat_level_key}")
    print(f"camera network probability={camera_network.threat_probability:.6f}, level={camera_network.threat_level_key}")
    print(f"risky probability={suspicious.threat_probability:.6f}, level={suspicious.threat_level_key}")


if __name__ == "__main__":
    main()
