# List Cloud Run Services and Instances

```bash
# List all Cloud Run services across all regions
./bin/list_cloud_run

# List services with active revisions and container images
./bin/list_cloud_run -r

# Inspect a specific service
./bin/list_cloud_run -s mandelbrot -l us-east5
```
