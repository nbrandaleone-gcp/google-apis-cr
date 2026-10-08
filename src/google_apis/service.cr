require "./client"

module GoogleApis
  # Base class for API services.
  class Service
    getter client : Client

    def initialize(@client : Client)
    end
  end
end
