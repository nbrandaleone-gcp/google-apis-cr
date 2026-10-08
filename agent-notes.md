# Agent Project Notes & Design Decisions

**Project:** `google-apis-cr` (Google APIs Client Library for Crystal)  
**Date:** October 8, 2026  
**Language:** Crystal (1.21.1)  
**Linter:** Ameba (1.6.4)  
**Target Platform:** macOS / Darwin (Apple Silicon arm64)

---

## 1. Project Goals & Context

The goal specified in `AGENTS.md` was to build a reusable Crystal client library that interfaces with Google APIs, specifically Google Cloud Storage, capable of listing buckets and the files inside them.

### Key Requirements
1. **Application Default Credentials (ADC)**: Authenticate against Google APIs using local ADC credentials.
2. **Google Discovery Service**: Follow Google's Discovery Service approach to understand API shapes and generate strongly-typed Crystal clients.
3. **Embedded Crystal (ECR)**: Use ECR as the template engine for code generation.
4. **Reusable Shard & CLI Executables**: Provide a reusable library structure along with an executable in `bin/` to demonstrate listing buckets and objects.
5. **Definition of Done**: Verify that listing buckets against Google Cloud Storage includes:
   - `nbrandaleone-bucket`
   - `nbrandaleone-testing`

---

## 2. Environment & Credential Reconnaissance

Before writing code, we inspected the existing machine environment:
- **Crystal & Ameba**: Crystal 1.21.1 and Ameba 1.6.4 were installed via Homebrew.
- **gcloud CLI State**: The global `gcloud` command was encountering a Python 3.14 OpenSSL compatibility error in its virtual environment.
- **Application Default Credentials**: An active ADC credentials file was located at:
  `~/.config/gcloud/application_default_credentials.json`
  - Type: `authorized_user`
  - Quota Project: `testing-355714`
  - Contained `client_id`, `client_secret`, and a valid `refresh_token`.
- **Live Endpoint Verification**: Tested token refresh at `https://oauth2.googleapis.com/token` and verified that querying `https://storage.googleapis.com/storage/v1/b?project=testing-355714` returns the target buckets (`nbrandaleone-bucket` and `nbrandaleone-testing`).

---

## 3. Sub-Agent Authentication Implementation

Per `AGENTS.md` instructions, a sub-agent was dispatched (`delegate_task`) to implement and verify authentication in isolation:

### Implementation (`src/google_apis/auth.cr`)
- **Resolution Precedence**: Checks `$GOOGLE_APPLICATION_CREDENTIALS` environment variable first, then falls back to `~/.config/gcloud/application_default_credentials.json` (or `%APPDATA%/gcloud/...` on Windows) with path expansion.
- **Credential Model**:
  - `AuthorizedUserCredentials`:
    - Handles OAuth2 `refresh_token` exchange at `https://oauth2.googleapis.com/token`.
    - Implements proactive token refresh: refreshes whenever expired or within 60 seconds of expiration.
    - Fiber/thread-safe token access via `Mutex`.
    - Generates standard `authorization_header` (`"Bearer <token>"`).
    - Exposes `project_id` and `quota_project_id`.
    - Redacts secret fields in `#inspect` and `#to_s` to prevent secret leakage in logs or stack traces.
  - `ServiceAccountCredentials`:
    - Parses service account JSON properties.
    - Raises `UnsupportedCredentialsTypeError` explaining that RS256 JWT signing requires external cryptography shards beyond Crystal's standard library.
- **Unit Specs**: Mock HTTP server verifying token exchange, caching behavior, and error handling (`spec/google_apis/auth_spec.cr`).

---

## 4. Google Discovery Service Architecture & ECR Code Generation

### Why Code Generation over Runtime Reflection?
Crystal is a statically-typed, compiled language without dynamic class creation at runtime. Generating code from the Discovery document gives:
- Complete compile-time type safety.
- IDE auto-completion and documentation comments on methods and schemas.
- High runtime performance with zero dynamic reflection overhead.

### How Embedded Crystal (ECR) Was Utilized
Crystal includes `ecr` in its standard library. `ECR.def_to_s("template.ecr")` compiles the template directly into Crystal bytecode inside a view class, generating a `#to_s(io : IO)` method.

#### View Architecture (`src/google_apis/generator/views.cr`)
1. `TypesView`: Renders `types.cr` containing all Discovery schemas.
2. `ResourceServiceView`: Renders individual resource services (e.g. `BucketsService`, `ObjectsService`).
3. `ClientView`: Renders `Client` exposing resource accessors (`client.buckets`, `client.objects`).
4. `ServiceModuleView`: Renders the service module entrypoint (`v1.cr`).

