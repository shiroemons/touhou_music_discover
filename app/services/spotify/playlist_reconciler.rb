# frozen_string_literal: true

module Spotify
  # Spotify上の現在のプレイリストと、DBから正規化した期待値を比較する。
  #
  # dry-run (apply: false) を既定にして、既に反映済みの重複・旧Spotify ID・
  # 順序ずれを一括で洗い出せるようにする。apply: true の場合も、書き込みは
  # PlaylistTrackWriter に集約し、PUT後の全件検証まで行う。
  class PlaylistReconciler
    Result = Data.define(
      :playlist_id,
      :playlist_name,
      :status,
      :selection,
      :current_uris,
      :desired_uris,
      :exact_duplicate_count,
      :semantic_duplicate_group_count
    ) do
      def current_count
        current_uris.size
      end

      def desired_count
        desired_uris.size
      end

      def changed?
        current_uris != desired_uris
      end

      def missing_count
        multiset_difference_count(desired_uris, current_uris)
      end

      def extra_count
        multiset_difference_count(current_uris, desired_uris)
      end

      private

      def multiset_difference_count(left, right)
        right_counts = right.tally
        left.sum do |uri|
          count = right_counts[uri].to_i
          right_counts[uri] = count - 1
          count.positive? ? 0 : 1
        end
      end
    end

    # rubocop:disable Metrics/ParameterLists -- reconciliation options are explicit so callers cannot
    # accidentally turn a dry-run into a write.
    def initialize(session:, playlist_id:, original_song:, playlist_name: nil, apply: false,
                   source: 'Spotify::PlaylistReconciler')
      @session = session
      @playlist_id = playlist_id
      @original_song = original_song
      @playlist_name = playlist_name.presence || original_song.title
      @apply = apply
      @source = source
    end
    # rubocop:enable Metrics/ParameterLists

    def call
      selection = PlaylistTrackSelector.call(original_song)
      raise PlaylistTrackSelector::AmbiguousSelectionError, selection.ambiguous_groups if selection.ambiguous?

      desired_uris = selection.spotify_uris
      current_uris = read_current_uris
      exact_duplicate_count = current_uris.size - current_uris.uniq.size
      semantic_duplicate_group_count = count_semantic_duplicate_groups(current_uris)

      status = if selection.raw_count.zero?
                 # DB側の候補が無いときに空PUTを許すと、既存プレイリストを
                 # 意図せず全消しするため、必ず確認対象として止める。
                 :skipped_empty
               elsif current_uris == desired_uris
                 :unchanged
               elsif apply
                 write_and_verify(selection.tracks)
                 :repaired
               else
                 :would_repair
               end

      Result.new(
        playlist_id:,
        playlist_name:,
        status:,
        selection:,
        current_uris:,
        desired_uris:,
        exact_duplicate_count:,
        semantic_duplicate_group_count:
      )
    end

    private

    attr_reader :session, :playlist_id, :original_song, :playlist_name, :apply, :source

    def read_current_uris
      SpotifyRetry.with_retry(source: "#{source}#read") do
        items = SpotifyApi::Playlist.all_items(session, playlist_id, limit: PlaylistTrackWriter::MAX_ITEMS_PER_REQUEST)
        items.each_with_index.map { |item, index| item_uri(item, index) }
      end
    end

    def item_uri(item, index)
      track = item && (item['track'] || item['item'])
      track_id = track&.[]('id').presence
      return "spotify:track:#{track_id}" if track_id

      # unavailable / null item も1枠として扱い、検証で見落とさない。
      "spotify:unavailable:#{index}"
    end

    def count_semantic_duplicate_groups(current_uris)
      spotify_ids = current_uris.filter_map do |uri|
        match = uri.match(/\Aspotify:track:(.+)\z/)
        match && match[1]
      end.uniq
      return 0 if spotify_ids.empty?

      SpotifyTrack.unscoped.where(spotify_id: spotify_ids).includes(:track).to_a
                  .group_by { |track| track.track&.isrc.presence || [:track, track.track_id] }
                  .count { |_track_id, tracks| tracks.map(&:spotify_id).uniq.size > 1 }
    end

    def write_and_verify(tracks)
      PlaylistTrackWriter.call(
        session:,
        playlist_id:,
        spotify_tracks: tracks,
        source:,
        verify: true
      )
    end
  end
end
