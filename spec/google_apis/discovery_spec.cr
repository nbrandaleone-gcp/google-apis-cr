require "../spec_helper"

describe GoogleApis::DiscoveryTarget do
  it "calculates up_to_date? and out_of_date? correctly" do
    t1 = GoogleApis::DiscoveryTarget.new(
      id: "storage:v1",
      name: "storage",
      version: "v1",
      title: "Cloud Storage",
      discovery_url: "https://storage.googleapis.com/$discovery/rest?version=v1",
      generated_version: "v1"
    )
    t1.generated?.should be_true
    t1.up_to_date?.should be_true
    t1.out_of_date?.should be_false
    t1.status_label.should eq("[UP TO DATE]")

    t2 = GoogleApis::DiscoveryTarget.new(
      id: "run:v2",
      name: "run",
      version: "v2",
      title: "Cloud Run",
      discovery_url: "https://run.googleapis.com/$discovery/rest?version=v2",
      generated_version: "v1"
    )
    t2.generated?.should be_true
    t2.up_to_date?.should be_false
    t2.out_of_date?.should be_true
    t2.status_label.should eq("[OUTDATED: current v1 -> latest v2]")

    t3 = GoogleApis::DiscoveryTarget.new(
      id: "youtube:v3",
      name: "youtube",
      version: "v3",
      title: "YouTube",
      discovery_url: "https://youtube.googleapis.com/$discovery/rest?version=v3",
      generated_version: nil
    )
    t3.generated?.should be_false
    t3.up_to_date?.should be_false
    t3.out_of_date?.should be_false
    t3.status_label.should eq("[AVAILABLE]")
  end
end

describe GoogleApis::DiscoveryCatalog do
  it "loads local targets from discovery directory" do
    targets = GoogleApis::DiscoveryCatalog.load_local_targets("discovery")
    targets.should_not be_empty

    storage_target = targets.find { |target| target.name == "storage" }
    storage_target.should_not be_nil
    if storage_target
      storage_target.version.should eq("v1")
      storage_target.title.should eq("Cloud Storage JSON API")
    end

    run_target = targets.find { |target| target.name == "run" }
    run_target.should_not be_nil
    if run_target
      run_target.version.should eq("v2")
      run_target.title.should eq("Cloud Run Admin API")
    end
  end

  it "finds targets by query string" do
    cat = GoogleApis::DiscoveryCatalog.load("discovery", "src/google_apis", allow_network: false)

    t1 = cat.find_target("storage:v1")
    t1.should_not be_nil
    t1.try(&.name).should eq("storage")

    t2 = cat.find_target("run")
    t2.should_not be_nil
    t2.try(&.version).should eq("v2")
  end

  it "detects generated APIs in src/google_apis" do
    cat = GoogleApis::DiscoveryCatalog.load("discovery", "src/google_apis", allow_network: false)
    storage = cat.find_target("storage")
    storage.should_not be_nil
    storage.try(&.generated?).should be_true
    storage.try(&.generated_version).should eq("v1")

    run = cat.find_target("run")
    run.should_not be_nil
    run.try(&.generated?).should be_true
    run.try(&.generated_version).should eq("v2")
  end
end
