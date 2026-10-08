require "../spec_helper"
require "http/server"

describe GoogleApis::Auth do
  describe ".from_json" do
    it "raises InvalidCredentialsError on invalid JSON" do
      expect_raises(GoogleApis::Auth::InvalidCredentialsError, /Invalid JSON/) do
        GoogleApis::Auth.from_json("not valid json")
      end
    end

    it "raises InvalidCredentialsError when type is missing" do
      expect_raises(GoogleApis::Auth::InvalidCredentialsError, /Missing 'type'/) do
        GoogleApis::Auth.from_json(%({"client_id": "test"}))
      end
    end

    it "raises UnsupportedCredentialsTypeError when type is unknown" do
      expect_raises(GoogleApis::Auth::UnsupportedCredentialsTypeError, /Unsupported credentials type: 'compute_engine'/) do
        GoogleApis::Auth.from_json(%({"type": "compute_engine"}))
      end
    end
  end

  describe GoogleApis::Auth::AuthorizedUserCredentials do
    it "parses valid authorized_user credentials" do
      json = <<-JSON
      {
        "type": "authorized_user",
        "client_id": "mock_client_id.apps.googleusercontent.com",
        "client_secret": "mock_secret",
        "refresh_token": "mock_refresh_token",
        "quota_project_id": "test-project-123"
      }
      JSON

      creds = GoogleApis::Auth.from_json(json).as(GoogleApis::Auth::AuthorizedUserCredentials)
      creds.client_id.should eq("mock_client_id.apps.googleusercontent.com")
      creds.client_secret.should eq("mock_secret")
      creds.refresh_token.should eq("mock_refresh_token")
      creds.quota_project_id.should eq("test-project-123")
      creds.project_id.should eq("test-project-123")
    end

    it "raises InvalidCredentialsError when required fields are missing" do
      json = <<-JSON
      {
        "type": "authorized_user",
        "client_id": "mock_client_id"
      }
      JSON

      expect_raises(GoogleApis::Auth::InvalidCredentialsError, /missing required fields/) do
        GoogleApis::Auth.from_json(json)
      end
    end

    it "redacts secret values in inspect and to_s" do
      creds = GoogleApis::Auth::AuthorizedUserCredentials.new(
        client_id: "test-client",
        client_secret: "super-secret-key",
        refresh_token: "refresh-token-secret",
        quota_project_id: "my-project"
      )

      creds.inspect.should_not contain("super-secret-key")
      creds.inspect.should_not contain("refresh-token-secret")
      creds.to_s.should_not contain("super-secret-key")
      creds.to_s.should_not contain("refresh-token-secret")
    end

    it "checks expired? correctly based on margin" do
      creds = GoogleApis::Auth::AuthorizedUserCredentials.new(
        client_id: "cid",
        client_secret: "csec",
        refresh_token: "rt"
      )
      # No token yet -> expired
      creds.expired?.should be_true

      # Token expiring in 30 seconds (< 60s remaining) -> expired
      creds_soon = GoogleApis::Auth::AuthorizedUserCredentials.new(
        client_id: "cid",
        client_secret: "csec",
        refresh_token: "rt",
        access_token: "tok",
        expires_at: Time.utc + 30.seconds
      )
      creds_soon.expired?.should be_true

      # Token expiring in 300 seconds (> 60s remaining) -> valid
      creds_valid = GoogleApis::Auth::AuthorizedUserCredentials.new(
        client_id: "cid",
        client_secret: "csec",
        refresh_token: "rt",
        access_token: "tok",
        expires_at: Time.utc + 300.seconds
      )
      creds_valid.expired?.should be_false
    end

    it "refreshes token via mock HTTP server and caches access token" do
      request_count = 0
      captured_body = ""
      captured_content_type = ""

      server = HTTP::Server.new do |context|
        request_count += 1
        captured_content_type = context.request.headers["Content-Type"]? || ""
        captured_body = context.request.body.try(&.gets_to_end) || ""

        context.response.content_type = "application/json"
        context.response.print %({"access_token": "ya29.mock_token_123", "expires_in": 3600, "token_type": "Bearer"})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        token_uri = "http://#{address.address}:#{address.port}/token"
        creds = GoogleApis::Auth::AuthorizedUserCredentials.new(
          client_id: "mock_client",
          client_secret: "mock_secret",
          refresh_token: "mock_refresh",
          quota_project_id: "mock-proj",
          token_uri: token_uri
        )

        creds.expired?.should be_true

        token = creds.access_token
        token.should eq("ya29.mock_token_123")
        creds.authorization_header.should eq("Bearer ya29.mock_token_123")
        creds.token_type.should eq("Bearer")
        creds.expires_at.should_not be_nil
        creds.expired?.should be_false
        request_count.should eq(1)

        captured_content_type.should eq("application/x-www-form-urlencoded")
        captured_body.should contain("client_id=mock_client")
        captured_body.should contain("client_secret=mock_secret")
        captured_body.should contain("refresh_token=mock_refresh")
        captured_body.should contain("grant_type=refresh_token")

        # Second call should use cached token without hitting server
        token2 = creds.access_token
        token2.should eq("ya29.mock_token_123")
        request_count.should eq(1)
      ensure
        server.close
      end
    end

    it "handles token refresh error from server" do
      server = HTTP::Server.new do |context|
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.content_type = "application/json"
        context.response.print %({"error": "invalid_grant", "error_description": "Token has been revoked."})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        token_uri = "http://#{address.address}:#{address.port}/token"
        creds = GoogleApis::Auth::AuthorizedUserCredentials.new(
          client_id: "cid",
          client_secret: "csec",
          refresh_token: "rt",
          token_uri: token_uri
        )

        expect_raises(GoogleApis::Auth::TokenRefreshError, /Failed to refresh token: HTTP 400/) do
          creds.access_token
        end
      ensure
        server.close
      end
    end
  end

  describe GoogleApis::Auth::ServiceAccountCredentials do
    it "parses service_account credentials and raises on access_token" do
      json = <<-JSON
      {
        "type": "service_account",
        "project_id": "sa-project-456",
        "private_key_id": "key123",
        "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIE...\\n-----END PRIVATE KEY-----\\n",
        "client_email": "sa@sa-project-456.iam.gserviceaccount.com",
        "client_id": "123456789"
      }
      JSON

      creds = GoogleApis::Auth.from_json(json).as(GoogleApis::Auth::ServiceAccountCredentials)
      creds.project_id.should eq("sa-project-456")
      creds.client_email.should eq("sa@sa-project-456.iam.gserviceaccount.com")
      creds.quota_project_id.should be_nil
      creds.expired?.should be_true

      expect_raises(GoogleApis::Auth::UnsupportedCredentialsTypeError, /service_account credentials require RS256 JWT signing/) do
        creds.access_token
      end

      expect_raises(GoogleApis::Auth::UnsupportedCredentialsTypeError) do
        creds.authorization_header
      end
    end
  end

  describe ".default_credentials" do
    it "loads from an explicit valid file path" do
      tempfile = File.tempfile("creds", ".json")
      begin
        tempfile.print <<-JSON
        {
          "type": "authorized_user",
          "client_id": "file_cid",
          "client_secret": "file_csec",
          "refresh_token": "file_rt",
          "quota_project_id": "file_proj"
        }
        JSON
        tempfile.flush

        creds = GoogleApis::Auth.default_credentials(tempfile.path)
        creds.should be_a(GoogleApis::Auth::AuthorizedUserCredentials)
        creds.project_id.should eq("file_proj")
      ensure
        tempfile.delete
      end
    end

    it "raises CredentialsNotFoundError when explicit file does not exist" do
      expect_raises(GoogleApis::Auth::CredentialsNotFoundError, /Could not find Application Default Credentials/) do
        GoogleApis::Auth.default_credentials("/non/existent/path/credentials.json")
      end
    end

    it "loads live default credentials on this system" do
      path = GoogleApis::Auth.default_credentials_path
      if path && File.exists?(path)
        creds = GoogleApis::Auth.default_credentials
        creds.project_id.should_not be_nil

        # Fetch live access token
        token = creds.access_token
        token.empty?.should be_false
        token.starts_with?("ya29.").should be_true

        creds.authorization_header.starts_with?("Bearer ya29.").should be_true
        creds.expires_at.should_not be_nil
        creds.expired?.should be_false
      end
    end
  end
end
