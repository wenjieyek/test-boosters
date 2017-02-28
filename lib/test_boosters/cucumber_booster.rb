module Semaphore
  require "json"
  require "test_boosters/cli_parser"
  require "test_boosters/logger"
  require "test_boosters/executor"
  require "test_boosters/display_files"
  require "test_boosters/leftover_files"

  class CucumberBooster
    def initialize(thread_index)
      @thread_index = thread_index
      @report_path = ENV["REPORT_PATH"] || "#{ENV["HOME"]}/cucumber_report.json"
      @spec_path = ENV["SPEC_PATH"] || "features"
    end

    def run
      exit_code = true
      begin
        features_to_run = select

        if features_to_run.empty?
          puts "No feature files in this thread!"
        else
          exit_code = Semaphore::execute("bundle exec cucumber #{features_to_run.join(" ")}")
        end
      rescue StandardError => e
        if @thread_index == 0
          exit_code = Semaphore::execute("bundle exec cucumber #{@spec_path}")
        end
      end
      exit_code
    end

    def select
      with_fallback do
        feature_report = JSON.parse(File.read(@report_path))
        thread_count = feature_report.count
        thread = feature_report[@thread_index]

        all_features = Dir["#{@spec_path}/**/*.feature"].sort
        all_known_features = feature_report.map { |t| t["files"] }.flatten.sort

        all_leftover_features = all_features - all_known_features
        thread_leftover_features = LeftoverFiles::select(all_leftover_features, thread_count, @thread_index)
        thread_features = all_features & thread["files"].sort
        features_to_run = thread_features + thread_leftover_features

        Semaphore::display_files("This thread features:", thread_features)
        Semaphore::display_title_and_count("All leftover features:", all_leftover_features)
        Semaphore::display_files("This thread leftover features:", thread_leftover_features)

        features_to_run
      end
    end

    def with_fallback
      yield
    rescue StandardError => e
      error = %{
        WARNING: An error detected while parsing the test boosters report file.
        WARNING: All tests will be executed on the first thread.
      }

      puts error

      error += %{Exception: #{e.message}}

      Semaphore::log(error)

      raise
    end
  end
end