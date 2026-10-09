require "option_parser"
require "json"
require "../google_apis_cr"

# CLI tool to list Google Artifact Registry repositories (default: docker).
project_id : String? = nil
region_filter : String? = nil
format_filter = "DOCKER"
mode_filter : String? = nil
name_filter : String? = nil
raw_api_filter : String? = nil
show_details = false
output_json = false

OptionParser.parse do |opts|
  opts.banner = "Usage: list_registries [options]"

  opts.on("-p PROJECT", "--project=PROJECT", "Google Cloud Project ID (default: from ADC credentials)") do |arg|
    project_id = arg
  end

  opts.on("-r REGION", "--region=REGION", "Filter by region/location (e.g. us-central1, us, europe; default: all)") do |arg|
    region_filter = arg
  end

  opts.on("-l LOCATION", "--location=LOCATION", "Alias for --region") do |arg|
    region_filter = arg
  end

  opts.on("-f FORMAT", "--format=FORMAT", "Filter by repository format (default: DOCKER, 'all' for any)") do |arg|
    format_filter = arg.upcase
  end

  opts.on("-m MODE", "--mode=MODE", "Filter by mode: standard, remote, virtual") do |arg|
    mode_filter = arg.downcase
  end

  opts.on("-n NAME", "--name=NAME", "Filter by repository name substring") do |arg|
    name_filter = arg
  end

  opts.on("--filter=FILTER", "Raw Google API filter expression (e.g. 'name=\"...\"')") do |arg|
    raw_api_filter = arg
  end

  opts.on("-d", "--details", "Show full repository metadata and configuration") do
    show_details = true
  end

  opts.on("-j", "--json", "Output results as formatted JSON") do
    output_json = true
  end

  opts.on("-h", "--help", "Show help documentation") do
    puts opts
    exit 0
  end
end

def extract_location(resource_name : String) : String
  parts = resource_name.split('/')
  loc_index = parts.index("locations")
  if loc_index && loc_index + 1 < parts.size
    parts[loc_index + 1]
  else
    "unknown"
  end
end

def extract_repo_name(resource_name : String) : String
  resource_name.split('/').last
end

def format_size(size_bytes : String?) : String
  return "0 B" if size_bytes.nil? || size_bytes.empty?
  bytes = size_bytes.to_i64? || 0_i64
  if bytes < 1024
    "#{bytes} B"
  elsif bytes < 1024 * 1024
    "#{(bytes / 1024.0).round(2)} KB"
  elsif bytes < 1024 * 1024 * 1024
    "#{(bytes / (1024.0 * 1024.0)).round(2)} MB"
  else
    "#{(bytes / (1024.0 * 1024.0 * 1024.0)).round(2)} GB"
  end
end

# 1. Load Application Default Credentials
credentials = begin
  GoogleApis::Auth.default_credentials
rescue ex
  STDERR.puts "Error loading credentials: #{ex.message}"
  STDERR.puts "Make sure gcloud auth application-default login has been run or GOOGLE_APPLICATION_CREDENTIALS is set."
  exit 1
end

project = project_id || credentials.quota_project_id || ENV["GOOGLE_CLOUD_PROJECT"]? || ENV["GCLOUD_PROJECT"]?

unless project
  STDERR.puts "Error: No Google Cloud Project ID found. Please specify -p <project-id>."
  exit 1
end

client = GoogleApis::Artifactregistry::V1::Client.new(credentials)

# 2. Determine target locations
locations_to_query = [] of String

if r = region_filter
  if r.in?("all", "*", "-", "")
    # Query all locations
  else
    locations_to_query << r
  end
end

if locations_to_query.empty?
  # Fetch all locations for the project
  begin
    loc_response = client.projects_locations.list(name: "projects/#{project}")
    if locs = loc_response.locations
      locations_to_query = locs.compact_map(&.location_id)
    end
  rescue ex
    STDERR.puts "Error fetching locations for project #{project}: #{ex.message}"
    exit 1
  end
end

# 3. Query repositories across target locations concurrently
channel = Channel(Array(GoogleApis::Artifactregistry::V1::Repository)).new

locations_to_query.each do |loc_id|
  spawn do
    parent = "projects/#{project}/locations/#{loc_id}"
    repos = [] of GoogleApis::Artifactregistry::V1::Repository
    page_token : String? = nil

    loop do
      begin
        resp = client.projects_locations_repositories.list(
          parent: parent,
          filter: raw_api_filter,
          page_token: page_token
        )
        if items = resp.repositories
          repos.concat(items)
        end
        page_token = resp.next_page_token
        break if page_token.nil? || page_token.empty?
      rescue
        # Location might not have Artifact Registry enabled or no permissions
        break
      end
    end

    channel.send(repos)
  end
