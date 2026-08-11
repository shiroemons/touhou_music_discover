# frozen_string_literal: true

module Spotify
  # 原曲別プレイリストへ登録する SpotifyTrack を、内部 Track 単位で正規化する。
  #
  # 同じ内部 Track に複数の SpotifyTrack が存在することがある。これは Spotify 側の
  # 再登録・アルバム差し替えで発生しうるが、原曲別プレイリストには同じ内部 Track を
  # 1 回だけ登録する。採用候補は SpotifyAlbum.active を正とし、候補が一意に決まらない
  # データは推測で書き換えず、呼び出し元へ要確認として返す。
  class PlaylistTrackSelector
    Selection = Data.define(
      :tracks,
      :raw_count,
      :duplicate_groups,
      :ambiguous_groups
    ) do
      def canonical_count
        spotify_uris.size
      end

      def spotify_uris
        tracks.map { |track| "spotify:track:#{track.spotify_id}" }.uniq
      end

      def duplicate_count
        duplicate_groups.sum do |group|
          group['spotify_ids'].uniq.size - 1
        end
      end

      def ambiguous?
        ambiguous_groups.any?
      end
    end

    class AmbiguousSelectionError < StandardError
      attr_reader :groups

      def initialize(groups)
        @groups = groups
        super("SpotifyTrack の採用候補を一意に決められない内部Trackが #{groups.size} 件あります")
      end
    end

    class << self
      def call(original_song)
        spotify_tracks = original_song.spotify_tracks.includes(:spotify_album).to_a
        select(spotify_tracks)
      end

      # テストおよび修復処理から、取得済みの配列を直接正規化するための入口。
      def select(spotify_tracks)
        # Track ID は通常もっとも強い同一性キーだが、同じ録音が別の Track
        # レコードとして取り込まれている場合は ISRC が共通する。ISRC がある
        # ときはそれを優先し、同じ曲のSpotify ID差し替えも同じ候補群として扱う。
        groups = spotify_tracks.group_by { |track| identity_key(track) }
        selected_tracks = []
        duplicate_groups = []
        ambiguous_groups = []

        groups.each_value do |candidates|
          duplicate_groups << duplicate_group(candidates) if candidates.size > 1

          active_candidates = candidates.select { |track| track.spotify_album&.active? }
          if candidates.size == 1
            selected_tracks << candidates.first
          elsif active_candidates.size == 1
            selected_tracks << active_candidates.first
          else
            ambiguous_groups << duplicate_group(candidates, active_candidates:)
          end
        end

        # 別の同一性グループに誤って同じSpotify IDが紐づいていても、
        # プレイリストへ同じURIを二度渡さない。
        selected_tracks = selected_tracks.uniq(&:spotify_id)

        Selection.new(
          tracks: selected_tracks,
          raw_count: spotify_tracks.size,
          duplicate_groups:,
          ambiguous_groups:
        )
      end

      private

      def identity_key(track)
        isrc = track.isrc.presence
        return [:isrc, isrc] if isrc

        [:track, track.track_id]
      end

      def duplicate_group(candidates, active_candidates: candidates.select { |track| track.spotify_album&.active? })
        {
          'track_ids' => candidates.map(&:track_id).uniq,
          'spotify_ids' => candidates.map(&:spotify_id),
          'active_spotify_ids' => active_candidates.map(&:spotify_id),
          'isrc' => candidates.first.isrc
        }
      end
    end
  end
end
