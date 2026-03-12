# typed: strict
# frozen_string_literal: true

require 'logger'
require 'set'

module SorbetView
  module Lsp
    class Server
      extend T::Sig

      sig { params(input: IO, output: IO, sorbet_args: T::Array[String]).void }
      def initialize(input: $stdin, output: $stdout, sorbet_args: [])
        @config = T.let(Configuration.load, Configuration)
        @sorbet_args = T.let(sorbet_args, T::Array[String])
        @logger = T.let(Logger.new(File.open('sorbet_view_lsp.log', 'a')), Logger)
        @transport = T.let(Transport.new(input: input, output: output), Transport)
        @document_store = T.let(DocumentStore.new, DocumentStore)
        @uri_mapper = T.let(UriMapper.new(config: @config), UriMapper)
        @position_translator = T.let(PositionTranslator.new, PositionTranslator)
        @compiler = T.let(Compiler::TemplateCompiler.new(config: @config), Compiler::TemplateCompiler)
        @component_compiler = T.let(Compiler::ComponentCompiler.new(config: @config), Compiler::ComponentCompiler)
        @output_manager = T.let(FileSystem::OutputManager.new(@config.output_dir), FileSystem::OutputManager)
        @sorbet = T.let(SorbetProcess.new(config: @config, logger: @logger), SorbetProcess)
        @file_watcher = T.let(nil, T.nilable(FileSystem::FileWatcher))
        @initialized = T.let(false, T::Boolean)
        @shutdown = T.let(false, T::Boolean)
        @sorbet_open_uris = T.let(Set.new, T::Set[String])
        @component_version = T.let(0, Integer)
      end

      sig { void }
      def start
        @logger.info('SorbetView LSP server starting')

        loop do
          message = @transport.read_message
          break if message.nil?

          handle_message(message)
          break if @shutdown
        end
      rescue => e
        @logger.error("Server error: #{e.message}\n#{e.backtrace&.join("\n")}")
      ensure
        @file_watcher&.stop
        @sorbet.stop
        @logger.info('SorbetView LSP server stopped')
      end

      private

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_message(message)
        method_name = message['method']
        id = message['id']

        @logger.debug("Received: #{method_name || 'response'} (id=#{id})")

        case method_name
        when 'initialize'
          handle_initialize(message)
        when 'initialized'
          handle_initialized(message)
        when 'shutdown'
          handle_shutdown(message)
        when 'exit'
          @shutdown = true
        when 'textDocument/didOpen'
          handle_did_open(message)
        when 'textDocument/didChange'
          handle_did_change(message)
        when 'textDocument/didClose'
          handle_did_close(message)
        when 'textDocument/didSave'
          handle_did_save(message)
        when 'textDocument/hover'
          handle_proxied_request(message)
        when 'textDocument/completion'
          handle_proxied_request(message)
        when 'textDocument/definition'
          handle_proxied_request(message)
        when 'textDocument/references'
          handle_proxied_request(message)
        when 'textDocument/signatureHelp'
          handle_proxied_request(message)
        else
          # Pass through to Sorbet for anything else
          forward_to_sorbet(message)
        end
      rescue => e
        @logger.error("Error handling #{message['method']}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        @transport.send_error(message['id'], -32603, e.message) if message['id']
      end

      # --- Lifecycle ---

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_initialize(message)
        # Compile all templates first
        compile_all_templates

        # Start Sorbet LSP
        @sorbet.start(extra_args: @sorbet_args)

        # Register handler for diagnostics from Sorbet
        @sorbet.on_notification('textDocument/publishDiagnostics') do |msg|
          handle_sorbet_diagnostics(msg)
        end

        # Forward initialize to Sorbet and merge capabilities
        sorbet_result = @sorbet.send_request('initialize', message['params'])

        capabilities = sorbet_result&.dig('result', 'capabilities') || {}

        # Respond with merged capabilities
        @transport.send_response(message['id'], {
          'capabilities' => capabilities.merge({
            'textDocumentSync' => {
              'openClose' => true,
              'change' => 1, # Full sync
              'save' => { 'includeText' => true }
            }
          })
        })
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_initialized(message)
        @initialized = true
        @sorbet.send_notification('initialized', {})
        start_file_watcher
        @logger.info('SorbetView LSP initialized')
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_shutdown(message)
        @sorbet.send_request('shutdown', nil)
        @transport.send_response(message['id'], nil)
      end

      # --- Document Sync ---

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_did_open(message)
        params = message['params']
        td = params['textDocument']
        uri = td['uri']
        text = td['text']
        version = td['version'] || 0

        if @uri_mapper.template_uri?(uri)
          doc = @document_store.open(uri, text, version)
          compile_and_sync(doc)
        else
          # Forward .rb files to Sorbet; also recompile if they contain erb_template
          forward_to_sorbet(message)
          compile_component_if_needed(uri, text)
          recompile_templates_for_controller(uri)
        end
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_did_change(message)
        params = message['params']
        uri = params['textDocument']['uri']
        version = params['textDocument']['version'] || 0

        if @uri_mapper.template_uri?(uri)
          # Full sync: take the last content change
          changes = params['contentChanges']
          text = changes&.last&.fetch('text', '')
          doc = @document_store.change(uri, text, version)
          compile_and_sync(doc) if doc
        else
          forward_to_sorbet(message)
          changes = params['contentChanges']
          text = changes&.last&.fetch('text', nil)
          compile_component_if_needed(uri, text) if text
          recompile_templates_for_controller(uri)
        end
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_did_close(message)
        uri = message.dig('params', 'textDocument', 'uri')

        if @uri_mapper.template_uri?(uri)
          @document_store.close(uri)
          template_path = @uri_mapper.uri_to_path(uri)
          @position_translator.unregister(template_path)
        else
          forward_to_sorbet(message)
        end
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_did_save(message)
        uri = message.dig('params', 'textDocument', 'uri')
        text = message.dig('params', 'text')

        if @uri_mapper.template_uri?(uri)
          doc = @document_store.get(uri)
          compile_and_sync(doc) if doc
        else
          compile_component_if_needed(uri, text)
          recompile_templates_for_controller(uri)
        end
      end

      # --- Proxied Requests (hover, completion, definition, etc.) ---

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_proxied_request(message)
        params = message['params']
        uri = params.dig('textDocument', 'uri')

        if @uri_mapper.template_uri?(uri)
          handle_template_proxied_request(message, uri)
        elsif try_handle_component_proxied_request(message, uri)
          # Handled as component heredoc
        else
          forward_to_sorbet(message)
        end
      end

      sig { params(message: T::Hash[String, T.untyped], uri: String).void }
      def handle_template_proxied_request(message, uri)
        Perf.measure("lsp.proxy.#{message['method']}") do
          params = message['params']
          template_path = @uri_mapper.uri_to_path(uri)
          ruby_uri = @uri_mapper.template_to_ruby_uri(uri)
          position = params['position']

          # Translate position from template to Ruby
          ruby_position = @position_translator.template_to_ruby(template_path, position)
          unless ruby_position
            # Cursor is in HTML, not Ruby code
            @transport.send_response(message['id'], nil)
            next
          end

          # Rewrite request for Sorbet
          rewritten = message.dup
          rewritten['params'] = params.merge({
            'textDocument' => { 'uri' => ruby_uri },
            'position' => ruby_position
          })

          # Forward to Sorbet
          result = Perf.measure('lsp.sorbet_roundtrip') do
            @sorbet.send_request(message['method'], rewritten['params'])
          end
          sorbet_result = result&.fetch('result', nil)

          # Translate response back to template coordinates
          translated = translate_result(message['method'], template_path, uri, sorbet_result)
          @transport.send_response(message['id'], translated)
        end
      end

      # Try to handle a proxied request for a .rb component with erb_template heredoc.
      # Returns true if handled, false if not a component or cursor is outside heredoc.
      sig { params(message: T::Hash[String, T.untyped], uri: String).returns(T::Boolean) }
      def try_handle_component_proxied_request(message, uri)
        path = @uri_mapper.uri_to_path(uri)
        @logger.debug("try_handle_component: path=#{path} end_with_rb=#{path.end_with?('.rb')}")
        return false unless path.end_with?('.rb')

        # Check if we have a source map registered for this component
        sm = @position_translator.source_map_for(path)
        @logger.debug("try_handle_component: source_map=#{sm ? 'found' : 'nil'} registered_keys=#{@position_translator.registered_paths.inspect}")
        return false unless sm

        params = message['params']
        position = params['position']

        # Try translating — returns nil if cursor is outside heredoc Ruby code
        ruby_position = @position_translator.template_to_ruby(path, position)
        @logger.debug("try_handle_component: position=#{position.inspect} -> ruby_position=#{ruby_position.inspect}")
        return false unless ruby_position

        ruby_uri = @uri_mapper.component_to_ruby_uri(uri)

        # Rewrite request for the generated __erb_template.rb
        rewritten = message.dup
        rewritten['params'] = params.merge({
          'textDocument' => { 'uri' => ruby_uri },
          'position' => ruby_position
        })

        # Forward to Sorbet
        result = @sorbet.send_request(message['method'], rewritten['params'])
        sorbet_result = result&.fetch('result', nil)

        # Translate response back to .rb file coordinates
        translated = translate_result(message['method'], path, uri, sorbet_result)
        @transport.send_response(message['id'], translated)
        true
      end

      # --- Sorbet Diagnostics ---

      sig { params(message: T::Hash[String, T.untyped]).void }
      def handle_sorbet_diagnostics(message)
        params = message['params']
        uri = params['uri']

        # Check if this is a generated Ruby file
        template_uri = @uri_mapper.ruby_to_template_uri(uri)
        @logger.debug("Diagnostics for #{uri} -> template_uri=#{template_uri.inspect}")
        unless template_uri
          # Not a generated file, pass through
          @transport.send_notification('textDocument/publishDiagnostics', params)
          return
        end

        template_path = @uri_mapper.uri_to_path(template_uri)
        raw_diags = params['diagnostics'] || []
        @logger.debug("#{raw_diags.length} raw diagnostics for #{template_path}")

        # Translate each diagnostic's range back to template coordinates
        translated_diagnostics = raw_diags.filter_map do |diag|
          range = diag['range']
          next nil unless range

          template_range = @position_translator.ruby_range_to_template(template_path, range)
          @logger.debug("  diag ruby=#{range.inspect} -> template=#{template_range.inspect}")
          next nil unless template_range # Skip diagnostics in boilerplate

          diag.merge(
            'range' => template_range,
            'source' => 'sorbet_view'
          )
        end

        @logger.debug("Sending #{translated_diagnostics.length} translated diagnostics to #{template_uri}")
        @transport.send_notification('textDocument/publishDiagnostics', {
          'uri' => template_uri,
          'diagnostics' => translated_diagnostics
        })
      end

      # --- Result Translation ---

      sig do
        params(
          method_name: String,
          template_path: String,
          template_uri: String,
          result: T.untyped
        ).returns(T.untyped)
      end
      def translate_result(method_name, template_path, template_uri, result)
        return nil if result.nil?

        case method_name
        when 'textDocument/hover'
          translate_hover(template_path, result)
        when 'textDocument/completion'
          translate_completion(template_path, result)
        when 'textDocument/definition', 'textDocument/references'
          translate_locations(template_path, template_uri, result)
        else
          result
        end
      end

      sig { params(template_path: String, result: T::Hash[String, T.untyped]).returns(T.untyped) }
      def translate_hover(template_path, result)
        return result unless result.is_a?(Hash) && result['range']

        range = @position_translator.ruby_range_to_template(template_path, result['range'])
        return result unless range

        result.merge('range' => range)
      end

      sig { params(template_path: String, result: T.untyped).returns(T.untyped) }
      def translate_completion(template_path, result)
        return result unless result.is_a?(Hash)

        items = result['items'] || result
        return result unless items.is_a?(Array)

        translated_items = items.map do |item|
          if item.is_a?(Hash) && item.dig('textEdit', 'range')
            range = @position_translator.ruby_range_to_template(template_path, item['textEdit']['range'])
            if range
              item.merge('textEdit' => item['textEdit'].merge('range' => range))
            else
              item
            end
          else
            item
          end
        end

        if result.is_a?(Hash) && result.key?('items')
          result.merge('items' => translated_items)
        else
          translated_items
        end
      end

      sig { params(template_path: String, template_uri: String, result: T.untyped).returns(T.untyped) }
      def translate_locations(template_path, template_uri, result)
        return result unless result.is_a?(Array)

        result.filter_map do |loc|
          next loc unless loc.is_a?(Hash)

          loc_uri = loc['uri'] || loc.dig('targetUri')
          target_template_uri = @uri_mapper.ruby_to_template_uri(loc_uri)

          if target_template_uri
            # Location points to a generated file, translate back
            target_path = @uri_mapper.uri_to_path(target_template_uri)
            range_key = loc.key?('targetRange') ? 'targetRange' : 'range'
            range = loc[range_key]
            translated_range = @position_translator.ruby_range_to_template(target_path, range)
            next nil unless translated_range

            uri_key = loc.key?('targetUri') ? 'targetUri' : 'uri'
            loc.merge(uri_key => target_template_uri, range_key => translated_range)
          else
            loc
          end
        end
      end

      # --- Compilation ---

      sig { params(doc: Document).void }
      def compile_and_sync(doc)
        Perf.measure('lsp.compile_and_sync') do
        template_path = @uri_mapper.uri_to_path(doc.uri)
        result = @compiler.compile(template_path, doc.content)
        doc.compile_result = result

        # Write generated .rb to disk
        @output_manager.write(result)

        # Register source map
        @position_translator.register(template_path, result.source_map)

        # Notify Sorbet about the changed .rb file
        ruby_uri = @uri_mapper.template_to_ruby_uri(doc.uri)
        if @sorbet_open_uris.include?(ruby_uri)
          @sorbet.send_notification('textDocument/didChange', {
            'textDocument' => { 'uri' => ruby_uri, 'version' => doc.version },
            'contentChanges' => [{ 'text' => result.ruby_source }]
          })
        else
          @sorbet.send_notification('textDocument/didOpen', {
            'textDocument' => {
              'uri' => ruby_uri,
              'languageId' => 'ruby',
              'version' => doc.version,
              'text' => result.ruby_source
            }
          })
          @sorbet_open_uris.add(ruby_uri)
        end
        end # Perf.measure
      end

      sig { params(uri: String, text: T.nilable(String)).void }
      def compile_component_if_needed(uri, text)
        path = @uri_mapper.uri_to_path(uri)
        return unless path.end_with?('.rb')

        source = if text
          text
        else
          # Try mapped path first, then original URI path
          if File.exist?(path)
            File.read(path)
          else
            raw_path = URI.decode_www_form_component(URI.parse(uri).path || '')
            unless File.exist?(raw_path)
              @logger.debug("compile_component: file not found at #{path} or #{raw_path}")
              return
            end
            File.read(raw_path)
          end
        end

        unless Compiler::HeredocExtractor.contains_erb_template?(source)
          return
        end

        @logger.debug("compile_component: compiling #{path}")
        results = @component_compiler.compile(path, source)
        results.each do |result|
          @output_manager.write(result)
          @position_translator.register(path, result.source_map)

          @component_version += 1
          ruby_uri = @uri_mapper.path_to_uri(result.source_map.ruby_path)
          if @sorbet_open_uris.include?(ruby_uri)
            @sorbet.send_notification('textDocument/didChange', {
              'textDocument' => { 'uri' => ruby_uri, 'version' => @component_version },
              'contentChanges' => [{ 'text' => result.ruby_source }]
            })
          else
            @sorbet.send_notification('textDocument/didOpen', {
              'textDocument' => {
                'uri' => ruby_uri,
                'languageId' => 'ruby',
                'version' => @component_version,
                'text' => result.ruby_source
              }
            })
            @sorbet_open_uris.add(ruby_uri)
          end
        end
      end

      sig { void }
      def compile_all_templates
        Perf.reset!
        templates = FileSystem::ProjectScanner.scan(@config)
        @logger.info("Compiling #{templates.length} templates")

        Perf.measure('lsp.compile_all_templates') do
          templates.each do |path|
            source = File.read(path)
            result = @compiler.compile(path, source)

            next if result.source_map.entries.empty? && @config.skip_missing_locals && requires_locals?(path)

            @output_manager.write(result)
            @position_translator.register(path, result.source_map)
          end
        end

        compile_all_components
        Perf.report_to_logger(@logger)
      end

      sig { void }
      def compile_all_components
        components = FileSystem::ProjectScanner.scan_components(@config)
        @logger.info("Compiling #{components.length} component(s) with erb_template")

        components.each do |path|
          results = @component_compiler.compile_file(path)
          results.each do |result|
            @output_manager.write(result)
            @position_translator.register(path, result.source_map)
          end
        end
      end

      sig { params(path: String).returns(T::Boolean) }
      def requires_locals?(path)
        basename = File.basename(path)
        basename.start_with?('_') || basename.end_with?('.turbo_stream.erb')
      end

      # --- File Watching ---

      sig { void }
      def start_file_watcher
        @file_watcher = FileSystem::FileWatcher.new(config: @config) do |modified, added, removed|
          handle_file_changes(modified, added, removed)
        end
        @file_watcher.start
        @logger.info("FileWatcher started for: #{@config.input_dirs.join(', ')}")
      rescue => e
        @logger.warn("Failed to start FileWatcher: #{e.message}")
      end

      sig { params(modified: T::Array[String], added: T::Array[String], removed: T::Array[String]).void }
      def handle_file_changes(modified, added, removed)
        (modified + added).each do |path|
          # Skip files already open in the editor (editor manages those)
          template_uri = @uri_mapper.path_to_uri(path)
          next if @document_store.get(template_uri)

          @logger.debug("File changed on disk: #{path}")
          source = File.read(path)

          if path.end_with?('.rb')
            # Component .rb file — compile and notify Sorbet
            compile_component_if_needed(template_uri, source)
            recompile_templates_for_controller(template_uri)
          else
            result = @compiler.compile(path, source)
            next if result.source_map.entries.empty? && @config.skip_missing_locals && requires_locals?(path)

            @output_manager.write(result)
            @position_translator.register(path, result.source_map)
          end
        end

        removed.each do |path|
          @logger.debug("File removed: #{path}")
          @position_translator.unregister(path)
        end
      rescue => e
        @logger.error("FileWatcher callback error: #{e.message}")
      end

      # --- Controller → Template Recompilation ---

      sig { params(uri: String).void }
      def recompile_templates_for_controller(uri)
        path = @uri_mapper.uri_to_path(uri)
        return unless path.end_with?('_controller.rb')

        controller_relative = extract_controller_relative_path(path)
        return unless controller_relative

        @logger.debug("Controller changed: #{path} → recompiling templates for #{controller_relative}")
        @compiler.invalidate_ivar_cache!

        @config.input_dirs.each do |input_dir|
          view_dir = File.join(input_dir, controller_relative)
          next unless Dir.exist?(view_dir)

          Dir.glob(File.join(view_dir, '**', '*.erb')).each do |template_path|
            source = File.read(template_path)
            result = @compiler.compile(template_path, source)
            @output_manager.write(result)
            @position_translator.register(template_path, result.source_map)
            notify_sorbet_template_changed(template_path, result)
          end
        end
      rescue => e
        @logger.error("recompile_templates_for_controller error: #{e.message}")
      end

      sig { params(path: String).returns(T.nilable(String)) }
      def extract_controller_relative_path(path)
        match = path.match(%r{controllers/(.+)_controller\.rb\z})
        match ? match[1] : nil
      end

      sig { params(template_path: String, result: Compiler::CompileResult).void }
      def notify_sorbet_template_changed(template_path, result)
        ruby_uri = @uri_mapper.path_to_uri(result.source_map.ruby_path)
        if @sorbet_open_uris.include?(ruby_uri)
          @sorbet.send_notification('textDocument/didChange', {
            'textDocument' => { 'uri' => ruby_uri, 'version' => 0 },
            'contentChanges' => [{ 'text' => result.ruby_source }]
          })
        else
          @sorbet.send_notification('textDocument/didOpen', {
            'textDocument' => {
              'uri' => ruby_uri,
              'languageId' => 'ruby',
              'version' => 0,
              'text' => result.ruby_source
            }
          })
          @sorbet_open_uris.add(ruby_uri)
        end
      end

      sig { params(message: T::Hash[String, T.untyped]).void }
      def forward_to_sorbet(message)
        @sorbet.forward(message)
      end
    end
  end
end
