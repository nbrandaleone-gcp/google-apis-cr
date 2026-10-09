require "../spec_helper"
require "file_utils"

describe GoogleApis::ApiListRegistry do
  it "loads and parses api-list.yaml" do
    registry = GoogleApis::ApiListRegistry.load("api-list.yaml")
    registry.apis.should_not be_empty

    storage_entry = registry.apis["storage"]?
    storage_entry.should_not be_nil
    if storage_entry
      storage_entry.title.should eq("Cloud Storage JSON API")
      storage_entry.latest_version.should eq("v1")
      storage_entry.generated_version.should eq("v1")
      storage_entry.status.should eq("up_to_date")
      storage_entry.up_to_date?.should be_true
      storage_entry.out_of_date?.should be_false
    end
  end

  it "detects out-of-date APIs" do
    sample_yaml = <<-YAML
    last_updated: "2026-10-09 12:00:00 UTC"
    apis:
      storage:
        title: "Cloud Storage"
        latest_version: "v2"
        generated_version: "v1"
        status: "out_of_date"
        discovery_url: "https://storage.googleapis.com"
      run:
        title: "Cloud Run"
        latest_version: "v2"
        generated_version: "v2"
        status: "up_to_date"
        discovery_url: "https://run.googleapis.com"
    YAML

    reg = GoogleApis::ApiListRegistry.from_yaml(sample_yaml)
    outdated = reg.out_of_date_apis
    outdated.size.should eq(1)
    outdated.first[0].should eq("storage")
    outdated.first[1].latest_version.should eq("v2")
    outdated.first[1].generated_version.should eq("v1")
  end

  it "saves registry to YAML file" do
    temp_yaml = "scratch_test_api_list.yaml"
    begin
      reg = GoogleApis::ApiListRegistry.new
      reg.apis["custom"] = GoogleApis::ApiEntry.new(
        title: "Custom API",
        latest_version: "v1",
        generated_version: "v1",
        status: "up_to_date",
        discovery_url: "https://example.com"
      )
      reg.save(temp_yaml)

      File.exists?(temp_yaml).should be_true
      loaded = GoogleApis::ApiListRegistry.load(temp_yaml)
      loaded.apis.has_key?("custom").should be_true
      loaded.apis["custom"].title.should eq("Custom API")
    ensure
      FileUtils.rm_f(temp_yaml)
    end
  end
end
