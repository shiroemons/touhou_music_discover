# frozen_string_literal: true

module SpotifyApi
  # Spotify のページングオブジェクト（paging object）を表す小さなクラス。
  #
  # { "items" => [...], "total" => n, "limit" => l, "offset" => o, "next" => url } という
  # 形の Hash を受け取る。Response はネストした値を生の Hash / Array のまま保持する
  # 設計のため、response.items のようにアクセスすると Hash の配列のままでメソッド
  # アクセスができない。ページングを扱うリソースメソッド（Album.tracks / Album.search
  # など）では items を Response.build で包んだ上で total / limit / offset をまとめて
  # 返す必要があるため、このクラスを用意する。
  class Page
    include Enumerable

    attr_reader :items, :total, :limit, :offset, :next_url, :body

    delegate :size, :empty?, to: :items

    class << self
      # body は paging object の Hash。nil や items 欠落にも耐える。
      def build(body)
        new(body || {})
      end
    end

    def initialize(body)
      @body = body
      @items = Response.build(body['items'] || [])
      @total = body['total']
      @limit = body['limit']
      @offset = body['offset']
      @next_url = body['next']
    end

    def each(&)
      items.each(&)
    end

    # Spotify は最終ページで next が null になるため、それを最終ページの判定に使う。
    # items.size < limit による判定は limit 省略時に誤判定するため使わない。
    def last_page?
      next_url.blank?
    end
  end
end
