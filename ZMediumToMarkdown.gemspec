Gem::Specification.new do |gem|
    gem.authors       = ['ZhgChgLi']
    gem.description   = 'ZMediumToMarkdown converts Medium posts into clean, portable Markdown. It can download a single post or every post from a Medium username, preserving headings, lists, blockquotes, code blocks, images, links, and common embeds such as GitHub Gists, Twitter / X, YouTube, Vimeo, SoundCloud, and Spotify. Images are downloaded locally, with output paths ready for plain Markdown or Jekyll projects.'
    gem.summary       = 'Convert Medium posts to portable Markdown with structure, images, code blocks, and common embeds preserved.'
    gem.homepage      = 'https://github.com/ZhgChgLi/ZMediumToMarkdown'
    gem.files         = Dir['lib/**/*.*']
    gem.executables   = ['ZMediumToMarkdown']
    gem.name          = 'ZMediumToMarkdown'
    gem.version       = '3.3.0'
    gem.required_ruby_version = '>= 3.2'
  
    gem.license       = "MIT"
  
    gem.add_dependency 'nokogiri', '~> 1.18', '>= 1.18.9'
    gem.add_dependency 'net-http', '~> 0.1.0'
    gem.add_dependency 'rubyzip', '~> 2.3.2'
    gem.add_dependency 'uri', '>= 1.0.4', '< 2.0'
    gem.add_dependency 'ferrum', '~> 0.15'
end
