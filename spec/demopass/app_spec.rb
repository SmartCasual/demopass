require "spec_helper"

require "demopass/app"
require "rack"

RSpec.describe Demopass::App do
  subject(:app) { described_class.new(downstream, except: except) }

  let(:lint_app) { Rack::Lint.new(app) }
  let(:downstream) { double(:rack_app) } # rubocop:disable RSpec/VerifiedDoubles
  let(:except) { nil }

  let(:token_secret) { "this-is-a-secret" }
  let(:password) { "this-is-a-password" }
  let(:token) do
    OpenSSL::HMAC.new(token_secret, OpenSSL::Digest.new("SHA256"))
      .update(password)
      .hexdigest
  end

  around do |example|
    with_env(
      "DEMOPASS_SECRET" => token_secret,
      "DEMOPASS_PASSWORD" => password,
    ) do
      example.run
    end
  end

  before do
    allow(downstream).to receive(:call)
  end

  it "has a `call` method" do
    expect(app).to respond_to(:call)
  end

  it "supports a full authentication flow" do
    allow(downstream).to receive(:call).and_return([200, {}, "Test response"])

    # Make unauthenticated downstream request
    env = Rack::MockRequest.env_for("/some-app-path", method: Rack::GET)
    response = Rack::MockResponse.new(*app.call(env), env[Rack::RACK_ERRORS])
    expect(response.status).to eq(200)
    expect(response.body).not_to eq("Test response")

    # Parse form
    form = response.body
    path = form.match(/action="([^"]+)"/)[1]
    method = form.match(/method="([^"]+)"/)[1]
    key = form.match(/input type="password" name="([^"]+)"/)[1]

    # Make authentication request
    env = Rack::MockRequest.env_for(path,
      method: method,
      input: StringIO.new("#{key}=#{password}"),
    )
    response = Rack::MockResponse.new(*app.call(env), env[Rack::RACK_ERRORS])
    expect(response.status).to eq(302)
    expect(response.location).to eq("/")

    # Make authenticated downstream request
    env = Rack::MockRequest.env_for("/some-app-path", method: Rack::GET)
    env["HTTP_COOKIE"] = response.cookies.values.map(&:to_s).join(";")
    response = Rack::MockResponse.new(*app.call(env), env[Rack::RACK_ERRORS])
    expect(response.status).to eq(200)
    expect(response.body).to eq("Test response")
  end

  describe "#call" do
    let(:env) do
      Rack::MockRequest.env_for(path, method: method, input: input).tap do |env_hash|
        env_hash["HTTP_COOKIE"] = cookie
      end
    end

    let(:input) { nil }
    let(:cookie) { "" }

    let(:response) do
      Rack::MockResponse.new(*lint_app.call(env), env[Rack::RACK_ERRORS])
    end

    context "when making a downstream GET request" do
      let(:method) { Rack::GET }
      let(:path) { "/some-app-path" }

      context "when the token is missing" do
        let(:cookie) { "" }

        it "responds with a form" do
          expect(response.status).to eq(200)
          expect(response.body).to include("form")
        end

        context "but the URL is excluded" do
          let(:except) { Regexp.new("^#{path}$") }

          it "delegates to the downstream app and returns the result" do
            downstream_response = [200, {}, ""]
            allow(downstream).to receive(:call).with(env).and_return(downstream_response)

            expect(app.call(env)).to eq(downstream_response)
          end
        end
      end

      context "when the token is present and valid" do
        let(:cookie) { "#{described_class::TOKEN_KEY}=#{token}" }

        it "delegates to the downstream app and returns the result" do
          downstream_response = [200, {}, ""]
          allow(downstream).to receive(:call).with(env).and_return(downstream_response)

          expect(app.call(env)).to eq(downstream_response)
        end
      end
    end

    context "when authorizing" do
      let(:method) { Rack::POST }
      let(:path) { described_class::PASSWORD_PATH }

      context "when the token is missing" do
        let(:input) { nil }

        it "responds with a form" do
          expect(response.status).to eq(200)
          expect(response.body).to include("form")
        end
      end

      context "when the token is blank" do
        let(:input) { "" }

        it "responds with a form" do
          expect(response.status).to eq(200)
          expect(response.body).to include("form")
        end
      end

      context "when the token is incorrect" do
        let(:input) { "this-is-wrong" }

        it "responds with a form" do
          expect(response.status).to eq(200)
          expect(response.body).to include("form")
        end
      end

      context "when the password is present and valid" do
        let(:input) { StringIO.new("#{described_class::PASSWORD_KEY}=#{password}") }

        it "assigns the token and redirects" do
          expect(response.status).to eq(302)
          expect(response.cookies[described_class::TOKEN_KEY]).not_to be_nil
          expect(response.cookies[described_class::TOKEN_KEY]).not_to eq("")
        end
      end
    end
  end
end
