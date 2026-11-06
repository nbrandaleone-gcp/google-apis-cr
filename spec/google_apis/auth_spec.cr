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
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    private_pem = rsa_key.to_pem
    public_pem = rsa_key.public_key.to_pem

    it "parses valid service_account credentials with all metadata fields" do
      json = {
        "type"                        => "service_account",
        "project_id"                  => "sa-project-456",
        "private_key_id"              => "key123",
        "private_key"                 => private_pem,
        "client_email"                => "sa@sa-project-456.iam.gserviceaccount.com",
        "client_id"                   => "123456789",
        "auth_uri"                    => "https://accounts.google.com/o/oauth2/auth",
        "token_uri"                   => "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url"        => "https://www.googleapis.com/robot/v1/metadata/x509/sa",
        "universe_domain"             => "googleapis.com",
      }.to_json

      creds = GoogleApis::Auth.from_json(json).as(GoogleApis::Auth::ServiceAccountCredentials)
      creds.project_id.should eq("sa-project-456")
      creds.client_email.should eq("sa@sa-project-456.iam.gserviceaccount.com")
      creds.private_key_id.should eq("key123")
      creds.private_key.should eq(private_pem)
      creds.client_id.should eq("123456789")
      creds.auth_uri.should eq("https://accounts.google.com/o/oauth2/auth")
      creds.token_uri.should eq("https://oauth2.googleapis.com/token")
      creds.auth_provider_x509_cert_url.should eq("https://www.googleapis.com/oauth2/v1/certs")
      creds.client_x509_cert_url.should eq("https://www.googleapis.com/robot/v1/metadata/x509/sa")
      creds.universe_domain.should eq("googleapis.com")
      creds.scope.should eq("https://www.googleapis.com/auth/cloud-platform")
      creds.quota_project_id.should be_nil
      creds.expired?.should be_true
    end

    it "supports custom scopes as String or Array(String)" do
      json = {
        "type"         => "service_account",
        "private_key"  => private_pem,
        "client_email" => "sa@sa-project-456.iam.gserviceaccount.com",
      }.to_json

      creds = GoogleApis::Auth.from_json(
        json,
        scope: ["https://www.googleapis.com/auth/devstorage.read_only", "https://www.googleapis.com/auth/cloud-platform"]
      ).as(GoogleApis::Auth::ServiceAccountCredentials)

      creds.scope.should eq("https://www.googleapis.com/auth/devstorage.read_only https://www.googleapis.com/auth/cloud-platform")
    end

    it "raises InvalidCredentialsError when required fields are missing" do
      missing_key_json = %({"type": "service_account", "client_email": "sa@example.com"})
      expect_raises(GoogleApis::Auth::InvalidCredentialsError, /missing required fields/) do
        GoogleApis::Auth.from_json(missing_key_json)
      end

      missing_email_json = %({"type": "service_account", "private_key": "-----BEGIN PRIVATE KEY-----"})
      expect_raises(GoogleApis::Auth::InvalidCredentialsError, /missing required fields/) do
        GoogleApis::Auth.from_json(missing_email_json)
      end
    end

    it "redacts private_key in inspect and to_s" do
      creds = GoogleApis::Auth::ServiceAccountCredentials.new(
        client_email: "sa@example.com",
        private_key: private_pem,
        project_id: "my-sa-project",
        private_key_id: "kid-999"
      )

      creds.inspect.should_not contain("BEGIN")
      creds.inspect.should_not contain(private_pem)
      creds.to_s.should_not contain("BEGIN")
      creds.inspect.should contain("sa@example.com")
    end

    it "generates a valid RS256 signed JWT assertion" do
      creds = GoogleApis::Auth::ServiceAccountCredentials.new(
        client_email: "sa@sa-project-456.iam.gserviceaccount.com",
        private_key: private_pem,
        private_key_id: "key123",
        token_uri: "https://oauth2.googleapis.com/token",
        scope: "https://www.googleapis.com/auth/devstorage.read_write"
      )

      fixed_time = Time.utc(2026, 11, 6, 12, 0, 0)
      jwt_token = creds.generate_jwt(now: fixed_time, lifetime: 1.hour)

      payload, header = JWT.decode(jwt_token, public_pem, JWT::Algorithm::RS256, validate: false)
      header["alg"].as_s.should eq("RS256")
      header["typ"].as_s.should eq("JWT")
      header["kid"].as_s.should eq("key123")

      payload["iss"].as_s.should eq("sa@sa-project-456.iam.gserviceaccount.com")
      payload["scope"].as_s.should eq("https://www.googleapis.com/auth/devstorage.read_write")
      payload["aud"].as_s.should eq("https://oauth2.googleapis.com/token")
      payload["iat"].as_i64.should eq(fixed_time.to_unix)
      payload["exp"].as_i64.should eq((fixed_time + 1.hour).to_unix)
    end

    it "exchanges signed JWT assertion for access token via mock HTTP server and caches it" do
      request_count = 0
      captured_content_type = ""
      captured_grant_type = ""
      captured_assertion = ""

      server = HTTP::Server.new do |context|
        request_count += 1
        captured_content_type = context.request.headers["Content-Type"]? || ""
        raw_body = context.request.body.try(&.gets_to_end) || ""
        params = URI::Params.parse(raw_body)
        captured_grant_type = params["grant_type"]? || ""
        captured_assertion = params["assertion"]? || ""

        context.response.content_type = "application/json"
        context.response.print %({"access_token": "ya29.sa_mock_token_456", "expires_in": 3600, "token_type": "Bearer"})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        token_uri = "http://#{address.address}:#{address.port}/token"
        creds = GoogleApis::Auth::ServiceAccountCredentials.new(
          client_email: "sa@sa-project-456.iam.gserviceaccount.com",
          private_key: private_pem,
          project_id: "sa-project-456",
          private_key_id: "key123",
          token_uri: token_uri,
          scope: "https://www.googleapis.com/auth/cloud-platform"
        )

        creds.expired?.should be_true

        token = creds.access_token
        token.should eq("ya29.sa_mock_token_456")
        creds.authorization_header.should eq("Bearer ya29.sa_mock_token_456")
        creds.token_type.should eq("Bearer")
        creds.expires_at.should_not be_nil
        creds.expired?.should be_false
        request_count.should eq(1)

        captured_content_type.should eq("application/x-www-form-urlencoded")
        captured_grant_type.should eq("urn:ietf:params:oauth:grant-type:jwt-bearer")
        captured_assertion.empty?.should be_false

        # Verify the assertion sent to the server is a valid RS256 JWT signed by our RSA key
        payload, header = JWT.decode(captured_assertion, public_pem, JWT::Algorithm::RS256)
        header["alg"].as_s.should eq("RS256")
        header["kid"].as_s.should eq("key123")
        payload["iss"].as_s.should eq("sa@sa-project-456.iam.gserviceaccount.com")
        payload["scope"].as_s.should eq("https://www.googleapis.com/auth/cloud-platform")
        payload["aud"].as_s.should eq(token_uri)

        # Second call should use cached token without hitting server
        token2 = creds.access_token
        token2.should eq("ya29.sa_mock_token_456")
        request_count.should eq(1)
      ensure
        server.close
      end
    end

    it "raises TokenRefreshError when private key is invalid PEM" do
      creds = GoogleApis::Auth::ServiceAccountCredentials.new(
        client_email: "sa@sa-project-456.iam.gserviceaccount.com",
        private_key: "not-a-valid-pem-key"
      )

      expect_raises(GoogleApis::Auth::TokenRefreshError, /Failed to sign service account JWT/) do
        creds.access_token
      end
    end

    it "raises TokenRefreshError when server returns an HTTP error" do
      server = HTTP::Server.new do |context|
        context.response.status = HTTP::Status::BAD_REQUEST
        context.response.content_type = "application/json"
        context.response.print %({"error": "invalid_grant", "error_description": "Invalid JWT Signature."})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        token_uri = "http://#{address.address}:#{address.port}/token"
        creds = GoogleApis::Auth::ServiceAccountCredentials.new(
          client_email: "sa@sa-project-456.iam.gserviceaccount.com",
          private_key: private_pem,
          token_uri: token_uri
        )

        expect_raises(GoogleApis::Auth::TokenRefreshError, /Failed to refresh service account token: HTTP 400/) do
          creds.access_token
        end
      ensure
        server.close
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
