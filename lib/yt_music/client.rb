# frozen_string_literal: true

require 'cgi'
require 'digest/sha1'

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
    # クラス変数へのメモ化を複数スレッドから同時に行うと、コネクションが二重に
    # 生成されうるため排他制御する。
    CLIENT_MUTEX = Mutex.new

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

        execute_request { client.post(path, body.to_json, headers) }
      end

      def send_youtube_request(endpoint, body: nil)
        path = "#{endpoint}#{YTM_PARAMS}"
        body ||= youtube_context

        execute_request { youtube_client.post(path, body.to_json, youtube_headers) }
      end

      def generate_youtube_body(video_id:)
        youtube_context.merge(videoId: video_id)
      end

      private

      def execute_request
        validate_response(yield)
      rescue Faraday::RetriableResponse => e
        raise RequestError.new(status: e.response_status)
      end

      def validate_response(response)
        raise RequestError.new(status: response.status) unless response.success?
        raise RequestError.new(status: response.status, invalid_body: true) unless response.body.is_a?(Hash)

        response
      end

      def client
        CLIENT_MUTEX.synchronize do
          @client ||= ExternalApi::Connection.build(:yt_music, url: YTM_BASE_API) do |conn|
            conn.response :json, content_type: /\bjson\z/
          end
        end
      end

      def youtube_client
        CLIENT_MUTEX.synchronize do
          @youtube_client ||= ExternalApi::Connection.build(:yt_music, url: YOUTUBE_BASE_API) do |conn|
            conn.response :json, content_type: /\bjson\z/
          end
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
        @sapisid ||= parse_cookie_header(ENV.fetch('YOUTUBE_MUSIC_COOKIE', nil))['SAPISID']
      end

      # Ruby 4.0 で cgi/cookie が削除されたため、その parse 相当の処理を自前で行う。
      # "NAME1=value1; NAME2=value2" 形式の Cookie ヘッダを 名前 => 値 のハッシュに変換する。
      def parse_cookie_header(raw_cookie)
        return {} if raw_cookie.blank?

        raw_cookie.split(/;\s*/).each_with_object({}) do |pair, cookies|
          name, value = pair.split('=', 2)
          next if value.nil?

          name = CGI.unescape(name)
          next if cookies.key?(name)

          # 旧実装は値を '&' 区切りの複数値として扱っていたため、先頭の値を採用する
          cookies[name] = CGI.unescape(value.split('&').first.to_s)
        end
      end

      def auth_token
        date = Time.now.strftime('%s%L').to_i
        sha1 = Digest::SHA1.hexdigest("#{date} #{sapisid} #{YTM_DOMAIN}")
        "SAPISIDHASH #{date}_#{sha1}"
      end
    end
  end
end
