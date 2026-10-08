require "http/client"
require "json"

module GoogleApis
  module Auth
    # Base error class for all authentication-related errors.
    class Error < Exception
    end

    # Raised when credentials file cannot be found.
    class CredentialsNotFoundError < Error
    end

    # Raised when credentials format or content is invalid.
    class InvalidCredentialsError < Error
    end

    # Raised when the credentials type is unsupported.
    class UnsupportedCredentialsTypeError < Error
    end

    # Raised when token refresh fails.
    class TokenRefreshError < Error
    end

    # Abstract base class representing Google credentials.
    abstract class Credentials
      # Returns a valid access token, refreshing if necessary.
      abstract def access_token : String

      # Returns the HTTP Authorization header string, e.g. "Bearer <token>".
      abstract def authorization_header : String

      # Returns the Google Cloud project ID associated with the credentials, if available.
      abstract def project_id : String?

      # Returns the quota project ID associated with the credentials, if available.
      abstract def quota_project_id : String?

      # Checks whether the access token is expired or within the expiration margin.
      abstract def expired?(margin : Time::Span = 60.seconds) : Bool

      # Forces a token refresh and returns the new access token.
      abstract def refresh_token! : String

      # Expiration timestamp for the current access token.
      abstract def expires_at : Time?

      # Token type, typically "Bearer".
      abstract def token_type : String?

      # Convenience alias for `refresh_token!`.
      def refresh! : String
        refresh_token!
      end
    end

    # Authorized user credentials obtained from `gcloud auth application-default login`.
    class AuthorizedUserCredentials < Credentials
      DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token"

      getter client_id : String
      getter client_secret : String
      getter refresh_token : String
      getter quota_project_id : String?
      getter account : String?
      getter universe_domain : String?
      getter token_uri : String

      getter expires_at : Time?
      getter token_type : String?
      getter scope : String?

      @access_token : String?
      @mutex = Mutex.new

      def initialize(
        @client_id : String,
        @client_secret : String,
        @refresh_token : String,
        @quota_project_id : String? = nil,
        @project_id : String? = nil,
        @account : String? = nil,
        @universe_domain : String? = nil,
        @token_uri : String = DEFAULT_TOKEN_URI,
        @access_token : String? = nil,
        @expires_at : Time? = nil,
        @token_type : String? = "Bearer",
        @scope : String? = nil,
      )
      end

      # Creates AuthorizedUserCredentials from a JSON string.
      def self.from_json(json_str : String, token_uri : String = DEFAULT_TOKEN_URI) : AuthorizedUserCredentials
        parser = JSON.parse(json_str)
        from_json_any(parser, token_uri)
      end

      # Creates AuthorizedUserCredentials from a parsed JSON::Any object.
      def self.from_json_any(parser : JSON::Any, token_uri : String = DEFAULT_TOKEN_URI) : AuthorizedUserCredentials
        client_id = parser["client_id"]?.try(&.as_s?)
        client_secret = parser["client_secret"]?.try(&.as_s?)
        refresh_token = parser["refresh_token"]?.try(&.as_s?)

        if client_id.nil? || client_secret.nil? || refresh_token.nil?
          raise InvalidCredentialsError.new(
            "authorized_user credentials missing required fields (client_id, client_secret, refresh_token)"
          )
        end

        uri = parser["token_uri"]?.try(&.as_s?) || token_uri

        new(
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token,
          quota_project_id: parser["quota_project_id"]?.try(&.as_s?),
          project_id: parser["project_id"]?.try(&.as_s?),
          account: parser["account"]?.try(&.as_s?),
          universe_domain: parser["universe_domain"]?.try(&.as_s?),
          token_uri: uri
        )
      end

      # Returns quota_project_id if present, otherwise project_id.
      def project_id : String?
        @quota_project_id || @project_id
      end

      # Returns true if token is nil, expires_at is nil, or expires within `margin`.
      def expired?(margin : Time::Span = 60.seconds) : Bool
        expiry = @expires_at
        return true if expiry.nil? || @access_token.nil?

        Time.utc >= (expiry - margin)
      end

      # Returns the access token, automatically refreshing if expired or near expiry.
      def access_token : String
        @mutex.synchronize do
          refresh_token_unlocked if expired?
          @access_token || raise TokenRefreshError.new("Access token is unavailable")
        end
      end

      # Returns the Authorization HTTP header value, e.g. "Bearer <token>".
      def authorization_header : String
        "Bearer #{access_token}"
      end

      # Refreshes the access token using the refresh_token.
      def refresh_token! : String
        @mutex.synchronize do
          refresh_token_unlocked
        end
      end

      private def refresh_token_unlocked : String
        params = HTTP::Params.encode({
          "client_id"     => @client_id,
          "client_secret" => @client_secret,
          "refresh_token" => @refresh_token,
          "grant_type"    => "refresh_token",
        })

        headers = HTTP::Headers{
          "Content-Type" => "application/x-www-form-urlencoded",
        }

        response = HTTP::Client.post(@token_uri, headers: headers, body: params)

        unless response.success?
          raise TokenRefreshError.new("Failed to refresh token: HTTP #{response.status_code} - #{response.body}")
        end

        begin
          parsed = JSON.parse(response.body)
        rescue ex : JSON::ParseException
          raise TokenRefreshError.new("Failed to parse token response JSON: #{ex.message}")
        end

        token = parsed["access_token"]?.try(&.as_s?)
        unless token
          raise TokenRefreshError.new("Token response missing 'access_token': #{response.body}")
        end

        expires_in_val = parsed["expires_in"]?
        expires_in_seconds = case expires_in_val
                             when .nil?
                               3600_i64
                             else
                               expires_in_val.as_i64? || expires_in_val.as_i? || expires_in_val.as_s?.try(&.to_i64?) || 3600_i64
                             end

        @expires_at = Time.utc + expires_in_seconds.seconds
        @access_token = token
        @token_type = parsed["token_type"]?.try(&.as_s?) || "Bearer"
        @scope = parsed["scope"]?.try(&.as_s?)

        token
      end

      # Redacts secrets in inspection output.
      def inspect(io : IO) : Nil
        io << "#<" << self.class.name
        io << " client_id=" << @client_id.inspect
        io << " quota_project_id=" << @quota_project_id.inspect
        io << " project_id=" << project_id.inspect
        io << " expires_at=" << @expires_at.inspect
        io << " token_type=" << @token_type.inspect
        io << ">"
      end

      def to_s(io : IO) : Nil
        inspect(io)
      end
    end

    # Service account credentials representation.
    class ServiceAccountCredentials < Credentials
      getter project_id : String?
      getter client_email : String?
      getter private_key_id : String?
      getter private_key : String?
      getter client_id : String?
      getter auth_uri : String?
      getter token_uri : String
      getter universe_domain : String?

      def initialize(
        @project_id : String? = nil,
        @client_email : String? = nil,
        @private_key_id : String? = nil,
        @private_key : String? = nil,
        @client_id : String? = nil,
        @auth_uri : String? = nil,
        @token_uri : String = "https://oauth2.googleapis.com/token",
        @universe_domain : String? = nil,
      )
      end

      def self.from_json_any(parser : JSON::Any) : ServiceAccountCredentials
        new(
          project_id: parser["project_id"]?.try(&.as_s?),
          client_email: parser["client_email"]?.try(&.as_s?),
          private_key_id: parser["private_key_id"]?.try(&.as_s?),
          private_key: parser["private_key"]?.try(&.as_s?),
          client_id: parser["client_id"]?.try(&.as_s?),
          auth_uri: parser["auth_uri"]?.try(&.as_s?),
          token_uri: parser["token_uri"]?.try(&.as_s?) || "https://oauth2.googleapis.com/token",
          universe_domain: parser["universe_domain"]?.try(&.as_s?)
        )
      end

      def quota_project_id : String?
        nil
      end

      def access_token : String
        raise UnsupportedCredentialsTypeError.new(
          "service_account credentials require RS256 JWT signing, " \
          "which is not supported by the Crystal standard library without external dependencies"
        )
      end

      def authorization_header : String
        "Bearer #{access_token}"
      end

      def expired?(margin : Time::Span = 60.seconds) : Bool
        true
      end

      def refresh_token! : String
        access_token
      end

      def expires_at : Time?
        nil
      end

      def token_type : String?
        nil
      end

      def inspect(io : IO) : Nil
        io << "#<" << self.class.name
        io << " project_id=" << @project_id.inspect
        io << " client_email=" << @client_email.inspect
        io << ">"
      end

      def to_s(io : IO) : Nil
        inspect(io)
      end
    end

    WELL_KNOWN_CREDENTIALS_PATH = "~/.config/gcloud/application_default_credentials.json"

    # Resolves the default credentials path following Google ADC rules.
    def self.default_credentials_path : Path?
      if env_path = ENV["GOOGLE_APPLICATION_CREDENTIALS"]?
        return Path[env_path].expand(home: true) unless env_path.strip.empty?
      end

      well_known = if appdata = ENV["APPDATA"]?
                     Path[appdata] / "gcloud" / "application_default_credentials.json"
                   else
                     Path[WELL_KNOWN_CREDENTIALS_PATH].expand(home: true)
                   end

      well_known if File.exists?(well_known)
    end

    # Loads Application Default Credentials.
    # Checks GOOGLE_APPLICATION_CREDENTIALS first, then the well-known path,
    # or uses the provided explicit path.
    def self.default_credentials(path : String | Path | Nil = nil) : Credentials
      target_path = if path
                      Path[path].expand(home: true)
                    else
                      default_credentials_path
                    end

      if target_path.nil? || !File.exists?(target_path)
        searched = target_path ? target_path.to_s : default_search_locations_description
        raise CredentialsNotFoundError.new("Could not find Application Default Credentials file at #{searched}")
      end

      from_file(target_path)
    end

    # Loads credentials from a file path.
    def self.from_file(path : String | Path) : Credentials
      expanded = Path[path].expand(home: true)
      unless File.exists?(expanded)
        raise CredentialsNotFoundError.new("Credentials file not found: #{expanded}")
      end
      content = File.read(expanded)
      from_json(content)
    end

    # Parses credentials from a JSON string.
    def self.from_json(json_str : String) : Credentials
      begin
        parsed = JSON.parse(json_str)
      rescue ex : JSON::ParseException
        raise InvalidCredentialsError.new("Invalid JSON in credentials: #{ex.message}")
      end

      cred_type = parsed["type"]?.try(&.as_s?)
      unless cred_type
        raise InvalidCredentialsError.new("Missing 'type' in credentials JSON")
      end

      case cred_type
      when "authorized_user"
        AuthorizedUserCredentials.from_json_any(parsed)
      when "service_account"
        ServiceAccountCredentials.from_json_any(parsed)
      else
        raise UnsupportedCredentialsTypeError.new("Unsupported credentials type: '#{cred_type}'")
      end
    end

    private def self.default_search_locations_description : String
      parts = [] of String
      if env = ENV["GOOGLE_APPLICATION_CREDENTIALS"]?
        parts << "$GOOGLE_APPLICATION_CREDENTIALS (#{env})" unless env.strip.empty?
      end
      parts << WELL_KNOWN_CREDENTIALS_PATH
      parts.join(" or ")
    end
  end
end
