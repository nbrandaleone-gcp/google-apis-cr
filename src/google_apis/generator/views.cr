require "ecr"
require "./models"

module GoogleApis
  module Generator
    # Renders types / schemas.
    class TypesView
      def initialize(@service : ServiceModel)
      end

      ECR.def_to_s "#{__DIR__}/templates/types.cr.ecr"
    end

    # Renders a resource service (e.g. BucketsService, ObjectsService).
    class ResourceServiceView
      def initialize(@service : ServiceModel, @resource : ResourceModel)
      end

      ECR.def_to_s "#{__DIR__}/templates/resource_service.cr.ecr"
    end

    # Renders the high-level API Client.
    class ClientView
      def initialize(@service : ServiceModel)
      end

      ECR.def_to_s "#{__DIR__}/templates/client.cr.ecr"
    end

    # Renders the top-level service module (e.g. v1.cr).
    class ServiceModuleView
      def initialize(@service : ServiceModel)
      end

      ECR.def_to_s "#{__DIR__}/templates/service_module.cr.ecr"
    end
  end
end
