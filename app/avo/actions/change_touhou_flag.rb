# frozen_string_literal: true

class ChangeTouhouFlag < Avo::BaseAction
  self.name = '東方フラグを変更'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    total_count = Track.count + Album.count
    Admin::ActionProgress.start(total: total_count, message: '楽曲の東方フラグを再判定しています')

    # 原曲紐づけがないTrackは未判定のため、falseには倒さない
    Track.includes(:original_songs).find_each do |track|
      original_songs = track.original_songs
      if original_songs.present?
        is_touhou = original_songs.all? { it.title != 'オリジナル' } && !original_songs.all? { it.title == 'その他' }
        track.update(is_touhou:) if track.is_touhou != is_touhou
      end
      Admin::ActionProgress.advance(message: "楽曲を処理しています: #{track.jan_code}")
    end

    # 原曲紐づけがないTrackを含むAlbumは未判定のため、falseには倒さない
    Album.includes(tracks: :original_songs).find_each do |album|
      if album.tracks.present? && album.tracks.none? { |track| track.original_songs.empty? }
        is_touhou = album.tracks.map(&:is_touhou).any?
        album.update!(is_touhou:) if album.is_touhou != is_touhou
      end
      Admin::ActionProgress.advance(message: "アルバムを処理しています: #{album.jan_code}")
    end

    succeed 'Done!'
    reload
  end
end
