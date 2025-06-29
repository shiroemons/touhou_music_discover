# frozen_string_literal: true

class LineMusicTrack < ApplicationRecord
  default_scope { includes(:album).order('albums.jan_code desc').order(disc_number: :asc).order(track_number: :asc) }

  belongs_to :album
  belongs_to :line_music_album
  belongs_to :track

  delegate :jan_code, :is_touhou, :circle_name, to: :album, allow_nil: true
  delegate :isrc, to: :track, allow_nil: true
  delegate :image_url, to: :line_music_album, allow_nil: true

  scope :line_music_id, ->(line_music_id) { find_by(line_music_id:) }
  scope :album_line_music_id, ->(line_music_id) { eager_load(:line_music_album).where(line_music_album: { line_music_id: }) }
  scope :is_touhou, -> { eager_load(:track).where(tracks: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:track).where(tracks: { is_touhou: false }) }

  def self.fetch_tracks
    Rails.logger.info 'LINE MUSIC トラック取得処理を開始します'
    album_ids = Album.pluck(:id)
    total_count = album_ids.size
    Rails.logger.info "処理対象アルバム数: #{total_count}件"

    processed_count = 0
    batch_size = 1000
    album_ids.each_slice(batch_size) do |ids|
      batch_count = ids.size
      Rails.logger.info "バッチ処理開始: #{batch_count}件"

      Album.includes(:spotify_album, :apple_music_album, :line_music_album).where(id: ids).then do |records|
        Parallel.each(records, in_processes: 4) do |r|
          process_album(r)
        end
      end

      processed_count += batch_count
      Rails.logger.info "バッチ処理完了: 合計 #{processed_count}/#{total_count}件処理済み"
    end
    Rails.logger.info 'LINE MUSIC トラック取得処理が完了しました'
  end

  def self.process_album(album)
    Rails.logger.info "アルバム処理: (ID: #{album.id})"

    if album.line_music_album.blank?
      Rails.logger.info 'LINE MUSIC アルバムが存在しないためスキップします'
      return
    end

    lm_album = album.line_music_album

    if lm_album.total_tracks == lm_album.line_music_tracks.size
      Rails.logger.info "すべてのトラックが既に登録済みのためスキップします: #{lm_album.name} (#{lm_album.line_music_tracks.size}/#{lm_album.total_tracks})"
      return
    end

    Rails.logger.info "トラック処理開始: #{lm_album.name} (現在: #{lm_album.line_music_tracks.size}/#{lm_album.total_tracks})"

    if album.spotify_album.present?
      Rails.logger.info "Spotifyアルバムからトラックを処理します: #{album.spotify_album.name}"
      match_and_save_tracks_for_spotify(album.spotify_album, lm_album)
    elsif album.apple_music_album.present?
      Rails.logger.info "Apple Musicアルバムからトラックを処理します: #{album.apple_music_album.name}"
      match_and_save_tracks_for_apple_music(album.apple_music_album, lm_album)
    end

    Rails.logger.info "トラック処理完了: #{lm_album.name} (現在: #{lm_album.line_music_tracks.reload.size}/#{lm_album.total_tracks})"
  end

  def self.match_and_save_tracks_for_spotify(spotify_album, line_music_album)
    Rails.logger.info "LINE MUSIC トラック取得: アルバムID #{line_music_album.line_music_id}"

    with_retry(max_attempts: 3) do
      lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
      Rails.logger.info "LINE MUSIC トラック取得成功: #{lm_tracks.size}件"

      matched_count = 0
      spotify_album.spotify_tracks.each do |s_track|
        Rails.logger.info "Spotifyトラック処理: #{s_track.name} (Disc: #{s_track.disc_number}, Track: #{s_track.track_number})"

        lm_track = lm_tracks.find { |lm| lm.disc_number == s_track.disc_number && lm.track_number == s_track.track_number }

        if lm_track
          Rails.logger.info "一致するLINE MUSICトラックが見つかりました: #{lm_track.track_title}"
          save_track(s_track.album_id, s_track.track_id, line_music_album, lm_track)
          matched_count += 1
        else
          Rails.logger.info '一致するLINE MUSICトラックが見つかりませんでした'
        end
      end

      Rails.logger.info "マッチング完了: #{matched_count}/#{spotify_album.spotify_tracks.size}件のトラックを処理しました"
    end
  end

  def self.match_and_save_tracks_for_apple_music(apple_music_album, line_music_album)
    Rails.logger.info "LINE MUSIC トラック取得: アルバムID #{line_music_album.line_music_id}"

    with_retry(max_attempts: 3) do
      lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
      Rails.logger.info "LINE MUSIC トラック取得成功: #{lm_tracks.size}件"

      matched_count = 0
      apple_music_album.apple_music_tracks.each do |am_track|
        Rails.logger.info "Apple Musicトラック処理: #{am_track.name} (Disc: #{am_track.disc_number}, Track: #{am_track.track_number})"

        lm_track = lm_tracks.find { |lm| lm.disc_number == am_track.disc_number && lm.track_number == am_track.track_number }

        if lm_track
          Rails.logger.info "一致するLINE MUSICトラックが見つかりました: #{lm_track.track_title}"
          save_track(am_track.album_id, am_track.track_id, line_music_album, lm_track)
          matched_count += 1
        else
          Rails.logger.info '一致するLINE MUSICトラックが見つかりませんでした'
        end
      end

      Rails.logger.info "マッチング完了: #{matched_count}/#{apple_music_album.apple_music_tracks.size}件のトラックを処理しました"
    end
  end

  def self.save_track(album_id, track_id, lm_album, lm_track)
    url = "https://music.line.me/webapp/track/#{lm_track.track_id}"
    Rails.logger.info "LINE MUSIC トラック情報保存: #{lm_track.track_title} (ID: #{lm_track.track_id})"

    line_music_track = ::LineMusicTrack.find_or_create_by!(
      album_id:,
      track_id:,
      line_music_album_id: lm_album.id,
      line_music_id: lm_track.track_id,
      name: lm_track.track_title,
      url:,
      disc_number: lm_track.disc_number,
      track_number: lm_track.track_number
    )
    line_music_track.update(payload: lm_track.as_json)
    Rails.logger.info "LINE MUSIC トラック情報を保存しました: #{lm_track.track_title}"
  end

  # リトライ機能を提供するヘルパーメソッド
  def self.with_retry(max_attempts: 3, retry_delay: 2)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue Faraday::ConnectionFailed, Net::OpenTimeout => e
      if attempts < max_attempts
        Rails.logger.warn "接続エラーが発生しました。#{attempts}回目のリトライを実行します: #{e.message}"
        sleep retry_delay * attempts # 指数バックオフ
        retry
      else
        Rails.logger.error "最大リトライ回数(#{max_attempts}回)に達しました: #{e.message}"
        raise
      end
    end
  end

  def artist_name
    payload['artists']&.map { it['artist_name'] }&.join(' / ')
  end
end
