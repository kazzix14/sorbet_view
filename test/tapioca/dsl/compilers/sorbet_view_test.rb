# typed: true
# frozen_string_literal: true

require 'test_helper'

module RBI
  class Scope; end
  class Param; end
end

module Tapioca
  module Dsl
    class Compiler
      def self.type_member(*)
        Object.new
      end
    end
  end
end

require File.expand_path('../../../../lib/tapioca/dsl/compilers/sorbet_view', __dir__)

class TapiocaSorbetViewCompilerTest < Minitest::Test
  class FakeRbiClass
    attr_reader :includes

    def initialize
      @includes = []
    end

    def create_include(include_name)
      @includes << include_name
    end
  end

  FakeMethodInfo = Struct.new(:fqn, :ivars)
  FakeIvar = Struct.new(:name, :type)
  FakeController = Struct.new(:name)

  # Emulates srb-lens name resolution: a query like "FoosController#show" returns every
  # method whose FQN ends with it, in index order; when nothing matches directly, methods
  # found on ancestor classes are returned instead (their FQN does not match the query).
  class FakeProject
    def initialize(methods, inherited: [])
      @methods = methods
      @inherited = inherited
    end

    def find_methods(query)
      direct = @methods.select { |m| m.fqn.end_with?(query) }
      direct.empty? ? @inherited : direct
    end
  end

  def setup
    @compiler = Tapioca::Dsl::Compilers::SorbetView.allocate
  end

  def test_find_method_info_prefers_exact_fqn_match_over_suffix_match
    namespaced = FakeMethodInfo.new('Admin::FoosController#show', [])
    exact = FakeMethodInfo.new('FoosController#show', [])
    @compiler.instance_variable_set(:@project, FakeProject.new([namespaced, exact]))

    result = @compiler.send(:find_method_info, FakeController.new('FoosController'), 'show')

    assert_same exact, result
  end

  def test_find_method_info_falls_back_to_first_match_when_no_exact_match
    inherited = FakeMethodInfo.new('BaseController#show', [])
    @compiler.instance_variable_set(:@project, FakeProject.new([], inherited: [inherited]))

    result = @compiler.send(:find_method_info, FakeController.new('FoosController'), 'show')

    assert_same inherited, result
  end

  def test_find_method_info_keeps_first_match_for_anonymous_controllers
    namespaced = FakeMethodInfo.new('Admin::FoosController#show', [])
    other = FakeMethodInfo.new('FoosController#show', [])
    @compiler.instance_variable_set(:@project, FakeProject.new([namespaced, other]))

    result = @compiler.send(:find_method_info, FakeController.new(nil), 'show')

    assert_same namespaced, result
  end

  def test_extract_ivars_from_srb_lens_uses_ivars_from_exact_fqn_match
    namespaced = FakeMethodInfo.new(
      'Admin::FoosController#show',
      [FakeIvar.new('@bars', 'T.nilable(T::Array[Bar])')]
    )
    exact = FakeMethodInfo.new(
      'FoosController#show',
      [FakeIvar.new('@foo', 'T.nilable(Foo)')]
    )
    @compiler.instance_variable_set(:@project, FakeProject.new([namespaced, exact]))

    result = @compiler.send(:extract_ivars_from_srb_lens, FakeController.new('FoosController'), 'show')

    assert_equal({ '@foo' => 'T.nilable(Foo)' }, result)
  end

  def test_merge_layout_include_lines_sorts_contributors_and_deduplicates_includes
    contributions = [
      {
        controller_name: 'ZController',
        helper_module_name: 'SorbetView::Helpers::Z',
        controller_helper_modules: ['SharedHelper', 'ZHelper']
      },
      {
        controller_name: 'AController',
        helper_module_name: 'SorbetView::Helpers::A',
        controller_helper_modules: ['SharedHelper', 'AHelper']
      }
    ]

    assert_equal(
      [
        'SorbetView::Helpers::A',
        '::SharedHelper',
        '::AHelper',
        'SorbetView::Helpers::Z',
        '::ZHelper'
      ],
      @compiler.send(:merge_layout_include_lines, contributions)
    )
  end

  def test_emit_merged_layout_includes_creates_layout_class_with_merged_includes
    emitted_classes = {}
    @compiler.define_singleton_method(:create_class_from_path) do |class_name, &block|
      klass = FakeRbiClass.new
      emitted_classes[class_name] = klass
      block.call(klass)
    end

    @compiler.instance_variable_set(
      :@layout_contributions,
      {
        'SorbetView::Generated::Layouts::Application::Html' => [
          {
            controller_name: 'UsersController',
            helper_module_name: 'SorbetView::Helpers::Users',
            controller_helper_modules: ['UsersHelper', 'SharedHelper']
          },
          {
            controller_name: 'AdminController',
            helper_module_name: 'SorbetView::Helpers::Admin',
            controller_helper_modules: ['AdminHelper', 'SharedHelper']
          }
        ]
      }
    )

    @compiler.send(:emit_merged_layout_includes)

    layout_class = emitted_classes['SorbetView::Generated::Layouts::Application::Html']
    refute_nil layout_class
    assert_equal(
      [
        'SorbetView::Helpers::Admin',
        '::AdminHelper',
        '::SharedHelper',
        'SorbetView::Helpers::Users',
        '::UsersHelper'
      ],
      layout_class.includes
    )
  end
end
