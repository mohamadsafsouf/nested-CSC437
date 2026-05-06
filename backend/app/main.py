from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from app.api.routes import auth, devices, events, health, protection, test_simulator
from app.core.config import get_settings
from app.core.logging import configure_logging


def create_app() -> FastAPI:
    configure_logging()
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="CamGuard backend API for Supabase-backed authentication and security event ingestion.",
    )

    # Local simulator pages (e.g. :3000) POST metadata to :8000.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_methods=["POST", "OPTIONS"],
        allow_headers=["*"],
    )

    app.include_router(health.router, prefix=settings.api_v1_prefix)
    app.include_router(auth.router, prefix=settings.api_v1_prefix)
    app.include_router(devices.router, prefix=settings.api_v1_prefix)
    app.include_router(events.router, prefix=settings.api_v1_prefix)
    app.include_router(protection.router, prefix=settings.api_v1_prefix)
    # Unversioned; used only by the local web attack simulator (metadata-only).
    app.include_router(test_simulator.router)

    @app.get("/", response_class=HTMLResponse, include_in_schema=False)
    async def auth_callback_page() -> str:
        return """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CamGuard Account Confirmation</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #020617; color: #f8fafc; }
    main { width: min(560px, calc(100vw - 48px)); padding: 32px; border: 1px solid rgba(255,255,255,.12); border-radius: 24px; background: rgba(15,23,42,.92); box-shadow: 0 24px 80px rgba(0,0,0,.35); }
    .badge { display: inline-flex; gap: 8px; align-items: center; color: #22c55e; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; font-size: 12px; }
    h1 { margin: 18px 0 10px; font-size: 32px; }
    p { color: #94a3b8; line-height: 1.55; }
    code { color: #f8fafc; background: rgba(255,255,255,.08); padding: 2px 6px; border-radius: 6px; }
  </style>
</head>
<body>
  <main>
    <div class="badge" id="statusBadge">CamGuard Account</div>
    <h1 id="title">Confirming email...</h1>
    <p id="message">Securing your CamGuard account.</p>
  </main>
  <script>
    const title = document.getElementById("title");
    const message = document.getElementById("message");
    const badge = document.getElementById("statusBadge");

    function setState(nextTitle, nextMessage, color = "#22c55e") {
      title.textContent = nextTitle;
      message.textContent = nextMessage;
      badge.style.color = color;
    }

    async function confirmFromHash() {
      const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
      const error = hash.get("error_description") || hash.get("error");
      if (error) {
        setState("Confirmation failed", error + ". Request a fresh confirmation email from CamGuard.", "#f59e0b");
        return;
      }

      const accessToken = hash.get("access_token");
      const refreshToken = hash.get("refresh_token");
      if (!accessToken || !refreshToken) {
        setState("Confirmation link incomplete", "Open this page from the newest CamGuard confirmation email.", "#f59e0b");
        return;
      }

      try {
        const response = await fetch("/api/v1/auth/confirm-session", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            access_token: accessToken,
            refresh_token: refreshToken,
            token_type: hash.get("token_type") || "bearer",
            expires_in: hash.get("expires_in") ? Number(hash.get("expires_in")) : null,
            expires_at: hash.get("expires_at") ? Number(hash.get("expires_at")) : null
          })
        });

        if (!response.ok) {
          const data = await response.json().catch(() => ({}));
          throw new Error(data.detail || "CamGuard could not validate this session.");
        }

        window.history.replaceState({}, document.title, "/");
        setState("Email confirmed", "Your CamGuard account is confirmed. Return to the macOS app and sign in.");
      } catch (error) {
        setState("Confirmation failed", error.message, "#ef4444");
      }
    }

    confirmFromHash();
  </script>
</body>
</html>
        """
    return app


app = create_app()
