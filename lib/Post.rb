require 'net/http'
require 'uri'
require 'json'
require 'date'

require 'Request'
require 'ImageDownloader'
require 'PathPolicy'

class Post
  POST_VIEWER_EDGE_QUERY_PATH = File.expand_path('Queries/PostViewerEdgeContentQuery.graphql', __dir__).freeze
  POST_PAGE_QUERY_PATH        = File.expand_path('Queries/PostPageQuery.graphql', __dir__).freeze

  class PostInfo
    attr_accessor :title, :tags, :creator, :firstPublishedAt, :latestPublishedAt, :collectionName, :description, :previewImage
  end

  def self.getPostIDFromPostURLString(postURLString)
    uri = URI.parse(postURLString)
    uri.path.split('/').last.split('-').last
  end

  def self.getPostPathFromPostURLString(postURLString)
    uri = URI.parse(postURLString)
    uri.path.split('/').last
  end

  def self.fetchPostParagraphs(postID)
    json = postGraphQL("PostViewerEdgeContentQuery", postViewerEdgeContentQueryString,
                       { "postId" => postID })
    json&.dig(0, "data", "post", "viewerEdge", "fullContent")
  end

  # Fetches post-level metadata (title, tags, creator, dates, preview image,
  # collection) directly from Medium's PostPageQuery GraphQL operation.
  # Replaces the previous approach of scraping window.__APOLLO_STATE__ out of
  # the post HTML page, which Medium has been progressively dismantling.
  #
  # When `skipImages: true`, the preview-image download is skipped entirely
  # and `postInfo.previewImage` is left nil. Used by --stdout / --list /
  # listPostsByUsername to avoid touching the filesystem.
  def self.parsePostInfo(postID, pathPolicy, skipImages: false)
    json = postGraphQL("PostPageQuery", postPageQueryString,
                       { "postId" => postID,
                         "postMeteringOptions" => { "referrer" => "https://medium.com/me/stories" },
                         "includeShouldFollowPost" => false })
    return nil if json.nil?

    result = json.dig(0, "data", "postResult")
    return nil if result.nil?

    postInfo = PostInfo.new
    postInfo.description = result.dig("previewContent", "subtitle")&.gsub(/[^[:print:]]/, '')
    postInfo.title = result["title"]&.gsub(/[^[:print:]]/, '')
    postInfo.tags = result["tags"]&.map { |tag| tag["normalizedTagSlug"] }
    postInfo.creator = result.dig("creator", "name")
    postInfo.collectionName = result.dig("collection", "name")

    firstPublishedAt = result["firstPublishedAt"]
    postInfo.firstPublishedAt = Time.at(0, firstPublishedAt, :millisecond) if firstPublishedAt

    latestPublishedAt = result["latestPublishedAt"]
    postInfo.latestPublishedAt = Time.at(0, latestPublishedAt, :millisecond) if latestPublishedAt

    previewImageFileName = result.dig("previewImage", "id")
    if previewImageFileName && !skipImages && pathPolicy
      imagePathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath(postID), pathPolicy.getRelativePath(postID))
      absolutePath = imagePathPolicy.getAbsolutePath(previewImageFileName)

      miro_host = Request.miroHost
      imageURL = "#{miro_host}/#{previewImageFileName}"

      if ImageDownloader.download(absolutePath, imageURL)
        postInfo.previewImage = imagePathPolicy.getRelativePath(previewImageFileName)
      end
    end

    postInfo
  end

  def self.postViewerEdgeContentQueryString
    @postViewerEdgeContentQueryString ||= File.read(POST_VIEWER_EDGE_QUERY_PATH)
  end

  def self.postPageQueryString
    @postPageQueryString ||= File.read(POST_PAGE_QUERY_PATH)
  end

  def self.postGraphQL(operationName, queryString, variables)
    body = [{
      "operationName" => operationName,
      "variables" => variables,
      "query" => queryString
    }]

    response = Request.body(Request.URL(Request.mediumGraphqlEndpoint, 'POST', body))
    return nil if response.nil?

    JSON.parse(response)
  end
end
