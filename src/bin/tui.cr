require "option_parser"
require "../google_apis/manager"
require "../google_apis/tui/app"

mode = :tui
target_api : String? = nil
test_target : String? = nil

parser = OptionParser.parse do |opt_parser|
  opt_parser.banner = "Usage: tui [options]"

  opt_parser.on("-l", "--list", "Show all API targets that can be built from Google Discovery Docs") do
    mode = :list
  end

  opt_parser.on("-g API", "--generate=API", "Generate Google API client (name, id, or discovery file)") do |api|
    mode = :generate
    target_api = api
  end

  opt_parser.on("-d", "--docs", "Generate documentation using `crystal docs`") do
    mode = :docs
  end

  opt_parser.on("--remove-docs", "Remove the entire set of generated documentation") do
    mode = :remove_docs
  end

  opt_parser.on("-t API", "--test=API", "Run unit tests for a particular API") do |api|
    mode = :test_api
    test_target = api
  end

  opt_parser.on("-a", "--test-all", "Run all unit tests") do
    mode = :test_all
  end

  opt_parser.on("-c", "--clear-and-regenerate", "Clear out existing generated APIs and regenerate them") do
    mode = :clear_and_regenerate
  end

  opt_parser.on("-s", "--sync-yaml", "Save/sync Discovery Docs latest version numbers to api-list.yaml") do
    mode = :sync_yaml
  end

  opt_parser.on("--tui", "Launch Crysterm Terminal User Interface (default)") do
    mode = :tui
  end

  opt_parser.on("-h", "--help", "Print help documentation") do
    mode = :help
  end
end

case mode
when :list
  puts "Fetching Discovery targets..."
  targets = GoogleApis::Manager.list_targets(allow_network: true)
  puts "\nFound #{targets.size} Google Discovery API targets:\n"
  targets.each do |target|
    puts "  #{target.status_label.ljust(15)} #{target.id.ljust(35)} #{target.title}"
  end
  _, msg = GoogleApis::Manager.sync_api_list_yaml
  puts "\n#{msg}"
when :generate
  target = target_api
  target_name = (target.nil? || target.empty?) ? "storage" : target
  puts "Generating #{target_name}..."
  success, msg, _ = GoogleApis::Manager.generate_api(target_name)
  puts msg
  exit(success ? 0 : 1)
when :docs
  puts "Generating docs..."
  success, msg = GoogleApis::Manager.generate_docs
  puts msg
  exit(success ? 0 : 1)
when :remove_docs
  puts "Removing docs..."
  success, msg = GoogleApis::Manager.remove_docs
  puts msg
  exit(success ? 0 : 1)
when :test_api
  target = test_target
  target_name = (target.nil? || target.empty?) ? "storage" : target
  puts "Running tests for #{target_name}..."
  success, output = GoogleApis::Manager.run_tests_for(target_name)
  puts output
  exit(success ? 0 : 1)
when :test_all
  puts "Running all tests..."
  success, output = GoogleApis::Manager.run_all_tests
  puts output
  exit(success ? 0 : 1)
when :clear_and_regenerate
  puts "Clearing and regenerating APIs..."
  success, msg = GoogleApis::Manager.clear_and_regenerate
  puts msg
  exit(success ? 0 : 1)
when :sync_yaml
  puts "Syncing api-list.yaml..."
  success, msg = GoogleApis::Manager.sync_api_list_yaml
  puts msg
  exit(success ? 0 : 1)
when :help
  puts GoogleApis::Manager.help_text
  puts "\nCLI Flags:"
  puts parser
when :tui
  app = GoogleApis::Tui::App.new
  app.run
end
