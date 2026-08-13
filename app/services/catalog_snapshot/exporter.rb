# frozen_string_literal: true

module CatalogSnapshot
  class Exporter
    attr_reader :output_dir

    def initialize(output_dir: DEFAULT_OUTPUT_DIR, now: Time.current)
      @output_dir = Pathname.new(output_dir.to_s)
      @output_dir = Rails.root.join(@output_dir) unless @output_dir.absolute?
      @now = now
    end

    def preflight
      catalog = Builder.new.build
      report = QualityGate.new(catalog).call
      report_path = write_report(report, prefix: 'preflight')
      { valid: report.valid?, report:, report_path: }
    end

    def call
      catalog = Builder.new.build
      report = QualityGate.new(catalog).call
      unless report.valid?
        report_path = write_report(report, prefix: 'export-failed')
        raise Error.new("Catalog snapshot quality gate failed: #{report.errors.length} error(s); report=#{report_path}", report:)
      end

      rows = RowBuilder.new(catalog).rows
      forbidden_keys = forbidden_export_keys(rows)
      if forbidden_keys.any?
        forbidden_keys.uniq.each do |key|
          report.add_error(:forbidden_export_field, 'Snapshot contains a forbidden field', key:)
        end
        report_path = write_report(report, prefix: 'export-failed')
        raise Error.new("Catalog snapshot contains forbidden fields; report=#{report_path}", report:)
      end

      rows['quality_report.json'] = report.to_h
      write_snapshot(rows)
    end

    private

    def write_snapshot(rows)
      FileUtils.mkdir_p(output_dir)
      temporary_dir = output_dir.join(".tmp-#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(temporary_dir)

      file_entries = []
      begin
        rows.keys.sort.each do |name|
          path = temporary_dir.join(name)
          write_jsonl(path, rows.fetch(name)) if name.end_with?('.jsonl')
          File.write(path, "#{JSON.generate(rows.fetch(name))}\n") if name == 'quality_report.json'
          file_entries << {
            name:,
            sha256: Digest::SHA256.file(path).hexdigest,
            rows: name == 'quality_report.json' ? 1 : rows.fetch(name).length
          }
        end

        snapshot_digest = Digest::SHA256.hexdigest(JSON.generate(file_entries))
        snapshot_id = "#{@now.utc.iso8601}-#{snapshot_digest[0, 16]}"
        manifest = {
          schema_version: SCHEMA_VERSION,
          snapshot_id:,
          generated_at: @now.utc.iso8601,
          files: file_entries
        }
        File.write(temporary_dir.join('manifest.json'), "#{JSON.pretty_generate(manifest)}\n")

        final_dir = output_dir.join(snapshot_id)
        if final_dir.exist?
          existing_manifest_path = final_dir.join('manifest.json')
          existing_manifest = JSON.parse(existing_manifest_path.read)
          if existing_manifest['files'] == file_entries
            FileUtils.remove_entry_secure(temporary_dir)
            return { snapshot_id:, path: final_dir.to_s, manifest: existing_manifest, reused: true }
          end

          raise Error, "Catalog snapshot destination already exists with different contents: #{final_dir}"
        end

        FileUtils.mv(temporary_dir, final_dir)
        { snapshot_id:, path: final_dir.to_s, manifest: }
      rescue StandardError
        FileUtils.remove_entry_secure(temporary_dir) if temporary_dir.exist?
        raise
      end
    end

    def write_jsonl(path, rows)
      File.open(path, 'w') do |file|
        rows.each do |row|
          file.write(JSON.generate(row))
          file.write("\n")
        end
      end
    end

    def forbidden_export_keys(value)
      case value
      when Hash
        value.each_with_object([]) do |(key, child), keys|
          key_name = key.to_s.downcase
          keys << key_name if FORBIDDEN_EXPORT_KEYS.include?(key_name)
          keys.concat(forbidden_export_keys(child))
        end
      when Array
        value.flat_map { |child| forbidden_export_keys(child) }
      else
        []
      end
    end

    def write_report(report, prefix:)
      report_dir = output_dir.join('reports')
      FileUtils.mkdir_p(report_dir)
      path = report_dir.join("#{prefix}-#{@now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(4)}.json")
      File.write(path, "#{JSON.pretty_generate(report.to_h)}\n")
      path.to_s
    end
  end
end
