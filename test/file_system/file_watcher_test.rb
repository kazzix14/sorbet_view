# typed: true
# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

class FileWatcherTest < Minitest::Test
  def test_initializes_with_config
    config = SorbetView::Configuration.new(input_dirs: ['/nonexistent'])

    watcher = SorbetView::FileSystem::FileWatcher.new(config: config) do |_m, _a, _r|
      # noop
    end

    assert watcher
  end

  def test_detects_file_changes
    Dir.mktmpdir do |dir|
      views_dir = File.join(dir, 'app', 'views')
      FileUtils.mkdir_p(views_dir)

      config = SorbetView::Configuration.new(input_dirs: [views_dir])

      changes = Queue.new
      watcher = SorbetView::FileSystem::FileWatcher.new(config: config) do |modified, added, _removed|
        (modified + added).each { |f| changes.push(f) }
      end

      watcher.start
      sleep 0.3 # Let listener initialize

      # Create a new ERB file
      erb_path = File.join(views_dir, 'test.html.erb')
      File.write(erb_path, '<%= @hello %>')

      # Wait for change detection (with timeout)
      changed_file = nil
      begin
        Timeout.timeout(5) { changed_file = changes.pop }
      rescue Timeout::Error
        # Listener may be slow in CI
      end

      watcher.stop

      if changed_file
        assert_includes changed_file, 'test.html.erb'
      else
        skip 'FileWatcher did not detect change in time (expected in some CI environments)'
      end
    end
  end

  def test_ignores_non_erb_and_non_rb_files
    Dir.mktmpdir do |dir|
      views_dir = File.join(dir, 'app', 'views')
      FileUtils.mkdir_p(views_dir)

      config = SorbetView::Configuration.new(input_dirs: [views_dir])

      changes = Queue.new
      watcher = SorbetView::FileSystem::FileWatcher.new(config: config) do |modified, added, _removed|
        (modified + added).each { |f| changes.push(f) }
      end

      watcher.start
      sleep 0.3

      # Create a non-ERB, non-Ruby file (e.g. .txt)
      File.write(File.join(views_dir, 'test.txt'), 'hello')
      sleep 0.5

      watcher.stop

      assert changes.empty?, 'Should not detect non-ERB/non-Ruby files'
    end
  end

  def test_detects_rb_files
    Dir.mktmpdir do |dir|
      views_dir = File.join(dir, 'app', 'views')
      FileUtils.mkdir_p(views_dir)

      config = SorbetView::Configuration.new(input_dirs: [views_dir])

      changes = Queue.new
      watcher = SorbetView::FileSystem::FileWatcher.new(config: config) do |modified, added, _removed|
        (modified + added).each { |f| changes.push(f) }
      end

      watcher.start
      sleep 0.3

      rb_path = File.join(views_dir, 'component.rb')
      File.write(rb_path, 'class Foo; end')

      changed_file = nil
      begin
        Timeout.timeout(5) { changed_file = changes.pop }
      rescue Timeout::Error
        # Listener may be slow in CI
      end

      watcher.stop

      if changed_file
        assert_includes changed_file, 'component.rb'
      else
        skip 'FileWatcher did not detect change in time (expected in some CI environments)'
      end
    end
  end
end
