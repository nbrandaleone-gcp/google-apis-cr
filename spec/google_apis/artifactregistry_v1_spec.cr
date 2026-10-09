require "../spec_helper"
require "http/server"

describe GoogleApis::Artifactregistry::V1 do
  it "initializes client with credentials and exposes repositories service" do
    creds = MockCredentials.new
    client = GoogleApis::Artifactregistry::V1::Client.new(creds)
    client.client.base_url.should eq("https://artifactregistry.googleapis.com/")
    client.projects_locations_repositories.should_not be_nil
    client.projects_locations.should_not be_nil
  end

  describe "ProjectsLocationsRepositoriesService" do
    it "lists repositories and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v1/projects/test-proj/locations/us-central1/repositories")
        context.request.query_params["filter"]?.should eq("name=\"my-docker-repo\"")

        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "repositories": [
            {
              "name": "projects/test-proj/locations/us-central1/repositories/my-docker-repo",
              "format": "DOCKER",
              "mode": "STANDARD_REPOSITORY",
              "description": "My Docker repository",
              "sizeBytes": "1048576",
              "registryUri": "us-central1-docker.pkg.dev/test-proj/my-docker-repo",
              "createTime": "2026-01-01T00:00:00Z",
              "updateTime": "2026-01-02T00:00:00Z"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        client = GoogleApis::Artifactregistry::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        response = client.projects_locations_repositories.list(
          parent: "projects/test-proj/locations/us-central1",
          filter: "name=\"my-docker-repo\""
        )

        repos = response.repositories
        repos.should_not be_nil
        if repos
          repos.size.should eq(1)
          repo = repos[0]
          repo.name.should eq("projects/test-proj/locations/us-central1/repositories/my-docker-repo")
          repo.format.should eq("DOCKER")
          repo.mode.should eq("STANDARD_REPOSITORY")
          repo.description.should eq("My Docker repository")
          repo.size_bytes.should eq("1048576")
          repo.registry_uri.should eq("us-central1-docker.pkg.dev/test-proj/my-docker-repo")
        end
      ensure
        server.close
      end
    end
  end

  describe "ProjectsLocationsService" do
    it "lists locations and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/v1/projects/test-proj/locations")

        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "locations": [
            {
              "name": "projects/test-proj/locations/us-central1",
              "locationId": "us-central1",
              "displayName": "Iowa"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        client = GoogleApis::Artifactregistry::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        response = client.projects_locations.list(
          name: "projects/test-proj"
        )

        locs = response.locations
        locs.should_not be_nil
        if locs
          locs.size.should eq(1)
          loc = locs[0]
          loc.location_id.should eq("us-central1")
          loc.display_name.should eq("Iowa")
        end
      ensure
        server.close
      end
    end
  end
end
