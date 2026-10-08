require "../spec_helper"
require "http/server"

describe GoogleApis::Client do
  it "builds URIs with path and query parameters" do
    creds = MockCredentials.new
    client = GoogleApis::Client.new(creds, "https://storage.googleapis.com/storage/v1")

    uri = client.build_uri("b", {"project" => "test-proj", "maxResults" => 100_i64})
    uri.to_s.should eq("https://storage.googleapis.com/storage/v1/b?project=test-proj&maxResults=100")
  end

  it "attaches Authorization and headers on request" do
    server = HTTP::Server.new do |context|
      context.request.headers["Authorization"]?.should eq("Bearer mock_access_token_123")
      context.request.headers["Accept"]?.should eq("application/json")
      context.request.headers["User-Agent"]?.should eq("GoogleApis-Crystal/0.1.0")
      context.response.content_type = "application/json"
      context.response.print %({"name": "test-bucket"})
    end

    address = server.bind_unused_port
    spawn { server.listen }

    begin
      creds = MockCredentials.new
      client = GoogleApis::Client.new(creds, "http://#{address.address}:#{address.port}/")

      response = client.execute_raw("GET", "b/test-bucket")
      response.status_code.should eq(200)
    ensure
      server.close
    end
  end

  it "raises HttpError on non-2xx status code and extracts error message" do
    server = HTTP::Server.new do |context|
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.content_type = "application/json"
      context.response.print <<-JSON
      {
        "error": {
          "code": 404,
          "message": "The specified bucket does not exist."
        }
      }
      JSON
    end

    address = server.bind_unused_port
    spawn { server.listen }

    begin
      creds = MockCredentials.new
      client = GoogleApis::Client.new(creds, "http://#{address.address}:#{address.port}/")

      expect_raises(GoogleApis::HttpError, /The specified bucket does not exist/) do
        client.execute_raw("GET", "b/nonexistent-bucket")
      end
    ensure
      server.close
    end
  end
end
