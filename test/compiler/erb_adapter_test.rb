# typed: true
# frozen_string_literal: true

require 'test_helper'

class ErbAdapterTest < Minitest::Test
  def setup
    @adapter = SorbetView::Compiler::Adapters::ErbAdapter.new
  end

  def test_extracts_expression
    segments = @adapter.extract_segments('<%= @title %>')
    assert_equal 1, segments.length
    assert_equal :expression, segments[0].type
    assert_includes segments[0].code, '@title'
  end

  def test_extracts_statement
    segments = @adapter.extract_segments('<% if true %>')
    assert_equal 1, segments.length
    assert_equal :statement, segments[0].type
    assert_includes segments[0].code, 'if true'
  end

  def test_extracts_comment
    segments = @adapter.extract_segments('<%# this is a comment %>')
    assert_equal 1, segments.length
    assert_equal :comment, segments[0].type
  end

  def test_extracts_multiple_segments
    source = <<~ERB
      <h1><%= @title %></h1>
      <% if @show %>
        <p><%= @content %></p>
      <% end %>
    ERB

    segments = @adapter.extract_segments(source)
    code_segments = segments.reject { |s| s.type == :comment }
    assert_equal 4, code_segments.length
  end

  def test_extracts_locals_from_comment
    source = '<%# locals: (user:, name:) %>'
    segments = @adapter.extract_segments(source)
    assert_equal 1, segments.length
    assert_equal :comment, segments[0].type
    assert_includes segments[0].code, 'locals:'
  end

  def test_line_numbers_are_set
    source = <<~ERB
      <div>
        <%= @foo %>
      </div>
    ERB

    segments = @adapter.extract_segments(source)
    expression = segments.find { |s| s.type == :expression }
    assert expression
    assert_equal 1, expression.line # 0-based, second line
  end

  def test_segment_position_skips_leading_space_in_expression
    # `<%= foo %>` — content token starts at col 3 (after `<%=`), the actual
    # `f` is at col 4. The segment column must point at the code, not the space.
    segments = @adapter.extract_segments('<%= foo %>')
    assert_equal 1, segments.length
    assert_equal 0, segments[0].line
    assert_equal 4, segments[0].column
    assert_equal 'foo', segments[0].code
  end

  def test_segment_position_skips_leading_space_in_statement
    segments = @adapter.extract_segments('<% foo %>')
    assert_equal 1, segments.length
    assert_equal 0, segments[0].line
    assert_equal 3, segments[0].column
    assert_equal 'foo', segments[0].code
  end

  def test_segment_position_advances_past_leading_newlines
    # Multi-line block: `<%`, newline, indented code, newline, `%>`.
    # Segment must point at the actual code line/column, not the spot just
    # after `<%` (which is what Herb's content token gives).
    source = "<%\n  something invalid\n%>"
    segments = @adapter.extract_segments(source)
    assert_equal 1, segments.length
    assert_equal 'something invalid', segments[0].code
    assert_equal 1, segments[0].line
    assert_equal 2, segments[0].column
  end

  def test_end_segment_position_skips_leading_space
    source = "<% if foo %>\n<% end %>"
    segments = @adapter.extract_segments(source)
    end_seg = segments.find { |s| s.code == 'end' }
    assert end_seg
    assert_equal 1, end_seg.line
    assert_equal 3, end_seg.column
  end
end
