module GoogleApis
  module Generator
    # Represents a property in a schema.
    class PropertyModel
      getter json_name : String
      getter crystal_name : String
      getter crystal_type : String
      getter description : String?

      def initialize(@json_name : String, @crystal_name : String, @crystal_type : String, @description : String? = nil)
      end
    end

    # Represents a schema object.
    class SchemaModel
      getter name : String
      getter description : String?
      getter properties : Array(PropertyModel)

      def initialize(@name : String, @description : String?, @properties : Array(PropertyModel))
      end
    end

    # Represents an API method parameter.
    class ParameterModel
      getter json_name : String
      getter crystal_name : String
      getter crystal_type : String
      getter location : String # "path" or "query"
      getter? required : Bool
      getter description : String?

      def initialize(
        @json_name : String,
        @crystal_name : String,
        @crystal_type : String,
        @location : String,
        @required : Bool,
        @description : String? = nil,
      )
      end
    end

    # Represents an API method on a resource.
    class MethodModel
      getter id : String
      getter crystal_name : String
      getter http_method : String
      getter path : String
      getter description : String?
      getter parameters : Array(ParameterModel)
      getter request_ref : String?
      getter response_ref : String?

      def initialize(
        @id : String,
        @crystal_name : String,
        @http_method : String,
        @path : String,
        @description : String?,
        @parameters : Array(ParameterModel),
        @request_ref : String?,
        @response_ref : String?,
      )
      end

      def path_parameters : Array(ParameterModel)
        @parameters.select { |param| param.location == "path" }
      end

      def query_parameters : Array(ParameterModel)
        @parameters.select { |param| param.location == "query" }
      end

      def required_parameters : Array(ParameterModel)
        @parameters.select(&.required?)
      end

      def optional_parameters : Array(ParameterModel)
        @parameters.reject(&.required?)
      end
    end

    # Represents a resource (e.g. buckets, objects).
    class ResourceModel
      getter name : String
      getter class_name : String
      getter getter_name : String
      getter file_name : String
      getter methods : Array(MethodModel)

      def initialize(
        @name : String,
        @class_name : String,
        @getter_name : String,
        @file_name : String,
        @methods : Array(MethodModel),
      )
      end
    end

    # Represents the entire discovery service.
    class ServiceModel
      getter name : String
      getter version : String
      getter title : String?
      getter description : String?
      getter root_url : String
      getter service_path : String
      getter base_url : String
      getter module_name : String
      getter schemas : Array(SchemaModel)
      getter resources : Array(ResourceModel)

      def initialize(
        @name : String,
        @version : String,
        @title : String?,
        @description : String?,
        @root_url : String,
        @service_path : String,
        @base_url : String,
        @module_name : String,
        @schemas : Array(SchemaModel),
        @resources : Array(ResourceModel),
      )
      end
    end
  end
end
