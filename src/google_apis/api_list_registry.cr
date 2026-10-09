require "yaml"
require "./discovery"

module GoogleApis
  # Represents an individual API entry in api-list.yaml.
  class ApiEntry
    include YAML::Serializable

    getter title : String
    getter latest_version : String
    getter generated_version : String?
    getter status : String
    getter discovery_url : String

    def initialize(
      @title : String,
      @latest_version : String,
      @generated_version : String?,
      @status : String,
      @discovery_url : String,
    )
    end

    def out_of_date? : Bool
      @status == "out_of_date"
    end

    def up_to_date? : Bool
      @status == "up_to_date"
    end
  end

  # Manages reading, writing, and synchronizing api-list.yaml.
  class ApiListRegistry
    include YAML::Serializable

    getter last_updated : String
    getter apis : Hash(String, ApiEntry)

    def initialize(
      @last_updated : String = Time.utc.to_s("%Y-%m-%d %H:%M:%S UTC"),
      @apis : Hash(String, ApiEntry) = Hash(String, ApiEntry).new,
    )
    end

    # Loads the registry from file if it exists, or creates an empty one.
    def self.load(file_path : String = "api-list.yaml") : ApiListRegistry
      if File.exists?(file_path)
        from_yaml(File.read(file_path))
      else
        ApiListRegistry.new
      end
    end

    # Synchronizes catalog targets against locally generated code and writes to api-list.yaml.
    def self.sync_and_save(
      catalog : DiscoveryCatalog,
      file_path : String = "api-list.yaml",
    ) : ApiListRegistry
      registry = load(file_path)

      catalog.targets.each do |target|
        gen_ver = target.generated_version
        status = if gen_ver
                   gen_ver == target.version ? "up_to_date" : "out_of_date"
                 else
                   "not_generated"
                 end

        registry.apis[target.name] = ApiEntry.new(
          title: target.title,
          latest_version: target.version,
          generated_version: gen_ver,
          status: status,
          discovery_url: target.discovery_url
        )
      end

      registry.save(file_path)
      registry
    end

    # Saves current registry to file_path.
    def save(file_path : String = "api-list.yaml")
      @last_updated = Time.utc.to_s("%Y-%m-%d %H:%M:%S UTC")
      File.write(file_path, to_yaml)
    end

    # Returns array of [api_name, entry] pairs that are out of date.
    def out_of_date_apis : Array(Tuple(String, ApiEntry))
      result = [] of Tuple(String, ApiEntry)
      @apis.each do |name, entry|
        result << {name, entry} if entry.out_of_date?
      end
      result
    end
  end
end