end

all_repos = [] of GoogleApis::Artifactregistry::V1::Repository
locations_to_query.size.times do
  all_repos.concat(channel.receive)
end

# 4. Filter repositories based on CLI options
filtered_repos = all_repos.select do |repo|
  # Format filter (e.g. DOCKER)
  if format_filter != "ALL"
    repo_fmt = repo.format.to_s.upcase
    next false unless repo_fmt == format_filter
  end

  # Region filter
  if reg = region_filter
    unless reg.in?("all", "*", "-", "")
      loc = extract_location(repo.name || "")
      next false unless loc.downcase == reg.downcase
    end
  end

  # Mode filter (standard, remote, virtual)
  if m = mode_filter
    repo_mode = repo.mode.to_s.downcase
    next false unless repo_mode.includes?(m)
  end

  # Name filter
  if n = name_filter
    full_name = repo.name || ""
    short_name = extract_repo_name(full_name)
    uri = repo.registry_uri || ""
    next false unless short_name.downcase.includes?(n.downcase) || uri.downcase.includes?(n.downcase)
  end

  true
end

# Sort by region, then repo name
filtered_repos.sort_by! do |repo|
  full = repo.name || ""
  {extract_location(full), extract_repo_name(full)}
end

# 5. Output results
if output_json
  puts filtered_repos.to_pretty_json
  exit 0
end

fmt_label = format_filter == "ALL" ? "All Formats" : "#{format_filter}"
reg_label = region_filter.nil? || region_filter.in?("all", "*", "-") ? "all regions" : "region #{region_filter}"

puts "================================================================================"
puts " Google Artifact Registry — #{fmt_label} Repositories"
puts " Project: #{project} | Scope: #{reg_label}"
puts " Found:   #{filtered_repos.size} matching #{fmt_label.downcase} repositor#{filtered_repos.size == 1 ? "y" : "ies"}"
puts "================================================================================"

if filtered_repos.empty?
  puts "\nNo repositories found matching the criteria."
  puts "Tip: Check if the region or project ID is correct, or use --format=all."
  exit 0
end

filtered_repos.each_with_index do |repo, idx|
  full_name = repo.name || "unknown"
  short_name = extract_repo_name(full_name)
  loc = extract_location(full_name)
  fmt = repo.format || "UNKNOWN"
  mode = repo.mode || "STANDARD"
  uri = repo.registry_uri || "n/a"
  size_str = format_size(repo.size_bytes)

  puts "\n[#{idx + 1}] #{short_name}  (#{fmt} | #{mode})"
  puts "    Region:       #{loc}"
  puts "    Registry URI: #{uri}"
  puts "    Full Name:    #{full_name}"
  puts "    Size:         #{size_str}"

  if desc = repo.description
    puts "    Description:  #{desc}" unless desc.strip.empty?
  end

  if update_time = repo.update_time
    puts "    Updated:      #{update_time}"
  end

  if show_details
    if create_time = repo.create_time
      puts "    Created:      #{create_time}"
    end
    if kms = repo.kms_key_name
      puts "    KMS Key:      #{kms}"
    end
    if satisfies_pzs = repo.satisfies_pzs
      puts "    Satisfies PZS: #{satisfies_pzs}"
    end
    if satisfies_pzi = repo.satisfies_pzi
      puts "    Satisfies PZI: #{satisfies_pzi}"
    end
    if dry_run = repo.cleanup_policy_dry_run
      puts "    Cleanup DryRun: #{dry_run}"
    end
    if d_cfg = repo.docker_config
      puts "    Docker Config: immutableTags=#{d_cfg.immutable_tags}"
    end
    if r_cfg = repo.remote_repository_config
      puts "    Remote Config: #{r_cfg.description || "configured"}"
    end
    if v_cfg = repo.virtual_repository_config
      puts "    Virtual Config: configured"
    end
    if labels = repo.labels
      unless labels.empty?
        labels_str = labels.map { |k, v| "#{k}=#{v}" }.join(", ")
        puts "    Labels:       #{labels_str}"
      end
    end
  end
end

puts "\n--------------------------------------------------------------------------------"
puts "Total: #{filtered_repos.size} repository/repositories displayed."
puts "--------------------------------------------------------------------------------"
