require 'net/http'
require 'uri'
require 'nokogiri'
require 'json'
require 'date'

require 'Request'
require 'ImageDownloader'
require 'PathPolicy'

class Post
  APOLLO_STATE_REGEX                  = /(<script>window\.__APOLLO_STATE__ \= ){1}(.*)(<\/script>){1}/.freeze
  POST_VIEWER_EDGE_QUERY_PATH         = File.expand_path('Queries/PostViewerEdgeContentQuery.graphql', __dir__).freeze

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

  def self.parsePostContentFromHTML(html)
    return nil unless html

    json = nil
    html.search('script').each do |script|
      match = script.to_s[APOLLO_STATE_REGEX, 2]
      if !match.nil? && match != ""
        json = JSON.parse(match)
      end
    end
    json
  end

  def self.fetchPostParagraphs(postID)
    query = [
      {
        "operationName": "PostViewerEdgeContentQuery",
        "variables": {
          "postId": postID
        },
        "query": postViewerEdgeContentQueryString
      }
    ]

    host = ENV.fetch('MEDIUM_HOST', 'https://medium.com/_/graphql')
    body = Request.body(Request.URL(host, 'POST', query))
    return nil if body.nil?

    json = JSON.parse(body)
    json&.dig(0, "data", "post", "viewerEdge", "fullContent")
  end

  def self.parsePostInfoFromPostContent(content, postID, pathPolicy)
    postInfo = PostInfo.new()
    return postInfo if content.nil?

    postRoot = content.dig("Post:#{postID}")
    return postInfo if postRoot.nil?

    postInfo.description = postRoot.dig("previewContent", "subtitle")&.gsub(/[^[:print:]]/, '')
    postInfo.title = postRoot["title"]&.gsub(/[^[:print:]]/, '')
    postInfo.tags = postRoot["tags"]&.map { |tag| tag["__ref"].to_s.sub(/^Tag:/, '') }

    previewImage = postRoot.dig("previewImage", "__ref")
    if !previewImage.nil?
      previewImageFileName = content.dig(previewImage, "id")

      imagePathPolicy = PathPolicy.new(pathPolicy.getAbsolutePath(postID), pathPolicy.getRelativePath(postID))
      absolutePath = imagePathPolicy.getAbsolutePath(previewImageFileName)

      miro_host = ENV.fetch('MIRO_MEDIUM_HOST', 'https://miro.medium.com')
      imageURL = "#{miro_host}/#{previewImageFileName}"

      if ImageDownloader.download(absolutePath, imageURL)
        postInfo.previewImage = imagePathPolicy.getRelativePath(previewImageFileName)
      end
    end

    creatorRef = postRoot.dig("creator", "__ref")
    postInfo.creator = content.dig(creatorRef, "name") if creatorRef

    collectionRef = postRoot.dig("collection", "__ref")
    postInfo.collectionName = content.dig(collectionRef, "name") if collectionRef

    firstPublishedAt = postRoot["firstPublishedAt"]
    postInfo.firstPublishedAt = Time.at(0, firstPublishedAt, :millisecond) if firstPublishedAt

    latestPublishedAt = postRoot["latestPublishedAt"]
    postInfo.latestPublishedAt = Time.at(0, latestPublishedAt, :millisecond) if latestPublishedAt

    postInfo
  end

  def self.postViewerEdgeContentQueryString
    @postViewerEdgeContentQueryString ||= File.read(POST_VIEWER_EDGE_QUERY_PATH)
  end
end
