require "http/client"
require "option_parser"
require "../google_apis/generator"

input_source = "discovery/storage_v1.json"
output_dir = "src/google_apis/storage/v1"

OptionParser.parse do |parser|
  parser.banner = "Usage: generate_api [options] [input_file_or_url] [output_dir]"

  parser.on("-i SOURCE", "--input=SOURCE", "Discovery document JSON file or URL") do |src|
    input_source = src
  end

  parser.on("-o DIR", "--output=DIR", "Output directory for generated Crystal files") do |dir|
    output_dir = dir
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

if ARGV.size >= 1
  input_source = ARGV[0]
end
if ARGV.size >= 2
  output_dir = ARGV[1]
end

puts "Reading Discovery document from #{input_source}..."

json_content = if input_source.starts_with?("http://") || input_source.starts_with?("https://")
                 resp = HTTP::Client.get(input_source)
                 unless resp.success?
                   STDERR.puts "Error downloading #{input_source}: HTTP #{resp.status_code}"
                   exit 1
                 end
                 resp.body
               else
                 unless File.exists?(input_source)
                   STDERR.puts "Error: File #{input_source} does not exist"
                   exit 1
                 end
                 File.read(input_source)
               end

puts "Parsing discovery document..."
service = GoogleApis::Generator.parse(json_content)

puts "Generating #{service.name} (#{service.version}) client into #{output_dir}..."
GoogleApis::Generator.generate(service, output_dir)

puts "Generated successfully:"
puts "  - Schemas: #{service.schemas.size}"
puts "  - Resources: #{service.resources.size}"
puts "  - Target: #{output_dir}"
