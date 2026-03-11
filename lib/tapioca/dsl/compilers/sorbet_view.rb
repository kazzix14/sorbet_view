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
        end

        private

        # Generate a mapping of controller_path -> defined instance variables
        # Used by the compiler to declare undefined ivars as NilClass
        sig { params(controllers: T::Array[T.untyped]).void }
        def generate_ivar_mapping(controllers)
          config = ::SorbetView::Configuration.load
          mapping = T.let({}, T::Hash[String, T::Array[String]])

          controllers.each do |controller|
            path = controller.controller_path
            ivars = extract_defined_ivars(controller)
            mapping[path] = ivars unless ivars.empty?
          end

          mapping_path = File.join(config.output_dir, '.defined_ivars.json')
          FileUtils.mkdir_p(File.dirname(mapping_path))
          File.write(mapping_path, JSON.pretty_generate(mapping))
        rescue StandardError
          # Non-critical: if mapping fails, all ivars default to NilClass
        end

        # Extract instance variables assigned in the controller source
        sig { params(controller: T.untyped).returns(T::Array[String]) }
        def extract_defined_ivars(controller)
          source_file = "app/controllers/#{controller.controller_path}_controller.rb"
          return [] unless File.exist?(source_file)

          source = File.read(source_file)
          source.scan(/(?<!@)@([a-zA-Z_]\w*)\s*(?:=|\|\|=)/).map { |m| "@#{m[0]}" }.uniq.sort
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
