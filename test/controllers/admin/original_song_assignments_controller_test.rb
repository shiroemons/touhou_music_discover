# frozen_string_literal: true

require 'test_helper'

module Admin
  class OriginalSongAssignmentsControllerTest < ActionDispatch::IntegrationTest
    test 'shows albums with missing tracks by default' do
      missing_track = create_track(jan_code: '9777777779101', isrc: 'JPABC269101')
      linked_track = create_track(jan_code: '9777777779102', isrc: 'JPABC269102')
      linked_track.original_songs << create_original_song(code: 'ASSIGN-DEFAULT-001', title: 'Assigned Default Song')

      get admin_track_original_song_assignments_url

      assert_response :success
      assert_select 'h1', '楽曲の原曲紐づけ'
      assert_select 'nav.admin-nav a.admin-nav-link.active[href=?]', admin_track_original_song_assignments_path,
                    text: '楽曲の原曲紐づけ'
      assert_select 'a[href=?]', admin_resource_action_path('tracks', 'auto_assign_original_songs'),
                    text: '自動紐づけ候補を確認'
      assert_select 'input[type=hidden][name=?][value=?]', 'scroll', 'infinite'
      assert_select '.admin-view-mode-link.is-active', text: 'アルバム表示'
      assert_select '.admin-view-mode-link.is-active', text: '無限スクロール'
      assert_select 'select[name=?] option[selected]', 'status', text: '原曲未設定'
      assert_select 'input[name=?][type=?]', 'show_identifiers', 'checkbox', count: 1
      assert_select 'table.admin-original-song-assignment-table th', { text: 'JANコード', count: 0 }
      assert_select 'table.admin-original-song-assignment-table th', { text: 'ISRC', count: 0 }
      assert_select 'table.admin-original-song-album-table'
      album_headers = css_select('table.admin-original-song-album-table thead th').map { |header| header.text.strip }

      assert_equal %w[JANコード サークル アルバム 未設定楽曲数], album_headers
      assert_select 'details[data-controller=?]', 'admin-original-song-album', count: 1
      assert_select 'td', { text: missing_track.isrc, count: 0 }
      assert_select 'form[method=?]', 'post'
      assert_select 'input[name=?]', "assignments[#{missing_track.id}][original_song_codes]", count: 0
      assert_select 'input[name=?]', "assignments[#{linked_track.id}][original_song_codes]", count: 0
    end

    test 'loads only the missing tracks when an album is expanded' do
      album = Album.create!(jan_code: '9777777779103')
      missing_track = Track.create!(album:, isrc: 'JPABC269103')
      linked_track = Track.create!(album:, isrc: 'JPABC269104')
      linked_track.original_songs << create_original_song(code: 'ASSIGN-ALBUM-001', title: 'Assigned Album Song')

      get admin_track_original_song_assignment_album_url(album.jan_code)

      assert_response :success
      assert_select 'table.admin-original-song-album-track-table-inner'
      assert_select 'input[name=?]', "assignments[#{missing_track.id}][original_song_codes]"
      assert_select 'input[name=?]', "assignments[#{linked_track.id}][original_song_codes]", count: 0
      assert_select 'td.admin-original-song-search-cell', count: 1
    end

    test 'does not expose the album track endpoint for non-missing status' do
      album = Album.create!(jan_code: '9777777779104')
      track = Track.create!(album:, isrc: 'JPABC269105')
      track.original_songs << create_original_song(code: 'ASSIGN-ALBUM-002', title: 'Already Assigned Album Song')

      get admin_track_original_song_assignment_album_url(album.jan_code), params: { status: 'present' }

      assert_response :not_found
    end

    test 'supports pagination and infinite scroll display modes' do
      (Admin::Resource::DEFAULT_ITEMS + 1).times do |index|
        create_track(jan_code: format('977777777%04d', index), isrc: format('JPABC%07d', index))
      end

      get admin_track_original_song_assignments_url, params: { view: 'tracks' }

      assert_response :success
      assert_select '.admin-original-song-assignment-panel[data-controller~=?]', 'admin-infinite-scroll'
      assert_select '.admin-original-song-assignment-panel[data-admin-infinite-scroll-next-url-value*=?]', 'scroll=infinite'
      assert_select '.admin-original-song-assignment-panel[data-admin-infinite-scroll-next-url-value*=?]', 'page=2'
      assert_select 'tbody[data-admin-infinite-scroll-target=?]', 'rows'
      assert_select '.admin-infinite-scroll-status', text: '下までスクロールすると追加で読み込みます。'
      assert_select '.admin-infinite-scroll-sentinel'
      assert_select 'nav.admin-pagination', 0

      get admin_track_original_song_assignments_url, params: { scroll: 'pagination', view: 'tracks' }

      assert_response :success
      assert_select '.admin-view-mode-link.is-active', text: 'ページ送り'
      assert_select 'nav.admin-pagination[aria-label=?]', 'ページ送り'
      assert_select '.admin-infinite-scroll-status', 0
    end

    test 'shows the streaming track number between album and name' do
      track = create_track(jan_code: '9777777779141', isrc: 'JPABC269141')
      spotify_album = create_spotify_album(album: track.album, spotify_id: 'assign-display-album')
      create_spotify_track(album: track.album, track:, spotify_album:, spotify_id: 'assign-display-track', track_number: 7)

      get admin_track_original_song_assignments_url, params: { view: 'tracks' }

      assert_response :success
      headers = css_select('thead tr th').map { |header| header.text.strip }

      assert_equal %w[サークル アルバム名 トラック番号 名前 原曲検索 設定済み原曲], headers
      assert_select 'tbody tr td:nth-child(3)', text: '7'
      assert_select '.admin-original-song-paste-hint',
                    text: '複数行は区切り文字があれば曲ごとに配布。区切り文字なしは現在の曲へ。Shift貼り付けで1行ずつ配布。'
    end

    test 'renders album and track names as copy buttons' do
      track = create_track(jan_code: '9777777779142', isrc: 'JPABC269142')
      spotify_album = create_spotify_album(album: track.album, spotify_id: 'assign-copy-album')
      create_spotify_track(album: track.album, track:, spotify_album:, spotify_id: 'assign-copy-track', track_number: 1)

      get admin_track_original_song_assignments_url, params: { view: 'tracks' }

      assert_response :success
      assert_select 'form.admin-original-song-assignment-form[data-controller~=?]', 'admin-clipboard'
      assert_select '.admin-copy-status[data-admin-clipboard-target=?][aria-live=?]', 'status', 'polite'
      assert_select 'td:nth-child(2) button.admin-copyable-value[type=?][data-action=?][data-admin-clipboard-text-value=?]',
                    'button', 'admin-clipboard#copy', 'assign-copy-album', text: 'assign-copy-album'
      assert_select 'td:nth-child(4) button.admin-copyable-value[type=?][data-action=?][data-admin-clipboard-text-value=?]',
                    'button', 'admin-clipboard#copy', 'assign-copy-track', text: 'assign-copy-track'
    end

    test 'renders album names as copy buttons in album view' do
      track = create_track(jan_code: '9777777779144', isrc: 'JPABC269144')
      create_spotify_album(album: track.album, spotify_id: 'assign-copy-group-album')

      get admin_track_original_song_assignments_url

      assert_response :success
      assert_select 'summary.admin-original-song-album-summary .admin-copyable-value[type=?][data-action=?][data-admin-clipboard-text-value=?]',
                    'button', 'admin-clipboard#copy', 'assign-copy-group-album', text: 'assign-copy-group-album'
    end

    test 'shows the album thumbnail without adding it to the track name' do
      track = create_track(jan_code: '9777777779143', isrc: 'JPABC269143')
      spotify_album = create_spotify_album(
        album: track.album,
        spotify_id: 'assign-thumbnail-album',
        image_url: 'https://example.test/assign-thumbnail.jpg'
      )
      create_spotify_track(album: track.album, track:, spotify_album:, spotify_id: 'assign-thumbnail-track', track_number: 1)

      get admin_track_original_song_assignments_url, params: { view: 'tracks' }

      assert_response :success
      assert_select 'td.admin-original-song-assignment-album-cell img.admin-record-thumb', count: 1
      assert_select 'td.admin-original-song-assignment-track-name-cell img.admin-record-thumb', count: 0
    end

    test 'can show tracks that already have original songs' do
      missing_track = create_track(jan_code: '9777777779111', isrc: 'JPABC269111')
      linked_track = create_track(jan_code: '9777777779112', isrc: 'JPABC269112')
      linked_track.original_songs << create_original_song(code: 'ASSIGN-PRESENT-001', title: 'Assigned Present Song')

      get admin_track_original_song_assignments_url, params: { status: 'present', view: 'tracks' }

      assert_response :success
      assert_select 'input[name=?]', "assignments[#{linked_track.id}][original_song_codes]"
      assert_select 'input[name=?]', "assignments[#{missing_track.id}][original_song_codes]", count: 0
    end

    test 'can show track identifiers when requested' do
      track = create_track(jan_code: '9777777779113', isrc: 'JPABC269113')

      get admin_track_original_song_assignments_url, params: { show_identifiers: '1', view: 'tracks' }

      assert_response :success
      assert_select 'input[name=?][type=?][checked=?]', 'show_identifiers', 'checkbox', 'checked'
      assert_select 'th', text: 'JANコード'
      assert_select 'th', text: 'ISRC'
      assert_select 'td', text: track.jan_code
      assert_select 'td', text: track.isrc
    end

    test 'orders tracks by streaming track number within the same album' do
      album = Album.create!(jan_code: '9777777779115')
      spotify_album = create_spotify_album(album:, spotify_id: 'assign-order-album')
      second_track = Track.create!(album:, isrc: 'JPABC2691152')
      first_track = Track.create!(album:, isrc: 'JPABC2691151')
      create_spotify_track(album:, track: second_track, spotify_album:, spotify_id: 'assign-order-track-2', track_number: 2)
      create_spotify_track(album:, track: first_track, spotify_album:, spotify_id: 'assign-order-track-1', track_number: 1)

      get admin_track_original_song_assignments_url, params: { q: album.jan_code, view: 'tracks' }

      assert_response :success
      assert_operator response.body.index('assign-order-track-1'), :<, response.body.index('assign-order-track-2')
    end

    test 'updates original song assignments with multiple selected songs' do
      track = create_track(jan_code: '9777777779121', isrc: 'JPABC269121')
      first_song = create_original_song(code: 'ASSIGN-UPDATE-001', title: 'Assigned Update First', track_number: 1)
      second_song = create_original_song(code: 'ASSIGN-UPDATE-002', title: 'Assigned Update Second', track_number: 2)

      patch admin_track_original_song_assignments_url,
            params: {
              view: 'tracks',
              scroll: 'pagination',
              assignments: {
                track.id => {
                  original_song_codes: "#{first_song.code},#{second_song.code}"
                }
              }
            }

      assert_redirected_to admin_track_original_song_assignments_path(view: 'tracks', scroll: 'pagination')
      assert_equal [first_song.code, second_song.code], track.reload.original_songs.order(:track_number).pluck(:code)
    end

    test 'does not persist partial updates when an original song code is invalid' do
      valid_track = create_track(jan_code: '9777777779131', isrc: 'JPABC269131')
      invalid_track = create_track(jan_code: '9777777779132', isrc: 'JPABC269132')
      song = create_original_song(code: 'ASSIGN-ROLLBACK-001', title: 'Assigned Rollback Song')

      patch admin_track_original_song_assignments_url,
            params: {
              assignments: {
                valid_track.id => { original_song_codes: song.code },
                invalid_track.id => { original_song_codes: 'ASSIGN-MISSING-999' }
              }
            }

      assert_redirected_to admin_track_original_song_assignments_path
      assert_empty valid_track.reload.original_songs
      assert_empty invalid_track.reload.original_songs
    end

    test 'searches original song options' do
      create_original_song(code: 'ASSIGN-OPTION-001', title: 'Needle Mountain')
      create_original_song(code: 'ASSIGN-OPTION-002', title: 'Unrelated Song')

      get admin_track_original_song_assignment_options_url, params: { q: 'Needle' }

      assert_response :success
      options = response.parsed_body.fetch('options')
      option_values = options.map { |option| option.fetch('value') }

      assert_equal ['ASSIGN-OPTION-001'], option_values
      assert_match(/Needle Mountain/, options.first.fetch('label'))
    end

    test 'resolves pasted original song titles split by common delimiters' do
      first_song = create_original_song(code: 'ASSIGN-PASTE-001', title: 'Paste First')
      second_song = create_original_song(code: 'ASSIGN-PASTE-002', title: 'Paste Second')
      third_song = create_original_song(code: 'ASSIGN-PASTE-003', title: 'Paste Third')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: "#{first_song.title} / #{second_song.title}、#{third_song.code}" }

      assert_response :success
      resolutions = response.parsed_body.fetch('resolutions')
      resolution_queries = resolutions.map { |resolution| resolution.fetch('query') }
      resolution_option_values = resolutions.map { |resolution| resolution.fetch('options').pluck('value') }

      assert_equal ['Paste First', 'Paste Second', 'ASSIGN-PASTE-003'], resolution_queries
      assert_equal [[first_song.code], [second_song.code], [third_song.code]], resolution_option_values
    end

    test 'resolves slash-separated original songs independently on each pasted line' do
      first_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-001', title: '蠢々秋月　～ Mooned Insect')
      second_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-002', title: 'もう歌しか聞こえない')
      third_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-003', title: '少女綺想曲　～ Dream Battle')
      fourth_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-004', title: '恋色マスタースパーク')
      fifth_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-005', title: 'シンデレラケージ　～ Kagome-Kagome')
      sixth_song = create_original_song(code: 'ASSIGN-PASTE-ROWS-006', title: 'エクステンドアッシュ　～ 蓬莱人')

      get admin_resolve_track_original_song_assignments_url,
          params: {
            text: <<~TEXT
              #{first_song.title}/#{second_song.title}
              #{third_song.title}/#{fourth_song.title}
              #{fifth_song.title}/#{sixth_song.title}
            TEXT
          }

      assert_response :success
      resolutions = response.parsed_body.fetch('resolutions')
      resolution_queries = resolutions.map { |resolution| resolution.fetch('query') }
      resolution_option_values = resolutions.map { |resolution| resolution.fetch('options').pluck('value') }

      assert_equal [first_song.title, second_song.title, third_song.title, fourth_song.title, fifth_song.title, sixth_song.title],
                   resolution_queries
      assert_equal [[first_song.code], [second_song.code], [third_song.code], [fourth_song.code], [fifth_song.code], [sixth_song.code]],
                   resolution_option_values
    end

    test 'does not split a pasted original song title that contains common delimiters' do
      comma_song = create_original_song(code: 'ASSIGN-PASTE-DELIMITER-001', title: 'Paste、Delimiter Song')
      slash_song = create_original_song(code: 'ASSIGN-PASTE-DELIMITER-002', title: 'Paste／Delimiter Song')
      ascii_comma_song = create_original_song(code: 'ASSIGN-PASTE-DELIMITER-003', title: 'Paste, Delimiter Song')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: "#{comma_song.title}\n#{slash_song.title}\n#{ascii_comma_song.title}" }

      assert_response :success
      resolutions = response.parsed_body.fetch('resolutions')
      resolution_queries = resolutions.map { |resolution| resolution.fetch('query') }
      resolution_option_values = resolutions.map { |resolution| resolution.fetch('options').pluck('value') }

      assert_equal [comma_song.title, slash_song.title, ascii_comma_song.title], resolution_queries
      assert_equal [[comma_song.code], [slash_song.code], [ascii_comma_song.code]], resolution_option_values
    end

    test 'splits pasted songs while preserving delimiters inside known titles' do
      comma_song = create_original_song(code: 'ASSIGN-PASTE-MIXED-001', title: 'Paste、Known Song')
      slash_song = create_original_song(code: 'ASSIGN-PASTE-MIXED-002', title: 'Paste／Known Song')
      ascii_comma_song = create_original_song(code: 'ASSIGN-PASTE-MIXED-003', title: 'Paste, Known Song')
      plain_song = create_original_song(code: 'ASSIGN-PASTE-MIXED-004', title: 'Paste Plain Song')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: "#{comma_song.title}、#{slash_song.title}／#{ascii_comma_song.title},#{plain_song.title}" }

      assert_response :success
      resolutions = response.parsed_body.fetch('resolutions')
      resolution_queries = resolutions.map { |resolution| resolution.fetch('query') }
      resolution_option_values = resolutions.map { |resolution| resolution.fetch('options').pluck('value') }

      assert_equal [comma_song.title, slash_song.title, ascii_comma_song.title, plain_song.title], resolution_queries
      assert_equal [[comma_song.code], [slash_song.code], [ascii_comma_song.code], [plain_song.code]], resolution_option_values
    end

    test 'returns multiple choices for ambiguous pasted original song titles' do
      first_song = create_original_song(code: 'ASSIGN-AMBIGUOUS-001', title: 'Ambiguous Paste Song')
      second_song = create_original_song(code: 'ASSIGN-AMBIGUOUS-002', title: 'Ambiguous Paste Song')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: 'Ambiguous Paste Song' }

      assert_response :success
      options = response.parsed_body.fetch('resolutions').first.fetch('options')
      option_values = options.map { |option| option.fetch('value') }

      assert_equal [first_song.code, second_song.code], option_values
    end

    test 'resolves pasted titles with normalized spaces' do
      song = create_original_song(code: 'ASSIGN-SPACE-001', title: 'Space　Normalized Song')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: 'Space Normalized Song' }

      assert_response :success
      options = response.parsed_body.fetch('resolutions').first.fetch('options')
      option_values = options.map { |option| option.fetch('value') }

      assert_equal [song.code], option_values
    end

    test 'resolves pasted titles with compact tilde spacing' do
      song = create_original_song(code: 'ASSIGN-TILDE-001', title: '最後の一人は慣れてるから　～ Stone Goddess')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: '最後の一人は慣れてるから ～Stone Goddess' }

      assert_response :success
      options = response.parsed_body.fetch('resolutions').first.fetch('options')
      option_values = options.map { |option| option.fetch('value') }

      assert_equal [song.code], option_values
    end

    test 'resolves pasted titles with normalized question marks' do
      song = create_original_song(code: 'ASSIGN-QUESTION-001', title: 'U.N.オーエンは彼女なのか？')

      get admin_resolve_track_original_song_assignments_url,
          params: { text: 'U.N.オーエンは彼女なのか?' }

      assert_response :success
      options = response.parsed_body.fetch('resolutions').first.fetch('options')
      option_values = options.map { |option| option.fetch('value') }

      assert_equal [song.code], option_values
    end

    test 'resolves pasted titles with original song labels and wrapper quotes' do
      first_song = create_original_song(code: 'ASSIGN-LABEL-001', title: '妖魔夜行')
      second_song = create_original_song(code: 'ASSIGN-LABEL-002', title: 'U.N.オーエンは彼女なのか？')

      get admin_resolve_track_original_song_assignments_url,
          params: {
            text: <<~TEXT
              """
              原曲: 妖魔夜行
              原曲： U.N.オーエンは彼女なのか?
              """
            TEXT
          }

      assert_response :success
      resolutions = response.parsed_body.fetch('resolutions')
      resolution_queries = resolutions.map { |resolution| resolution.fetch('query') }
      resolution_option_values = resolutions.map { |resolution| resolution.fetch('options').pluck('value') }

      assert_equal ['妖魔夜行', 'U.N.オーエンは彼女なのか?'], resolution_queries
      assert_equal [[first_song.code], [second_song.code]], resolution_option_values
    end

    private

    def create_track(jan_code:, isrc:)
      album = Album.create!(jan_code:)
      Track.create!(album:, isrc:)
    end

    def create_spotify_album(album:, spotify_id:, image_url: nil)
      SpotifyAlbum.create!(
        album:,
        spotify_id:,
        album_type: 'album',
        name: spotify_id,
        label: Album::TOUHOU_MUSIC_LABEL,
        active: true,
        payload: {
          'available_markets' => ['JP'],
          'images' => (image_url.present? ? [{ 'url' => image_url }] : [])
        }
      )
    end

    def create_spotify_track(album:, track:, spotify_album:, spotify_id:, track_number:)
      SpotifyTrack.create!(
        album:,
        track:,
        spotify_album:,
        spotify_id:,
        name: spotify_id,
        label: Album::TOUHOU_MUSIC_LABEL,
        disc_number: 1,
        track_number:,
        duration_ms: 180_000,
        payload: {}
      )
    end

    def create_original_song(code:, title:, track_number: 1)
      original = Original.find_or_create_by!(code: "#{code}-ORIGINAL") do |record|
        record.title = "#{title} Original"
        record.short_title = "#{title} Original"
        record.original_type = 'other'
        record.series_order = 900.0
      end

      OriginalSong.create!(
        code:,
        original:,
        title:,
        composer: 'ZUN',
        track_number:
      )
    end
  end
end
