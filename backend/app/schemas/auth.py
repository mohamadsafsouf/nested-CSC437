from datetime import datetime
from typing import Any, Dict, Optional
from uuid import UUID
from pydantic import BaseModel, Field, field_validator


def normalize_email(value: str) -> str:
    email = value.strip().lower()
    if "@" not in email or "." not in email.rsplit("@", maxsplit=1)[-1]:
        raise ValueError("Enter a valid email address.")
    return email


class SignUpRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=120)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)


class SignInRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class ConfirmSessionRequest(BaseModel):
    access_token: str = Field(min_length=1)
    refresh_token: str = Field(min_length=1)
    token_type: str = "bearer"
    expires_in: Optional[int] = None
    expires_at: Optional[int] = None


class ResendConfirmationRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)


class SignOutRequest(BaseModel):
    access_token: str = Field(min_length=1)


class AuthUser(BaseModel):
    id: UUID
    email: Optional[str] = None
    display_name: Optional[str] = None
    created_at: Optional[datetime] = None


class AuthSession(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: Optional[int] = None
    expires_at: Optional[int] = None


class AuthResponse(BaseModel):
    user: AuthUser
    session: Optional[AuthSession] = None


class SupabaseAuthPayload(BaseModel):
    user: Optional[Dict[str, Any]] = None
    session: Optional[Dict[str, Any]] = None
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
    token_type: Optional[str] = None
    expires_in: Optional[int] = None
    expires_at: Optional[int] = None
