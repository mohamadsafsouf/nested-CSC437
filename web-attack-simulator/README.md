# Web attack simulator (static test page)

This folder holds static assets (for example `camera-upload-test/index.html`) used to exercise Cam Guard flows during development.

There is **no** Python package or `backend/` directory here. The FastAPI server lives in the repository root under **`backend/`**.

## Run the API (from another terminal)

From the **repository root** or by changing into `backend`:

```sh
cd /path/to/netsec/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The API listens on `http://127.0.0.1:8000` (see `backend/README.md`).

## Run this static test page

From this directory (only serves HTML; it does not run FastAPI):

```sh
cd /path/to/netsec/web-attack-simulator
python3 -m http.server 3000
```

Then open the test HTML under `camera-upload-test/` in a browser, with the **backend** already running in the other terminal.

## Why `ModuleNotFoundError: No module named 'app'`

`uvicorn app.main:app` must be executed with the **current working directory** set to `backend/`, so Python can import the `app` package. If you start uvicorn from `web-attack-simulator/`, that package is not on the path and the import fails.
