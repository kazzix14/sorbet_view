# typed: true
# frozen_string_literal: true

require 'test_helper'

class TemplateContextTest < Minitest::Test
  def setup
    @config = SorbetView::Configuration.new
  end

  def test_controller_view
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.html.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Show', ctx.class_name
    assert_nil ctx.superclass
    assert_includes ctx.includes, '::ActionView::Helpers'
    assert_includes ctx.includes, '::ApplicationController::HelperMethods'
  end

  def test_partial
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/_card.html.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Card', ctx.class_name
  end

  def test_layout
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/layouts/application.html.erb', @config)

    assert_equal 'SorbetView::Generated::Layouts::Application', ctx.class_name
    assert_includes ctx.includes, '::ActionView::Helpers'
  end

  def test_nested_path
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/admin/users/index.html.erb', @config)

    assert_equal 'SorbetView::Generated::Admin::Users::Index', ctx.class_name
  end

  def test_ruby_path
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.html.erb', @config)

    assert_equal 'sorbet/templates/app/views/users/show.html.erb.rb', ctx.ruby_path
  end

  def test_extra_includes_from_config
    config = SorbetView::Configuration.new(extra_includes: ['Pagy::Frontend'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.html.erb', config)

    assert_includes ctx.includes, 'Pagy::Frontend'
  end
end
