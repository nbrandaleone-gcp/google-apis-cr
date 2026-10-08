require "spec"
require "../src/google_apis_cr"

class MockCredentials < GoogleApis::Auth::Credentials
  getter access_token : String
  getter authorization_header : String
  getter project_id : String?
  getter quota_project_id : String?
  getter expires_at : Time?
  getter token_type : String?

  def initialize(
    @access_token : String = "mock_access_token_123",
    @project_id : String? = "mock-project-id",
    @quota_project_id : String? = "mock-project-id",
  )
    @authorization_header = "Bearer #{@access_token}"
    @expires_at = Time.utc + 3600.seconds
    @token_type = "Bearer"
  end

  def expired?(margin : Time::Span = 60.seconds) : Bool
    false
  end

  def refresh_token! : String
    @access_token
  end
end
