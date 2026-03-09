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
end
