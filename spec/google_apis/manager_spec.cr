require "../spec_helper"
require "file_utils"

describe GoogleApis::Manager do
  it "finds generated API names in src/google_apis" do
    names = GoogleApis::Manager.find_generated_api_names
    names.includes?("storage").should be_true
    names.includes?("run").should be_true
    names.includes?("generator").should be_false
    names.includes?("tui").should be_false
  end

  it "lists targets with filtering" do
    targets = GoogleApis::Manager.list_targets("storage", allow_network: false)
    targets.should_not be_empty
    targets.any? { |target| target.name == "storage" }.should be_true
  end

  it "provides complete help text" do
    help = GoogleApis::Manager.help_text
    help.includes?("Google APIs Generator & Manager Help").should be_true
    help.includes?("[G] Generate API").should be_true
    help.includes?("[D] Generate Documentation").should be_true
    help.includes?("[R] Remove API and documentation").should be_true
    help.includes?("[T] Run Unit Tests for API").should be_true
    help.includes?("[A] Run All Unit Tests").should be_true
    help.includes?("[C] Clear & Regenerate").should be_true
    help.includes?("[S] Sync api-list.yaml").should be_true
  end

  it "runs unit tests for a specific API" do
    success, output = GoogleApis::Manager.run_tests_for("storage")
    success.should be_true
    output.includes?("examples, 0 failures").should be_true
  end

  it "removes an API and its associated files including discovery JSON" do
    test_api_dir = "src/google_apis/testapi"
    test_bin_src = "src/bin/list_testapi.cr"
    test_bin = "bin/list_testapi"
    test_disc = "discovery/testapi_v1.json"
    FileUtils.mkdir_p(File.join(test_api_dir, "v1"))
    File.write(File.join(test_api_dir, "v1", "client.cr"), "# dummy client")
    FileUtils.mkdir_p("src/bin")
    File.write(test_bin_src, "# dummy script")
    FileUtils.mkdir_p("bin")
    File.write(test_bin, "# dummy binary")
    FileUtils.mkdir_p("discovery")
    File.write(test_disc, "{\"name\":\"testapi\",\"version\":\"v1\"}")

    success, msg = GoogleApis::Manager.remove_api("testapi")
    success.should be_true
    Dir.exists?(test_api_dir).should be_false
    File.exists?(test_bin_src).should be_false
    File.exists?(test_bin).should be_false
    File.exists?(test_disc).should be_false
    msg.includes?("Successfully removed testapi API").should be_true
    msg.includes?("discovery/testapi_v1.json").should be_true
  end

  it "removes documentation directory safely" do
    test_docs = "docs"
    FileUtils.mkdir_p(test_docs)
    File.write(File.join(test_docs, "test.html"), "<h1>Docs</h1>")

    success, msg = GoogleApis::Manager.remove_docs
    success.should be_true
    Dir.exists?(test_docs).should be_false
    msg.includes?("removed").should be_true
  end

  it "removes an API when queried by target ID (e.g. name:version)" do
    test_api_dir = "src/google_apis/testidapi"
    FileUtils.mkdir_p(File.join(test_api_dir, "v1"))
    File.write(File.join(test_api_dir, "v1", "client.cr"), "# dummy client")

    success, msg = GoogleApis::Manager.remove_api("testidapi:v1")
    success.should be_true
    Dir.exists?(test_api_dir).should be_false
    msg.includes?("Successfully removed testidapi API").should be_true
  end
end

describe GoogleApis::Generator do
  it "generates a README with usage instructions" do
    service = GoogleApis::Generator.parse(File.read("discovery/storage_v1.json"))
    readme = GoogleApis::Generator.generate_readme(service)
    readme.includes?("# Cloud Storage JSON API (V1)").should be_true
    readme.includes?("GoogleApis::Auth.default_credentials").should be_true
    readme.includes?("GoogleApis::Storage::V1::Client.new").should be_true
    readme.includes?("## Available Resources").should be_true
  end

  it "generates spec scaffold for a service" do
    service = GoogleApis::Generator.parse(File.read("discovery/storage_v1.json"))
    temp_dir = "scratch_test_spec_dir"
    begin
      spec_path = GoogleApis::Generator.generate_spec(service, temp_dir)
      File.exists?(spec_path).should be_true
      content = File.read(spec_path)
      content.includes?("describe GoogleApis::Storage::V1").should be_true
      content.includes?("MockCredentials.new").should be_true
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end
end
