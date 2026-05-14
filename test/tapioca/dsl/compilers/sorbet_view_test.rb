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

  def setup
    @compiler = Tapioca::Dsl::Compilers::SorbetView.allocate
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
