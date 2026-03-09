# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'sorbet_view/version'
require_relative 'sorbet_view/configuration'
require_relative 'sorbet_view/source_map/position'
require_relative 'sorbet_view/source_map/range'
require_relative 'sorbet_view/source_map/mapping_entry'
require_relative 'sorbet_view/source_map/source_map'
require_relative 'sorbet_view/compiler/ruby_segment'
require_relative 'sorbet_view/compiler/parser_adapter'
require_relative 'sorbet_view/compiler/adapters/erb_adapter'
require_relative 'sorbet_view/compiler/template_context'
require_relative 'sorbet_view/compiler/ruby_generator'
require_relative 'sorbet_view/compiler/template_compiler'
require_relative 'sorbet_view/file_system/output_manager'
require_relative 'sorbet_view/file_system/project_scanner'
require_relative 'sorbet_view/file_system/file_watcher'
require_relative 'sorbet_view/lsp/transport'
require_relative 'sorbet_view/lsp/uri_mapper'
require_relative 'sorbet_view/lsp/document_store'
require_relative 'sorbet_view/lsp/position_translator'
require_relative 'sorbet_view/lsp/sorbet_process'
require_relative 'sorbet_view/lsp/server'
require_relative 'sorbet_view/cli/runner'

module SorbetView
  extend T::Sig

  CONFIG_FILE_NAME = '.sorbet_view.yml'
end
