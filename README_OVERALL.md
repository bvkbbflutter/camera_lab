# Camera Lab

A Flutter + Node.js proof of concept for benchmarking camera capture,
image formats (JPEG/PNG/WebP), compression, and — the core focus — **EXIF/
GPS metadata embedded directly inside the image file**, verified after
every processing step rather than assumed.

```
camera-lab/
├── app/        Flutter app (Camera Lab)
├── server/     Node.js + Express + Multer backend, db.json + assets/
├── VALIDATION.md   Exactly what was tested here, and how (read this first)
└── README.md   This file
```

**Read [`VALIDATION.md`](VALIDATION.md) before relying on this.** The
Node server was fully run and tested in the environment that built this
(22/22 tests passing against real EXIF fixtures). The Flutter app could
not be compiled here (no Dart/Flutter SDK in that sandbox) — its
metadata-embedding algorithms were cross-validated by porting them to
Node and round-tripping through the tested server parser, but the Dart
source itself needs `flutter pub get && flutter test && flutter analyze`
on a real machine before you trust it further.

---

## The core principle

> **Metadata lives inside the image file, not in a separate JSON
> object.** GPS, capture time, camera make/model, orientation and DPI are
> written into the image's own EXIF (JPEG APP1 / PNG eXIf chunk / WebP
> EXIF chunk) by hand-written code in `app/lib/services/metadata/` — no
> EXIF plugin, no black box. The server extracts metadata *from the
> uploaded image* rather than trusting request fields for it.

Every processing step follows: **read original metadata → decode pixels
→ resize/rotate → encode → write metadata → reopen the output → read its
metadata again → compare against the original.** Nothing is assumed
preserved; the Metadata Comparison screen shows exactly what survived,
what changed, and what your chosen encoder doesn't support — see
`app/lib/services/metadata/metadata_verifier.dart`.

---

## Quick start

### 1. Server

```bash
cd server
npm install
npm start
```

Starts on `http://localhost:3000`. `GET /api/health` should return
`{"success":true,...}`. Full endpoint docs: [`server/API.md`](server/API.md).

Run its test suite any time with `npm test` (22 tests, no network or
Flutter needed).

### 2. Flutter app — first-time setup

This project's Dart source (`app/lib/`) and `app/pubspec.yaml` are
complete, but **`flutter create .` has not been run** in it yet — there's
no `android/`/`ios/` platform scaffold, since the environment that built
this has no Flutter SDK to generate one. On a machine that does:

```bash
cd app
flutter create . --project-name camera_lab --org com.example
flutter pub get
```

`flutter create .` on an existing project only fills in the missing
platform folders — it won't overwrite `lib/` or `pubspec.yaml`. Then:

1. Merge [`app/android_permissions_snippet.xml`](app/android_permissions_snippet.xml)
   into the generated `android/app/src/main/AndroidManifest.xml`.
2. Merge [`app/ios_permissions_snippet.plist`](app/ios_permissions_snippet.plist)
   into the generated `ios/Runner/Info.plist`.
3. `flutter test` (includes `test/metadata_roundtrip_test.dart`) and
   `flutter analyze`, and fix anything that surfaces — see `VALIDATION.md`
   for why this step matters here specifically.
4. `flutter run`.

### 3. Point the app at the server

Settings → Server → **Server base URL**:

| Running on | URL |
|---|---|
| Android emulator | `http://10.0.2.2:3000` (default) |
| iOS simulator | `http://localhost:3000` |
| Physical device (same Wi-Fi as your machine) | `http://<your-machine's-LAN-IP>:3000` |

The server binds `0.0.0.0` by default specifically so a phone on the same
network can reach it. Find your machine's LAN IP with `ipconfig` (Windows)
or `ifconfig`/`ip addr` (macOS/Linux).

---

## How capture → upload works

```
Camera → collect device/camera metadata → get GPS fix (if enabled)
       → embed metadata into the captured file → save locally → Preview
```

From Preview, **Process Image** runs the full pipeline (resize, re-encode
as JPEG/PNG/WebP, re-embed the metadata you choose to keep, verify), and
**Upload** enqueues the file for Base64-JSON or multipart delivery via a
persistent local queue — captures are never lost if the network is down;
they stay in the Upload Queue tab with Retry/Delete/Upload-now controls
until the server confirms success.

### How location metadata works

Settings → Location: toggle metadata on/off, and separately whether to
**require** a fix before allowing capture (off by default — capture is
never blocked on GPS unless you opt into that). A "maximum location age"
setting controls how stale a pre-warmed fix is allowed to be before the
app re-queries the OS at capture time.

### How EXIF works here

`app/lib/services/metadata/tiff.dart` implements a real TIFF/EXIF reader
and writer from scratch — IFD0, the Exif sub-IFD, and the GPS sub-IFD,
correctly linked by pointer tags, with values over 4 bytes placed in the
TIFF "overflow" area as the format requires. `exif_builder.dart` turns
what the app knows about a capture (`CaptureMetadata`) into that block.

### How DPI works

