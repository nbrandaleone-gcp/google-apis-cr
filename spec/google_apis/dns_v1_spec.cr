require "../spec_helper"
require "../../src/google_apis/dns/v1/v1"

describe GoogleApis::Dns::V1 do
  it "initializes dns client with credentials" do
    creds = MockCredentials.new
    client = GoogleApis::Dns::V1::Client.new(creds)
    client.client.base_url.should eq("https://dns.googleapis.com/")
  end

  it "exposes changes service" do
    creds = MockCredentials.new
    client = GoogleApis::Dns::V1::Client.new(creds)
    client.changes.should_not be_nil
  end
end
