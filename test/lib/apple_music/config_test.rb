# frozen_string_literal: true

require 'test_helper'

module AppleMusic
  class ConfigTest < ActiveSupport::TestCase
    setup do
      @config = Config.new
      @config.secret_key_path = nil
      @config.secret_key = OpenSSL::PKey::EC.generate('prime256v1').to_pem
      @config.team_id = 'TEAM_ID'
      @config.music_id = 'MUSIC_ID'
    end

    test 'reuses the cached token while it is still valid' do
      token = @config.authentication_token

      assert_equal token, @config.authentication_token

      travel_to Time.current + Config::TOKEN_TTL - Config::REFRESH_MARGIN - 1.minute do
        assert_equal token, @config.authentication_token
      end
    end

    test 'regenerates the token once the refresh margin is reached' do
      token = @config.authentication_token

      travel_to Time.current + Config::TOKEN_TTL - Config::REFRESH_MARGIN + 1.minute do
        assert_not_equal token, @config.authentication_token
      end
    end

    test 'issues a token whose exp matches TOKEN_TTL' do
      issued_at = Time.current
      payload, = JWT.decode(@config.authentication_token, nil, false)

      assert_in_delta (issued_at + Config::TOKEN_TTL).to_i, payload['exp'], 5
      assert_equal 'TEAM_ID', payload['iss']
    end

    test 'raises when no secret key is configured' do
      @config.secret_key = nil

      assert_raises(ParameterMissing) { @config.authentication_token }
    end
  end
end
