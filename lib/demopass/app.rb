require "openssl"

class Demopass::App
  PASSWORD_PATH = "/demopass".freeze
  PASSWORD_KEY = "password".freeze
  TOKEN_KEY = "demopass_token".freeze

  def initialize(downstream, except: nil)
    @downstream = downstream
    @except = except
    @response = Rack::Response.new

    @hmac_key = ENV["DEMOPASS_SECRET"]
    @password = ENV["DEMOPASS_PASSWORD"]

    @digest = OpenSSL::Digest.new("SHA256")
    @valid_hmac = hmac_for(@password)

    validate_arguments
  end

  def call(env)
    request = Rack::Request.new(env)
    return @downstream.call(env) if path_excluded?(request) || token_valid?(request)

    if (password = extract_password(request))
      assign_token_and_redirect(password)
    else
      respond_with_form
    end

    @response.finish
  end

private

  def path_excluded?(request)
    @except && request.path =~ @except
  end

  def token_valid?(request)
    request.cookies[TOKEN_KEY] == @valid_hmac
  end

  def extract_password(request)
    return unless request.post? && request.path == PASSWORD_PATH

    request.POST[PASSWORD_KEY]
  end

  def assign_token_and_redirect(password)
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
