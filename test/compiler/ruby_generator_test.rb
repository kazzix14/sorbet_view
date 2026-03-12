# typed: true
# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'

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

  def test_ivars_with_typed_mapping
    Dir.mktmpdir do |tmpdir|
      # Write a typed ivar mapping (keyed by template path without extensions)
      mapping = {
        'app/views/posts/show' => { '@post' => 'Post', '@comments' => 'Post::ActiveRecord_Associations_CollectionProxy' }
      }
      File.write(File.join(tmpdir, '.defined_ivars.json'), JSON.generate(mapping))

      config = SorbetView::Configuration.new(output_dir: tmpdir)

      segments = [
        SorbetView::Compiler::RubySegment.new(code: '@post.title', line: 0, column: 5, type: :expression),
        SorbetView::Compiler::RubySegment.new(code: '@comments.each do |c|', line: 1, column: 4, type: :statement),
        SorbetView::Compiler::RubySegment.new(code: 'end', line: 3, column: 4, type: :statement)
      ]

      context = SorbetView::Compiler::TemplateContext.new(
        class_name: 'SorbetView::Generated::Posts::Show',
        superclass: nil,
        includes: ['::ActionView::Helpers'],
        template_path: 'app/views/posts/show.html.erb',
        ruby_path: 'sorbet/templates/app/views/posts/show.html.erb.rb'
      )

      result = @generator.generate(segments: segments, context: context, config: config)

      # Defined ivars should get their srb-lens types
      assert_includes result.ruby_source, '@post = T.let(T.unsafe(nil), Post)'
      assert_includes result.ruby_source, '@comments = T.let(T.unsafe(nil), Post::ActiveRecord_Associations_CollectionProxy)'

      # Should be valid Ruby
      assert RubyVM::InstructionSequence.compile(result.ruby_source)
    end
  end

  def test_undefined_ivars_get_nilclass
    Dir.mktmpdir do |tmpdir|
      # Mapping exists but doesn't include @unknown
      mapping = {
        'app/views/posts/show' => { '@post' => 'Post' }
      }
      File.write(File.join(tmpdir, '.defined_ivars.json'), JSON.generate(mapping))

      config = SorbetView::Configuration.new(output_dir: tmpdir)

      segments = [
        SorbetView::Compiler::RubySegment.new(code: '@post.title', line: 0, column: 5, type: :expression),
        SorbetView::Compiler::RubySegment.new(code: '@unknown.foo', line: 1, column: 5, type: :expression)
      ]

      context = SorbetView::Compiler::TemplateContext.new(
        class_name: 'SorbetView::Generated::Posts::Show',
        superclass: nil,
        includes: ['::ActionView::Helpers'],
        template_path: 'app/views/posts/show.html.erb',
        ruby_path: 'sorbet/templates/app/views/posts/show.html.erb.rb'
      )

      result = @generator.generate(segments: segments, context: context, config: config)

      # Defined ivar gets its type, undefined gets NilClass
      assert_includes result.ruby_source, '@post = T.let(T.unsafe(nil), Post)'
      assert_includes result.ruby_source, '@unknown = T.let(nil, NilClass)'
    end
  end

  def test_no_mapping_file_defaults_to_nilclass
    Dir.mktmpdir do |tmpdir|
      # No .defined_ivars.json exists
      config = SorbetView::Configuration.new(output_dir: tmpdir)

      segments = [
        SorbetView::Compiler::RubySegment.new(code: '@user.name', line: 0, column: 5, type: :expression)
      ]

      context = SorbetView::Compiler::TemplateContext.new(
        class_name: 'SorbetView::Generated::Users::Show',
        superclass: nil,
        includes: ['::ActionView::Helpers'],
        template_path: 'app/views/users/show.html.erb',
        ruby_path: 'sorbet/templates/app/views/users/show.html.erb.rb'
      )

      result = @generator.generate(segments: segments, context: context, config: config)

      assert_includes result.ruby_source, '@user = T.let(nil, NilClass)'
    end
  end

  def test_ivars_with_custom_input_dirs
    Dir.mktmpdir do |tmpdir|
      # JSON key is the template path without extensions (as generated by tapioca)
      mapping = {
        'custom/views/posts/show' => { '@post' => 'Post' }
      }
      File.write(File.join(tmpdir, '.defined_ivars.json'), JSON.generate(mapping))

      config = SorbetView::Configuration.new(output_dir: tmpdir, input_dirs: ['custom/views'])

      segments = [
        SorbetView::Compiler::RubySegment.new(code: '@post.title', line: 0, column: 5, type: :expression)
      ]

      context = SorbetView::Compiler::TemplateContext.new(
        class_name: 'SorbetView::Generated::Posts::Show',
        superclass: nil,
        includes: ['::ActionView::Helpers'],
        template_path: 'custom/views/posts/show.html.erb',
        ruby_path: "#{tmpdir}/custom/views/posts/show.html.erb.rb"
      )

      result = @generator.generate(segments: segments, context: context, config: config)

      assert_includes result.ruby_source, '@post = T.let(T.unsafe(nil), Post)'
    end
  end

  def test_ivars_with_input_dir_parent_of_views
    Dir.mktmpdir do |tmpdir|
      # JSON key is the full template path without extensions
      mapping = {
        'app/views/admin_area/v21/booths/index' => { '@booths' => 'Booth::PrivateRelation' }
      }
      File.write(File.join(tmpdir, '.defined_ivars.json'), JSON.generate(mapping))

      config = SorbetView::Configuration.new(output_dir: tmpdir, input_dirs: ['app/'])

      segments = [
        SorbetView::Compiler::RubySegment.new(code: '@booths.each do |booth|', line: 0, column: 4, type: :statement),
        SorbetView::Compiler::RubySegment.new(code: 'end', line: 2, column: 4, type: :statement)
      ]

      context = SorbetView::Compiler::TemplateContext.new(
        class_name: 'SorbetView::Generated::AdminArea::V21::Booths::Index',
        superclass: nil,
        includes: ['::ActionView::Helpers'],
        template_path: 'app/views/admin_area/v21/booths/index.html.erb',
        ruby_path: "#{tmpdir}/app/views/admin_area/v21/booths/index.html.erb.rb"
      )

      result = @generator.generate(segments: segments, context: context, config: config)

      assert_includes result.ruby_source, '@booths = T.let(T.unsafe(nil), Booth::PrivateRelation)'
    end
  end
end
