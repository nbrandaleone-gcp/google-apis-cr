# Cloud DNS API (V1)



This client was generated from the Google Discovery document for `dns` (v1).

## Usage Example

```crystal
require "google_apis_cr"

# Load Application Default Credentials (ADC)
credentials = GoogleApis::Auth.default_credentials

# Initialize Cloud DNS API Client
client = GoogleApis::Dns::V1::Client.new(credentials)

# Access changes methods:
# response = client.changes.list(project: "value", managed_zone: "value")
```

## Available Resources

| Resource | Service Class | Methods |
|---|---|---|
| `changes` | `ChangesService` | `list, get, create` |
| `projects` | `ProjectsService` | `get` |
| `resource_record_sets` | `ResourceRecordSetsService` | `list, get, patch, delete, create` |
| `policies` | `PoliciesService` | `get, update, list, delete, patch, create` |
| `dns_keys` | `DnsKeysService` | `list, get` |
| `response_policy_rules` | `ResponsePolicyRulesService` | `get, patch, list, update, create, delete` |
| `managed_zone_operations` | `ManagedZoneOperationsService` | `list, get` |
| `managed_zones` | `ManagedZonesService` | `update, get_iam_policy, patch, test_iam_permissions, list, get, set_iam_policy, create, delete` |
| `response_policies` | `ResponsePoliciesService` | `list, update, patch, delete, get, create` |

