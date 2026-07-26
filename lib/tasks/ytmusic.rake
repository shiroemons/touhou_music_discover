# frozen_string_literal: true

namespace :ytmusic do
  desc 'YouTube Music アルバムを検索してアルバム情報を取得'
  task search_albums_and_save: :environment do
    max_count = Album.missing_ytmusic_album.count
    count = 0
    Album.includes(:spotify_album, :apple_music_album).missing_ytmusic_album.order(:jan_code).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      sleep(0.2)
      s_album = album.spotify_album
      am_album = album.apple_music_album
      if s_album.present?
        browse_id = YtmusicAlbum::JAN_TO_ALBUM_BROWSE_IDS[album.jan_code]
        next if browse_id && YtmusicAlbum.find_and_save(browse_id, s_album)

        spotify_artist_names = s_album.payload['artists'].filter { it['name'] != 'ZUN' }&.map { it['name'] }&.join(' ')
        if s_album.name.unicode_normalize.include?('【睡眠用】東方ピアノ癒やし子守唄')
          s_album_name = s_album.name.unicode_normalize.sub(/\(.*\z/, '').tr('０-９', '0-9').strip
          query = "#{s_album_name} #{spotify_artist_names}"
          next if YtmusicAlbum.search_and_save(query, s_album)
        end
        s_album_name = s_album.name.unicode_normalize
                              .gsub(/( -|─|☆|■|≒|⇔)/, ' ')
                              .gsub(/\p{In_Halfwidth_and_Fullwidth_Forms}+/) { |str| str.unicode_normalize(:nfkd) }
                              .gsub(/ [(|（\[].*[)|）\]]/, '')
                              .tr('０-９', '0-9').strip
        query = "#{s_album_name} #{spotify_artist_names}"
        next if YtmusicAlbum.search_and_save(query, s_album)
        next if YtmusicAlbum.search_and_save(s_album_name, s_album)
        next if YtmusicAlbum.search_and_save(s_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), s_album)
        next if YtmusicAlbum.search_and_save(s_album.name, s_album)
      end
      next if am_album.blank?

      am_album_name = am_album.name.gsub(/(-|─|☆|■|≒|⇔)/, '')
      artist_name = am_album.artist_name
      query = "#{am_album_name} #{artist_name}"
      next if YtmusicAlbum.search_and_save(query, am_album)
      next if YtmusicAlbum.search_and_save(am_album_name, am_album)
      next if YtmusicAlbum.search_and_save(am_album_name.sub(/ [(|\[].*[)|\]]\z/, ''), am_album)
      next if YtmusicAlbum.search_and_save(am_album.name, am_album)
      next if YtmusicAlbum.search_and_save(am_album.name.sub(' - EP', ''), am_album)
    end
  end

  desc 'YouTube Music アルバム情報からトラック情報を取得'
  task album_tracks_save: :environment do
    max_count = Album.count
    count = 0
    Album.includes(:ytmusic_album, spotify_album: [:spotify_tracks], apple_music_album: [:apple_music_tracks]).each do |album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      ytm_album = album.ytmusic_album
      next if ytm_album.blank?

      next if ytm_album.total_tracks == ytm_album.ytmusic_tracks.size

      ytm_tracks = ytm_album.payload&.dig('tracks')

      s_album = album.spotify_album
      if s_album.present?
        s_album.spotify_tracks.each do |s_track|
          ytm_track = ytm_tracks.find { it['track_number'] == s_track.track_number }
          next if ytm_track.nil?

          YtmusicTrack.save_track(album.id, s_track.track_id, ytm_album, ytm_track)
        end
        next
      end

      am_album = album.apple_music_album
      next if am_album.blank?

      am_album.apple_music_tracks.each do |am_track|
        ytm_track = ytm_tracks.find { it['track_number'] == am_track.track_number }
        next if ytm_track.nil?

        YtmusicTrack.save_track(album.id, am_track.track_id, ytm_album, ytm_track)
      end
    end

    # トラック保存が成功した後の追加ステップとして、未取得の配信日メタデータだけを取得して集計する。
    # 例外はここで握りつぶし、保存済みトラックには一切影響しないようにする。
    # SKIP_DISTRIBUTION_DATES=1 で自動実行を無効化できる（大量バックフィル等でこのタスク自体を高速に流したい場合の逃げ道）。
    unless ENV['SKIP_DISTRIBUTION_DATES'] == '1'
      begin
        DistributionDate::YtmusicCollector.new(apply: true, only_missing: true).run
      rescue StandardError => e
        Rails.logger.error "ytmusic:album_tracks_save: 配信日取得でエラーが発生しました: #{e.class}: #{e.message}"
        warn "配信日取得でエラーが発生しました（トラック保存には影響しません）: #{e.class}: #{e.message}"
      end
    end
  end

  desc 'YouTube Music アルバム情報を取得'
  task fetch_albums: :environment do
    max_count = YtmusicAlbum.where(url: nil).count
    count = 0
    YtmusicAlbum.where(url: nil).each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      album = YtMusic::Album.find(ytmusic_album.browse_id)
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url) if album
    end
  end

  desc 'YouTube Music アルバムとトラック情報を更新'
  task update_album_and_tracks: :environment do
    max_count = YtmusicAlbum.count
    count = 0
    YtmusicAlbum.all.each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      album = YtMusic::Album.find(ytmusic_album.browse_id)
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url) if album

      tracks = ytmusic_album.payload['tracks']
      ytmusic_album.ytmusic_tracks.each do |ytm_track|
        track = tracks.find { it['track_number'] == ytm_track.track_number }
        ytm_track.update_track(track) if track
      end
    end
  end

  desc 'YouTube Music アルバムの劣化した payload を再取得して修復する（既定はdry-run。APPLY=1で実行。PARALLEL_WORKERSでワーカー数を上書き可能。ALL=1で劣化の有無に関わらず全アルバムを再取得。回帰ガードにより既存payloadが悪化することはない）'
  task repair_degraded_album_payloads: :environment do
    Repair::YtmusicAlbumPayloads.new(
      apply: ENV['APPLY'] == '1',
      limit: ENV['LIMIT'].presence&.to_i,
      max_attempts: ENV.fetch('MAX_ATTEMPTS', Repair::YtmusicAlbumPayloads::DEFAULT_MAX_ATTEMPTS).to_i,
      sync_tracks: ENV['SYNC_TRACKS'] == '1',
      all: ENV['ALL'] == '1'
    ).run
  end

  desc 'YouTube Music の配信日を取得して集計する（既定はdry-run。APPLY=1で実行。PARALLEL_WORKERSでワーカー数を上書き可能（下げるとレート制御にもなる）。ALL=1で配信日確定済みのアルバムも含めて全件対象。ONLY_MISSING=0で取得済みトラックも再取得。REQUEST_INTERVALで1動画取得ごとのウェイト秒数を上書き可能（既定0.2秒。YouTube側が縮退レスポンスを返し始めるレートを避けるため)'
  task fetch_distribution_dates: :environment do
    DistributionDate::YtmusicCollector.new(
      apply: ENV['APPLY'] == '1',
      limit: ENV['LIMIT'].presence&.to_i,
      all: ENV['ALL'] == '1',
      only_missing: ENV['ONLY_MISSING'] != '0',
      max_attempts: ENV.fetch('MAX_ATTEMPTS', DistributionDate::YtmusicCollector::DEFAULT_MAX_ATTEMPTS).to_i,
      request_interval: ENV.fetch('REQUEST_INTERVAL', DistributionDate::YtmusicCollector::DEFAULT_REQUEST_INTERVAL).to_f
    ).run
  end

  desc '保存済みのYouTube Musicトラックから配信日を再集計する（HTTPアクセスなし・高速。既定は配信日未確定のアルバムのみ、ALL=1で全アルバムを対象。集計ルールを変更した後、再取得せずに再集計したい場合に使う）'
  task recalculate_distribution_dates: :environment do
    scope = ENV['ALL'] == '1' ? YtmusicAlbum.unscoped : YtmusicAlbum.unscoped.distribution_missing
    max_count = scope.count
    count = 0
    scope.find_each do |ytmusic_album|
      count += 1
      print "\rアルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"

      ytmusic_album.recalculate_distribution!
    end
  end

  desc '縮退レスポンス等で配信日関連カラムが汚染されたときに、リセットして再取得できるようにする（既定はdry-run。APPLY=1で実行。元に戻せません）'
  task reset_distribution_dates: :environment do
    album_scope = YtmusicAlbum.unscoped.where(
      'distributed_on IS NOT NULL OR youtube_published_on IS NOT NULL OR original_released_on IS NOT NULL OR ' \
      'distribution_source IS NOT NULL OR distribution_stats IS NOT NULL OR distribution_fetched_at IS NOT NULL OR ' \
      'distribution_track_metadata IS NOT NULL'
    )
    track_scope = YtmusicTrack.unscoped.where(
      'published_on IS NOT NULL OR uploaded_on IS NOT NULL OR original_released_on IS NOT NULL OR ' \
      'provided_by IS NOT NULL OR video_metadata IS NOT NULL OR video_fetched_at IS NOT NULL OR art_track = true'
    )
    album_count = album_scope.count
    track_count = track_scope.count

    puts "対象アルバム数: #{album_count} 件 / 対象トラック数: #{track_count} 件"

    unless ENV['APPLY'] == '1'
      puts 'dry-run のため何も変更していません。実行するには APPLY=1 を付けて再実行してください。'
      next
    end

    puts 'リセットを実行します。この操作は元に戻せません（再取得が必要になります）。'

    # rubocop:disable Rails/SkipsModelValidations -- 対象は数千行規模で、リセットするカラムに
    # バリデーション・コールバックは無いため、find_each + save! ではなく update_all で一括更新する。
    album_scope.update_all(
      distributed_on: nil, youtube_published_on: nil, original_released_on: nil,
      distribution_source: nil, distribution_stats: nil, distribution_fetched_at: nil,
      distribution_track_metadata: nil
    )
    track_scope.update_all(
      published_on: nil, uploaded_on: nil, original_released_on: nil,
      provided_by: nil, video_metadata: nil, video_fetched_at: nil, art_track: false
    )
    # rubocop:enable Rails/SkipsModelValidations

    puts "完了: アルバム #{album_count} 件 / トラック #{track_count} 件をリセットしました。"
  end
end
