# frozen_string_literal: true

require 'csv'

ActiveRecord::Base.connection.execute('TRUNCATE TABLE originals;')
now = Time.zone.now
insert_data = CSV.table('db/fixtures/originals.tsv', col_sep: "\t", converters: nil).map do |o|
  {
    code: o[:code],
    title: o[:title],
    short_title: o[:short_title],
    original_type: o[:original_type],
    series_order: o[:series_order],
    created_at: now,
    updated_at: now
  }
end
Original.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
