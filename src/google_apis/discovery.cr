require "json"
require "http/client"
require "file_utils"

module GoogleApis
  # Represents a Google API target discovered from Google Discovery Docs.
  class DiscoveryTarget
    getter id : String
    getter name : String
    getter version : String
    getter title : String
    getter description : String?
    getter discovery_url : String
    getter? preferred : Bool
    getter local_path : String?
    property generated_version : String?

    def initialize(
      @id : String,
      @name : String,
      @version : String,
      @title : String,
      @discovery_url : String,
      @description : String? = nil,
      @preferred : Bool = true,
      @local_path : String? = nil,
      @generated_version : String? = nil,
    )
    end

    def generated? : Bool
      !@generated_version.nil?
    end

    def up_to_date? : Bool
      if gen_v = @generated_version
        gen_v == @version
      else
        false
      end
    end

    def out_of_date? : Bool
      if gen_v = @generated_version
        gen_v != @version
      else
        false
      end
    end

    def status_label : String
      if generated?
        if up_to_date?
          "[UP TO DATE]"
        else
          "[OUTDATED: current #{generated_version} -> latest #{version}]"
        end
      else
        "[AVAILABLE]"
      end
    end
  end

  # Catalog to list and query Google API targets.
  class DiscoveryCatalog
    DIRECTORY_URL = "https://discovery.googleapis.com/discovery/v1/apis"

    getter targets : Array(DiscoveryTarget)

    def initialize(@targets : Array(DiscoveryTarget) = [] of DiscoveryTarget)
    end

    # Loads targets from local discovery files (*.json in discovery_dir).
    def self.load_local_targets(discovery_dir : String = "discovery") : Array(DiscoveryTarget)
      targets = [] of DiscoveryTarget
      return targets unless Dir.exists?(discovery_dir)

      Dir.glob(File.join(discovery_dir, "*.json")).each do |file|
        next if File.basename(file) == "directory.json"
        parse_local_discovery_file(file).try { |parsed_target| targets << parsed_target }
      end
      targets
    end

    private def self.parse_local_discovery_file(file : String) : DiscoveryTarget?
      content = File.read(file)
      json = JSON.parse(content)
      name = json["name"]?.try(&.as_s?)
      version = json["version"]?.try(&.as_s?)
      return nil unless name && version

      id = json["id"]?.try(&.as_s?) || "#{name}:#{version}"
      title = json["title"]?.try(&.as_s?) || "#{name.capitalize} API"
      desc = json["description"]?.try(&.as_s?)
      root_url = json["rootUrl"]?.try(&.as_s?) || ""
      service_path = json["servicePath"]?.try(&.as_s?) || ""
      disc_url = "#{root_url}#{service_path}"

      DiscoveryTarget.new(
        id: id,
        name: name,
        version: version,
        title: title,
        discovery_url: disc_url,
        description: desc,
        preferred: true,
        local_path: file
      )
    rescue
      nil
    end

    # Loads targets from Google Discovery Directory API (or cached discovery/directory.json).
    def self.load_directory(discovery_dir : String = "discovery", allow_network : Bool = true) : Array(DiscoveryTarget)
      cached_file = File.join(discovery_dir, "directory.json")
      json_content = allow_network ? fetch_remote_directory_json(discovery_dir, cached_file) : nil

      if json_content.nil? && File.exists?(cached_file)
        json_content = File.read(cached_file)
      end

      return [] of DiscoveryTarget unless json_content
      parse_directory_json(json_content, discovery_dir)
    end

    private def self.fetch_remote_directory_json(discovery_dir : String, cached_file : String) : String?
      uri = URI.parse(DIRECTORY_URL)
      client = HTTP::Client.new(uri)
      client.connect_timeout = 5.seconds
      client.read_timeout = 10.seconds
      response = client.get("/discovery/v1/apis")
      if response.success?
        FileUtils.mkdir_p(discovery_dir)
        File.write(cached_file, response.body)
        response.body
      else
        nil
      end
    rescue
      nil
    end

    private def self.parse_directory_json(content : String, discovery_dir : String) : Array(DiscoveryTarget)
      targets = [] of DiscoveryTarget
      parsed = JSON.parse(content)
      items = parsed["items"]?.try(&.as_a?)
      return targets unless items

      items.each do |item|
        parse_single_directory_item(item, discovery_dir).try { |target| targets << target }
      end
      targets
    rescue
      [] of DiscoveryTarget
    end

    private def self.parse_single_directory_item(item : JSON::Any, discovery_dir : String) : DiscoveryTarget?
      name = item["name"]?.try(&.as_s?) || ""
      version = item["version"]?.try(&.as_s?) || ""
      return nil if name.empty? || version.empty?

      id = item["id"]?.try(&.as_s?) || "#{name}:#{version}"
      title = item["title"]?.try(&.as_s?) || name
      desc = item["description"]?.try(&.as_s?)
      disc_url = item["discoveryRestUrl"]?.try(&.as_s?) || ""
      preferred = item["preferred"]?.try(&.as_bool?) || false

      local_f = File.join(discovery_dir, "#{name}_#{version}.json")
      local_path = File.exists?(local_f) ? local_f : nil

      DiscoveryTarget.new(
        id: id,
        name: name,
        version: version,
        title: title,
        discovery_url: disc_url,
        description: desc,
        preferred: preferred,
        local_path: local_path
      )
    end

    # Builds a catalog merging directory targets and local discovery targets.
    def self.load(discovery_dir : String = "discovery", src_dir : String = "src/google_apis", allow_network : Bool = true) : DiscoveryCatalog
      local_targets = load_local_targets(discovery_dir)
      dir_targets = load_directory(discovery_dir, allow_network)

      target_map = Hash(String, DiscoveryTarget).new
      dir_targets.each do |directory_target|
        target_map[directory_target.id] = directory_target
      end
      local_targets.each do |local_target|
        target_map[local_target.id] = local_target
      end

      catalog = DiscoveryCatalog.new(target_map.values.sort_by!(&.name))
      catalog.detect_generated_apis(src_dir)
      catalog
    end

    # Inspects src_dir to detect generated versions.
    def detect_generated_apis(src_dir : String = "src/google_apis")
      @targets.each do |target|
        target.generated_version = nil
      end
      return unless Dir.exists?(src_dir)

      @targets.each do |target|
        api_dir = File.join(src_dir, target.name)
        if Dir.exists?(api_dir)
          Dir.children(api_dir).each do |entry|
            v_dir = File.join(api_dir, entry)
            if Dir.exists?(v_dir) && File.exists?(File.join(v_dir, "client.cr"))
              target.generated_version = entry
            end
          end
        end
      end
    end

    # Finds a target by query (id or name).
    def find_target(query : String) : DiscoveryTarget?
      query_norm = query.downcase.strip
      @targets.find { |target| target.id.downcase == query_norm } ||
        @targets.find { |target| target.name.downcase == query_norm && target.preferred? } ||
        @targets.find { |target| target.name.downcase == query_norm }
    end

    # Fetches or reads discovery JSON for a target.
    def fetch_discovery_json(target : DiscoveryTarget, discovery_dir : String = "discovery") : String
      if local = target.local_path
        if File.exists?(local)
          return File.read(local)
        end
      end

      cached_f = File.join(discovery_dir, "#{target.name}_#{target.version}.json")
      if File.exists?(cached_f)
        return File.read(cached_f)
      end

      url = target.discovery_url
      if url.empty?
        raise "No discovery URL available for #{target.id}"
      end

      response = HTTP::Client.get(url)
      unless response.success?
        raise "Failed to fetch discovery document from #{url}: HTTP #{response.status_code}"
      end

      content = response.body
      FileUtils.mkdir_p(discovery_dir)
      File.write(cached_f, content)
      content
    end
  end
end
