# frozen_string_literal: true

require 'csv'

ActiveRecord::Base.connection.execute('TRUNCATE TABLE master_artists;')
insert_data = []
now = Time.zone.now
CSV.table('db/fixtures/master_artists.tsv', col_sep: "\t", converters: nil).each do |ma|
  insert_data << {
    name: ma[:name],
    key: ma[:key],
    streaming_type: ma[:streaming_type],
    created_at: now,
    updated_at: now
  }
end
MasterArtist.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