DPI/PPI is **display metadata, not pixel data** — a 4000×3000 photo at 72
DPI and the same photo at 300 DPI contain the exact same pixels; DPI only
tells a printer/renderer how large to draw them. The DPI screen makes
this explicit rather than implying higher DPI = higher quality. When
written, DPI is stored as EXIF XResolution/YResolution/ResolutionUnit
(JPEG, and PNG's own `pHYs` chunk as a fallback) and — critically — the
app reopens the output file and confirms the value actually landed there
before reporting it as preserved.

### How JPEG / PNG / WebP metadata work (and differ)

- **JPEG**: EXIF lives in an APP1 segment (`app/lib/services/metadata/jpeg_container.dart`).
  Re-embedding strips any old APP1 and inserts a fresh one immediately
  after SOI, without touching the compressed scan data — verified
  byte-for-byte in `VALIDATION.md`.
- **PNG**: lossless, and its EXIF mechanism is the separate `eXIf` chunk
  (`png_container.dart`), inserted right after `IHDR` with a real CRC-32 —
  PNG readers reject a chunk with a wrong CRC, so this is computed
  properly (`crc32.dart`), not stubbed.
- **WebP**: a "simple" WebP (just a VP8/VP8L chunk) has nowhere to put
  EXIF. `webp_container.dart` upgrades it to the **Extended WebP** format
  (adds a `VP8X` chunk) and appends an `EXIF` chunk, tested against both
  lossy and lossless source files.

Each format's Image Details / Metadata Comparison screen reports
`Not supported by encoder` rather than silently pretending a field
survived, if verification shows otherwise.

### Base64 vs. multipart upload

Both send the *processed image itself* as the payload — GPS/date/camera
are never sent as separate JSON fields the server would have to trust.
Base64 inflates payload size by ~33% (shown live, not estimated — the app
only builds the Base64 string when that mode is actually selected, to
avoid holding both encodings in memory unnecessarily) and adds an
encode/decode step multipart skips. The Benchmark screen measures both
for real against your running server, rather than asserting either is
universally better — see spec principle "do not hardcode JPEG/WebP is
always best" — the same philosophy applies to upload method.

### How to inspect metadata

Any image's **⋮ → View Details** reads its metadata live from the file on
disk — never from a cached/separate record — matching exactly what
`GET /api/images/:id/metadata` reports once uploaded (the server performs
the identical kind of extraction independently, in `server/src/image/`).

### Upload queue

`app/lib/services/upload/upload_queue.dart`: PENDING → UPLOADING →
SUCCESS, or → RETRY/FAILED with the error kept and shown, and the image
file is only ever deleted by an explicit user action — never
automatically on a failed upload. The queue is persisted to disk
(`camera_lab_queue.json` in the app's documents directory) so it survives
an app restart.

### Running benchmarks

Benchmark tab → pick a captured source image → **Run Full Benchmark**.
Sweeps JPEG 60–95, PNG, WebP 75–90 and WebP Lossless against that one
source, timing every stage with a real `Stopwatch` (decode, resize,
encode, metadata write, metadata verify, Base64 encode, and — if "also
measure upload" is on — real multipart/Base64 upload time against your
running server). Export the run as CSV or JSON via the share sheet.

### Interpreting results

- **Size/quality**: compare `reductionPercent` against the Quality
  Comparison screen's zoomed view — a smaller file that's visibly worse
  on faces/text/documents isn't actually a win for that use case (spec
  §51's document-vs-photo distinction).
- **metadataPreserved = false** in a row means verification caught a
  field that didn't survive that specific format/quality — check the
  Metadata Comparison screen for *which* field and why (removed by your
  own settings vs. genuinely unsupported by the encoder).
- **Base64 vs multipart timing** is only meaningful with "also measure
  upload" on and a reachable server; otherwise those columns show `—`.

---

## Server internals (for the curious / for extending)

- `server/src/image/` — format sniffing by magic bytes, JPEG/PNG/WebP
  container parsers, and a from-scratch TIFF/EXIF reader — no exiftool,
  no native binding, pure JS, fully unit-tested against real EXIF
  fixtures (`server/test/`).
- `server/src/storage/` — a small `StorageService` interface with a
  `LocalStorageService` implementation (writes to `assets/jpeg|png|webp/`).
  Swap in an S3/Azure/GCS/Firebase/Cloudinary implementation behind the
  same interface for production, per spec §29/§57 — nothing else in the
  route layer needs to change.
- `server/src/db/jsonDb.js` — `db.json` is an atomically-written flat
  file for this POC (write-to-temp + rename, serialized writes). It holds
  an **index** of metadata extracted from each image, never the source of
  truth. Swap for PostgreSQL/MongoDB behind the same four methods
  (`insertImage`, `getImage`, `listImages`, `deleteImage`) for production.
- For very large images, spec §58 documents a signed-upload-URL
  architecture (client uploads directly to object storage, bypassing the
  app server for the binary) as a future option; this POC's `assets/`
  storage is the simpler in-process alternative appropriate for local
  development.

## Security notes

- The server never trusts a client-declared MIME type or file extension —
  every upload's actual format is sniffed from magic bytes
  (`server/src/image/sniff.js`), and a mismatched/fake image is rejected
  with `415 UNSUPPORTED_FORMAT` (tested in `server/test/integration.api.test.js`).
- Request/response logging (`server/src/middleware/requestLogger.js`)
  never logs body content — no Base64 image data, no raw bytes, no
  Authorization header value.
- File size, pixel count and dimension limits are enforced server-side
  regardless of what the client sends (`server/src/config.js`).

## What's intentionally out of scope for this POC

- Multi-frame / animated WebP metadata embedding (documented limitation
  in `webp_container.dart` — animated WebP falls back to being rejected
  rather than silently corrupted).
- A production auth system (the optional bearer token is a placeholder).
- The signed-upload-URL large-file architecture (documented, not built).
