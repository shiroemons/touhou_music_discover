# frozen_string_literal: true

module SpotifyApi
  # Spotify の JSON レスポンスを、メソッドアクセスできるオブジェクトに包む。
  #
  # Apple Music と違い Spotify の JSON はフラット（attributes ラッパーが無い）ため、
  # トップレベルのキーをそのまま公開するだけでよい。
  # ネストした値は生の Hash / Array のまま保持するので、
  # album.external_ids['upc'] や album.external_urls['spotify'] のような
  # 既存の書き方がそのまま動く。
  class Response
    class << self
      # Hash はこのクラスで包み、Array は各要素を包んだ配列にし、
      # それ以外（nil やスカラー）はそのまま返す。
      def build(value)
        case value
        when Hash then new(value)
        when Array then value.map { |element| build(element) }
        else value
        end
      end
    end

    attr_reader :data

    def initialize(data)
      @data = data
    end

    # キー名でのアクセス。文字列・シンボルのどちらでも引ける。
    def [](key)
      data[key.to_s]
    end

    def key?(key)
      data.key?(key.to_s)
    end

    # ネストした値を辿る。Page#items は各要素を Response に包むため、
    # playlist.dig('tracks', 'total') のような書き方が呼び出し側で必要になる。
    # キーが無い場合は Hash#dig と同じく nil を返す。
    #
    # 整数キーは to_s で文字列化しない。配列の要素は文字列キーではなく添字で
    # 辿る必要があるため（例: dig('images', 0, 'url')）、ここを to_s してしまうと
    # Array#dig に '0' を渡すことになり、常に nil が返って要素を取得できなくなる。
    def dig(*keys)
      data.dig(*keys.map { |key| key.is_a?(Integer) ? key : key.to_s })
    end

    def to_h
      data
    end

    # DB の payload カラムにそのまま保存されるため、生の Hash を返す。
    # ここで整形すると保存済みデータとの互換性が崩れる。
    def as_json(_options = {})
      data
    end

    def respond_to_missing?(name, include_private = false)
      key?(name) || super
    end

    # 未定義のキーは nil を返すだけ。
    #
    # RSpotify::Base#method_missing は未取得の属性にアクセスされると裏で API を
    # 叩き直す。この暗黙のリクエストが Development Mode のクォータ枯渇の主因のため、
    # 同様の仕組みは絶対に実装しない。
    def method_missing(name, *args)
      return super unless args.empty?

      data[name.to_s]
    end
  end
end
