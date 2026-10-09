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
          sample_src, sample_bin = Generator.generate_sample_cli(service, project_root)
          sync_api_list_yaml(project_root)
          msg = "Successfully generated #{service.name} (#{service.version}) from #{target_query} into #{output_dir}\nSpec: #{spec_file}\nSample CLI: #{sample_bin || sample_src}"
          return {true, msg, service}
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

      # Generate sample CLI program and executable in bin/
      sample_src, sample_bin = Generator.generate_sample_cli(service, project_root)

      # Sync and save api-list.yaml
      sync_api_list_yaml(project_root)

      msg = String.build do |builder|
        builder << "Successfully generated Google #{service.name} (#{service.version}) client!\n"
        builder << "  - Schemas: #{service.schemas.size}\n"
        builder << "  - Resources: #{service.resources.size}\n"
        builder << "  - Location: #{output_dir}\n"
        builder << "  - Documentation: #{File.join(output_dir, "README.md")}\n"
        builder << "  - Spec: #{spec_file}\n"
        builder << "  - Sample CLI Source: #{sample_src}\n"
        if sample_bin
          builder << "  - Sample CLI Executable: #{sample_bin}"
        else
          builder << "  - Sample CLI Executable: (build pending)"
        end
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

    # Removes a generated API or documentation.
    # Removes associated files in src/google_apis, src/bin, bin, spec, shard.yml, src/google_apis_cr.cr, and docs.
    def self.remove_api(api_query : String, project_root : String = ".") : Tuple(Bool, String)
      query = api_query.strip.downcase
      return {false, "API name cannot be empty."} if query.empty?
      return remove_docs(project_root) if query == "docs"
      return remove_all_apis(project_root) if query == "all"

      generated = find_generated_api_names(project_root)
      target_api = generated.find { |name| name.downcase == query || name.downcase.includes?(query) }
      unless target_api
        return {false, "No generated API found matching '#{api_query}'. Generated APIs: #{generated.join(", ")}"}
      end

      if PROTECTED_DIRS.includes?(target_api)
        return {false, "Cannot remove protected directory '#{target_api}'."}
      end

      removed_items = remove_single_api(target_api, project_root)
      sync_api_list_yaml(project_root)

      msg = String.build do |builder|
        builder << "Successfully removed #{target_api} API and associated files:\n"
        removed_items.each do |item|
          builder << "  - #{item}\n"
        end
      end
      {true, msg.strip}
    end

    private def self.remove_all_apis(project_root : String) : Tuple(Bool, String)
      generated = find_generated_api_names(project_root)
      if generated.empty?
        remove_docs(project_root)
        return {true, "No generated APIs to remove. Cleaned documentation."}
      end

      all_removed = [] of String
      generated.each do |api_name|
        all_removed.concat(remove_single_api(api_name, project_root))
      end
      remove_docs(project_root)
      sync_api_list_yaml(project_root)

      msg = "Successfully removed all generated APIs (#{generated.join(", ")}):\n" +
            all_removed.map { |item| "  - #{item}" }.join("\n")
      {true, msg}
    end

    private def self.remove_single_api(target_api : String, project_root : String) : Array(String)
      removed_items = [] of String

      # 1. src/google_apis/<api>
      api_dir = File.join(project_root, "src/google_apis", target_api)
      if Dir.exists?(api_dir)
        FileUtils.rm_rf(api_dir)
        removed_items << "src/google_apis/#{target_api}/"
      end

      # 2. src/bin scripts
      src_bin_dir = File.join(project_root, "src/bin")
      target_names = collect_api_target_names(target_api)
      target_names.each do |target_name|
        script_file = File.join(src_bin_dir, "#{target_name}.cr")
        if File.exists?(script_file)
          FileUtils.rm(script_file)
          removed_items << "src/bin/#{target_name}.cr"
        end
      end

      # 3. bin executables
      bin_dir = File.join(project_root, "bin")
      target_names.each do |target_name|
        bin_file = File.join(bin_dir, target_name)
        if File.exists?(bin_file)
          FileUtils.rm(bin_file)
          removed_items << "bin/#{target_name}"
        end
        dwarf_file = File.join(bin_dir, "#{target_name}.dwarf")
        if File.exists?(dwarf_file)
          FileUtils.rm(dwarf_file)
        end
      end

      # 4. spec files
      spec_dir = File.join(project_root, "spec/google_apis")
      if Dir.exists?(spec_dir)
        Dir.glob(File.join(spec_dir, "*#{target_api}*.cr")).each do |spec_file|
          FileUtils.rm(spec_file)
          removed_items << "spec/google_apis/#{File.basename(spec_file)}"
        end
      end

      # 5. shard.yml targets
      remove_shard_targets(project_root, target_names)

      # 6. src/google_apis_cr.cr requires
      remove_main_require(project_root, target_api)

      # 7. docs
      docs_api_dir = File.join(project_root, "docs/GoogleApis", target_api.camelcase)
      if Dir.exists?(docs_api_dir)
        FileUtils.rm_rf(docs_api_dir)
        removed_items << "docs/GoogleApis/#{target_api.camelcase}/"
      end

      removed_items
    end

    private def self.collect_api_target_names(api_name : String) : Array(String)
      names = ["list_#{api_name}", "list_#{api_name.underscore}"]
      case api_name
      when "run"
        names << "list_cloud_run"
      when "artifactregistry"
        names << "list_registries"
      when "storage"
        names << "list_storage"
      end
      names.uniq
    end

    private def self.remove_shard_targets(project_root : String, target_names : Array(String))
      shard_path = File.join(project_root, "shard.yml")
      return unless File.exists?(shard_path)
      lines = File.read_lines(shard_path)
      new_lines = [] of String
      skip_next_main = false

      lines.each do |line|
        if skip_next_main
          skip_next_main = false
          next if line.strip.starts_with?("main:")
        end

        matched = target_names.any? do |t_name|
          stripped = line.strip
          stripped == "#{t_name}:" || stripped.starts_with?("#{t_name}:")
        end

        if matched
          skip_next_main = true
          next
        end

        new_lines << line
      end

      File.write(shard_path, new_lines.join("\n") + "\n")
    end

    private def self.remove_main_require(project_root : String, api_name : String)
      main_file = File.join(project_root, "src/google_apis_cr.cr")
      return unless File.exists?(main_file)
      lines = File.read_lines(main_file)
      pattern = %(require "./google_apis/#{api_name}/)
      new_lines = lines.reject(&.includes?(pattern))
      File.write(main_file, new_lines.join("\n") + "\n")
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

      2. [D] Generate Documentation:
         Runs 'crystal docs' to build the complete Crystal HTML documentation site in 'docs/'.

      3. [R] Remove API and documentation:
         Removes a generated API (or 'all', or 'docs'), deleting its client library in
         'src/google_apis/', sample CLI in 'src/bin/', executable in 'bin/', spec in
         'spec/google_apis/', shard target in 'shard.yml', and associated documentation.

      4. [T] Run Unit Tests for API:
         Runs specs for a particular API target (e.g. 'storage', 'run') via 'crystal spec'.

      5. [A] Run All Unit Tests:
         Executes the full test suite with 'crystal spec'.

      6. [C] Clear & Regenerate:
         Clears out existing generated API directories and regenerates them cleanly
         from discovery documents, including updated READMEs and specs.

      7. [S] Sync api-list.yaml:
         Synchronizes latest version numbers from Google Discovery Docs into 'api-list.yaml'
         so you can detect whenever a generated API is out of date.

      8. [H] Help:
         Displays this help text.

      9. [Q] Quit:
         Exits the application.
      HELP
    end
  end
end
