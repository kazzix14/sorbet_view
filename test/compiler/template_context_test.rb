# typed: true
# frozen_string_literal: true

require 'test_helper'

class TemplateContextTest < Minitest::Test
  def setup
    @config = SorbetView::Configuration.new
    reset_controller_cache
  end

  def teardown
    reset_controller_cache
  end

  def test_controller_view
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.html.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Show::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
    assert_includes ctx.includes, '::ApplicationController::HelperMethods'
  end

  def test_controller_view_turbo_stream
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.turbo_stream.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Show::TurboStream', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
  end

  def test_controller_view_without_format
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Show', ctx.class_name
  end

  def test_partial
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/_card.html.erb', @config)

    assert_equal 'SorbetView::Generated::Users::Card::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
  end

  def test_layout
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/layouts/application.html.erb', @config)

    assert_equal 'SorbetView::Generated::Layouts::Application::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
  end

  def test_nested_path
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/admin/users/index.html.erb', @config)

    assert_equal 'SorbetView::Generated::Admin::Users::Index::Html', ctx.class_name
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

  def test_custom_input_dirs_controller_view
    config = SorbetView::Configuration.new(input_dirs: ['custom/views'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('custom/views/users/show.html.erb', config)

    assert_equal 'SorbetView::Generated::Users::Show::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
    assert_includes ctx.includes, '::ApplicationController::HelperMethods'
  end

  def test_custom_input_dirs_layout
    config = SorbetView::Configuration.new(input_dirs: ['custom/views'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('custom/views/layouts/application.html.erb', config)

    assert_equal 'SorbetView::Generated::Layouts::Application::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
  end

  def test_custom_input_dirs_partial
    config = SorbetView::Configuration.new(input_dirs: ['custom/views'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('custom/views/users/_card.html.erb', config)

    assert_equal 'SorbetView::Generated::Users::Card::Html', ctx.class_name
  end

  def test_custom_input_dirs_nested
    config = SorbetView::Configuration.new(input_dirs: ['custom/views'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('custom/views/admin/users/index.html.erb', config)

    assert_equal 'SorbetView::Generated::Admin::Users::Index::Html', ctx.class_name
  end

  # input_dirs: ['app/'] with views under app/views/ — strips both app/ and views/
  def test_input_dir_parent_of_views
    config = SorbetView::Configuration.new(input_dirs: ['app/'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/users/show.html.erb', config)

    assert_equal 'SorbetView::Generated::Users::Show::Html', ctx.class_name
    assert_equal '::ActionView::Base', ctx.superclass
    assert_includes ctx.includes, '::ApplicationController::HelperMethods'
  end

  def test_input_dir_parent_of_views_layout
    config = SorbetView::Configuration.new(input_dirs: ['app/'])
    ctx = SorbetView::Compiler::TemplateContext.resolve('app/views/layouts/application.html.erb', config)

    assert_equal 'SorbetView::Generated::Layouts::Application::Html', ctx.class_name
  end

  def test_resolve_runtime_helper_includes_falls_back_without_action_controller
    without_action_controller_stubs do
      includes = template_context_class.send(:resolve_runtime_helper_includes, 'app/views/users/show.html.erb', @config)

      assert_equal ['::ApplicationController::HelperMethods'], includes
    end
  end

  def test_resolve_runtime_helper_includes_for_controller_view_layout_and_partial
    with_action_controller_stubs do
      assert_equal [
        '::UsersController::HelperMethods',
        '::UsersHelper',
        '::ApplicationHelper',
        '::ActionView::Helpers::TagHelper',
        '::Turbo::StreamsHelper'
      ], template_context_class.send(
        :resolve_runtime_helper_includes,
        'app/views/users/show.html.erb',
        @config
      )
      assert_equal [
        '::ActionView::Helpers::TagHelper',
        '::AdminHelper',
        '::ApplicationHelper',
        '::Turbo::StreamsHelper',
        '::UsersController::HelperMethods',
        '::UsersHelper'
      ], template_context_class.send(
        :resolve_runtime_helper_includes,
        'app/views/layouts/application.html.erb',
        @config
      )
      assert_equal [
        '::UsersController::HelperMethods',
        '::UsersHelper',
        '::ApplicationHelper',
        '::ActionView::Helpers::TagHelper',
        '::Turbo::StreamsHelper'
      ], template_context_class.send(
        :resolve_runtime_helper_includes,
        'app/views/users/forms/_field.html.erb',
        @config
      )
    end
  end

  def test_helper_modules_for_controller_view_matches_controller_path
    with_action_controller_stubs do
      assert_equal [
        'UsersController::HelperMethods',
        'UsersHelper',
        'ApplicationHelper',
        'ActionView::Helpers::TagHelper',
        'Turbo::StreamsHelper'
      ], template_context_class.send(:helper_modules_for_controller_view, 'users/show.html.erb')
    end
  end

  def test_helper_modules_for_layout_uses_controllers_with_matching_layout
    with_action_controller_stubs do
      assert_equal [
        'ActionView::Helpers::TagHelper',
        'AdminHelper',
        'ApplicationHelper',
        'Turbo::StreamsHelper',
        'UsersController::HelperMethods',
        'UsersHelper'
      ], template_context_class.send(:helper_modules_for_layout, 'layouts/application.html.erb')
    end
  end

  def test_helper_modules_for_partial_walks_up_parent_directories
    with_action_controller_stubs do
      assert_equal [
        'UsersController::HelperMethods',
        'UsersHelper',
        'ApplicationHelper',
        'ActionView::Helpers::TagHelper',
        'Turbo::StreamsHelper'
      ], template_context_class.send(:helper_modules_for_partial, 'users/forms/_field.html.erb')
    end
  end

  def test_all_concrete_controllers_reads_from_object_space
    with_action_controller_stubs do
      controllers = template_context_class.send(:all_concrete_controllers)

      assert_includes controllers, UsersController
      assert_includes controllers, AdminController
      refute_includes controllers, ApplicationController
    end
  end

  def test_helper_module_names_for_preserves_runtime_helpers_and_filters_controller_framework_modules
    with_action_controller_stubs do
      assert_equal [
        'UsersController::HelperMethods',
        'UsersHelper',
        'ApplicationHelper',
        'ActionView::Helpers::TagHelper',
        'Turbo::StreamsHelper'
      ], template_context_class.send(:helper_module_names_for, UsersController)
    end
  end

  private

  def template_context_class
    SorbetView::Compiler::TemplateContext
  end

  def reset_controller_cache
    template_context_class.instance_variable_set(:@all_concrete_controllers, nil)
  end

  def without_action_controller_stubs
    with_replaced_constants(ActionController: nil, AbstractController: nil, ApplicationController: nil) do
      yield
    end
  end

  def with_action_controller_stubs
    with_replaced_constants(
      ActionController: nil,
      AbstractController: nil,
      ApplicationController: nil,
      ApplicationHelper: nil,
      UsersHelper: nil,
      AdminHelper: nil,
      ActionView: nil,
      Turbo: nil,
      UsersController: nil,
      AdminController: nil
    ) do
      define_action_controller_stubs
      reset_controller_cache
      yield
    ensure
      reset_controller_cache
    end
  end

  def with_replaced_constants(replacements)
    previous = replacements.transform_values { |name| nil }
    replacements.each_key do |name|
      previous[name] = if Object.const_defined?(name, false)
        [true, Object.const_get(name)]
      else
        [false, nil]
      end
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end

    replacements.each do |name, value|
      Object.const_set(name, value) unless value.nil?
    end

    yield
  ensure
    replacements.each_key do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
      defined_before, value = previous[name]
      Object.const_set(name, value) if defined_before
    end
  end

  def define_action_controller_stubs
    action_controller = Module.new
    abstract_controller = Module.new
    Object.const_set(:ActionController, action_controller)
    Object.const_set(:AbstractController, abstract_controller)

    action_controller.const_set(:Renderers, Module.new)
    ActionController::Renderers.const_set(:All, Module.new)
    abstract_controller.const_set(:Helpers, Module.new)
    action_view = Module.new
    turbo = Module.new
    Object.const_set(:ActionView, action_view)
    Object.const_set(:Turbo, turbo)
    action_view.const_set(:Helpers, Module.new)
    ActionView::Helpers.const_set(:TagHelper, Module.new)
    turbo.const_set(:StreamsHelper, Module.new)

    base_controller = Class.new do
      def self.abstract?
        false
      end
    end
    action_controller.const_set(:Base, base_controller)

    Object.const_set(:ApplicationHelper, Module.new)
    Object.const_set(:UsersHelper, Module.new)
    Object.const_set(:AdminHelper, Module.new)

    application_controller = Class.new(ActionController::Base)
    application_helper_chain = helper_chain(ApplicationHelper)
    application_controller.define_singleton_method(:abstract?) { true }
    application_controller.define_singleton_method(:_helpers) { application_helper_chain }
    Object.const_set(:ApplicationController, application_controller)

    users_controller = Class.new(ApplicationController)
    Object.const_set(:UsersController, users_controller)
    UsersController.const_set(:HelperMethods, Module.new)
    users_helper_chain = helper_chain(
      UsersController::HelperMethods,
      UsersHelper,
      ApplicationHelper,
      ActionView::Helpers::TagHelper,
      Turbo::StreamsHelper,
      ActionController::Renderers::All,
      AbstractController::Helpers
    )
    users_controller.define_singleton_method(:abstract?) { false }
    users_controller.define_singleton_method(:controller_path) { 'users' }
    users_controller.define_singleton_method(:_layout) { 'application' }
    users_controller.define_singleton_method(:_helpers) { users_helper_chain }

    admin_controller = Class.new(ApplicationController)
    Object.const_set(:AdminController, admin_controller)
    admin_helper_chain = helper_chain(AdminHelper, ApplicationHelper)
    admin_controller.define_singleton_method(:abstract?) { false }
    admin_controller.define_singleton_method(:controller_path) { 'admin' }
    admin_controller.define_singleton_method(:_layout) { 'application' }
    admin_controller.define_singleton_method(:_helpers) { admin_helper_chain }
  end

  def helper_chain(*modules)
    Module.new.tap do |chain|
      chain.define_singleton_method(:ancestors) { modules }
    end
  end
end
