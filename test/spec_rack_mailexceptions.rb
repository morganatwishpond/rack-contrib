# frozen_string_literal: true

require 'minitest/autorun'
require 'rack/mock'

begin
  require './lib/rack/contrib/mailexceptions'
  require './test/mail_settings.rb'

  class TestError < RuntimeError
  end

  def test_exception
    raise TestError, 'Suffering Succotash!'
  rescue => boom
    return boom
  end

  describe 'Rack::MailExceptions' do
    def mail_exception(app, options = {}, &block)
      middleware = Rack::MailExceptions.new(@app, &block)
      if options[:test_mode]
        middleware.enable_test_mode
      end
      Rack::Lint.new(middleware)
    end

    before do
      @app = lambda { |env| raise TestError, 'Why, I say' }
      @env = Rack::MockRequest.env_for("/foo",
        'FOO' => 'BAR',
        :method => 'GET',
        :input => 'THE BODY'
      )
      @smtp_settings = {
        :server         => 'example.com',
        :domain         => 'example.com',
        :port           => 500,
        :authentication => :login,
        :user_name      => 'joe',
        :password       => 'secret'
      }
    end

    specify 'yields a configuration object to the block when created' do
      called = false
      mailer =
        mail_exception(@app) do |mail|
          called = true
          mail.to 'foo@example.org'
          mail.from 'bar@example.org'
          mail.subject '[ERROR] %s'
          mail.smtp @smtp_settings
        end
      _(called).must_equal(true)
    end

    specify 'generates a Mail object with configured settings' do
      # Don't use Rack::Lint because we the private method `generate_mail` is tested here
      mailer =
        Rack::MailExceptions.new(@app) do |mail|
          mail.to 'foo@example.org'
          mail.from 'bar@example.org'
          mail.subject '[ERROR] %s'
          mail.smtp @smtp_settings
        end

      mail = mailer.send(:generate_mail, test_exception, @env)
      _(mail.to).must_equal ['foo@example.org']
      _(mail.from).must_equal ['bar@example.org']
      _(mail.subject).must_equal '[ERROR] Suffering Succotash!'
      _(mail.body).wont_equal(nil)
      _(mail.body.to_s).must_match(/FOO:\s+"BAR"/)
      _(mail.body.to_s).must_match(/^\s*THE BODY\s*$/)
    end

    specify 'filters HTTP_EXCEPTION body' do
      # Don't use Rack::Lint because we the private method `generate_mail` is tested here
      mailer =
        Rack::MailExceptions.new(@app) do |mail|
          mail.to 'foo@example.org'
          mail.from 'bar@example.org'
          mail.subject '[ERROR] %s'
          mail.smtp @smtp_settings
        end

      env = @env.dup
      env['HTTP_AUTHORIZATION'] = 'Basic xyzzy12345'

      mail = mailer.send(:generate_mail, test_exception, env)
      _(mail.body.to_s).must_match /HTTP_AUTHORIZATION:\s+"Basic \*filtered\*"/
    end

    specify 'catches exceptions raised from app, sends mail, and re-raises' do
      mailer =
        mail_exception(@app, test_mode: true) do |mail|
          mail.to 'foo@example.org'
          mail.from 'bar@example.org'
          mail.subject '[ERROR] %s'
          mail.smtp @smtp_settings
        end
      _(lambda { mailer.call(@env) }).must_raise(TestError)
      _(@env['mail.sent']).must_equal(true)
      _(Mail::TestMailer.deliveries.length).must_equal(1)
    end
  end
rescue LoadError => boom
  STDERR.puts "WARN: Skipping Rack::MailExceptions tests (mail not installed)"
end
