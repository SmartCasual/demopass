require "openssl"
require "forwardable"
require_relative "logger"

class Demopass::App
  extend Forwardable

  PASSWORD_PATH = "/demopass".freeze
  PASSWORD_KEY = "password".freeze
  TOKEN_KEY = "demopass_token".freeze

  def initialize(downstream, except: nil, log_level: nil)
    @downstream = downstream
    @except = except

    @hmac_key = ENV["DEMOPASS_SECRET"]
    @password = ENV["DEMOPASS_PASSWORD"]

    @digest = OpenSSL::Digest.new("SHA256")
    @valid_hmac = hmac_for(@password)

    @logger = Demopass::Logger.new(log_level: log_level)

    validate_arguments
  end

  def call(env)
    @response = Rack::Response.new

    request = Rack::Request.new(env)
    debug("Beginning #{request.request_method} to #{request.path}")
    debug("Downstream is #{@downstream.class.name}")

    if (excluded = path_excluded?(request)) || token_valid?(request)
      reason = excluded ? "the path was excluded" : "the token was valid"
      debug("Passing downstream because #{reason}")

      return @downstream.call(env)
    end

    if (password = extract_password(request))
      assign_token_and_redirect(password)
    else
      info("Password or token missing or invalid; responding with a login form")
      respond_with_form
    end

    debug("Ending call to #{request.path}")
    @response.finish
  end

private

  def_delegators :@logger, :debug, :info

  def path_excluded?(request)
    @except && request.path =~ @except
  end

  def token_valid?(request)
    request.cookies[TOKEN_KEY] == @valid_hmac
  end

  def extract_password(request)
    unless request.post?
      debug("Ignoring passwords; request was not a POST")
      return
    end

    unless request.path == PASSWORD_PATH
      debug("Ignoring passwords; request path #{request.path} was not #{PASSWORD_PATH}")
      return
    end

    request.POST[PASSWORD_KEY]
  end

  def assign_token_and_redirect(password)
    debug("Setting token from password and redirecting to /")
    @response.set_cookie(TOKEN_KEY, hmac_for(password))
    @response.redirect("/")
  end

  def hmac_for(password)
    OpenSSL::HMAC.new(@hmac_key, @digest)
      .update(password)
      .hexdigest
  end

  FORM = <<~HTML.freeze
    <!DOCTYPE html>
    <html lang="en" dir="ltr">
      <head>
        <meta charset="utf-8">
        <title>Demopass authentication</title>
      </head>
      <body>
        <h1>Please enter the demo password</h1>
        <form action="/demopass" method="post">
          <input type="password" name="#{PASSWORD_KEY}" />
          <button>Submit</button>
        </form>
      </body>
    </html>
  HTML

  def respond_with_form
    @response.write(FORM)
  end

  def validate_arguments
    if @except && !@except.is_a?(Regexp)
      raise Demopass::Error, "The `except` option must be a regular expression (or blank)."
    end

    raise Demopass::Error, "Please configure DEMOPASS_SECRET and DEMOPASS_PASSWORD" unless @hmac_key && @password
  end
end
