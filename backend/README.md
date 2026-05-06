# CamGuard Backend API

FastAPI backend used by the macOS app, iPhone app, and dashboard. Apps should call this API instead of directly implementing separate auth/network logic per client.

## Setup

Install dependencies:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run locally from `backend/`:

```sh
uvicorn app.main:app --reload
```

The API will be available at:

```text
http://127.0.0.1:8000/api/v1
```

The macOS app defaults to that base URL. For a different backend URL during development, set this macOS `UserDefaults` value:

```sh
defaults write com.Safsouf.NetSecMacos camguard.backend.baseURL "http://127.0.0.1:8000/api/v1"
```

The backend reads Supabase values from environment variables. For local development it can also read the repo root `.env`. Do not commit or log secret values.

## Auth Endpoints

Base path: `/api/v1`

### `POST /auth/sign-up`

Creates a Supabase Auth user and attempts to upsert the matching `public.users` profile row.

```json
{
  "email": "user@example.com",
  "password": "minimum-8-characters",
  "display_name": "User Name"
}
```

### `POST /auth/sign-in`

Signs in through Supabase Auth.

```json
{
  "email": "user@example.com",
  "password": "password"
}
```

### `POST /auth/refresh`

Refreshes a Supabase session.

```json
{
  "refresh_token": "..."
}
```

### `POST /auth/confirm-session`

Validates an access token returned in a Supabase email confirmation URL fragment and returns the normalized auth response.

This is used by the root callback page at:

```text
http://localhost:8000/#access_token=...
```

The browser does not send URL fragments to the server, so the page reads the fragment locally and posts it to this endpoint.

### `POST /auth/resend-confirmation`

Requests a fresh Supabase signup confirmation email.

```json
{
  "email": "user@example.com"
}
```

If Supabase redirects confirmation links to `localhost:3000`, that is controlled by the Supabase Auth URL configuration. Until the dashboard exists, the browser may show “can't connect” after confirmation even when the email token itself is valid.

### `GET /auth/me`

Returns the current user. Send:

```text
Authorization: Bearer <access_token>
```

### `POST /auth/sign-out`

Signs out the Supabase session.

```json
{
  "access_token": "..."
}
```

## Response Shape

Auth endpoints return:

```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "User Name",
    "created_at": "timestamp"
  },
  "session": {
    "access_token": "...",
    "refresh_token": "...",
    "token_type": "bearer",
    "expires_in": 3600,
    "expires_at": 1234567890
  }
}
```

## Notes

- The backend uses the Supabase publishable key for user-scoped Auth requests.
- Service-role access should only be added for backend-owned ingestion/scoring paths, not client-facing auth.
- The macOS app now calls these backend auth endpoints and stores the returned Supabase session in Keychain.
- Optional: set `CAMGUARD_AUTH_EMAIL_REDIRECT_TO` in the backend environment to override the confirmation redirect URL, and allow that URL in Supabase Auth settings.
