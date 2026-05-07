# frozen_string_literal: true

require 'cgi'
require 'digest/sha1'
require 'faraday'
require 'faraday/retry'

module YtMusic
  class Client
    YTM_VERSION = '1.20241111.01.00'
    YTM_DOMAIN = 'https://music.youtube.com'
    YTM_BASE_API = "#{YTM_DOMAIN}/youtubei/v1/".freeze
    YOUTUBE_DOMAIN = 'https://www.youtube.com'
    YOUTUBE_BASE_API = "#{YOUTUBE_DOMAIN}/youtubei/v1/".freeze
    YOUTUBE_VERSION = '2.20260501.00.00'
    YOUTUBE_API_KEY = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30'
    YTM_PARAMS = "?alt=json&key=#{YOUTUBE_API_KEY}".freeze
    class << self
      def generate_body(options = {})
        context = initialize_context

        if options[:type] && options[:id]
          context.merge(
            {
              'browseEndpointContextSupportedConfigs' => {
                'browseEndpointContextMusicConfig' => {
                  'pageType' => "MUSIC_PAGE_TYPE_#{options[:type]}"
                }
              },
              'browseId' => options[:id]
            }
          )
        elsif options[:id]
          context.merge({ 'browseId' => options[:id] })
        else
          context
        end
      end

      def send_request(endpoint, body: nil, options: {})
        path = "#{endpoint}#{YTM_PARAMS}"
        body ||= generate_body(options)

        client.post(path, body.to_json, headers)
      end

      def send_youtube_request(endpoint, body: nil)
        path = "#{endpoint}#{YTM_PARAMS}"
        body ||= youtube_context

        youtube_client.post(path, body.to_json, youtube_headers)
      end

      def generate_youtube_body(video_id:)
        youtube_context.merge(videoId: video_id)
      end

      private

      def client
        @client ||= Faraday.new(YTM_BASE_API) do |conn|
          conn.request :retry, max: 3, interval: 0.5, backoff_factor: 2, exceptions: [Faraday::ConnectionFailed, Faraday::SSLError, Net::OpenTimeout]
          conn.response :json, content_type: /\bjson\z/
        end
      end

      def youtube_client
        @youtube_client ||= Faraday.new(YOUTUBE_BASE_API) do |conn|
          conn.request :retry, max: 3, interval: 0.5, backoff_factor: 2, exceptions: [Faraday::ConnectionFailed, Faraday::SSLError, Net::OpenTimeout]
          conn.response :json, content_type: /\bjson\z/
        end
      end

      def headers
        {
          accept: '*/*',
          authorization: auth_token,
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:72.0) Gecko/20100101 Firefox/72.0',
          'accept-language': 'en-US,en;q=0.5',
          'content-type': 'application/json',
          'x-goog-authUser': '0',
          'x-goog-visitor-id': 'Cgs3TE1LMHQyTE5DNCjItua5BjIKCgJKUBIEGgAgaQ%3D%3D',
          'x-youtube-client-name': '67',
          'x-youtube-client-version': YTM_VERSION,
          'x-youtube-chrome-connected': 'source=Chrome,mode=0,enable_account_consistency=true,supervised=false,consistency_enabled_by_default=false',
          'x-origin': YTM_DOMAIN,
          origin: YTM_DOMAIN,
          cookie: ENV.fetch('YOUTUBE_MUSIC_COOKIE', nil)
        }
      end

      def youtube_headers
        {
          accept: '*/*',
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:72.0) Gecko/20100101 Firefox/72.0',
          'accept-language': 'ja,en-US;q=0.9,en;q=0.8',
          'content-type': 'application/json',
          'x-youtube-client-name': '1',
          'x-youtube-client-version': YOUTUBE_VERSION,
          origin: YOUTUBE_DOMAIN
        }
      end

      def initialize_context
        {
          context: {
            capabilities: {},
            client: {
              clientName: 'WEB_REMIX',
              clientVersion: YTM_VERSION,
              experimentIds: [],
              experimentsToken: '',
              gl: 'JP',
              hl: 'ja',
              locationInfo: { locationPermissionAuthorizationStatus: 'LOCATION_PERMISSION_AUTHORIZATION_STATUS_UNSUPPORTED' },
              musicAppInfo: {
                musicActivityMasterSwitch: 'MUSIC_ACTIVITY_MASTER_SWITCH_INDETERMINATE',
                musicLocationMasterSwitch: 'MUSIC_LOCATION_MASTER_SWITCH_INDETERMINATE',
                pwaInstallabilityStatus: 'PWA_INSTALLABILITY_STATUS_UNKNOWN'
              },
              utcOffsetMinutes: 60
            },
            request: {
              internalExperimentFlags: [
                { key: 'force_music_enable_outertube_tastebuilder_browse', value: 'true' },
                { key: 'force_music_enable_outertube_playlist_detail_browse', value: 'true' },
                { key: 'force_music_enable_outertube_search_suggestions', value: 'true' }
              ],
              sessionIndex: {}
            },
            user: { enableSafetyMode: false }
          }
        }
      end

      def youtube_context
        {
          context: {
            client: {
              clientName: 'WEB',
              clientVersion: YOUTUBE_VERSION,
              gl: 'JP',
              hl: 'ja'
            }
          }
        }
      end

      def sapisid
        @sapisid ||= CGI::Cookie.parse(ENV.fetch('YOUTUBE_MUSIC_COOKIE', nil))['SAPISID']&.first
      end

      def auth_token
        date = Time.now.strftime('%s%L').to_i
        sha1 = Digest::SHA1.hexdigest("#{date} #{sapisid} #{YTM_DOMAIN}")
        "SAPISIDHASH #{date}_#{sha1}"
      end
    end
  end
end
