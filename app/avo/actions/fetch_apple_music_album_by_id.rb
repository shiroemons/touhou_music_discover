# frozen_string_literal: true

class FetchAppleMusicAlbumById < Avo::BaseAction
  self.name = 'Apple MusicアルバムIDから取得'
  self.standalone = true
  self.visible = -> { view == :index }

  field :album_id, as: :text, required: true, help: 'Apple MusicのアルバムIDを入力してください'

  def handle(**args)
    field = args.values_at(:fields).first
    album_id = field['album_id']
    return error('アルバムIDを入力してください') if album_id.blank?

    begin
      am_album = AppleMusic::Album.find(album_id)
      return error('アルバムが見つかりませんでした') if am_album.nil?
    rescue AppleMusic::ApiError
      return error('アルバムが見つかりませんでした')
    end

    if AppleMusicAlbum.exists?(apple_music_id: album_id)
      apple_music_album = AppleMusicAlbum.find_by(apple_music_id: album_id)
      jan_code = am_album.upc
      album = ::Album.find_or_create_by!(jan_code:)
      apple_music_album.update(
        album_id: album.id,
        payload: am_album.as_json
      )
      succeed 'アルバム情報とトラックの取得が完了しました'
    else
      am_album = AppleMusicClient::Album.fetch(album_id)
      return error('アルバムが見つかりませんでした') if am_album.nil?

      apple_music_album = AppleMusicAlbum.find_by(apple_music_id: album_id)
    end

    AppleMusicClient::Track.fetch_album_tracks(apple_music_album)

    succeed 'アルバム情報とトラックの取得が完了しました'
    reload
  end
end
