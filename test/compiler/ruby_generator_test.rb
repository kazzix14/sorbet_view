# typed: true
# frozen_string_literal: true

require 'test_helper'

class RubyGeneratorTest < Minitest::Test
  def setup
    @generator = SorbetView::Compiler::RubyGenerator.new
    @config = SorbetView::Configuration.new
  end

  def test_generates_valid_ruby
    segments = [
      SorbetView::Compiler::RubySegment.new(code: '@user.name', line: 0, column: 5, type: :expression),
      SorbetView::Compiler::RubySegment.new(code: 'if @user.admin?', line: 1, column: 4, type: :statement),
      SorbetView::Compiler::RubySegment.new(code: 'end', line: 3, column: 4, type: :statement)
    ]

    context = SorbetView::Compiler::TemplateContext.new(
      class_name: 'SorbetView::Generated::Users::Show',
      superclass: nil,
      includes: ['::ActionView::Helpers'],
      template_path: 'app/views/users/show.html.erb',
      ruby_path: 'sorbet/templates/app/views/users/show.html.erb.rb'
    )

    result = @generator.generate(segments: segments, context: context, config: @config)

    # Should be valid Ruby
    assert RubyVM::InstructionSequence.compile(result.ruby_source)

    # Should contain the class
    assert_includes result.ruby_source, 'class SorbetView::Generated::Users::Show'
    assert_includes result.ruby_source, 'def __sorbet_view_render'
    assert_includes result.ruby_source, '@user.name'
    assert_includes result.ruby_source, 'if @user.admin?'
  end

  def test_extracts_locals_from_comments
    segments = [
      SorbetView::Compiler::RubySegment.new(
        code: 'locals: (user:, name: "default")',
        line: 0, column: 4, type: :comment
      ),
      SorbetView::Compiler::RubySegment.new(
        code: 'locals_sig: sig { params(user: User, name: String).void }',
        line: 1, column: 4, type: :comment
      ),
      SorbetView::Compiler::RubySegment.new(code: 'user.name', line: 3, column: 5, type: :expression)
    ]

    context = SorbetView::Compiler::TemplateContext.new(
      class_name: 'SorbetView::Generated::Users::Card',
      superclass: nil,
      includes: [],
      template_path: 'app/views/users/_card.html.erb',
      ruby_path: 'sorbet/templates/app/views/users/_card.html.erb.rb'
    )

    result = @generator.generate(segments: segments, context: context, config: @config)

    assert_equal '(user:, name: "default")', result.locals
    assert_equal 'sig { params(user: User, name: String).void }', result.locals_sig
    assert_includes result.ruby_source, 'def __sorbet_view_render(user:, name: "default")'
    assert_includes result.ruby_source, 'sig { params(user: User, name: String).void }'
  end

  def test_generates_source_map_entries
    segments = [
      SorbetView::Compiler::RubySegment.new(code: '@title', line: 0, column: 5, type: :expression)
    ]

    context = SorbetView::Compiler::TemplateContext.new(
      class_name: 'SorbetView::Generated::Test',
      superclass: nil,
      includes: [],
      template_path: 'test.html.erb',
      ruby_path: 'sorbet/templates/test.html.erb.rb'
    )

    result = @generator.generate(segments: segments, context: context, config: @config)

    assert_equal 1, result.source_map.entries.length
    entry = result.source_map.entries.first
    assert_equal 0, entry.template_range.start.line
    assert_equal :expression, entry.type
  end

  def test_typed_level_from_config
    config = SorbetView::Configuration.new(typed_level: 'strict')
    segments = []

    context = SorbetView::Compiler::TemplateContext.new(
      class_name: 'SorbetView::Generated::Test',
      superclass: nil,
      includes: [],
      template_path: 'test.html.erb',
      ruby_path: 'sorbet/templates/test.html.erb.rb'
    )

    result = @generator.generate(segments: segments, context: context, config: config)

    assert_includes result.ruby_source, '# typed: strict'
  end
end
