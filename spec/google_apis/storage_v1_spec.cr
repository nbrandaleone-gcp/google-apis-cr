require "../spec_helper"
require "http/server"

describe GoogleApis::Storage::V1 do
  describe "BucketsService" do
    it "lists buckets and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/b")
        context.request.query_params["project"]?.should eq("my-test-proj")
        context.request.query_params["maxResults"]?.should eq("50")

        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "kind": "storage#buckets",
          "items": [
            {
              "id": "nbrandaleone-bucket",
              "name": "nbrandaleone-bucket",
              "location": "US-EAST4",
              "storageClass": "STANDARD"
            },
            {
              "id": "nbrandaleone-testing",
              "name": "nbrandaleone-testing",
              "location": "US-CENTRAL1",
              "storageClass": "STANDARD"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        storage = GoogleApis::Storage::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        buckets_result = storage.buckets.list(project: "my-test-proj", max_results: 50_i64)
        buckets_result.kind.should eq("storage#buckets")

        items = buckets_result.items
        items.should_not be_nil
        if items
          items.size.should eq(2)
          items[0].name.should eq("nbrandaleone-bucket")
          items[0].location.should eq("US-EAST4")
          items[1].name.should eq("nbrandaleone-testing")
          items[1].location.should eq("US-CENTRAL1")
        end
      ensure
        server.close
      end
    end

    it "gets a specific bucket" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/b/nbrandaleone-bucket")
        context.response.content_type = "application/json"
        context.response.print %({"name": "nbrandaleone-bucket", "location": "US-EAST4"})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        storage = GoogleApis::Storage::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        bucket = storage.buckets.get(bucket: "nbrandaleone-bucket")
        bucket.name.should eq("nbrandaleone-bucket")
        bucket.location.should eq("US-EAST4")
      ensure
        server.close
      end
    end
  end

  describe "ObjectsService" do
    it "lists objects and deserializes response" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/b/my-bucket/o")
        context.request.query_params["prefix"]?.should eq("photos/")

        context.response.content_type = "application/json"
        context.response.print <<-JSON
        {
          "kind": "storage#objects",
          "items": [
            {
              "name": "photos/dog.png",
              "bucket": "my-bucket",
              "size": "1048576",
              "contentType": "image/png"
            }
          ]
        }
        JSON
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        storage = GoogleApis::Storage::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        objects_result = storage.objects.list(bucket: "my-bucket", prefix: "photos/")
        objects_result.kind.should eq("storage#objects")

        items = objects_result.items
        items.should_not be_nil
        if items
          items.size.should eq(1)
          items[0].name.should eq("photos/dog.png")
          items[0].bucket.should eq("my-bucket")
          items[0].size.should eq("1048576")
          items[0].content_type.should eq("image/png")
        end
      ensure
        server.close
      end
    end

    it "gets a specific object with URI-encoded segments" do
      server = HTTP::Server.new do |context|
        context.request.path.should eq("/b/my-bucket/o/sub%2Fmy%20file.txt")
        context.response.content_type = "application/json"
        context.response.print %({"name": "sub/my file.txt", "size": "42"})
      end

      address = server.bind_unused_port
      spawn { server.listen }

      begin
        creds = MockCredentials.new
        storage = GoogleApis::Storage::V1::Client.new(creds, "http://#{address.address}:#{address.port}/")

        obj = storage.objects.get(bucket: "my-bucket", object: "sub/my file.txt")
        obj.name.should eq("sub/my file.txt")
        obj.size.should eq("42")
      ensure
        server.close
      end
    end
  end
end
