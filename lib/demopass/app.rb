require "openssl"

class Demopass::App
  PASSWORD_PATH = "/demopass".freeze
  PASSWORD_KEY = "password".freeze
  TOKEN_KEY = "demopass_token".freeze

  def initialize(downstream)
    @downstream = downstream
    @response = Rack::Response.new

    @hmac_key = ENV["DEMOPASS_SECRET"]
    @password = ENV["DEMOPASS_PASSWORD"]

    raise Demopass::Error, "Please configure DEMOPASS_SECRET and DEMOPASS_PASSWORD" unless @hmac_key && @password

    @digest = OpenSSL::Digest.new("SHA256")
    @valid_hmac = hmac_for(@password)
  end

  def call(env)
    request = Rack::Request.new(env)
    return @downstream.call(env) if token_valid?(request)

    if (password = extract_password(request))
      assign_token_and_redirect(password)
    else
      respond_with_form
    end

    @response.finish
  end

private

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
end
