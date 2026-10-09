require "option_parser"
require "json"
require "../google_apis_cr"
require "../google_apis/dns/v1/v1"

# Sample CLI tool to list Google Cloud DNS API primary resources.
project_id : String? = nil
max_results : Int64? = nil
output_json = false

OptionParser.parse do |opts|
  opts.banner = "Usage: list_dns [options]"

  opts.on("-p PROJECT", "--project=PROJECT", "Google Cloud Project ID (default: from credentials/environment)") do |arg|
    project_id = arg
  end

  opts.on("-m NUM", "--max-results=NUM", "Max results to return") do |arg|
    max_results = arg.to_i64?
  end

  opts.on("-j", "--json", "Output response as formatted JSON") do
    output_json = true
  end

  opts.on("-h", "--help", "Show help documentation") do
    puts opts
    exit 0
  end
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

  client = GoogleApis::Dns::V1::Client.new(credentials)
  puts "Authenticated via Application Default Credentials"
  puts "Target Project: #{resolved_project}"
  puts "-" * 60

  response = client.managed_zones.list(project: resolved_project, max_results: max_results)

  if output_json
    puts response.to_json
    exit 0
  end

  if items = response.managed_zones
    if items.empty?
      puts "No managed zones found."
    else
      puts "Listing managed zones (#{items.size} found):"
      items.each do |item|
        details = [] of String
        if val = item.dns_name
          details << "dns_name: #{val}"
        end
        if val = item.description
          details << "description: #{val}"
        end
        if val = item.visibility
          details << "visibility: #{val}"
        end
        summary = details.empty? ? "" : " [#{details.join(", ")}]"
        label = item.name || "(unknown)"
        puts "  * #{label}#{summary}"
      end
    end
  else
    puts "No items returned."
  end
rescue ex : GoogleApis::HttpError
  STDERR.puts "API Error: #{ex.message} (HTTP #{ex.status_code})"
  STDERR.puts ex.body unless ex.body.empty?
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
