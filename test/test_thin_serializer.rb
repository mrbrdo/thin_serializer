require 'test_helper'
require 'active_record_helper'
require 'pry'

class CommentSerializer < ThinSerializer
  attributes :comment
end

class PostSerializer < ThinSerializer
  attributes :id
  attribute :author_name, "author_first_name || ' ' || author_last_name"
  virtual_attributes :author_first_name, :author_last_name
end

class PostWithMethodSerializer < ThinSerializer
  attributes :id, :author_first_name, :title
  virtual_attributes :author_last_name

  def author_first_name
    record_attributes["author_first_name"].upcase
  end

  def title
    "By Mr. #{author_last_name}"
  end
end

class PostWithCommentsSerializer < ThinSerializer
  attributes :id
  has_many :comments, :post_id, CommentSerializer
end

class BlogSerializer < ThinSerializer
  attributes :id, :title
  has_many :posts, :blog_id, PostSerializer
end

class BlogWithOnePostSerializer < ThinSerializer
  attributes :id, :title
  has_one :post, :blog_id, PostSerializer
end

class BlogWithPostCommentsSerializer < ThinSerializer
  attributes :id, :title
  has_many :posts, :blog_id, PostWithCommentsSerializer
end

class PostWithBlogSerializer < ThinSerializer
  attributes :id
  belongs_to :blog, :blog_id, BlogSerializer
end

class ThinSerializerTest < ActiveSupport::TestCase
  def teardown
    clean_db
  end

  def test_basic_serialization
    Post.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    assert_equal [{"id"=>1, "author_name"=>"John Doe"}],
      PostSerializer.new(Post.all).as_json
  end

  def test_attribute_methods
    Post.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    assert_equal [{"id"=>1, "author_first_name"=>"JOHN", "title"=>"By Mr. Doe"}],
      PostWithMethodSerializer.new(Post.all).as_json
  end

  def test_has_many
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    assert_equal [{"id"=>1, "title"=>"Blog 1", "posts"=>[{"id"=>1, "author_name"=>"John Doe"}]}],
      BlogSerializer.new(Blog.all).as_json
  end

  def test_has_many_nested
    blog = Blog.create! title: "Blog 1"
    post = blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    post.comments.create! comment: "Comment 1"
    post.comments.create! comment: "Comment 2"
    assert_equal [{"id"=>1, "title"=>"Blog 1", "posts"=>[{"id"=>1, "comments"=>[{"comment"=>"Comment 1"}, {"comment"=>"Comment 2"}]}]}],
      BlogWithPostCommentsSerializer.new(Blog.all).as_json
  end

  def test_belongs_to
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    assert_equal [{"id"=>1, "blog"=>{"id"=>1, "title"=>"Blog 1", "posts"=>[{"id"=>1, "author_name"=>"John Doe"}]}}],
      PostWithBlogSerializer.new(Post.all).as_json
  end

  def test_has_one
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    assert_equal [{"id"=>1, "title"=>"Blog 1", "post"=> {"id"=>1, "author_name"=>"John Doe"}}],
      BlogWithOnePostSerializer.new(Blog.all).as_json
  end
end
