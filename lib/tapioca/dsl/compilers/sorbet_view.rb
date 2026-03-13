# typed: true
# frozen_string_literal: true

return unless defined?(Tapioca::Dsl::Compiler)

require 'srb_lens'
require 'json'

module Tapioca
  module Dsl
    module Compilers
      class SorbetView < Compiler
        extend T::Sig

        ConstantType = type_member { { fixed: T.class_of(::SorbetView) } }

        class << self
          extend T::Sig

          sig { override.returns(T::Enumerable[Module]) }
          def gather_constants
            [::SorbetView]
          end
        end

        sig { override.void }
        def decorate
          @module_cache = T.let({}, T::Hash[String, RBI::Scope])
          @project = T.let(SrbLens::Project.load_or_index(Dir.pwd), T.untyped)

          controllers = ObjectSpace.each_object(Class).select do |klass|
            klass < ::ActionController::Base && !klass.abstract?
          rescue StandardError
            false
          end

          controllers.each do |controller|
            process_controller(controller)
          end

          generate_ivar_mapping(controllers)
          process_components
          compile_all_templates
        end

        private

        # Generate a mapping of template_path -> { ivar => type }
        # Used by the compiler to declare ivars with proper types
        sig { params(controllers: T::Array[T.untyped]).void }
        def generate_ivar_mapping(controllers)
          config = ::SorbetView::Configuration.load
          mapping = T.let({}, T::Hash[String, T::Hash[String, String]])

          # Get view directories from Rails (e.g. ["app/views"])
          view_dirs = resolve_view_dirs

          controllers.each do |controller|
            path = controller.controller_path

            controller.action_methods.each do |action_name|
              next unless action_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

              action_ivars = extract_ivars_from_srb_lens(controller, action_name.to_s)
              next if action_ivars.empty?

              # Template-path keys: "app/views/posts/show" => { "@post" => "Post" }
              view_dirs.each do |vd|
                template_key = File.join(vd, path, action_name.to_s)
                existing = mapping[template_key]
                if existing
                  # Multiple actions render the same template: narrow to intersection
                  mapping[template_key] = intersect_ivars(existing, action_ivars)
                else
                  mapping[template_key] = action_ivars
                end
              end
            end
          end

          mapping_path = File.join(config.output_dir, '.defined_ivars.json')
          FileUtils.mkdir_p(File.dirname(mapping_path))
          File.write(mapping_path, JSON.pretty_generate(mapping))
        rescue StandardError => e
          $stderr.puts "[SorbetView] generate_ivar_mapping failed: #{e.class}: #{e.message}"
          $stderr.puts e.backtrace&.first(5)&.join("\n")
        end

        # Resolve view directories from Rails, relative to project root
        # Only include directories within the project (exclude gem paths)
        sig { returns(T::Array[String]) }
        def resolve_view_dirs
          if defined?(::ActionController::Base) && ::ActionController::Base.respond_to?(:view_paths)
            cwd = Dir.pwd
            ::ActionController::Base.view_paths.paths.filter_map do |p|
              path_str = p.to_s
              next unless path_str.start_with?(cwd)

              relative = path_str.sub(%r{^#{Regexp.escape(cwd)}/?}, '')
              relative unless relative.empty?
            end
          else
            ['app/views']
          end
        rescue StandardError
          ['app/views']
        end

        # Intersect two ivar mappings: keep only ivars present in both, narrow types with T.all
        sig { params(a: T::Hash[String, String], b: T::Hash[String, String]).returns(T::Hash[String, String]) }
        def intersect_ivars(a, b)
          common_keys = a.keys & b.keys
          result = T.let({}, T::Hash[String, String])
          common_keys.each do |key|
            type_a = T.must(a[key])
            type_b = T.must(b[key])
            result[key] = if type_a == type_b
              type_a
            else
              "T.all(#{type_a}, #{type_b})"
            end
          end
          result
        end

        # Extract instance variables and their types from srb-lens for a controller action
        sig { params(controller: T.untyped, action_name: String).returns(T::Hash[String, String]) }
        def extract_ivars_from_srb_lens(controller, action_name)
          methods = @project.find_methods("#{controller.name}##{action_name}")
          method_info = methods&.first
          return {} unless method_info

          ivars = method_info.ivars
          return {} if ivars.nil? || ivars.empty?

          result = T.let({}, T::Hash[String, String])
          ivars.each do |ivar|
            name = ivar.name
            type = ivar.type
            next if name.nil? || name.empty?
            next if type.nil? || type.empty?

            result[name] = normalize_type(type)
          end
          result
        end

        # Compile all templates after generating ivar mapping
        sig { void }
        def compile_all_templates
          config = ::SorbetView::Configuration.load
          compiler = ::SorbetView::Compiler::TemplateCompiler.new(config: config)
          output_manager = ::SorbetView::FileSystem::OutputManager.new(config.output_dir)
          compiled_ruby_paths = Set.new

          templates = ::SorbetView::FileSystem::ProjectScanner.scan(config)
          templates.each do |path|
            result = compiler.compile_file(path)
            output_manager.write(result)
            compiled_ruby_paths << result.source_map.ruby_path
          end

          component_compiler = ::SorbetView::Compiler::ComponentCompiler.new(config: config)
          components = ::SorbetView::FileSystem::ProjectScanner.scan_components(config)
          components.each do |path|
            results = component_compiler.compile_file(path)
            results.each do |result|
              output_manager.write(result)
              compiled_ruby_paths << result.source_map.ruby_path
            end
          end

          # Clean stale compiled files
          Dir.glob(File.join(config.output_dir, '**', '*.rb')).each do |f|
            File.delete(f) unless compiled_ruby_paths.include?(f)
          end
        rescue StandardError => e
          $stderr.puts "[SorbetView] compile_all_templates failed: #{e.class}: #{e.message}"
        end

        sig { void }
        def process_components
          config = ::SorbetView::Configuration.load
          return if config.component_dirs.empty?

          component_files = ::SorbetView::FileSystem::ProjectScanner.scan_components(config)

          component_files.each do |path|
            source = File.read(path)
            extractions = ::SorbetView::Compiler::HeredocExtractor.extract(source, path)
            next if extractions.empty?

            class_name = T.must(extractions.first).class_name
            next if class_name.empty?

            begin
              klass = Object.const_get(class_name)
            rescue NameError
              next
            end

            generate_component_rbi(klass, class_name)
          end
        rescue StandardError
          # Configuration may not be available in all environments
        end

        sig { params(klass: T.untyped, class_name: String).void }
        def generate_component_rbi(klass, class_name)
          methods = klass.instance_methods(false)

          method_sigs = methods.filter_map do |method_name|
            method_name_s = method_name.to_s
            next unless method_name_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)

            method_info = find_method_info(klass, method_name_s)
            next unless method_info

            return_type = method_info&.return_type || ''
            next if return_type.empty? || return_type == 'T.untyped'

            params = build_params_from_srb_lens(method_info)
            [method_name_s, params, return_type]
          end

          return if method_sigs.empty?

          create_class_from_path(class_name) do |klass_rbi|
            method_sigs.each do |method_name, params, return_type|
              klass_rbi.create_method(method_name, parameters: params, return_type: return_type)
            end
          end
        end

        sig { params(controller: T.untyped).void }
        def process_controller(controller)
          helper_methods = extract_helper_methods(controller)
          return if helper_methods.empty?

          path = controller.controller_path
          parts = path.split('/').map { |p| camelize(p) }

          # 1) module SorbetView::Helpers::<controller_path> with helper methods
          helper_module_name = "SorbetView::Helpers::#{parts.join('::')}"
          create_module_from_path(helper_module_name) do |mod|
            helper_methods.each do |method_name, params, return_type|
              mod.create_method(method_name, parameters: params, return_type: return_type)
            end
          end

          # 2) Each action's template class includes the helper module
          actions = controller.action_methods.to_a
          actions.each do |action_name|
            next unless action_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

            class_name = "SorbetView::Generated::#{parts.join('::')}::#{camelize(action_name)}"
            create_class_from_path(class_name) do |klass|
              klass.create_include(helper_module_name)
            end
          end
        end

        # Returns [[method_name, params, return_type], ...]
        sig { params(controller: T.untyped).returns(T::Array[T.untyped]) }
        def extract_helper_methods(controller)
          return [] unless controller.respond_to?(:_helper_methods)

          controller._helper_methods.filter_map do |name|
            name_s = name.to_s
            next unless name_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)

            method_info = find_method_info(controller, name_s)
            params = if method_info
              build_params_from_srb_lens(method_info)
            else
              build_params_from_reflection(controller, name_s)
            end
            return_type = method_info&.return_type || 'T.untyped'
            return_type = 'T.untyped' if return_type.empty?

            [name_s, params, return_type]
          end
        end

        sig { params(controller: T.untyped, method_name: String).returns(T.untyped) }
        def find_method_info(controller, method_name)
          methods = @project.find_methods("#{controller.name}##{method_name}")
          methods&.first
        end

        sig { params(method_info: T.untyped).returns(T::Array[RBI::Param]) }
        def build_params_from_srb_lens(method_info)
          method_info.arguments.filter_map do |arg|
            name = arg.name.gsub(/\A[&*]+/, '') # strip *, **, & prefixes
            type = arg.type || 'T.untyped'
            type = 'T.untyped' if type.empty?

            case arg.kind
            when 'req' then create_param(name, type: type)
            when 'opt' then create_opt_param(name, type: type, default: 'T.unsafe(nil)')
            when 'rest' then create_rest_param(name.empty? ? 'args' : name, type: type)
            when 'key_req', 'keyreq' then create_kw_param(name, type: type)
            when 'key' then create_kw_opt_param(name, type: type, default: 'T.unsafe(nil)')
            when 'key_rest', 'keyrest' then create_kw_rest_param(name.empty? ? 'kwargs' : name, type: type)
            when 'block' then create_block_param(name.empty? ? 'blk' : name, type: type)
            end
          end
        end

        sig { params(controller: T.untyped, method_name: String).returns(T::Array[RBI::Param]) }
        def build_params_from_reflection(controller, method_name)
          method_obj = controller.instance_method(method_name)
          method_obj.parameters.filter_map do |type, name|
            param_name = name ? name.to_s.gsub(/\A[&*]+/, '') : nil
            case type
            when :req then create_param(param_name || 'arg', type: 'T.untyped')
            when :opt then create_opt_param(param_name || 'arg', type: 'T.untyped', default: 'T.unsafe(nil)')
            when :rest then create_rest_param(param_name.nil? || param_name.empty? ? 'args' : param_name, type: 'T.untyped')
            when :keyreq then create_kw_param(param_name || 'arg', type: 'T.untyped')
            when :key then create_kw_opt_param(param_name || 'arg', type: 'T.untyped', default: 'T.unsafe(nil)')
            when :keyrest then create_kw_rest_param(param_name.nil? || param_name.empty? ? 'kwargs' : param_name, type: 'T.untyped')
            when :block then create_block_param(param_name.nil? || param_name.empty? ? 'blk' : param_name, type: 'T.untyped')
            end
          end
        rescue NameError
          []
        end

        # Normalize Sorbet literal types to their base types
        # e.g. String("test") → String, Integer(42) → Integer, Symbol(:foo) → Symbol
        sig { params(type: String).returns(String) }
        def normalize_type(type)
          type.gsub(/\b([A-Z]\w*)\(.*?\)/) { $1 }
        end

        sig { params(str: String).returns(String) }
        def camelize(str)
          str.split('_').map(&:capitalize).join
        end

        sig { params(class_name: String, block: T.proc.params(klass: T.untyped).void).void }
        def create_class_from_path(class_name, &block)
          parts = class_name.split('::')
          current = resolve_module_path(parts[0..-2])
          current.create_class(T.must(parts.last), &block)
        end

        sig { params(module_name: String, block: T.proc.params(mod: T.untyped).void).void }
        def create_module_from_path(module_name, &block)
          parts = module_name.split('::')
          current = resolve_module_path(parts[0..-2])
          mod = current.create_module(T.must(parts.last))
          block.call(mod)
        end

        sig { params(parts: T::Array[String]).returns(RBI::Scope) }
        def resolve_module_path(parts)
          current = root
          path_so_far = +''

          parts.each do |part|
            path_so_far = path_so_far.empty? ? part : "#{path_so_far}::#{part}"
            if T.must(@module_cache).key?(path_so_far)
              current = T.must(T.must(@module_cache)[path_so_far])
            else
              current = current.create_module(part)
              T.must(@module_cache)[path_so_far] = current
            end
          end

          current
        end
      end
    end
  end
end
