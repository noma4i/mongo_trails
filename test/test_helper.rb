# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$VERBOSE = nil
require 'active_record'
require 'mongo_trails'

require 'bundler/setup'
Bundler.require(:default)
require 'minitest/autorun'
require 'minitest/pride'
require 'sqlite3'
require 'sidekiq/testing'

module SidekiqMinitestSupport
  def after_teardown
    Sidekiq::Job.clear_all
    super
  end
end

module MiniTest
  class Spec
    include SidekiqMinitestSupport
  end
end

module MiniTest
  class Unit
    class TestCase
      include SidekiqMinitestSupport
    end
  end
end

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
PaperTrail.config.mongo_config = { hosts: ['localhost:27017'], database: 'my_test_db' }

PaperTrail.config.mongo_prefix = lambda do
  'test'
end

Mongo::Logger.logger.level = Logger::INFO

require 'mongo_trails/mongo_support/config'

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