#### ECR Templates (`src/google_apis/generator/templates/`)
- `types.cr.ecr`:
  - Iterates over all 39 schemas in `storage_v1.json`.
  - Generates classes including `JSON::Serializable`.
  - Maps properties using `@[JSON::Field(key: "...")]` to preserve camelCase JSON wire keys while using idiomatic snake_case Crystal identifiers.
  - Adds an `initialize` constructor with default `nil` arguments.
- `resource_service.cr.ecr`:
  - Generates typed methods for each resource method.
  - Handles **Parameter Ordering**: required path and query parameters appear first; optional query parameters appear with default `= nil`.
  - Handles **URI Template Expansion**: replaces `{bucket}`, `{object}`, etc., using `URI.encode_path_segment(...)`.
  - Handles **Query Parameter Construction**: populates only non-nil query parameters.
  - Dispatches calls through `GoogleApis::Client#execute` with typed deserialization.
- `client.cr.ecr`:
  - Initializes `GoogleApis::Client` and all resource service instances.
- `service_module.cr.ecr`:
  - `require`s all generated files.

#### Type Mapping Logic (`src/google_apis/generator.cr`)
- `string` -> `String`
- `integer` -> `Int64`
- `number` -> `Float64`
- `boolean` -> `Bool`
- `array` of `$ref` -> `Array(RefName)`
- `object` with `additionalProperties` -> `Hash(String, ...)`
- Inline / untyped objects -> `JSON::Any`
- Sanitized Crystal keywords (`def`, `end`, `class`, `select`, `type`, etc.) by suffixing with `_param`.

---

## 5. Base HTTP Client & Error Handling

- **Base Client (`src/google_apis/client.cr`)**:
  - Automatically attaches `Authorization: Bearer <token>`, `Accept: application/json`, and `User-Agent: GoogleApis-Crystal/0.1.0`.
  - Handles URL construction, path interpolation, and query string merging.
  - Generic deserialization: `execute(type : T.class, ...)` parses response JSON directly into the requested type.
- **Error Handling (`src/google_apis/error.cr`)**:
  - `GoogleApis::HttpError`: extracts Google API error messages (`{"error": {"code": ..., "message": "..."}}`) from non-2xx responses.

---

## 6. CLI Executable (`bin/list_storage`)

Implemented in `src/bin/list_storage.cr` and compiled to `bin/list_storage`:
- Resolves project ID automatically via ADC `quota_project_id` or accepts `-p / --project`.
- Lists all buckets in the project, displaying name, location, and storage class.
- Supports listing objects inside specific buckets via `-b <bucket>`.
- Supports previewing objects in all buckets via `--all-objects`.
- Verified live against project `testing-355714`:
  - Found 26 buckets.
  - Confirmed presence of `nbrandaleone-bucket` and `nbrandaleone-testing`.

---

## 7. Testing, Linting & Quality Assurance

- **Unit Specs (`crystal spec`)**:
  - `spec/google_apis/auth_spec.cr`: ADC resolution, JSON parsing, mock token refresh, caching, error cases.
  - `spec/google_apis/client_spec.cr`: URI building, headers injection, error deserialization.
  - `spec/google_apis/storage_v1_spec.cr`: BucketsService and ObjectsService calls, path encoding, JSON serialization.
  - `spec/google_apis/generator_spec.cr`: Type mapping, identifier sanitization, discovery parsing.
  - **Results**: 24 examples, 0 failures, 0 errors.
- **Linter (`ameba`)**:
  - Inspected 33 files.
  - Resolved all warnings:
    - Removed `not_nil!` calls in specs and binaries.
    - Used descriptive block parameter names (avoiding single-letter names like `p` or `b`).
    - Lowered cyclomatic complexity by decomposing generator helper methods.
    - Converted boolean getters to `getter?`.
  - **Results**: 33 inspected, 0 failures.
- **Code Formatter (`crystal tool format`)**: All files formatted according to standard Crystal style conventions.
- **Git History**: All source files, templates, discovery docs, specs, and README committed to `main`.

---

## 8. Extensibility & Future Work

1. **Additional Google APIs**:
   - Running `bin/generate_api -i <url_or_file> -o <target_dir>` allows generating clients for any Discovery-compatible Google API (e.g., BigQuery, Pub/Sub, Drive, Compute).
2. **Service Account JWT Signing**:
   - Can be added in the future by adding an RS256 JWT shard (e.g. `jwt`) to `shard.yml` to support server-to-server service account JSON credentials.
3. **Chunked / Resumable Uploads**:
   - For uploading large files to GCS, implement media upload protocols using Google's multipart/resumable upload endpoints.
