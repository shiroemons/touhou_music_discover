# frozen_string_literal: true

require 'csv'

circles = CSV.table('db/fixtures/circles.tsv', col_sep: "\t", converters: nil)
return if circles.size == Circle.count

ActiveRecord::Base.connection.execute('TRUNCATE TABLE circles_albums, circles;')
insert_data = []
now = Time.zone.now
circles.each do |o|
  insert_data << {
    name: o[:name],
    created_at: now,
    updated_at: now
  }
end
Circle.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
