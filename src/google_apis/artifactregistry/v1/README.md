# Artifact Registry API (V1)

Store and manage build artifacts in a scalable and integrated service built on Google infrastructure.

This client was generated from the Google Discovery document for `artifactregistry` (v1).

## Usage Example

```crystal
require "google_apis_cr"

# Load Application Default Credentials (ADC)
credentials = GoogleApis::Auth.default_credentials

# Initialize Artifact Registry API Client
client = GoogleApis::Artifactregistry::V1::Client.new(credentials)

# Access projects methods:
# response = client.projects.update_project_settings(name: "value")
```

## Available Resources

| Resource | Service Class | Methods |
|---|---|---|
| `projects` | `ProjectsService` | `update_project_settings, get_project_settings` |
| `projects_locations` | `ProjectsLocationsService` | `update_project_config, update_vpcsc_config, get, get_vpcsc_config, get_project_config, list` |
| `projects_locations_operations` | `ProjectsLocationsOperationsService` | `cancel, get` |
| `projects_locations_repositories` | `ProjectsLocationsRepositoriesService` | `export_artifact, prewarm_artifact, delete, set_iam_policy, test_iam_permissions, create, get, remove_prewarmed_artifact, get_iam_policy, list, check_prewarmed_artifact, patch` |
| `projects_locations_repositories_packages` | `ProjectsLocationsRepositoriesPackagesService` | `patch, list, get, delete` |
| `projects_locations_repositories_packages_versions` | `ProjectsLocationsRepositoriesPackagesVersionsService` | `batch_delete, delete, list, patch, get` |
| `projects_locations_repositories_packages_tags` | `ProjectsLocationsRepositoriesPackagesTagsService` | `list, get, patch, create, delete` |
| `projects_locations_repositories_generic_artifacts` | `ProjectsLocationsRepositoriesGenericArtifactsService` | `upload` |
| `projects_locations_repositories_attachments` | `ProjectsLocationsRepositoriesAttachmentsService` | `create, get, delete, list` |
| `projects_locations_repositories_apt_artifacts` | `ProjectsLocationsRepositoriesAptArtifactsService` | `upload, import` |
| `projects_locations_repositories_docker_images` | `ProjectsLocationsRepositoriesDockerImagesService` | `list, get` |
| `projects_locations_repositories_rules` | `ProjectsLocationsRepositoriesRulesService` | `patch, get, delete, create, list` |
| `projects_locations_repositories_prewarmed_artifacts` | `ProjectsLocationsRepositoriesPrewarmedArtifactsService` | `list` |
| `projects_locations_repositories_googet_artifacts` | `ProjectsLocationsRepositoriesGoogetArtifactsService` | `upload, import` |
| `projects_locations_repositories_kfp_artifacts` | `ProjectsLocationsRepositoriesKfpArtifactsService` | `upload` |
| `projects_locations_repositories_files` | `ProjectsLocationsRepositoriesFilesService` | `download, patch, get, delete, list, upload` |
| `projects_locations_repositories_go_modules` | `ProjectsLocationsRepositoriesGoModulesService` | `upload` |
| `projects_locations_repositories_python_packages` | `ProjectsLocationsRepositoriesPythonPackagesService` | `get, list` |
| `projects_locations_repositories_npm_packages` | `ProjectsLocationsRepositoriesNpmPackagesService` | `list, get` |
| `projects_locations_repositories_maven_artifacts` | `ProjectsLocationsRepositoriesMavenArtifactsService` | `list, get` |
| `projects_locations_repositories_yum_artifacts` | `ProjectsLocationsRepositoriesYumArtifactsService` | `upload, import` |

