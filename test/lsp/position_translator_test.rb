# typed: true
# frozen_string_literal: true

require 'test_helper'

class PositionTranslatorTest < Minitest::Test
  def setup
    @translator = SorbetView::Lsp::PositionTranslator.new

    entry = SorbetView::SourceMap::MappingEntry.new(
      template_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 1, column: 5),
        end_: SorbetView::SourceMap::Position.new(line: 1, column: 15)
      ),
      ruby_range: SorbetView::SourceMap::Range.new(
        start: SorbetView::SourceMap::Position.new(line: 12, column: 4),
        end_: SorbetView::SourceMap::Position.new(line: 12, column: 14)
      ),
      type: :expression
    )

    source_map = SorbetView::SourceMap::SourceMap.new(
      template_path: 'app/views/test.html.erb',
      ruby_path: 'sorbet/templates/app/views/test.html.erb.rb',
      entries: [entry]
    )

    @translator.register('app/views/test.html.erb', source_map)
  end

  def test_template_to_ruby
    result = @translator.template_to_ruby(
      'app/views/test.html.erb',
      { 'line' => 1, 'character' => 7 }
    )

    assert result
    assert_equal 12, result[:line]
    assert_equal 6, result[:character]
  end

  def test_ruby_to_template
    result = @translator.ruby_to_template(
      'app/views/test.html.erb',
      { 'line' => 12, 'character' => 8 }
    )

    assert result
    assert_equal 1, result[:line]
    assert_equal 9, result[:character]
  end

  def test_position_outside_mapping_returns_nil
    result = @translator.template_to_ruby(
      'app/views/test.html.erb',
      { 'line' => 0, 'character' => 0 }
    )

    assert_nil result
  end

  def test_unknown_path_returns_nil
    result = @translator.template_to_ruby(
      'app/views/unknown.html.erb',
      { 'line' => 0, 'character' => 0 }
    )

    assert_nil result
  end

  def test_unregister
    @translator.unregister('app/views/test.html.erb')

    result = @translator.template_to_ruby(
      'app/views/test.html.erb',
      { 'line' => 1, 'character' => 7 }
    )

    assert_nil result
  end

  def test_ruby_range_to_template
    result = @translator.ruby_range_to_template(
      'app/views/test.html.erb',
      {
        'start' => { 'line' => 12, 'character' => 4 },
        'end' => { 'line' => 12, 'character' => 14 }
      }
    )

    assert result
    assert_equal 1, result['start'][:line]
    assert_equal 5, result['start'][:character]
    assert_equal 1, result['end'][:line]
    assert_equal 15, result['end'][:character]
  end
end
