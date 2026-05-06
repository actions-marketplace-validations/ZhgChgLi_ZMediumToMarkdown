require 'uri'
require 'json'

require 'Request'

class User
  USER_FOLLOWERS_QUERY_PATH    = File.expand_path('Queries/UserFollowersQuery.graphql', __dir__).freeze
  USER_PROFILE_QUERY_PATH      = File.expand_path('Queries/UserProfileQuery.graphql', __dir__).freeze

  def self.convertToUserIDFromUsername(username)
    username = username[1..] if username.start_with?('@')

    query = [
      {
        "operationName": "UserFollowers",
        "variables": {
          "id": nil,
          "username": username,
          "paging": nil
        },
        "query": userFollowersQueryString
      }
    ]

    body = Request.body(Request.URL(Request.mediumGraphqlEndpoint, "POST", query))
    return nil if body.nil?

    json = JSON.parse(body)
    json&.dig(0, "data", "userResult", "id")
  end

  def self.fetchUserPosts(userID, from)
    query = [
      {
        "operationName": "UserProfileQuery",
        "variables": {
          "homepagePostsFrom": from,
          "includeDistributedResponses": true,
          "id": userID,
          "homepagePostsLimit": 10
        },
        "query": userProfileQueryString
      }
    ]

    body = Request.body(Request.URL(Request.mediumGraphqlEndpoint, "POST", query))
    return { "nextID" => nil, "postURLs" => [] } if body.nil?

    json = JSON.parse(body)
    extractPosts(json)
  end

  # Pulled out so it can be exercised by tests without hitting the network.
  def self.extractPosts(json)
    nextInfo = json&.dig(0, "data", "userResult", "homepagePostsConnection", "pagingInfo", "next")
    postsInfo = json&.dig(0, "data", "userResult", "homepagePostsConnection", "posts")

    {
      "nextID" => nextInfo && nextInfo["from"],
      "postURLs" => (postsInfo || []).map { |post| { "url" => post["mediumUrl"], "pin" => post["pinnedByCreatorAt"].to_i > 0 } }
    }
  end

  def self.userFollowersQueryString
    @userFollowersQueryString ||= File.read(USER_FOLLOWERS_QUERY_PATH)
  end

  def self.userProfileQueryString
    @userProfileQueryString ||= File.read(USER_PROFILE_QUERY_PATH)
  end
end
