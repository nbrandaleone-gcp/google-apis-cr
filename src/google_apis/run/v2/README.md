# Cloud Run Admin API (V2)

Deploy and manage user provided container images that scale automatically based on incoming requests. The Cloud Run Admin API v1 follows the Knative Serving API specification, while v2 is aligned with Google Cloud AIP-based API standards, as described in https://google.aip.dev/.

This client was generated from the Google Discovery document for `run` (v2).

## Usage Example

```crystal
require "google_apis_cr"

# Load Application Default Credentials (ADC)
credentials = GoogleApis::Auth.default_credentials

# Initialize Cloud Run Admin API Client
client = GoogleApis::Run::V2::Client.new(credentials)

# Access projects_locations methods:
# response = client.projects_locations.export_image_metadata(name: "value")
```

## Available Resources

| Resource | Service Class | Methods |
|---|---|---|
| `projects_locations` | `ProjectsLocationsService` | `export_image_metadata, export_metadata, export_image, export_project_metadata` |
| `projects_locations_operations` | `ProjectsLocationsOperationsService` | `wait, get, list, delete` |
| `projects_locations_worker_pools` | `ProjectsLocationsWorkerPoolsService` | `get_iam_policy, patch, list, test_iam_permissions, delete, get, create, set_iam_policy` |
| `projects_locations_worker_pools_revisions` | `ProjectsLocationsWorkerPoolsRevisionsService` | `list, delete, get` |
| `projects_locations_builds` | `ProjectsLocationsBuildsService` | `submit` |
| `projects_locations_instances` | `ProjectsLocationsInstancesService` | `create, start, delete, test_iam_permissions, get, list, set_iam_policy, get_iam_policy, patch, stop` |
| `projects_locations_source_uploads` | `ProjectsLocationsSourceUploadsService` | `upload` |
| `projects_locations_services` | `ProjectsLocationsServicesService` | `delete, patch, get, test_iam_permissions, list, get_iam_policy, set_iam_policy, create` |
| `projects_locations_services_revisions` | `ProjectsLocationsServicesRevisionsService` | `delete, list, get, export_status` |
| `projects_locations_jobs` | `ProjectsLocationsJobsService` | `list, run, test_iam_permissions, get, set_iam_policy, delete, get_iam_policy, patch, create` |
| `projects_locations_jobs_executions` | `ProjectsLocationsJobsExecutionsService` | `export_status, delete, get, list, cancel` |
| `projects_locations_jobs_executions_tasks` | `ProjectsLocationsJobsExecutionsTasksService` | `get, list` |

