# Agent Project Notes & Design Decisions

**Project:** `google-apis-cr` (Google APIs Client Library for Crystal)  
**Date:** October 8, 2026  
**Language:** Crystal (1.21.1)  
**Linter:** Ameba (1.6.4)  
**Target Platform:** macOS / Darwin (Apple Silicon arm64)  
**Active GCP Project:** `testing-355714`  

---

## 1. Project Goals & Context

The initial goal specified in `AGENTS.md` was to build a reusable Crystal client library interfacing with Google APIs, featuring Google Cloud Storage (v1) to list buckets and files. In subsequent work, the library was expanded to generate and verify a strongly-typed client for the **Cloud Run Admin API (v2)**.

### Key Requirements
1. **Application Default Credentials (ADC)**: Authenticate against Google APIs using local ADC credentials with proactive token refresh.
2. **Google Discovery Service**: Follow Google's Discovery Service approach to understand API shapes and generate strongly-typed Crystal clients.
3. **Embedded Crystal (ECR)**: Use ECR as the template engine for compile-time code generation.
4. **Reusable Shard & CLI Executables**:
   - `bin/list_storage`: List GCS buckets and inspect objects.
   - `bin/list_cloud_run`: List Cloud Run services, active revisions, container images, and instances.
   - `bin/generate_api`: CLI code generator for Discovery JSON documents.
5. **Definitions of Done**:
   - GCS: Verify bucket listing includes `nbrandaleone-bucket` and `nbrandaleone-testing`.
   - Cloud Run: Generate Cloud Run Admin API v2 client and verify at least one running Cloud Run instance/service in `testing-355714`.

---

## 2. Environment & Credential Reconnaissance

- **Crystal & Ameba**: Crystal 1.21.1 and Ameba 1.6.4 installed via Homebrew.
- **Application Default Credentials**: Located at `~/.config/gcloud/application_default_credentials.json`:
  - Type: `authorized_user`
  - Quota Project: `testing-355714`
  - Contained `client_id`, `client_secret`, and a valid `refresh_token`.
- **Live Endpoint Verification**: Verified OAuth2 token exchange at `https://oauth2.googleapis.com/token`.

---

## 3. Authentication Implementation (`src/google_apis/auth.cr`)

- **Resolution Precedence**:
  1. `$GOOGLE_APPLICATION_CREDENTIALS` environment variable.
  2. Well-known user ADC file: `~/.config/gcloud/application_default_credentials.json` (or `%APPDATA%/gcloud/...` on Windows).
- **AuthorizedUserCredentials**:
  - Exposes `authorization_header` (`"Bearer <token>"`).
  - Proactive token caching and refresh: refreshes whenever expired or within 60 seconds of expiration.
  - Thread- and fiber-safe access via `Mutex`.
  - Exposes `project_id` and `quota_project_id`.
  - Redacts sensitive secrets in `#inspect` and `#to_s` to prevent leakage into logs.
- **ServiceAccountCredentials**:
  - Parses service account JSON metadata.
  - Raises `UnsupportedCredentialsTypeError` explaining that RS256 JWT signing requires cryptography shards beyond Crystal's standard library.
- **Unit Specs**: Mock HTTP server testing resolution, token refresh, caching, and error handling (`spec/google_apis/auth_spec.cr`).

---

## 4. Google Discovery Service Architecture & ECR Code Generation

### 4.1 Why Code Generation over Runtime Reflection?
Crystal is a statically-typed, compiled language without dynamic class creation at runtime. Generating code from Discovery documents provides:
- Complete compile-time type safety.
- IDE auto-completion and documentation comments on methods and schemas.
- High runtime performance with zero dynamic reflection overhead.

### 4.2 ECR View Architecture (`src/google_apis/generator/views.cr`)
Crystal includes `ecr` in its standard library. `ECR.def_to_s("template.ecr")` compiles templates directly into Crystal bytecode inside a view class:
1. `TypesView`: Renders `types.cr` containing all Discovery schemas.
2. `ResourceServiceView`: Renders individual resource services (e.g. `BucketsService`, `ProjectsLocationsServicesService`).
3. `ClientView`: Renders high-level `Client` exposing resource accessors (`client.buckets`, `client.projects_locations_services`).
4. `ServiceModuleView`: Renders top-level entrypoint module (`v1.cr`, `v2.cr`).

