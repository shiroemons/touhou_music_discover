# frozen_string_literal: true

class ChangeTouhouFlag < Avo::BaseAction
  self.name = 'Change touhou flag'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    # Trackのis_touhouフラグを変更
    Track.includes(:original_songs).find_each do |track|
      original_songs = track.original_songs
      is_touhou = original_songs.all? { _1.title != 'オリジナル' } && !original_songs.all? { _1.title == 'その他' }
      track.update(is_touhou:) if track.is_touhou != is_touhou
    end

    # Albumのis_touhouフラグを変更
    Album.includes(:tracks).find_each do |album|
      # トラック内にis_touhouがtrueがあれば、そのアルバムはis_touhouはtrueとする
      is_touhou = album.tracks.map(&:is_touhou).any?
      album.update!(is_touhou:) if album.is_touhou != is_touhou
    end

    succeed 'Done!'
    reload
  end
end
