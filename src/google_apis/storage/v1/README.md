# Cloud Storage JSON API (V1)

Stores and retrieves potentially large, immutable data objects.

This client was generated from the Google Discovery document for `storage` (v1).

## Usage Example

```crystal
require "google_apis_cr"

# Load Application Default Credentials (ADC)
credentials = GoogleApis::Auth.default_credentials

# Initialize Cloud Storage JSON API Client
client = GoogleApis::Storage::V1::Client.new(credentials)

# Access anywhere_caches methods:
# response = client.anywhere_caches.insert(bucket: "value")
```

## Available Resources

| Resource | Service Class | Methods |
|---|---|---|
| `anywhere_caches` | `AnywhereCachesService` | `insert, update, get, list, pause, resume, disable` |
| `rapid_caches` | `RapidCachesService` | `insert, update, get, list, disable` |
| `bucket_access_controls` | `BucketAccessControlsService` | `delete, get, insert, list, patch, update` |
| `buckets` | `BucketsService` | `delete, restore, relocate, get, get_iam_policy, get_storage_layout, insert, list, lock_retention_policy, patch, set_iam_policy, test_iam_permissions, update` |
| `operations` | `OperationsService` | `cancel, get, advance_relocate_bucket, list` |
| `channels` | `ChannelsService` | `stop` |
| `default_object_access_controls` | `DefaultObjectAccessControlsService` | `delete, get, insert, list, patch, update` |
| `folders` | `FoldersService` | `delete, delete_recursive, get, insert, list, rename` |
| `managed_folders` | `ManagedFoldersService` | `delete, get, update, get_iam_policy, insert, list, set_iam_policy, test_iam_permissions` |
| `notifications` | `NotificationsService` | `delete, get, insert, list` |
| `object_access_controls` | `ObjectAccessControlsService` | `delete, get, insert, list, patch, update` |
| `objects` | `ObjectsService` | `compose, copy, delete, get, get_iam_policy, insert, list, patch, rewrite, move, set_iam_policy, test_iam_permissions, update, restore, bulk_restore, view_full_context` |
| `projects_hmac_keys` | `ProjectsHmacKeysService` | `create, delete, get, list, update` |
| `projects_service_account` | `ProjectsServiceAccountService` | `get` |

