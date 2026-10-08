require "http/client"
require "json"
require "uri"
require "./auth"
require "./error"

module GoogleApis
  # Client handles executing authenticated HTTP requests against Google APIs.
  class Client
    getter credentials : Auth::Credentials
    getter base_url : String

    def initialize(@credentials : Auth::Credentials, @base_url : String)
      # Ensure base_url ends with a slash if not empty
      @base_url = "#{@base_url}/" unless @base_url.ends_with?('/')
    end

    # Executes an HTTP request and deserializes the JSON response into type T.
    def execute(
      type : T.class,
      http_method : String,
      path : String,
      params : Hash(String, String | Array(String) | Int32 | Int64 | Bool | Nil)? = nil,
      body : String? = nil,
      headers : HTTP::Headers? = nil,
    ) : T forall T
      response = execute_raw(http_method, path, params, body, headers)
      T.from_json(response.body)
    end

    # Executes an HTTP request and returns the raw HTTP::Client::Response.
    def execute_raw(
      http_method : String,
      path : String,
      params : Hash(String, String | Array(String) | Int32 | Int64 | Bool | Nil)? = nil,
      body : String? = nil,
      headers : HTTP::Headers? = nil,
    ) : HTTP::Client::Response
      full_uri = build_uri(path, params)

      req_headers = headers ? headers.dup : HTTP::Headers.new
      req_headers["Authorization"] = @credentials.authorization_header
      req_headers["Accept"] = "application/json"
      req_headers["User-Agent"] = "GoogleApis-Crystal/0.1.0"

      if body && !req_headers.has_key?("Content-Type")
        req_headers["Content-Type"] = "application/json"
      end

      response = HTTP::Client.exec(
        method: http_method.upcase,
        url: full_uri.to_s,
        headers: req_headers,
        body: body
      )

      unless response.success?
        raise HttpError.from_response(response.status_code, response.body)
      end

      response
    end

    # Resolves a relative path against base_url and appends query parameters.
    def build_uri(path : String, params : Hash(String, String | Array(String) | Int32 | Int64 | Bool | Nil)? = nil) : URI
      clean_path = path.starts_with?('/') ? path[1..] : path
      combined = "#{@base_url}#{clean_path}"
      uri = URI.parse(combined)

      if params && !params.empty?
        query_params = URI::Params.build do |form|
          # Preserve existing query parameters if any
          if existing_query = uri.query
            URI::Params.parse(existing_query) do |key, value|
              form.add(key, value)
            end
          end

          params.each do |key, val|
            case val
            when Nil
              # skip nil params
            when Array
              val.each { |item| form.add(key, item.to_s) }
            else
              form.add(key, val.to_s)
            end
          end
        end
        uri.query = query_params.to_s
      end

      uri
    end
  end
end
