require "file_utils"
require "./generator"
require "./discovery"
require "./api_list_registry"

module GoogleApis
  # Controller providing all operations for managing, generating, and testing Google APIs.
  class Manager
    PROTECTED_DIRS  = Set{"generator", "tui"}
    PROTECTED_FILES = Set{
      "auth.cr", "client.cr", "error.cr", "generator.cr", "service.cr",
      "discovery.cr", "api_list_registry.cr", "manager.cr", "tui.cr",
    }

    # Returns the discovery catalog.
    def self.catalog(discovery_dir : String = "discovery", src_dir : String = "src/google_apis", allow_network : Bool = true) : DiscoveryCatalog
      DiscoveryCatalog.load(discovery_dir, src_dir, allow_network)
    end

    # Lists available targets, optionally filtered by search substring.
    def self.list_targets(search : String? = nil, allow_network : Bool = true) : Array(DiscoveryTarget)
      cat = catalog(allow_network: allow_network)
      targets = cat.targets
      if query = search.try(&.strip.downcase)
        targets = targets.select do |target|
          target.id.downcase.includes?(query) || target.name.downcase.includes?(query) || target.title.downcase.includes?(query)
        end
      end
      targets
    end

    # Generates a chosen API by name, id, or local discovery file.
    def self.generate_api(
      target_query : String,
      project_root : String = ".",
      allow_network : Bool = true,
    ) : Tuple(Bool, String, Generator::ServiceModel?)
      cat = catalog(
        discovery_dir: File.join(project_root, "discovery"),
        src_dir: File.join(project_root, "src/google_apis"),
        allow_network: allow_network
      )

      target = cat.find_target(target_query)
      unless target
        # Check if target_query is a direct path to a json file
        if File.exists?(target_query)
          content = File.read(target_query)
          service = Generator.parse(content)
          output_dir = File.join(project_root, "src/google_apis", service.name, service.version.downcase)
          Generator.generate(service, output_dir)
          spec_file = Generator.generate_spec(service, File.join(project_root, "spec/google_apis"))
          sync_api_list_yaml(project_root)
          return {true, "Successfully generated #{service.name} (#{service.version}) from #{target_query} into #{output_dir}\nSpec created/verified at: #{spec_file}", service}
        end
        return {false, "Error: Could not find API target matching '#{target_query}'.", nil}
      end

      json_content = begin
        cat.fetch_discovery_json(target, File.join(project_root, "discovery"))
      rescue ex
        return {false, "Failed to fetch discovery JSON for #{target.id}: #{ex.message}", nil}
      end

      service = Generator.parse(json_content)
      output_dir = File.join(project_root, "src/google_apis", service.name, service.version.downcase)
      Generator.generate(service, output_dir)

      # Generate unit test spec scaffold if not present
      spec_file = Generator.generate_spec(service, File.join(project_root, "spec/google_apis"))

      # Sync and save api-list.yaml
      sync_api_list_yaml(project_root)

      msg = String.build do |builder|
        builder << "Successfully generated Google #{service.name} (#{service.version}) client!\n"
        builder << "  - Schemas: #{service.schemas.size}\n"
        builder << "  - Resources: #{service.resources.size}\n"
        builder << "  - Location: #{output_dir}\n"
        builder << "  - Documentation: #{File.join(output_dir, "README.md")}\n"
        builder << "  - Spec: #{spec_file}"
      end

      {true, msg, service}
    end

    # Runs `crystal docs` command in project_root.
    def self.generate_docs(project_root : String = ".") : Tuple(Bool, String)
      output = IO::Memory.new
      status = Process.run("crystal", ["docs"], chdir: project_root, output: output, error: output)
      success = status.success?
      text = output.to_s.strip
      msg = if success
              "Documentation generated successfully in #{File.join(project_root, "docs")}/\n#{text}"
            else
              "Failed to generate documentation (exit code #{status.exit_code}):\n#{text}"
            end
      {success, msg}
    end

    # Removes the generated docs directory.
    def self.remove_docs(project_root : String = ".") : Tuple(Bool, String)
      docs_dir = File.join(project_root, "docs")
      if Dir.exists?(docs_dir)
        FileUtils.rm_rf(docs_dir)
        {true, "Successfully removed generated documentation directory: #{docs_dir}"}
      else
        {true, "Documentation directory '#{docs_dir}' does not exist (already clean)."}
      end
    end

    # Runs unit tests for a particular API (e.g. "storage", "run", etc.).
    def self.run_tests_for(api_query : String, project_root : String = ".") : Tuple(Bool, String)
      spec_dir = File.join(project_root, "spec/google_apis")
      query = api_query.downcase.strip

      matching_files = [] of String
      if Dir.exists?(spec_dir)
        Dir.glob(File.join(spec_dir, "*.cr")).each do |spec_file|
          base = File.basename(spec_file)
          if base.downcase.includes?(query)
            matching_files << spec_file
          end
        end
      end

      if matching_files.empty?
        return {false, "No unit test files found in #{spec_dir} matching '#{api_query}'."}
      end

      output = IO::Memory.new
      status = Process.run("crystal", ["spec"] + matching_files, chdir: project_root, output: output, error: output)
      success = status.success?
      {success, output.to_s.strip}
    end

    # Runs all unit tests with `crystal spec`.
    def self.run_all_tests(project_root : String = ".") : Tuple(Bool, String)
      output = IO::Memory.new
      status = Process.run("crystal", ["spec"], chdir: project_root, output: output, error: output)
      success = status.success?
      {success, output.to_s.strip}
    end

    # Detects generated API directory names under src/google_apis.
    def self.find_generated_api_names(project_root : String = ".") : Array(String)
      src_dir = File.join(project_root, "src/google_apis")
      apis = [] of String
      return apis unless Dir.exists?(src_dir)

      Dir.children(src_dir).each do |child|
        full_path = File.join(src_dir, child)
        next unless Dir.exists?(full_path)
        next if PROTECTED_DIRS.includes?(child)

        has_client = Dir.children(full_path).any? do |v_dir|
          File.exists?(File.join(full_path, v_dir, "client.cr"))
        end
        apis << child if has_client
      end
      apis.sort
    end

    # Clears out existing generated APIs and regenerates them from discovery docs.
    def self.clear_and_regenerate(project_root : String = ".") : Tuple(Bool, String)
      generated_names = find_generated_api_names(project_root)
      src_dir = File.join(project_root, "src/google_apis")
      discovery_dir = File.join(project_root, "discovery")

      # Delete generated directories
      generated_names.each do |api_name|
        api_path = File.join(src_dir, api_name)
        FileUtils.rm_rf(api_path) if Dir.exists?(api_path)
      end

      # Find discovery docs to regenerate from
      regenerated = [] of String
      failed = [] of String

      cat = catalog(discovery_dir: discovery_dir, src_dir: src_dir, allow_network: true)

      generated_names.each do |api_name|
        target = cat.find_target(api_name)
        if target
          success, msg, _ = generate_api(target.id, project_root, allow_network: true)
          if success
            regenerated << "#{target.name} (#{target.version})"
          else
            failed << "#{api_name}: #{msg}"
          end
        else
          # Fallback: check discovery/*.json for matching file
          local_file = Dir.glob(File.join(discovery_dir, "#{api_name}_*.json")).first?
          if local_file && File.exists?(local_file)
            success, msg, _ = generate_api(local_file, project_root, allow_network: false)
            if success
              regenerated << api_name
            else
              failed << "#{api_name}: #{msg}"
            end
          else
            failed << "#{api_name}: Discovery document not found"
          end
        end
      end

      sync_api_list_yaml(project_root)

      res_msg = String.build do |builder|
        builder << "Regeneration completed:\n"
        builder << "  - Cleared: #{generated_names.join(", ")}\n"
        builder << "  - Regenerated: #{regenerated.join(", ")}\n"
        unless failed.empty?
          builder << "  - Warnings/Failures: #{failed.join("; ")}\n"
        end
      end

      {failed.empty?, res_msg}
    end

    # Synchronizes Discovery target versions to api-list.yaml.
    def self.sync_api_list_yaml(project_root : String = ".") : Tuple(Bool, String)
      cat = catalog(
        discovery_dir: File.join(project_root, "discovery"),
        src_dir: File.join(project_root, "src/google_apis"),
        allow_network: true
      )
      yaml_path = File.join(project_root, "api-list.yaml")
      registry = ApiListRegistry.sync_and_save(cat, yaml_path)

      outdated = registry.out_of_date_apis
      msg = String.build do |builder|
        builder << "Saved API version registry to #{yaml_path}\n"
        builder << "  - Total APIs tracked: #{registry.apis.size}\n"
        if outdated.empty?
          builder << "  - All generated APIs are UP TO DATE!"
        else
          builder << "  - OUT OF DATE APIs detected (#{outdated.size}):\n"
          outdated.each do |name, entry|
            builder << "    * #{name}: generated #{entry.generated_version} -> latest #{entry.latest_version}\n"
          end
        end
      end

      {true, msg}
    end

    # Returns help documentation.
    def self.help_text : String
      <<-HELP
      Google APIs Generator & Manager Help
      ====================================

      This application manages the Google APIs Crystal client library code generation
      using the Google Discovery Service.

      Options & Capabilities:
      -----------------------
      1. [G] Generate API:
         Choose a Google API target from Google Discovery Docs (or enter name/id like
         'storage', 'run', 'youtube:v3'). Generates strongly-typed Crystal clients in
         'src/google_apis/<name>/<version>/', creates a usage README.md in that directory,
         and generates a unit test spec in 'spec/google_apis/'.

      2. [L] Show all API Targets:
         Lists all targets available from Google Discovery Service and local discovery files,
         showing their title, latest version, and whether currently generated and up to date.

      3. [D] Generate Documentation:
         Runs 'crystal docs' to build the complete Crystal HTML documentation site in 'docs/'.

      4. [R] Remove Documentation:
         Cleans up and removes the entire 'docs/' directory.

      5. [T] Run Unit Tests for API:
         Runs specs for a particular API target (e.g. 'storage', 'run') via 'crystal spec'.

      6. [A] Run All Unit Tests:
         Executes the full test suite with 'crystal spec'.

      7. [C] Clear & Regenerate:
         Clears out existing generated API directories and regenerates them cleanly
         from discovery documents, including updated READMEs and specs.

      8. [S] Sync api-list.yaml:
         Synchronizes latest version numbers from Google Discovery Docs into 'api-list.yaml'
         so you can detect whenever a generated API is out of date.

      9. [H] Help:
         Displays this help text.

      10. [Q] Quit:
          Exits the application.
      HELP
    end
  end
end
