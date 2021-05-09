require "logger"

class Demopass::Logger
  def initialize(log_level: nil)
    log_level ||= env_log_level || rails_log_level || default_log_level
    return if log_level == :none

    @logger = ::Logger.new($stdout, level: log_level, progname: "Demopass")
  end

  def debug(message)
    log(message, log_level: ::Logger::DEBUG)
  end

  def info(message)
    log(message, log_level: ::Logger::INFO)
  end

private

  def log(message, log_level:)
    @logger&.add(log_level, message, "Demopass")
  end

  def env_log_level
    case ENV["LOG_LEVEL"]
    when "debug", "info", "warn", "error", "fatal"
      ENV["LOG_LEVEL"]
    end
  end

  def default_log_level
    ::Logger::INFO
  end

  def rails_log_level
    Rails.logger.level if defined?(Rails)
  end
end
