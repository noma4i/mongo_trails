require "test_helper"

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
        "data" => [{"a" => 1}, {"a" => 1}],
        "name" => ["old", "new"]
      },
      saved_changes: {}
    )

    event = build_event(record: record, after_callback: false)

    $test = true
    result = event.send(:load_changes_in_latest_version)
    $test = false

    assert_equal({"name" => ["old", "new"]}, result)
  end

  def test_keeps_changes_when_hashes_differ
    record = DummyRecord.new(
      changes: {
        "data" => [{"a" => 1}, {"a" => 2}]
      },
      saved_changes: {}
    )

    event = build_event(record: record, after_callback: false)

    result = event.send(:load_changes_in_latest_version)

    assert_equal({"data" => [{"a" => 1}, {"a" => 2}]}, result)
  end

  def test_uses_saved_changes_when_in_after_callback
    record = DummyRecord.new(
      changes: {
        "name" => ["old", "new"]
      },
      saved_changes: {
        "title" => ["a", "b"]
      }
    )

    event = build_event(record: record, after_callback: true)

    result = event.send(:load_changes_in_latest_version)

    assert_equal({"title" => ["a", "b"]}, result)
  end
end