### 4.3 Type Mapping Logic (`src/google_apis/generator.cr`)
- `string` -> `String`
- `integer` -> `Int64`
- `number` -> `Float64`
- `boolean` -> `Bool`
- `array` of `$ref` -> `Array(RefName)`
- `object` with `additionalProperties` -> `Hash(String, ...)`
- Inline / untyped objects -> `JSON::Any`
- Sanitized Crystal keywords (`def`, `end`, `class`, `select`, `type`, etc.) by suffixing with `_param`.

### 4.4 Generator Enhancements for Google AIP-style APIs
While GCS v1 is relatively flat and uses legacy REST conventions, Cloud Run Admin API v2 adheres to modern Google Cloud AIP standards (AIP-122 Resource Names, AIP-132 Standard Methods). Two critical enhancements were implemented:

1. **Dotted Query Parameter Names**:
   - Modern GCP APIs expose IAM methods (e.g., `getIamPolicy`) that accept query parameters with dots like `options.requestedPolicyVersion`.
   - Updated `GoogleApis::Generator.sanitize_identifier` to replace dots with underscores (`name.gsub(".", "_").underscore`) for Crystal parameter identifiers while preserving the raw key (`"options.requestedPolicyVersion"`) for URL query parameter construction.
2. **RFC 6570 URI Reserved Path Expansion (`{+name}`, `{+parent}`)**:
   - In AIP-style APIs, resource paths use hierarchical names containing slashes (e.g., `projects/{project}/locations/{location}/services/{service}`).
   - Methods specify `{+name}` or `{+parent}`, where `+` indicates Reserved Expansion (characters like `/` should not be percent-encoded as a whole).
   - In `resource_service.cr.ecr`, `{+param}` variables now encode individual segments while preserving path separators:
     ```crystal
     req_path = req_path.gsub("{+<%= param.json_name %>}", <%= param.crystal_name %>.to_s.split('/').map { |segment| URI.encode_path_segment(segment) }.join('/'))
     ```

---

## 5. Base HTTP Client & Error Handling

- **Base Client (`src/google_apis/client.cr`)**:
  - Automatically attaches `Authorization: Bearer <token>`, `Accept: application/json`, and `User-Agent: GoogleApis-Crystal/0.1.0`.
  - Handles URL construction, path interpolation, and query string parameter building.
  - Generic deserialization: `execute(type : T.class, ...)` parses response JSON directly into the requested `JSON::Serializable` type.
- **Error Handling (`src/google_apis/error.cr`)**:
  - `GoogleApis::HttpError`: Deserializes Google API error structures (`{"error": {"code": ..., "message": "..."}}`) from non-2xx responses.

---

## 6. CLI Executables & Live Verification

### 6.1 Google Cloud Storage (`bin/list_storage`)
- Resolves project ID via ADC `quota_project_id` or accepts `-p / --project`.
- Lists all buckets in the project, displaying name, location, and storage class.
- Supports listing objects inside specific buckets (`-b <bucket>`) or previewing across all buckets (`--all-objects`).
- **Live Verification against `testing-355714`**:
  - Found 26 buckets.
  - Confirmed presence of `nbrandaleone-bucket` and `nbrandaleone-testing`.

### 6.2 Cloud Run Admin API v2 (`bin/list_cloud_run`)
- Supports options:
  - `-p / --project`: GCP project ID.
  - `-l / --location`: Cloud Run location/region (defaults to `-` for multi-region wildcard query).
  - `-s / --service`: Inspect a specific service.
  - `-r / --revisions`: Fetch and display revisions and container image digests.
  - `--instances`: Check the standalone Cloud Run instances endpoint.
- **Live Verification against `testing-355714`**:
  ```text
  Authenticated via Application Default Credentials
  Target Project:  testing-355714
  Target Location: -
  ----------------------------------------------------------------------
  Listing Cloud Run services in projects/testing-355714/locations/-:
    * Service: mandelbrot [region: us-east5]
      - Full Resource: projects/testing-355714/locations/us-east5/services/mandelbrot
      - Status:        Ready (CONDITION_SUCCEEDED)
      - URI:           https://mandelbrot-yspciwmbia-ul.a.run.app
      - Active Rev:    mandelbrot-00001-6ff
      - Creator:       nbrand01@gmail.com
      - Created:       2026-10-08T20:59:56.465530Z
      - Container [mandelbrot-1]: us-central1-docker.pkg.dev/testing-355714/my-docker-repo/mandelbrot@sha256:3a2fb6614bc68698ac523ba75e22b55a96dafbb4136e7f76d65be4a3ad577401
        Revision: mandelbrot-00001-6ff
          Image: us-central1-docker.pkg.dev/testing-355714/my-docker-repo/mandelbrot@sha256:3a2fb6614bc68698ac523ba75e22b55a96dafbb4136e7f76d65be4a3ad577401

  ----------------------------------------------------------------------
  Total: 1 running Cloud Run service(s) found.
  ```

