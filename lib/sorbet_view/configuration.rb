# typed: strict
# frozen_string_literal: true

require 'psych'

module SorbetView
  class Configuration < T::Struct
    const :input_dirs, T::Array[String], default: ['app/views']
    const :exclude_paths, T::Array[String], default: []
    const :output_dir, String, default: 'sorbet/templates'
    const :extra_includes, T::Array[String], default: []
    const :extra_body, String, default: ''
    const :skip_missing_locals, T::Boolean, default: true
    const :sorbet_path, String, default: 'srb'
    const :typed_level, String, default: 'true'

    const :component_dirs, T::Array[String], default: []
    const :controller_dirs, T::Array[String], default: ['app/controllers']
    const :sorbet_options, T::Array[String], default: []

    class << self
      extend T::Sig

      sig { returns(Configuration) }
      def load
        path = File.join(Dir.pwd, SorbetView::CONFIG_FILE_NAME)
        hash = if File.exist?(path)
          Psych.safe_load_file(path) || {}
        else
          {}
        end
        from_hash(hash)
      end
    end
  end
end
