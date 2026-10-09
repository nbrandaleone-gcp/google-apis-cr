require "json"
require "file_utils"
require "./generator/models"
require "./generator/views"

module GoogleApis
  module Generator
    CRYSTAL_KEYWORDS = Set{
      "def", "end", "class", "module", "case", "when", "in", "out", "if",
      "unless", "else", "elsif", "while", "until", "break", "next", "return",
      "yield", "self", "super", "true", "false", "nil", "begin", "rescue",
      "ensure", "alias", "select", "do", "for", "type",
    }

    # Maps a JSON discovery schema property to a Crystal type string.
    def self.crystal_type_for(prop : JSON::Any) : String
      if ref = prop["$ref"]?.try(&.as_s?)
        return ref
      end

      if type = prop["type"]?.try(&.as_s?)
        case type
        when "string"  then "String"
        when "integer" then "Int64"
        when "number"  then "Float64"
        when "boolean" then "Bool"
        when "array", "object"
          container_type_for(type, prop)
        else
          "JSON::Any"
        end
      else
        "JSON::Any"
      end
    end

    private def self.container_type_for(type : String, prop : JSON::Any) : String
      if type == "array"
        if items = prop["items"]?
          "Array(#{crystal_type_for(items)})"
        else
          "Array(JSON::Any)"
        end
      elsif add_prop = prop["additionalProperties"]?
        "::Hash(String, #{crystal_type_for(add_prop)})"
      else
        "JSON::Any"
      end
    end

    # Sanitizes parameter or property names to avoid Crystal keyword collisions.
    def self.sanitize_identifier(name : String) : String
      s = name.gsub(".", "_").underscore
      CRYSTAL_KEYWORDS.includes?(s) ? "#{s}_param" : s
    end

    # Parses a Discovery Document JSON into a ServiceModel.
    def self.parse(json_str : String) : ServiceModel
      doc = JSON.parse(json_str)

      name = doc["name"].as_s
      version = doc["version"].as_s
      title = doc["title"]?.try(&.as_s)
      description = doc["description"]?.try(&.as_s)
      root_url = doc["rootUrl"].as_s
      service_path = doc["servicePath"]?.try(&.as_s) || ""
      base_url = "#{root_url}#{service_path}"

      module_name = "GoogleApis::#{name.camelcase}::#{version.upcase}"

      schemas_json = doc["schemas"]?.try(&.as_h) || {} of String => JSON::Any
      schemas = [] of SchemaModel

      schemas_json.each do |s_name, s_val|
        s_desc = s_val["description"]?.try(&.as_s)
        props = [] of PropertyModel

        if props_json = s_val["properties"]?.try(&.as_h)
          props_json.each do |p_name, p_val|
            p_c_name = sanitize_identifier(p_name)
            p_c_type = crystal_type_for(p_val)
            p_desc = p_val["description"]?.try(&.as_s)
            props << PropertyModel.new(p_name, p_c_name, p_c_type, p_desc)
          end
        end

        schemas << SchemaModel.new(s_name, s_desc, props)
      end

      # Sort schemas by name for consistent generated output
      schemas.sort_by!(&.name)

      resources_json = doc["resources"]?.try(&.as_h) || {} of String => JSON::Any
      resources = collect_resources(resources_json, schemas_json)

      ServiceModel.new(
        name: name,
        version: version,
        title: title,
        description: description,
        root_url: root_url,
        service_path: service_path,
        base_url: base_url,
        module_name: module_name,
        schemas: schemas,
        resources: resources
      )
    end

    # Recursively collects resources and subresources.
    def self.collect_resources(
      resources : Hash(String, JSON::Any),
      schemas : Hash(String, JSON::Any),
      prefix : String = "",
    ) : Array(ResourceModel)
      result = [] of ResourceModel

      resources.each do |name, resource_json|
        full_name = prefix.empty? ? name : "#{prefix}_#{name}"
        class_name = "#{full_name.camelcase}Service"
        getter_name = sanitize_identifier(full_name)
        file_name = "#{full_name.underscore}_service"

        methods = parse_methods_for_resource(full_name, resource_json)

        if !methods.empty?
          result << ResourceModel.new(
            name: full_name,
            class_name: class_name,
            getter_name: getter_name,
            file_name: file_name,
            methods: methods
          )
        end

        if sub_resources = resource_json["resources"]?.try(&.as_h)
          result.concat(collect_resources(sub_resources, schemas, full_name))
        end
      end

      result
    end

    private def self.parse_methods_for_resource(
      full_name : String,
      resource_json : JSON::Any,
    ) : Array(MethodModel)
      methods_json = resource_json["methods"]?.try(&.as_h)
      return [] of MethodModel unless methods_json

      methods = [] of MethodModel
      methods_json.each do |m_name, method_json|
        method_id = method_json["id"]?.try(&.as_s) || "#{full_name}.#{m_name}"
        crystal_name = sanitize_identifier(m_name)
        http_method = method_json["httpMethod"]?.try(&.as_s) || "GET"
        path = method_json["path"]?.try(&.as_s) || ""
        desc = method_json["description"]?.try(&.as_s)

        req_ref = method_json["request"]?.try(&.["$ref"]?.try(&.as_s))
        res_ref = method_json["response"]?.try(&.["$ref"]?.try(&.as_s))

        parameters = parse_method_parameters(method_json)

        methods << MethodModel.new(
          id: method_id,
          crystal_name: crystal_name,
          http_method: http_method,
          path: path,
          description: desc,
          parameters: parameters,
          request_ref: req_ref,
          response_ref: res_ref
        )
      end
      methods
    end

    private def self.parse_method_parameters(method_json : JSON::Any) : Array(ParameterModel)
      params_json = method_json["parameters"]?.try(&.as_h)
      return [] of ParameterModel unless params_json

      param_order = method_json["parameterOrder"]?.try(&.as_a.map(&.as_s)) || [] of String

      sorted_keys = params_json.keys.sort_by! do |key|
        p_val = params_json[key]
        is_req = p_val["required"]?.try(&.as_bool) || (p_val["location"]? == "path")
        order_idx = param_order.index(key) || 999
        {is_req ? 0 : 1, order_idx, key}
      end

      parameters = [] of ParameterModel
      sorted_keys.each do |p_key|
        p_val = params_json[p_key]
        p_loc = p_val["location"]?.try(&.as_s) || "query"
        p_req = p_val["required"]?.try(&.as_bool) || (p_loc == "path")
        p_c_name = sanitize_identifier(p_key)
        p_c_type = crystal_type_for(p_val)
        p_desc = p_val["description"]?.try(&.as_s)

        parameters << ParameterModel.new(
          json_name: p_key,
          crystal_name: p_c_name,
          crystal_type: p_c_type,
          location: p_loc,
          required: p_req,
          description: p_desc
        )
      end
      parameters
    end

    # Generates all client files for a ServiceModel into target_dir.
    def self.generate(service : ServiceModel, target_dir : String)
      FileUtils.mkdir_p(target_dir)

      # 1. Types
      types_content = TypesView.new(service).to_s
      File.write(File.join(target_dir, "types.cr"), types_content)

      # 2. Resource services
      service.resources.each do |resource|
        resource_content = ResourceServiceView.new(service, resource).to_s
        File.write(File.join(target_dir, "#{resource.file_name}.cr"), resource_content)
      end

      # 3. Client
      client_content = ClientView.new(service).to_s
      File.write(File.join(target_dir, "client.cr"), client_content)

      # 4. Service module (v1.cr)
      service_module_content = ServiceModuleView.new(service).to_s
      File.write(File.join(target_dir, "#{service.version.downcase}.cr"), service_module_content)

      # 5. README.md with usage example
      readme_content = generate_readme(service)
      File.write(File.join(target_dir, "README.md"), readme_content)

      # 6. Auto-format generated Crystal files
      Process.run("crystal", ["tool", "format", target_dir])
    end

    # Generates a README.md documenting usage of the generated client.
    def self.generate_readme(service : ServiceModel) : String
      String.build do |builder|
        title = service.title || "#{service.name.capitalize} API"
        builder << "# #{title} (#{service.version.upcase})\n\n"
        if desc = service.description
          builder << desc << "\n\n"
        end
        builder << "This client was generated from the Google Discovery document for `#{service.name}` (#{service.version}).\n\n"
        builder << "## Usage Example\n\n"
        builder << "```crystal\n"
        builder << "require \"google_apis_cr\"\n\n"
        builder << "# Load Application Default Credentials (ADC)\n"
        builder << "credentials = GoogleApis::Auth.default_credentials\n\n"
        builder << "# Initialize #{title} Client\n"
        builder << "client = #{service.module_name}::Client.new(credentials)\n"

        if first_res = service.resources.first?
          builder << "\n# Access #{first_res.getter_name} methods:\n"
          if first_method = first_res.methods.first?
            builder << "# response = client.#{first_res.getter_name}.#{first_method.crystal_name}("
            req_params = first_method.required_parameters
            if req_params.empty?
              builder << ")\n"
            else
              builder << req_params.map { |param| "#{param.crystal_name}: \"value\"" }.join(", ")
              builder << ")\n"
            end
          else
            builder << "# client.#{first_res.getter_name}\n"
          end
        end

        builder << "```\n\n"
        builder << "## Available Resources\n\n"
        builder << "| Resource | Service Class | Methods |\n"
        builder << "|---|---|---|\n"
        service.resources.each do |resource|
          methods_summary = resource.methods.map(&.crystal_name).join(", ")
          builder << "| `#{resource.getter_name}` | `#{resource.class_name}` | `#{methods_summary}` |\n"
        end
        builder << "\n"
      end
    end

    # Generates a spec file for the given ServiceModel if not already present.
    def self.generate_spec(service : ServiceModel, spec_dir : String = "spec/google_apis") : String
      FileUtils.mkdir_p(spec_dir)
      spec_file = File.join(spec_dir, "#{service.name.underscore}_#{service.version.downcase}_spec.cr")
      return spec_file if File.exists?(spec_file)

      content = String.build do |builder|
        builder << "require \"../spec_helper\"\n"
        builder << "require \"../../src/google_apis/#{service.name}/#{service.version.downcase}/#{service.version.downcase}\"\n\n"
        builder << "describe #{service.module_name} do\n"
        builder << "  it \"initializes #{service.name} client with credentials\" do\n"
        builder << "    creds = MockCredentials.new\n"
        builder << "    client = #{service.module_name}::Client.new(creds)\n"
        builder << "    client.client.base_url.should eq(\"#{service.base_url}\")\n"
        builder << "  end\n"
        if first_res = service.resources.first?
          builder << "\n  it \"exposes #{first_res.getter_name} service\" do\n"
          builder << "    creds = MockCredentials.new\n"
          builder << "    client = #{service.module_name}::Client.new(creds)\n"
          builder << "    client.#{first_res.getter_name}.should_not be_nil\n"
          builder << "  end\n"
        end
        builder << "end\n"
      end

      File.write(spec_file, content)
      spec_file
    end

    # Generates a sample CLI in src/bin/list_#{service.name}.cr and builds bin/list_#{service.name}.
    def self.generate_sample_cli(service : ServiceModel, project_root : String = ".") : Tuple(String, String?)
      bin_dir = File.join(project_root, "bin")
      src_bin_dir = File.join(project_root, "src/bin")
      FileUtils.mkdir_p(bin_dir)
      FileUtils.mkdir_p(src_bin_dir)

      target_name = "list_#{service.name.underscore}"
      sample_src_file = File.join(src_bin_dir, "#{target_name}.cr")
      sample_bin_file = File.join(bin_dir, target_name)

      # 1. Generate sample Crystal script if it does not already exist
      unless File.exists?(sample_src_file)
        picked = pick_primary_list_resource(service)
        res = picked.try(&.[0])
        meth = picked.try(&.[1])
        code = generate_sample_script_content(service, res, meth)
        File.write(sample_src_file, code)
        Process.run("crystal", ["tool", "format", sample_src_file])
      end

      # 2. Register target in shard.yml
      ensure_shard_target(project_root, target_name, "src/bin/#{target_name}.cr")

      # 3. Register in src/google_apis_cr.cr
      ensure_main_require(project_root, service)

      # 4. Compile binary into bin/
      build_output = IO::Memory.new
      status = Process.run(
        "crystal",
        ["build", sample_src_file, "-o", sample_bin_file],
        chdir: project_root,
        output: build_output,
        error: build_output
      )

      bin_path = status.success? ? sample_bin_file : nil
      {sample_src_file, bin_path}
    end

    # Picks the primary listable resource and method for the API service.
    def self.pick_primary_list_resource(service : ServiceModel) : Tuple(ResourceModel, MethodModel)?
      candidates = [] of Tuple(ResourceModel, MethodModel, Int32)

      service.resources.each do |res|
        res.methods.each do |meth|
          next unless meth.crystal_name == "list" || meth.crystal_name.starts_with?("list_")
          score = score_resource_for_sample(service, res, meth)
          candidates << {res, meth, score}
        end
      end

      best = candidates.sort_by { |candidate| candidate[2] }.first?
      best ? {best[0], best[1]} : nil
    end

    # Calculates a suitability score for picking a primary listing resource.
    def self.score_resource_for_sample(
      service : ServiceModel,
      res : ResourceModel,
      m : MethodModel,
    ) : Int32
      score = calculate_resource_penalties(res, m)
      score + calculate_resource_bonuses(service, res, m)
    end

    private def self.calculate_resource_penalties(res : ResourceModel, m : MethodModel) : Int32
      score = 0
      if res.name.ends_with?("operations") || res.name.ends_with?("locations")
        score += 60
      end
      if res.name.includes?("iam") || res.name.includes?("policy") || res.name.includes?("policies")
        score += 40
      end
      if res.name.includes?("zone_operations") || res.name.includes?("dns_keys") || res.name.includes?("changes")
        score += 30
      end

      req_params = m.required_parameters
      req_params.each do |param|
        p_name = param.crystal_name.downcase
        unless ["project", "parent", "name", "project_id"].includes?(p_name)
          score += 50
        end
      end
      score += req_params.size * 10
      score += res.name.split("_").size * 2
      score
    end

    private def self.calculate_resource_bonuses(service : ServiceModel, res : ResourceModel, m : MethodModel) : Int32
      score = 0
      r_name = res.name.downcase
      s_name = service.name.downcase
      score -= 20 if r_name.includes?(s_name)

      primary_suffixes = [
        "services", "buckets", "repositories", "managed_zones",
        "instances", "clusters", "topics", "subscriptions",
      ]
      if primary_suffixes.any? { |suffix| r_name.ends_with?(suffix) }
        score -= 30
      end

      if s_name == "run" && r_name.ends_with?("services")
        score -= 10
      end

      score -= 5 if m.response_ref
      score
    end

    # Generates the source code for a sample list CLI.
    def self.generate_sample_script_content(
      service : ServiceModel,
      res : ResourceModel?,
      m : MethodModel?,
    ) : String
      title = service.title || "#{service.name.capitalize} API"
      bin_name = "list_#{service.name.underscore}"

      String.build do |builder|
        builder << "require \"option_parser\"\n"
        builder << "require \"json\"\n"
        builder << "require \"../google_apis_cr\"\n"
        builder << "require \"../google_apis/#{service.name}/#{service.version.downcase}/#{service.version.downcase}\"\n\n"
        builder << "# Sample CLI tool to list Google #{title} primary resources.\n"
        builder << "project_id : String? = nil\n"

        needs_location = false
        if m
          needs_location = m.parameters.any? { |param| param.crystal_name == "location" } ||
                           m.path.includes?("locations") ||
                           m.parameters.any? { |param| param.crystal_name == "parent" && param.description.try(&.includes?("locations")) }
        end

        builder << "location_arg : String? = nil\n" if needs_location
        builder << "max_results : Int64? = nil\n"
        builder << "output_json = false\n\n"

        builder << "OptionParser.parse do |opts|\n"
        builder << "  opts.banner = \"Usage: #{bin_name} [options]\"\n\n"
        builder << "  opts.on(\"-p PROJECT\", \"--project=PROJECT\", \"Google Cloud Project ID (default: from credentials/environment)\") do |arg|\n"
        builder << "    project_id = arg\n"
        builder << "  end\n\n"

        if needs_location
          builder << "  opts.on(\"-l LOCATION\", \"--location=LOCATION\", \"Location or region (default: '-' or us-central1)\") do |arg|\n"
          builder << "    location_arg = arg\n"
          builder << "  end\n\n"
        end

        builder << "  opts.on(\"-m NUM\", \"--max-results=NUM\", \"Max results to return\") do |arg|\n"
        builder << "    max_results = arg.to_i64?\n"
        builder << "  end\n\n"

        builder << "  opts.on(\"-j\", \"--json\", \"Output response as formatted JSON\") do\n"
        builder << "    output_json = true\n"
        builder << "  end\n\n"

        builder << "  opts.on(\"-h\", \"--help\", \"Show help documentation\") do\n"
        builder << "    puts opts\n"
        builder << "    exit 0\n"
        builder << "  end\n"
        builder << "end\n\n"

        builder << "begin\n"
        builder << "  credentials = GoogleApis::Auth.default_credentials\n"
        builder << "  resolved_project = project_id ||\n"
        builder << "                     ENV[\"GOOGLE_CLOUD_PROJECT\"]? ||\n"
        builder << "                     ENV[\"GCP_PROJECT\"]? ||\n"
        builder << "                     credentials.quota_project_id ||\n"
        builder << "                     credentials.project_id\n\n"
        builder << "  unless resolved_project\n"
        builder << "    STDERR.puts \"Error: Project ID could not be determined. Please specify with -p/--project.\"\n"
        builder << "    exit 1\n"
        builder << "  end\n\n"

        builder << "  client = #{service.module_name}::Client.new(credentials)\n"
        builder << "  puts \"Authenticated via Application Default Credentials\"\n"
        builder << "  puts \"Target Project: \#{resolved_project}\"\n"
        builder << "  puts \"-\" * 60\n\n"

        if res && m
          build_sample_method_call(service, res, m, needs_location, builder)
        else
          builder << "  puts \"Client initialized successfully.\"\n"
        end

        builder << "rescue ex : GoogleApis::HttpError\n"
        builder << "  STDERR.puts \"API Error: \#{ex.message} (HTTP \#{ex.status_code})\"\n"
        builder << "  STDERR.puts ex.body unless ex.body.empty?\n"
        builder << "  exit 1\n"
        builder << "rescue ex\n"
        builder << "  STDERR.puts \"Error: \#{ex.message}\"\n"
        builder << "  exit 1\n"
        builder << "end\n"
      end
    end

    private def self.build_sample_method_call(
      service : ServiceModel,
      res : ResourceModel,
      m : MethodModel,
      needs_location : Bool,
      builder : IO,
    ) : Nil
      args_str = build_sample_call_args(m, needs_location).join(", ")
      builder << "  response = client.#{res.getter_name}.#{m.crystal_name}(#{args_str})\n\n"
      builder << "  if output_json\n"
      builder << "    puts response.to_json\n"
      builder << "    exit 0\n"
      builder << "  end\n\n"

      build_sample_items_loop(service, res, m, builder)
    end

    private def self.build_sample_call_args(m : MethodModel, needs_location : Bool) : Array(String)
      call_args = [] of String
      m.parameters.each do |param|
        if param.required?
          case param.crystal_name
          when "project", "project_id"
            call_args << "#{param.crystal_name}: resolved_project"
          when "parent", "name"
            if needs_location
              call_args << "#{param.crystal_name}: \"projects/\#{resolved_project}/locations/\#{location_arg || \"-\"}\""
            else
              call_args << "#{param.crystal_name}: \"projects/\#{resolved_project}\""
            end
          else
            call_args << "#{param.crystal_name}: \"default\""
          end
        elsif param.crystal_name == "max_results"
          call_args << "max_results: max_results"
        elsif param.crystal_name == "page_size"
          if param.crystal_type == "Int32"
            call_args << "page_size: max_results.try(&.to_i32)"
          else
            call_args << "page_size: max_results"
          end
        end
      end
      call_args
    end

    private def self.build_sample_items_loop(
      service : ServiceModel,
      res : ResourceModel,
      m : MethodModel,
      builder : IO,
    ) : Nil
      schema_names = service.schemas.map(&.name).to_set
      resp_schema = service.schemas.find { |s_item| s_item.name == m.response_ref }
      list_prop = resp_schema.try do |rs_item|
        rs_item.properties.find do |prop|
          prop.crystal_type.starts_with?("Array(") && (schema_names.includes?(prop.crystal_type[6...-1]) || prop.crystal_name == "items")
        end || rs_item.properties.find(&.crystal_type.starts_with?("Array("))
      end

      unless list_prop
        builder << "  puts \"Response:\"\n"
        builder << "  puts response.to_json\n"
        return
      end

      elem_type = list_prop.crystal_type.starts_with?("Array(") ? list_prop.crystal_type[6...-1] : nil
      elem_schema = elem_type ? service.schemas.find { |s_item| s_item.name == elem_type } : nil

      id_prop = elem_schema.try(&.properties.find { |prop| ["name", "id", "display_name", "title"].includes?(prop.crystal_name) })
      id_getter = id_prop ? id_prop.crystal_name : "name"

      detail_props = elem_schema.try do |es_item|
        candidates = ["description", "location", "status", "state", "format", "dns_name", "storage_class", "create_time", "visibility"]
        es_item.properties.select { |prop| candidates.includes?(prop.crystal_name) && prop.crystal_name != id_getter }.first(4)
      end || [] of PropertyModel

      builder << "  if items = response.#{list_prop.crystal_name}\n"
      builder << "    if items.empty?\n"
      builder << "      puts \"No #{res.name.underscore.tr("_", " ")} found.\"\n"
      builder << "    else\n"
      builder << "      puts \"Listing #{res.name.underscore.tr("_", " ")} (\#{items.size} found):\"\n"
      builder << "      items.each do |item|\n"
      builder << "        details = [] of String\n"
      detail_props.each do |prop|
        builder << "        if val = item.#{prop.crystal_name}\n"
        builder << "          details << \"#{prop.crystal_name}: \#{val}\"\n"
        builder << "        end\n"
      end
      builder << "        summary = details.empty? ? \"\" : \" [\#{details.join(\", \")}]\"\n"
      if id_prop
        builder << "        label = item.#{id_getter} || \"(unknown)\"\n"
      else
        builder << "        label = item.to_s\n"
      end
      builder << "        puts \"  * \#{label}\#{summary}\"\n"
      builder << "      end\n"
      builder << "    end\n"
      builder << "  else\n"
      builder << "    puts \"No items returned.\"\n"
      builder << "  end\n"
    end

    # Adds target to shard.yml if not already present.
    def self.ensure_shard_target(project_root : String, target_name : String, main_path : String)
      shard_path = File.join(project_root, "shard.yml")
      return unless File.exists?(shard_path)
      content = File.read(shard_path)
      return if content.includes?("#{target_name}:")

      new_content = if content.includes?("targets:")
                      content.sub("targets:", "targets:\n  #{target_name}:\n    main: #{main_path}")
                    else
                      content + "\ntargets:\n  #{target_name}:\n    main: #{main_path}\n"
                    end
      File.write(shard_path, new_content)
    end

    # Ensures the service module is required in src/google_apis_cr.cr.
    def self.ensure_main_require(project_root : String, service : ServiceModel)
      main_file = File.join(project_root, "src/google_apis_cr.cr")
      return unless File.exists?(main_file)
      content = File.read(main_file)
      require_stmt = %(require "./google_apis/#{service.name}/#{service.version.downcase}/#{service.version.downcase}")
      return if content.includes?(require_stmt)

      lines = content.lines
      last_req_idx = lines.rindex(&.strip.starts_with?("require "))
      if last_req_idx
        lines.insert(last_req_idx + 1, require_stmt)
        File.write(main_file, lines.join("\n") + "\n")
      end
    end
  end
end
