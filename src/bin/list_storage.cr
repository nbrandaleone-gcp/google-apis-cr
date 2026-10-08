require "option_parser"
require "../google_apis_cr"

# CLI tool to list Google Cloud Storage buckets and objects.
project_id : String? = nil
target_bucket : String? = nil
list_objects_for_all = false
max_results : Int64? = 1000_i64

OptionParser.parse do |opts|
  opts.banner = "Usage: list_storage [options]"

  opts.on("-p PROJECT", "--project=PROJECT", "Google Cloud Project ID (default: from credentials)") do |proj|
    project_id = proj
  end

  opts.on("-b BUCKET", "--bucket=BUCKET", "List objects inside this specific bucket") do |bucket_arg|
    target_bucket = bucket_arg
  end

  opts.on("-a", "--all-objects", "List objects inside all listed buckets") do
    list_objects_for_all = true
  end

  opts.on("-m NUM", "--max-results=NUM", "Max results to return (default: 1000)") do |num|
    max_results = num.to_i64?
  end

  opts.on("-h", "--help", "Show help") do
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

  puts "Authenticated via Application Default Credentials"
  puts "Target Project: #{resolved_project}"
  puts "-" * 60

  client = GoogleApis::Storage::V1::Client.new(credentials)

  if bucket_name = target_bucket
    puts "Listing objects in bucket '#{bucket_name}':"
    obj_response = client.objects.list(bucket: bucket_name, max_results: max_results)
    if items = obj_response.items
      items.each do |obj|
        size = obj.size || "0"
        updated = obj.updated || "unknown"
        puts "  * #{obj.name} (#{size} bytes, updated: #{updated})"
      end
      puts "Total: #{items.size} object(s)"
    else
      puts "  (bucket is empty)"
    end
  else
    puts "Listing buckets in project '#{resolved_project}':"
    buckets_response = client.buckets.list(project: resolved_project, max_results: max_results)

    if items = buckets_response.items
      items.each do |bucket|
        loc = bucket.location || "UNKNOWN"
        storage_class = bucket.storage_class || "STANDARD"
        puts "  * #{bucket.name} [location: #{loc}, class: #{storage_class}]"

        if list_objects_for_all
          if b_name = bucket.name
            begin
              obj_response = client.objects.list(bucket: b_name, max_results: 5_i64)
              if obj_items = obj_response.items
                obj_items.each do |obj|
                  puts "      - #{obj.name} (#{obj.size} bytes)"
                end
                if obj_items.size == 5
                  puts "      ... (showing first 5 objects)"
                end
              else
                puts "      (empty)"
              end
            rescue ex
              puts "      (unable to list objects: #{ex.message})"
            end
          end
        end
      end
      puts "-" * 60
      puts "Total: #{items.size} bucket(s) listed."
    else
      puts "No buckets found in project '#{resolved_project}'."
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
