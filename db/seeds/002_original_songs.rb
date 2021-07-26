# frozen_string_literal: true

require 'csv'

ActiveRecord::Base.connection.execute('TRUNCATE TABLE original_songs;')
insert_data = []
now = Time.zone.now
CSV.table('db/fixtures/original_songs.tsv', col_sep: "\t", converters: nil).each do |os|
  insert_data << {
    code: os[:code],
    original_code: os[:original_code],
    title: os[:title],
    composer: os[:composer].to_s,
    track_number: os[:track_number].to_i,
    is_duplicate: os[:is_duplicate].to_s == '1',
    created_at: now,
    updated_at: now
  }
end
OriginalSong.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
