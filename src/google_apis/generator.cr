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
        "Hash(String, #{crystal_type_for(add_prop)})"
      else
        "JSON::Any"
      end
    end

    # Sanitizes parameter or property names to avoid Crystal keyword collisions.
    def self.sanitize_identifier(name : String) : String
      s = name.underscore
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
    end
  end
end
