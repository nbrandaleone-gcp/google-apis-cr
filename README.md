# google_apis_cr

![Google APIs Crystal Architecture Pipeline](assets/pipeline_architecture.png)

A Crystal client library for Google APIs, featuring Application Default Credentials (ADC) authentication, Google Discovery Service typed code generation with Embedded Crystal (ECR) templates. 

There is a generated typed Google Cloud Storage client, as an example.

All code is agent generated (Gemini 3.8 Flash). While unit tested
to be correct, it is clearly not idiomatic crystal that humans would write.

## Features

- **Application Default Credentials (ADC)**: Automatic loading via `$GOOGLE_APPLICATION_CREDENTIALS` or well-known gcloud CLI path (`~/.config/gcloud/application_default_credentials.json`). Supports automatic token refresh and caching.
- **Google Cloud Storage (v1)**: Strongly-typed client for buckets, objects, ACLs, and other storage resources.
- **Discovery Service Code Generator**: Built-in generator using ECR templates to parse any Google Discovery document and produce typed Crystal clients and schemas.
- **CLI Utilities**:
  - `bin/list_storage`: Command-line tool to list GCS buckets and objects.
  - `bin/generate_api`: Code generation tool for Google Discovery documents.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  google_apis_cr:
    github: nbrandaleone/google-apis-cr
```

Run `shards install`.

## Usage

### Listing Buckets and Objects

```crystal
require "google_apis_cr"

# Load Application Default Credentials (ADC)
credentials = GoogleApis::Auth.default_credentials
project_id = credentials.quota_project_id || "your-project-id"

# Initialize Google Cloud Storage Client
storage = GoogleApis::Storage::V1::Client.new(credentials)

# List buckets in project
buckets_response = storage.buckets.list(project: project_id)
buckets_response.items.try(&.each do |bucket|
  puts "Bucket: #{bucket.name} (Location: #{bucket.location})"

  # List objects within bucket
  objects_response = storage.objects.list(bucket: bucket.name.not_nil!)
  objects_response.items.try(&.each do |object|
    puts "  - #{object.name} (#{object.size} bytes)"
  end)
end)
```

## CLI Tools

### Build CLI Tools

```bash
crystal build src/bin/list_storage.cr -o bin/list_storage
crystal build src/bin/generate_api.cr -o bin/generate_api
```

### List Buckets and Objects

```bash
# List all buckets in default ADC project
./bin/list_storage

# List objects inside a specific bucket
./bin/list_storage -b nbrandaleone-bucket

# List all buckets and preview objects in each
./bin/list_storage --all-objects
```

### Generate Clients from Discovery Documents

```bash
# Generate from local JSON file or URL
./bin/generate_api -i discovery/storage_v1.json -o src/google_apis/storage/v1
```

## Running Tests and Linting

```bash
# Run specs
crystal spec

# Lint with Ameba
ameba

# Auto-format
crystal tool format
```

## License

MIT

## References

1) https://docs.cloud.google.com/docs/discovery/build-client-library
2) https://developers.google.com/discovery/v1/building-a-client-library

## AI tools

All of the code in this repository was written by Gemini 3.8 Flash.
I included the goal in the `AGENTS.md` file, along with some of the
thoughts the agent had after we discussed its progress, in the
`agents-notes.md` file.
