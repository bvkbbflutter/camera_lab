# Camera Lab API

Base URL (default): `http://localhost:3000`. From an Android emulator use
`http://10.0.2.2:3000`; from a physical device use your machine's LAN IP,
e.g. `http://192.168.1.23:3000`.

## Authentication

Disabled by default (fine for a local POC). Set `API_TOKEN` in the
environment to require `Authorization: Bearer <token>` on every
`/api/images/*` route. `/api/health` never requires auth.

## Limits

| Limit | Default | Env var |
|---|---|---|
| Max file size | 25 MB | `MAX_FILE_MB` |
| Max dimension (either side) | 16384 px | `MAX_DIMENSION` |
| Max pixels | 100,000,000 (100 MP) | `MAX_PIXELS` |

Supported formats: **JPEG, PNG, WebP**, detected from the file's actual
magic bytes — the client's declared MIME type / filename extension is
never trusted on its own.

---

## `GET /api/health`

```json
{ "success": true, "status": "ok", "uptimeSeconds": 42, "timestamp": "2026-09-24T05:12:00.000Z" }
```

---

## `POST /api/images/base64`

Content-Type: `application/json`

### Request

```json
{
  "fileName": "IMG_001.jpg",
  "mimeType": "image/jpeg",
  "imageBase64": "<base64 of the actual JPEG/PNG/WebP bytes>",
  "uploadId": "optional-client-id",
  "userId": "optional-user-id"
}
```

`latitude`/`longitude` are **not** accepted as request fields — GPS must
already be embedded in the image's own EXIF. The server extracts it from
the file if needed.

### Response `201 Created`

```json
{
  "success": true,
  "fileId": "f0eaf37e-e93e-48d8-882b-421c5027087e",
  "image": {
    "id": "f0eaf37e-...",
    "fileName": "IMG_001.jpg",
    "format": "jpeg",
    "mimeType": "image/jpeg",
    "width": 1920,
    "height": 1440,
    "fileSizeBytes": 428531,
    "uploadMethod": "base64",
    "uploadedAt": "2026-09-24T05:56:04.253Z",
    "exifPresent": true,
    "hasGps": true,
    "url": "http://localhost:3000/api/images/f0eaf37e-...",
    "metadataUrl": "http://localhost:3000/api/images/f0eaf37e-.../metadata"
  }
}
```

### Errors

| Status | code | Cause |
|---|---|---|
| 400 | `MISSING_IMAGE_BASE64` | `imageBase64` missing/not a string |
| 400 | `INVALID_BASE64` | Not valid Base64 |
| 400 | `EMPTY_FILE` | Decoded to 0 bytes |
| 400 | `CORRUPT_IMAGE` | Recognized format but unparsable container |
| 400 | `DIMENSIONS_TOO_LARGE` / `TOO_MANY_PIXELS` | Exceeds configured limits |
| 413 | `FILE_TOO_LARGE` | Exceeds `MAX_FILE_MB` |
| 415 | `UNSUPPORTED_FORMAT` | Not a JPEG/PNG/WebP by magic bytes |
| 401 | `UNAUTHORIZED` | Missing/invalid bearer token (if `API_TOKEN` set) |

---

## `POST /api/images/multipart`

Content-Type: `multipart/form-data`

Fields: `file` (the image binary, required), `uploadId` (optional),
`userId` (optional).

```bash
curl -F "file=@photo.jpg" -F "uploadId=abc123" http://localhost:3000/api/images/multipart
```

Response shape and error codes are identical to the Base64 endpoint,
plus multer-specific errors (`MULTER_LIMIT_FILE_SIZE` → 413,
`MISSING_FILE` → 400 if the `file` field is absent).

---

## `GET /api/images`

Query params: `limit` (default 50, max 200), `offset` (default 0).

```json
{ "success": true, "total": 12, "limit": 50, "offset": 0, "images": [ /* summaries, as above */ ] }
```

## `GET /api/images/:id`

Streams the stored binary as-is (exact bytes originally uploaded — never
re-encoded), with the correct `Content-Type`.

## `GET /api/images/:id/metadata`

Re-reads the stored file itself on every call and extracts everything
embedded in it — this is a derived/indexed view, not the source of truth.

```json
{
  "success": true,
  "fileId": "f0eaf37e-...",
  "source": "embedded-in-image",
  "metadata": {
    "format": "jpeg", "mimeType": "image/jpeg", "width": 1920, "height": 1440,
    "fileSizeBytes": 428531,
    "exif": { "present": true, "sizeBytes": 596, "error": null },
    "metadataBytes": 596,
    "gps": { "latitude": 17.385044, "longitude": 78.486671, "latitudeRef": "N", "longitudeRef": "E", "altitude": 530, "horizontalAccuracyM": null, "gpsDate": "2026:09:24" },
    "capture": { "dateTimeOriginal": "2026:09:24 10:42:31", "dateTime": "2026:09:24 10:42:31", "offsetTimeOriginal": "+05:30", "capturedAt": "2026-09-24T10:42:31.123+05:30" },
    "camera": { "make": "Samsung", "model": "SM-S928B", "lensMake": null, "lensModel": "Back Camera 26mm f/1.8", "facing": "back", "software": "Camera Lab 1.0", "exposureTime": 0.0083, "fNumber": 1.8, "iso": 100, "focalLengthMm": 26 },
    "orientation": { "value": 1, "label": "Normal (0°)" },
    "dpi": { "x": 300, "y": 300, "source": "exif" },
    "nativeDensity": null,
    "formatDetails": { "progressive": false }
  },
  "indexed": { "latitude": 17.385044, "longitude": 78.486671, "altitude": 530, "capturedAt": "2026-09-24T10:42:31.123+05:30", "cameraMake": "Samsung", "cameraModel": "SM-S928B", "orientation": 1, "dpiX": 300, "dpiY": 300 }
}
```

`404 NOT_FOUND` if the id doesn't exist.

## `DELETE /api/images/:id`

Removes both the `db.json` record and the file under `assets/`.

```json
{ "success": true, "deletedId": "f0eaf37e-..." }
```

---

## Network-test header (dev only)

When the server is started with `SIMULATE=true`, every `/api/images/*`
request may carry an `X-Simulate` header to force a specific response,
for the app's Network Tests screen:

| Value | Effect |
|---|---|
| `400` / `401` / `413` / `500` | Immediately returns that status with a `SIMULATED_*` error code |
| `timeout` | Never responds — the client's own timeout must fire |
| `slow:2000` | Delays 2000ms, then processes normally |
