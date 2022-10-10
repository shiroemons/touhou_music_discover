# frozen_string_literal: true

require 'csv'

circles = CSV.table('db/fixtures/circles.tsv', col_sep: "\t", converters: nil)
return if circles.size == Circle.count

insert_data = []
now = Time.zone.now
circles.each do |o|
  next if Circle.exists?(name: o[:name])

  insert_data << {
    name: o[:name],
    created_at: now,
    updated_at: now
  }
end
Circle.insert_all(insert_data) # rubocop:disable Rails/SkipsModelValidations
