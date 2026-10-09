require "../spec_helper"
require "../../src/google_apis/generator"

describe GoogleApis::Generator do
  it "maps types properly" do
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"type": "string"}))).should eq("String")
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"type": "integer"}))).should eq("Int64")
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"type": "boolean"}))).should eq("Bool")
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"$ref": "Bucket"}))).should eq("Bucket")
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"type": "array", "items": {"$ref": "Bucket"}}))).should eq("Array(Bucket)")
    GoogleApis::Generator.crystal_type_for(JSON.parse(%({"type": "object", "additionalProperties": {"type": "string"}}))).should eq("::Hash(String, String)")
  end

  it "sanitizes Crystal keywords in identifiers" do
    GoogleApis::Generator.sanitize_identifier("select").should eq("select_param")
    GoogleApis::Generator.sanitize_identifier("end").should eq("end_param")
    GoogleApis::Generator.sanitize_identifier("normalName").should eq("normal_name")
  end

  it "parses discovery document structure" do
    sample_json = <<-JSON
    {
      "name": "sample",
      "version": "v1",
      "rootUrl": "https://sample.googleapis.com/",
      "servicePath": "sample/v1/",
      "schemas": {
        "Item": {
          "id": "Item",
          "type": "object",
          "properties": {
            "id": {"type": "string"},
            "name": {"type": "string"}
          }
        }
      },
      "resources": {
        "items": {
          "methods": {
            "list": {
              "id": "sample.items.list",
              "path": "items",
              "httpMethod": "GET",
              "response": {"$ref": "Item"}
            }
          }
        }
      }
    }
    JSON

    service = GoogleApis::Generator.parse(sample_json)
    service.name.should eq("sample")
    service.version.should eq("v1")
    service.module_name.should eq("GoogleApis::Sample::V1")
    service.schemas.size.should eq(1)
    service.schemas.first.name.should eq("Item")
    service.resources.size.should eq(1)
    service.resources.first.class_name.should eq("ItemsService")
    service.resources.first.methods.size.should eq(1)
    service.resources.first.methods.first.crystal_name.should eq("list")
    service.resources.first.methods.first.response_ref.should eq("Item")
  end
end
