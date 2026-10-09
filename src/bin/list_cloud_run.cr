require "option_parser"
require "../google_apis_cr"

# CLI tool to list Google Cloud Run services and instances.
project_id : String? = nil
location = "-"
target_service : String? = nil
show_revisions = false
check_instances = false

OptionParser.parse do |opts|
  opts.banner = "Usage: list_cloud_run [options]"

  opts.on("-p PROJECT", "--project=PROJECT", "Google Cloud Project ID (default: from credentials)") do |project_arg|
    project_id = project_arg
  end

  opts.on("-l LOCATION", "--location=LOCATION", "Cloud Run location / region (default: '-' for all)") do |loc_arg|
    location = loc_arg
  end

  opts.on("-s SERVICE", "--service=SERVICE", "Get details for a specific service name") do |service_arg|
    target_service = service_arg
  end

  opts.on("-r", "--revisions", "List active revisions and container images") do
    show_revisions = true
  end

  opts.on("--instances", "Also check Cloud Run standalone instances endpoint") do
    check_instances = true
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

def extract_region(resource_name : String) : String
  parts = resource_name.split('/')
  loc_index = parts.index("locations")
  if loc_index && loc_index + 1 < parts.size
    parts[loc_index + 1]
  else
    "unknown"
  end
end

def extract_service_name(resource_name : String) : String
  resource_name.split('/').last
end

def status_description(service : GoogleApis::Run::V2::GoogleCloudRunV2Service) : String
  if condition = service.terminal_condition
    "#{condition.type_param} (#{condition.state})"
  else
    "UNKNOWN"
  end
end

def print_container_templates(template : GoogleApis::Run::V2::GoogleCloudRunV2RevisionTemplate?)
  return unless template
  return unless containers = template.containers

  containers.each do |container|
    c_name = container.name || "app"
    c_image = container.image || "unknown"
    puts "    - Container [#{c_name}]: #{c_image}"
  end
end

def print_service_summary(service : GoogleApis::Run::V2::GoogleCloudRunV2Service)
  full_name = service.name || "unknown"
  short_name = extract_service_name(full_name)
  region = extract_region(full_name)
  uri = service.uri || "n/a"

  puts "  * Service: #{short_name} [region: #{region}]"
  puts "    - Full Resource: #{full_name}"
  puts "    - Status:        #{status_description(service)}"
  puts "    - URI:           #{uri}"
  if revision = service.latest_ready_revision
    puts "    - Active Rev:    #{extract_service_name(revision)}"
  end
  if creator = service.creator
    puts "    - Creator:       #{creator}"
  end
  if create_time = service.create_time
    puts "    - Created:       #{create_time}"
  end

  print_container_templates(service.template)
end

def print_service_revisions(
  client : GoogleApis::Run::V2::Client,
  service_name : String,
)
  rev_response = client.projects_locations_services_revisions.list(parent: service_name)
  if revisions = rev_response.revisions
    revisions.each do |rev|
      rev_short = extract_service_name(rev.name || "unknown")
      puts "      Revision: #{rev_short}"
      if containers = rev.containers
        containers.each do |container|
          puts "        Image: #{container.image}"
        end
      end
    end
  end
rescue ex
  puts "      (unable to fetch revisions: #{ex.message})"
end

def query_instances(
  client : GoogleApis::Run::V2::Client,
  resolved_project : String,
  target_location : String,
)
  parent = "projects/#{resolved_project}/locations/#{target_location}"
  puts "Checking Cloud Run instances in #{parent}:"
  inst_response = client.projects_locations_instances.list(parent: parent)
  if instances = inst_response.instances
    instances.each do |instance|
      inst_name = instance.name || "unknown"
      puts "  * Instance: #{extract_service_name(inst_name)} (#{inst_name})"
    end
    puts "Total: #{instances.size} standalone instance(s)"
  else
    puts "  No standalone instances found in #{target_location}."
  end
rescue ex
  puts "  Note: Cloud Run instances query in #{target_location}: #{ex.message}"
end

begin
  credentials = GoogleApis::Auth.default_credentials
  resolved_project = project_id ||
                     ENV["GOOGLE_CLOUD_PROJECT"]? ||
                     ENV["GCP_PROJECT"]? ||
                     credentials.quota_project_id ||
                     credentials.project_id

  unless resolved_project
    STDERR.puts "Error: Project ID could not be determined. Please specify with -p/--project."
    exit 1
  end

  puts "Authenticated via Application Default Credentials"
  puts "Target Project:  #{resolved_project}"
  puts "Target Location: #{location}"
  puts "-" * 70

  client = GoogleApis::Run::V2::Client.new(credentials)

  if single_service = target_service
    loc = location == "-" ? "us-central1" : location
    full_svc_name = if single_service.includes?('/')
                      single_service
                    else
                      "projects/#{resolved_project}/locations/#{loc}/services/#{single_service}"
                    end
    puts "Fetching Cloud Run service '#{full_svc_name}':"
    fetched_service = client.projects_locations_services.get(name: full_svc_name)
    print_service_summary(fetched_service)
    if show_revisions
      print_service_revisions(client, full_svc_name)
    end
  else
    parent_path = "projects/#{resolved_project}/locations/#{location}"
    puts "Listing Cloud Run services in #{parent_path}:"
    response = client.projects_locations_services.list(parent: parent_path)

    if services = response.services
      services.each do |svc_entry|
        print_service_summary(svc_entry)
        if show_revisions
          if s_name = svc_entry.name
            print_service_revisions(client, s_name)
          end
        end
        puts ""
      end
      puts "-" * 70
      puts "Total: #{services.size} running Cloud Run service(s) found."

      if check_instances
        regions = services.compact_map do |svc_entry|
          svc_name = svc_entry.name
          svc_name ? extract_region(svc_name) : nil
        end
        regions.uniq!
        regions.each do |region_name|
          query_instances(client, resolved_project, region_name)
        end
      end
    else
      puts "No Cloud Run services found in #{parent_path}."
    end
  end
rescue ex : GoogleApis::Auth::Error
  STDERR.puts "Authentication Error: #{ex.message}"
  exit 1
rescue ex : GoogleApis::HttpError
  STDERR.puts "API Error: #{ex.message}"
  exit 1
rescue ex : Exception
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
