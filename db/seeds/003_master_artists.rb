# frozen_string_literal: true

require 'csv'

ActiveRecord::Base.connection.execute('TRUNCATE TABLE master_artists;')
now = Time.zone.now
insert_data = CSV.table('db/fixtures/master_artists.tsv', col_sep: "\t", converters: nil).map do |ma|
  {
    name: ma[:name],
    key: ma[:key],
    streaming_type: ma[:streaming_type],
    created_at: now,
    updated_at: now
  }
end
MasterArtist.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
