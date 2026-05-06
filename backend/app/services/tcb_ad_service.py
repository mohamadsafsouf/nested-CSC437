import math
from dataclasses import dataclass
from typing import List, Sequence


@dataclass(frozen=True)
class TCBADFeatures:
    access_time_hour: float
    duration_seconds: float
    activation_frequency: int
    background_access: bool
    unknown_or_untrusted: bool
    network_upload_after_camera: bool
    permission_changed_recently: bool
    repeated_short_activation: bool
    same_source_recent_count: int = 1
    same_source_network_upload_count: int = 0


@dataclass(frozen=True)
class TCBADScore:
    anomaly_score: float
    contextual_score: float
    threat_probability: float
    threat_level_key: str


class TCBADService:
    """TCB-AD scoring: Mahalanobis anomaly + contextual suspicion + sigmoid probability."""

    default_mean: Sequence[float] = (13.0, 90.0, 2.0)
    default_covariance_inverse: Sequence[Sequence[float]] = (
        (0.028, 0.0, 0.0),
        (0.0, 0.0004, 0.0),
        (0.0, 0.0, 0.25),
    )
    anomaly_weight = 0.85
    contextual_weight = 1.0
    sigmoid_bias = 4.0

    def score(
        self,
        features: TCBADFeatures,
        mean: Sequence[float] = default_mean,
        covariance_inverse: Sequence[Sequence[float]] = default_covariance_inverse,
    ) -> TCBADScore:
        vector = [
            features.access_time_hour,
            features.duration_seconds,
            float(features.activation_frequency),
        ]
        anomaly_score = self.mahalanobis_distance(vector, mean, covariance_inverse)
        contextual_score = self.contextual_score(features)
        threat_probability = self.sigmoid(
            (self.anomaly_weight * anomaly_score)
            + (self.contextual_weight * contextual_score)
            - self.sigmoid_bias
        )
        return TCBADScore(
            anomaly_score=anomaly_score,
            contextual_score=contextual_score,
            threat_probability=threat_probability,
            threat_level_key=self.threat_level_key(threat_probability),
        )

    def mahalanobis_distance(
        self,
        vector: Sequence[float],
        mean: Sequence[float],
        covariance_inverse: Sequence[Sequence[float]],
    ) -> float:
        if len(vector) != len(mean) or len(covariance_inverse) != len(vector):
            raise ValueError("Feature vector, mean vector, and covariance inverse dimensions must match.")

        delta = [value - mean_value for value, mean_value in zip(vector, mean)]
        weighted: List[float] = []
        for row in covariance_inverse:
            if len(row) != len(vector):
                raise ValueError("Covariance inverse must be square and match feature vector dimensions.")
            weighted.append(sum(row[index] * delta[index] for index in range(len(delta))))

        squared_distance = sum(delta[index] * weighted[index] for index in range(len(delta)))
        return math.sqrt(max(squared_distance, 0.0))

    def contextual_score(self, features: TCBADFeatures) -> float:
        score = 0.0
        if features.background_access:
            score += 1.4
        if features.unknown_or_untrusted:
            score += 1.3
        if features.network_upload_after_camera:
            score += 3.4
        if features.permission_changed_recently:
            score += 0.8
        if features.repeated_short_activation:
            score += 1.2
        if features.same_source_recent_count >= 3:
            score += 1.4
        if features.same_source_recent_count >= 3 and features.same_source_network_upload_count > 0:
            score += 1.2
        return score

    def sigmoid(self, value: float) -> float:
        if value >= 0:
            z = math.exp(-value)
            return 1 / (1 + z)
        z = math.exp(value)
        return z / (1 + z)

    def threat_level_key(self, probability: float) -> str:
        if probability >= 0.85:
            return "critical"
        if probability >= 0.50:
            return "suspicious"
        return "normal"