---

## 7. Architecture Reflections & API Design Insights

### 7.1 Strengths of Crystal for Cloud SDK Tooling
1. **Compile-Time Safety over Runtime Metaprogramming**:
   Dynamic language SDKs often use runtime metaprogramming and dynamic hash maps, leading to runtime `KeyError` or nil exceptions. Crystal's ECR generator produces explicit classes with `JSON::Serializable`. Property access is statically verified at compile time.
2. **Instant Native Binary Performance**:
   Running `./bin/list_cloud_run` completes in under 400 milliseconds, including TLS handshake, OAuth token verification, and JSON parsing. There is no VM startup time, JIT warmup, or interpreter overhead.
3. **Lean Dependency Footprint**:
   The entire implementation (HTTP client, OAuth token exchange, JSON serialization, CLI option parsing, and template generation) runs entirely on the Crystal Standard Library with zero third-party shard dependencies.

### 7.2 Nuances of Cloud Run v2 (AIP vs Knative)
- **Knative v1 vs Cloud Run v2**: Cloud Run v1 followed the Knative Serving specification (`serving.knative.dev/v1`), nesting properties under Kubernetes-style `metadata`, `spec`, and `status`. Cloud Run v2 is aligned directly with Google Cloud AIP standards, placing fields at the top level (`uri`, `traffic_statuses`, `template`), yielding a cleaner, more idiomatic object model.
- **Services vs Instances**: In Cloud Run, running containers are autoscaled instances backing a `Service` revision. While Cloud Run v2 includes an experimental `projects.locations.instances` endpoint, standard production workloads are managed via `Services`. Supporting both resources in the generated client and CLI tool ensures complete visibility.

---

## 8. Testing, Linting & Quality Assurance

- **Unit Specs (`crystal spec`)**:
  - `spec/google_apis/auth_spec.cr`: ADC resolution, JSON parsing, mock token refresh, caching, error cases.
  - `spec/google_apis/client_spec.cr`: URI building, headers injection, error deserialization.
  - `spec/google_apis/storage_v1_spec.cr`: BucketsService and ObjectsService calls, path encoding, JSON serialization.
  - `spec/google_apis/run_v2_spec.cr`: ServicesService, InstancesService, RevisionsService endpoints, URI expansions, and typed responses.
  - `spec/google_apis/generator_spec.cr`: Type mapping, identifier sanitization, discovery parsing.
  - **Results**: 28 examples, 0 failures, 0 errors.
- **Linter (`ameba`)**:
  - Inspected 50 files.
  - Enforced zero `not_nil!` unwrap calls, descriptive block parameter names, low cyclomatic complexity, and boolean query predicate conventions (`getter?`).
  - **Results**: 50 inspected, 0 failures.
- **Code Formatter (`crystal tool format`)**: All files formatted according to standard Crystal style conventions.

---

## 9. Extensibility & Future Roadmap

1. **Automatic Pagination Iterators**:
   Add `each_item` or `each_page` helper methods to generated collection methods that automatically traverse `pageToken` / `nextPageToken` until exhausted.
2. **Long-Running Operation (LRO) Helpers**:
   Methods like `services.delete` or `services.patch` return `GoogleLongrunningOperation`. A polling helper (`wait_until_done`) wrapping `projects.locations.operations.wait` would provide synchronous ergonomics for asynchronous mutations.
3. **Service Account Key (JWT) Signing**:
   Add an RS256 JWT shard to sign assertion tokens for server-to-server authentication outside of user ADC environments (e.g., CI/CD or non-GCP hosts).
4. **Automated Discovery Catalog CLI**:
   Extend `generate_api` to accept an API identifier directly (e.g. `generate_api --api run --version v2`), fetching the JSON automatically from `https://discovery.googleapis.com/discovery/v1/apis`.
5. **Chunked / Resumable Uploads**:
   Implement Google's multipart and resumable upload protocols for high-throughput GCS object uploads.
