require "test_helper"

class Api::V1::NetworkingControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get api_v1_networking_index_url
    assert_response :success
  end
end
