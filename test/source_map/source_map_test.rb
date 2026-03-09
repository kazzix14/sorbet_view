# typed: true
# frozen_string_literal: true

require 'test_helper'

class SourceMapTest < Minitest::Test
  def test_template_to_ruby_translation
    entry = SorbetView::SourceMap::MappingEntry.new(
      template_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 0, column: 5),
        end_: SorbetView::SourceMap::Position.new(line: 0, column: 15)
      ),
      ruby_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 10, column: 4),
        end_: SorbetView::SourceMap::Position.new(line: 10, column: 14)
      ),
      type: :expression
    )

    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'test.html.erb',
      ruby_path: 'test.html.erb.rb',
      entries: [entry]
    )

    result = source_map.template_to_ruby(SorbetView::SourceMap::Position.new(line: 0, column: 7))
    assert result
    assert_equal 10, result.line
    assert_equal 6, result.column
  end

  def test_ruby_to_template_translation
    entry = SorbetView::SourceMap::MappingEntry.new(
      template_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 2, column: 4),
        end_: SorbetView::SourceMap::Position.new(line: 2, column: 20)
      ),
      ruby_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 12, column: 4),
        end_: SorbetView::SourceMap::Position.new(line: 12, column: 20)
      ),
      type: :code
    )

    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'test.html.erb',
      ruby_path: 'test.html.erb.rb',
      entries: [entry]
    )

    result = source_map.ruby_to_template(SorbetView::SourceMap::Position.new(line: 12, column: 10))
    assert result
    assert_equal 2, result.line
    assert_equal 10, result.column
  end

  def test_roundtrip
    entry = SorbetView::SourceMap::MappingEntry.new(
      template_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 3, column: 8),
        end_: SorbetView::SourceMap::Position.new(line: 3, column: 25)
      ),
      ruby_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 15, column: 4),
        end_: SorbetView::SourceMap::Position.new(line: 15, column: 21)
      ),
      type: :expression
    )

    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'test.html.erb',
      ruby_path: 'test.html.erb.rb',
      entries: [entry]
    )

    original = SorbetView::SourceMap::Position.new(line: 3, column: 12)
    ruby_pos = source_map.template_to_ruby(original)
    assert ruby_pos
    back = source_map.ruby_to_template(ruby_pos)
    assert back
    assert_equal original.line, back.line
    assert_equal original.column, back.column
  end

  def test_position_outside_mapping_returns_nil
    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'test.html.erb',
      ruby_path: 'test.html.erb.rb',
      entries: []
    )

    result = source_map.template_to_ruby(SorbetView::SourceMap::Position.new(line: 0, column: 0))
    assert_nil result
  end

  def test_boilerplate_returns_nil
    entry = SorbetView::SourceMap::MappingEntry.new(
      template_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 0, column: 0),
        end_: SorbetView::SourceMap::Position.new(line: 0, column: 10)
      ),
      ruby_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 0, column: 0),
        end_: SorbetView::SourceMap::Position.new(line: 0, column: 10)
      ),
      type: :boilerplate
    )

    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'test.html.erb',
      ruby_path: 'test.html.erb.rb',
      entries: [entry]
    )

    result = source_map.ruby_to_template(SorbetView::SourceMap::Position.new(line: 0, column: 5))
    assert_nil result
  end
end
