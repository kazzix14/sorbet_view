# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class TemplateContext < T::Struct
      const :class_name, String
      const :superclass, T.nilable(String)
      const :includes, T::Array[String]
      const :template_path, String
      const :ruby_path, String

      extend T::Sig

      sig { returns(String) }
      def superclass_clause
        superclass ? " < #{superclass}" : ''
      end

      sig { params(component_path: String, class_name: String, config: Configuration).returns(TemplateContext) }
      def self.resolve_component(component_path, class_name, config)
        ruby_path = File.join(config.output_dir, "#{component_path}__erb_template.rb")
        new(
          class_name: class_name,
          superclass: nil,
          includes: [],
          template_path: component_path,
          ruby_path: ruby_path
        )
      end

      sig { params(template_path: String, config: Configuration).returns(TemplateContext) }
      def self.resolve(template_path, config)
        ruby_path = File.join(config.output_dir, "#{template_path}.rb")
        classification = classify(template_path, config)

        case classification
        when :mailer_view
          resolve_mailer_view(template_path, ruby_path, config)
        when :layout
          resolve_layout(template_path, ruby_path, config)
        when :partial
          resolve_partial(template_path, ruby_path, config)
        when :controller_view
          resolve_controller_view(template_path, ruby_path, config)
        else
          resolve_generic(template_path, ruby_path, config)
        end
      end

      class << self
        extend T::Sig

        private

        # Strip the matching input_dir prefix from a template path
        # "app/views/users/show.html.erb" → "users/show.html.erb"
        # "app/users/show.html.erb" (input_dirs: ['app/']) → "users/show.html.erb"
        sig { params(path: String, config: Configuration).returns(String) }
        def strip_input_dir(path, config)
          config.input_dirs.each do |dir|
            prefix = dir.end_with?('/') ? dir : "#{dir}/"
            if path.start_with?(prefix)
              relative = path.delete_prefix(prefix)
              # Also strip "views/" if the input_dir didn't include it
              # e.g. input_dirs: ['app/'] with path 'app/views/users/show.html.erb'
              relative = relative.delete_prefix('views/') if relative.start_with?('views/')
              return relative
            end
          end
          path
        end

        sig { params(path: String, config: Configuration).returns(Symbol) }
        def classify(path, config)
          basename = File.basename(path)
          relative = strip_input_dir(path, config)

          if path.include?('_mailer/') || path.include?('mailers/')
            :mailer_view
          elsif relative.start_with?('layouts/')
            :layout
          elsif basename.start_with?('_')
            :partial
          elsif relative != path
            # input_dir prefix was stripped → this is a view under input_dirs
            :controller_view
          else
            :generic
          end
        end

        sig { params(path: String, config: Configuration).returns(String) }
        def path_to_class_name(path, config)
          relative = strip_input_dir(path, config)
          filename = File.basename(relative)
          filename_parts = filename.split('.')

          basename = T.must(filename_parts.first)
          basename = basename.delete_prefix('_') # strip partial prefix

          # With 3+ parts (e.g. show.html.erb → [show, html, erb]), the last is the
          # template handler and the middle parts are format/variant extensions.
          # Nest them as sub-classes so show.html.erb and show.turbo_stream.erb
          # don't collide as the same class name.
          format_parts = filename_parts.length >= 3 ? T.must(filename_parts[1..-2]) : []

          dir = File.dirname(relative)

          parts = if dir == '.'
            [basename]
          else
            dir.split('/') + [basename]
          end

          parts += format_parts

          parts.map { |p| camelize(p) }.join('::')
        end

        sig { params(str: String).returns(String) }
        def camelize(str)
          str.split(/[_\-]/).map(&:capitalize).join
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_controller_view(path, ruby_path, config)
          helper_includes = resolve_runtime_helper_includes(path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              *helper_includes,
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_mailer_view(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              '::ActionMailer::Base',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_layout(path, ruby_path, config)
          helper_includes = resolve_runtime_helper_includes(path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              *helper_includes,
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_partial(path, ruby_path, config)
          helper_includes = resolve_runtime_helper_includes(path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: '::ActionView::Base',
            includes: [
              *helper_includes,
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_generic(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path, config)}",
            superclass: nil,
            includes: config.extra_includes,
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, config: Configuration).returns(T::Array[String]) }
        def resolve_runtime_helper_includes(path, config)
          return ['::ApplicationController::HelperMethods'] unless defined?(::ActionController::Base)

          relative = strip_input_dir(path, config)
          names = if relative.start_with?('layouts/')
            helper_modules_for_layout(relative)
          elsif File.basename(relative).start_with?('_')
            helper_modules_for_partial(relative)
          else
            helper_modules_for_controller_view(relative)
          end

          return ['::ApplicationController::HelperMethods'] if names.empty?

          names.map { |name| "::#{name}" }
        rescue StandardError
          ['::ApplicationController::HelperMethods']
        end

        sig { params(relative: String).returns(T::Array[String]) }
        def helper_modules_for_controller_view(relative)
          controller_path = File.dirname(relative)
          return [] if controller_path.nil? || controller_path.empty? || controller_path == '.'

          controller = find_controller_by_path(controller_path)
          helper_module_names_for(controller)
        end

        sig { params(relative: String).returns(T::Array[String]) }
        def helper_modules_for_layout(relative)
          filename = File.basename(relative)
          layout_name = T.must(filename.split('.').first).to_s
          return [] if layout_name.empty?

          all_concrete_controllers.flat_map do |controller|
            next [] unless controller.respond_to?(:_layout)
            next [] unless controller._layout == layout_name

            helper_module_names_for(controller)
          end.uniq.sort
        end

        sig { params(relative: String).returns(T::Array[String]) }
        def helper_modules_for_partial(relative)
          dir = File.dirname(relative)
          return [] if dir.nil? || dir.empty? || dir == '.'

          # Try exact directory first, then walk up (e.g. users/forms -> users).
          parts = dir.split('/')
          candidates = parts.length.downto(1).map { |i| parts.first(i).join('/') }

          candidates.each do |controller_path|
            controller = find_controller_by_path(controller_path)
            names = helper_module_names_for(controller)
            return names unless names.empty?
          end

          []
        end

        sig { params(controller_path: String).returns(T.nilable(T.class_of(::ActionController::Base))) }
        def find_controller_by_path(controller_path)
          all_concrete_controllers.find do |controller|
            controller.respond_to?(:controller_path) && controller.controller_path == controller_path
          end
        end

        sig { returns(T::Array[T.class_of(::ActionController::Base)]) }
        def all_concrete_controllers
          ObjectSpace.each_object(Class).select do |klass|
            klass < ::ActionController::Base && !klass.abstract?
          rescue StandardError
            false
          end
        end

        sig { params(controller: T.nilable(T.class_of(::ActionController::Base))).returns(T::Array[String]) }
        def helper_module_names_for(controller)
          return [] unless controller

          # Use the actual runtime helper chain for this controller.
          controller._helpers.ancestors.filter_map do |mod|
            next unless mod.is_a?(Module) && !mod.is_a?(Class)
            name = mod.name
            next if name.nil? || name.empty?
            next if name.start_with?('ActionController::') || name.start_with?('AbstractController::')
            name
          end.uniq
        end
      end
    end
  end
end
