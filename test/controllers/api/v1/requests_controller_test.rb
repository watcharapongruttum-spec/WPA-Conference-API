require "test_helper"

class Api::V1::RequestsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get api_v1_requests_index_url
    assert_response :success
  end

  test "should get create" do
    get api_v1_requests_create_url
    assert_response :success
  end

  test "should get update" do
    get api_v1_requests_update_url
    assert_response :success
  end
end
