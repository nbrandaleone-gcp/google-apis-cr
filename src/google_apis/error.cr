require "json"

module GoogleApis
  # Base error class for all Google API client errors.
  class Error < Exception
  end

  # Error raised when an HTTP request to Google API returns a non-2xx status code.
  class HttpError < Error
    getter status_code : Int32
    getter body : String

    def initialize(@status_code : Int32, @body : String, message : String? = nil)
      msg = message || "Google API request failed with status #{status_code}: #{body}"
      super(msg)
    end

    # Tries to extract the error message from Google API error JSON format.
    def self.from_response(status_code : Int32, body : String) : HttpError
      parsed_message = nil
      begin
        parsed = JSON.parse(body)
        parsed_message = parsed["error"]?.try(&.["message"]?).try(&.as_s?)
      rescue
        # ignore parse errors
      end

      msg = if parsed_message
              "Google API error (#{status_code}): #{parsed_message}"
            else
              "Google API error (#{status_code}): #{body}"
            end

      new(status_code, body, msg)
    end
  end
end
