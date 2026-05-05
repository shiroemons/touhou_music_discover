# frozen_string_literal: true

class ChangeTouhouFlag < Avo::BaseAction
  self.name = '東方フラグを変更'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    # 原曲紐づけがないTrackは未判定のため、falseには倒さない
    Track.includes(:original_songs).find_each do |track|
      original_songs = track.original_songs
      next if original_songs.empty?

      is_touhou = original_songs.all? { it.title != 'オリジナル' } && !original_songs.all? { it.title == 'その他' }
      track.update(is_touhou:) if track.is_touhou != is_touhou
    end

    # 原曲紐づけがないTrackを含むAlbumは未判定のため、falseには倒さない
    Album.includes(tracks: :original_songs).find_each do |album|
      next if album.tracks.empty?
      next if album.tracks.any? { |track| track.original_songs.empty? }

      is_touhou = album.tracks.map(&:is_touhou).any?
      album.update!(is_touhou:) if album.is_touhou != is_touhou
    end

    succeed 'Done!'
    reload
  end
end
