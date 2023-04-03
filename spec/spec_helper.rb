# frozen_string_literal: true

require "bundler/compose"
require "tmpdir"
require "yaml"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# BELOW: copied from bundler

if File.expand_path(__FILE__) =~ %r{([^\w/.:-])}
  abort "The bundler specs cannot be run from a path that contains special characters " \
  "(particularly #{Regexp.last_match(1).inspect})"
end

require "bundler"
require "rspec/core"
require "rspec/expectations"
require "rspec/mocks"
require "rspec/support/differ"

require_relative "support/builders"
require_relative "support/build_metadata"
require_relative "support/filters"
require_relative "support/helpers"
require_relative "support/indexes"
require_relative "support/matchers"
require_relative "support/permissions"
require_relative "support/platforms"

RSpec.configure do |config|
  config.include Spec::Builders
  config.include Spec::Helpers
  config.include Spec::Indexes
  config.include Spec::Matchers
  config.include Spec::Path
  config.include Spec::Platforms
  config.include Spec::Permissions

  # Since failures cause us to keep a bunch of long strings in memory, stop
  # once we have a large number of failures (indicative of core pieces of
  # bundler being broken) so that running the full test suite doesn't take
  # forever due to memory constraints
  config.fail_fast ||= 25 if ENV["CI"]

  config.bisect_runner = :shell

  config.expect_with :rspec do |c|
    c.syntax = :expect

    c.max_formatted_output_length = 1000
  end

  config.mock_with :rspec do |mocks|
    mocks.allow_message_expectations_on_nil = false
  end

  config.before :suite do
    require_relative "support/rubygems_ext"
    Spec::Rubygems.test_setup
    ENV["BUNDLER_SPEC_RUN"] = "true"
    ENV["BUNDLER_NO_OLD_RUBYGEMS_WARNING"] = "true"
    ENV["BUNDLE_USER_CONFIG"] = ENV["BUNDLE_USER_CACHE"] = ENV["BUNDLE_USER_PLUGIN"] = nil
    ENV["BUNDLE_APP_CONFIG"] = nil
    ENV["BUNDLE_SILENCE_ROOT_WARNING"] = nil
    ENV["RUBYGEMS_GEMDEPS"] = nil
    ENV["XDG_CONFIG_HOME"] = nil
    ENV["GEMRC"] = nil

    # Don't wrap output in tests
    ENV["THOR_COLUMNS"] = "10000"

    extend(Spec::Helpers)
    begin
      bundler = Dir[File.join(base_system_gems, "**/bundler-*.gem")].first || \
                Gem.loaded_specs["bundler"].cache_file || \
                raise("No bundler found in #{base_system_gems}")
      system_gems bundler, "bundler-compose", path: pristine_system_gem_path
    rescue StandardError
      warn "Run `ruby -Ispec -rsupport/rubygems_ext -e 'Spec::Rubygems.install_test_deps'` to install deps"
      warn "Run specs via bin/rspec"
      raise
    end
  end

  config.before :all do
    check_test_gems!

    build_repo1

    reset_paths!
  end

  config.around do |example|
    FileUtils.cp_r pristine_system_gem_path, system_gem_path

    with_gem_path_as(system_gem_path) do
      Bundler.ui.silence { example.run }

      all_output = all_commands_output
      if example.exception && !all_output.empty?
        message = "#{all_output}\n#{example.exception.message}"
        summary = "#{all_output}\n\n#{example.exception.summary}" if example.exception.respond_to?(:summary)
        example.exception.singleton_class.send(:define_method, :summary) { summary }
        (class << example.exception; self; end).send(:define_method, :message) do
          message
        end
      end
    end
  ensure
    reset!
  end

  config.after :suite do
    FileUtils.rm_rf Spec::Path.pristine_system_gem_path
  end
end