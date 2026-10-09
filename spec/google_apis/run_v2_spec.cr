require "../spec_helper"
require "http/server"

describe GoogleApis::Run::V2 do
  describe "ProjectsLocationsServicesService" do
    it "lists services and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v2/projects/test-project/locations/-/services")
        context.request.query_params["pageSize"]?.should eq("10")

        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "services": [
            {
              "name": "projects/test-project/locations/us-east5/services/mandelbrot",
              "uid": "12345-67890",
              "uri": "https://mandelbrot-test.a.run.app",
              "creator": "user@example.com",
              "terminalCondition": {
                "type": "Ready",
                "state": "CONDITION_SUCCEEDED"
              },
              "template": {
                "containers": [
                  {
                    "name": "mandelbrot-1",
                    "image": "gcr.io/test-project/mandelbrot:latest"
                  }
                ]
              }
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        run_client = GoogleApis::Run::V2::Client.new(creds, "http://#{address.address}:#{address.port}/")

        response = run_client.projects_locations_services.list(
          parent: "projects/test-project/locations/-",
          page_size: 10_i64
        )

        services = response.services
        services.should_not be_nil
        if services
          services.size.should eq(1)
          svc = services[0]
          svc.name.should eq("projects/test-project/locations/us-east5/services/mandelbrot")
          svc.uri.should eq("https://mandelbrot-test.a.run.app")
          svc.creator.should eq("user@example.com")
          cond = svc.terminal_condition
          cond.should_not be_nil
          if cond
            cond.type_param.should eq("Ready")
            cond.state.should eq("CONDITION_SUCCEEDED")
          end
        end
      ensure
        server.close
      end
    end

    it "gets a specific service" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v2/projects/test-project/locations/us-east5/services/mandelbrot")
        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "name": "projects/test-project/locations/us-east5/services/mandelbrot",
          "uri": "https://mandelbrot-test.a.run.app"
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        run_client = GoogleApis::Run::V2::Client.new(creds, "http://#{address.address}:#{address.port}/")

        service = run_client.projects_locations_services.get(
          name: "projects/test-project/locations/us-east5/services/mandelbrot"
        )
        service.name.should eq("projects/test-project/locations/us-east5/services/mandelbrot")
        service.uri.should eq("https://mandelbrot-test.a.run.app")
      ensure
        server.close
      end
    end
  end

  describe "ProjectsLocationsInstancesService" do
    it "lists instances and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v2/projects/test-project/locations/us-east5/instances")
        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "instances": [
            {
              "name": "projects/test-project/locations/us-east5/instances/inst-1",
              "creator": "user@example.com"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        run_client = GoogleApis::Run::V2::Client.new(creds, "http://#{address.address}:#{address.port}/")

        response = run_client.projects_locations_instances.list(
          parent: "projects/test-project/locations/us-east5"
        )
        instances = response.instances
        instances.should_not be_nil
        if instances
          instances.size.should eq(1)
          instances[0].name.should eq("projects/test-project/locations/us-east5/instances/inst-1")
          instances[0].creator.should eq("user@example.com")
        end
      ensure
        server.close
      end
    end
  end

  describe "ProjectsLocationsServicesRevisionsService" do
    it "lists revisions" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v2/projects/test-project/locations/us-east5/services/mandelbrot/revisions")
        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "revisions": [
            {
              "name": "projects/test-project/locations/us-east5/services/mandelbrot/revisions/mandelbrot-00001",
              "service": "mandelbrot"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        run_client = GoogleApis::Run::V2::Client.new(creds, "http://#{address.address}:#{address.port}/")

        response = run_client.projects_locations_services_revisions.list(
          parent: "projects/test-project/locations/us-east5/services/mandelbrot"
        )
        revisions = response.revisions
        revisions.should_not be_nil
        if revisions
          revisions.size.should eq(1)
          revisions[0].service.should eq("mandelbrot")
        end
      ensure
        server.close
      end
    end
  end
end
