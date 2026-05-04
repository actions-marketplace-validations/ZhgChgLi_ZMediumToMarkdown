require_relative 'test_helper'

class UserExtractPostsTest < Minitest::Test
  def test_extract_posts_with_full_response
    json = [{
      'data' => {
        'userResult' => {
          'homepagePostsConnection' => {
            'pagingInfo' => { 'next' => { 'from' => 'cursor-2' } },
            'posts' => [
              { 'mediumUrl' => 'https://medium.com/@u/p1-aaa', 'pinnedByCreatorAt' => 1_700_000_000_000 },
              { 'mediumUrl' => 'https://medium.com/@u/p2-bbb', 'pinnedByCreatorAt' => 0 }
            ]
          }
        }
      }
    }]
    out = User.extractPosts(json)
    assert_equal 'cursor-2', out['nextID']
    assert_equal 2, out['postURLs'].length
    assert_equal 'https://medium.com/@u/p1-aaa', out['postURLs'][0]['url']
    assert_equal true, out['postURLs'][0]['pin']
    assert_equal false, out['postURLs'][1]['pin']
  end

  def test_extract_posts_when_no_next_cursor
    json = [{
      'data' => {
        'userResult' => {
          'homepagePostsConnection' => {
            'pagingInfo' => {},
            'posts' => [{ 'mediumUrl' => 'https://medium.com/p1-aaa', 'pinnedByCreatorAt' => 0 }]
          }
        }
      }
    }]
    out = User.extractPosts(json)
    assert_nil out['nextID']
    assert_equal 1, out['postURLs'].length
  end

  def test_extract_posts_with_nil_json
    assert_equal({ 'nextID' => nil, 'postURLs' => [] }, User.extractPosts(nil))
  end

  def test_extract_posts_with_missing_branch
    out = User.extractPosts([{ 'data' => {} }])
    assert_nil out['nextID']
    assert_equal [], out['postURLs']
  end
end
