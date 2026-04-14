# frozen_string_literal: true

require 'test_helper'

class PaperTrailEventsBaseTest < Minitest::Test
  class DummyRecord
    attr_reader :changes, :saved_changes

    def initialize(changes:, saved_changes:)
      @changes = changes
      @saved_changes = saved_changes
    end
  end

  def build_event(record:, after_callback:)
    event = PaperTrail::Events::Base.allocate
    event.instance_variable_set(:@record, record)
    event.instance_variable_set(:@in_after_callback, after_callback)
    event
  end

  def test_removes_changes_where_array_contains_identical_hashes
    record = DummyRecord.new(
      changes: {
        'data' => [{ 'a' => 1 }, { 'a' => 1 }],
        'name' => %w[old new]
      },
      saved_changes: {}
    )

    event = build_event(record: record, after_callback: false)
    result = event.send(:load_changes_in_latest_version)

    assert_equal({ 'name' => %w[old new] }, result)
  end

  def test_keeps_changes_when_hashes_differ
    record = DummyRecord.new(
      changes: {
        'data' => [{ 'a' => 1 }, { 'a' => 2 }]
      },
      saved_changes: {}
    )

    event = build_event(record: record, after_callback: false)

    result = event.send(:load_changes_in_latest_version)

    assert_equal({ 'data' => [{ 'a' => 1 }, { 'a' => 2 }] }, result)
  end

  def test_uses_saved_changes_when_in_after_callback
    record = DummyRecord.new(
      changes: {
        'name' => %w[old new]
      },
      saved_changes: {
        'title' => %w[a b]
      }
    )

    event = build_event(record: record, after_callback: true)

    result = event.send(:load_changes_in_latest_version)

    assert_equal({ 'title' => %w[a b] }, result)
  end
end
