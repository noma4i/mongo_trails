# frozen_string_literal: true

begin
  require 'bundler/inline'
rescue LoadError => e
  warn 'Bundler version 1.10 or later is required. Please update your Bundler'
  raise e
end

gemfile(true) do
  source 'https://rubygems.org'

  gem 'rails', '5.2.1'
  gem 'sqlite3', '~> 1.3.6'
  gem 'mongoid', '~> 6.0'
  gem 'pry'
  gem 'paper_trail', path: './'
end

require 'active_record'
require 'minitest/autorun'
require 'pry'

PaperTrail.config.mongo_config = { hosts: ['localhost:27017'], database: 'my_test_db' }

PaperTrail.config.mongo_prefix = lambda do
  'test'
end

require 'paper_trail/mongo_support/config'


ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
  end

  create_table :comments, force: true do |t|
    t.integer :user_id
    t.string :body
  end
end

class Comment < ActiveRecord::Base
  belongs_to :user
end

class User < ActiveRecord::Base
  has_many :comments

  has_paper_trail
end

class SimpleTest < Minitest::Test
  def setup
    PaperTrail.request.whodunnit = 'Andy Stewart'

    Mongoid.purge!
    @user = User.create(name: 'Bob')
  end

  def test_models
    [*1..20].each do |i|
      c = @user.comments.find_or_create_by(body: "Hello #{i}")
      c.update!(body: 'Hello again!')
      @user.update!(name: "Bob #{i}")
    end

    changeset = { 'name' => ['Bob 19', 'Bob 20'] }

    assert_equal 20, @user.comments.count
    assert_equal 21, @user.versions.count

    refute_same @user.versions.first, @user.versions.last
    assert_equal 'Bob 19', @user.paper_trail.previous_version.name
    assert_equal changeset, @user.versions.last.changeset

    PaperTrail::Version.find(1).next.reify.save!

    assert_equal 'Bob', User.first.name
  end
end
