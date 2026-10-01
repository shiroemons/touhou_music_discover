# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'tmpdir'

class DbRestoreTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join('scripts/db_restore').to_s
  CLIENT_COMMANDS = %w[pg_dump pg_restore createdb dropdb].freeze

  def test_missing_backup_reports_default_target_without_connecting
    Dir.mktmpdir('db-restore-', Rails.root.join('tmp')) do |directory|
      output, status = Open3.capture2e({ 'RESTORE_DB' => nil, 'BACKUP_FILE' => nil }, SCRIPT, chdir: directory)

      assert_equal 1, status.exitstatus, output
      assert_includes output, '復元先DB: touhou_music_discover_development'
      assert_includes output, 'リストア失敗'
    end
  end

  def test_invalid_restore_targets_are_rejected_without_running_pg_restore
    Dir.mktmpdir('db-restore-', Rails.root.join('tmp')) do |directory|
      backup = File.join(directory, 'backup.bak')
      marker = File.join(directory, 'pg_restore_called')
      client = File.join(directory, 'pg_restore')
      File.write(backup, 'not a PostgreSQL archive')
      File.write(client, "#!/bin/sh\n: > \"#{marker}\"\n")
      File.chmod(0o700, client)
      env = { 'PATH' => "#{directory}:#{ENV.fetch('PATH')}", 'BACKUP_FILE' => backup }
      targets = ['service=production', 'postgresql://localhost/production', '',
                 'touhou_music_discover_production', 'touhou_music_discover_test',
                 'touhou_music_discover_restore_check_bad-name',
                 'touhou_music_discover_restore_check_bad name', "touhou_music_discover_restore_check_bad\nname"]

      targets.each do |database|
        output, status = Open3.capture2e(env.merge('RESTORE_DB' => database), SCRIPT)

        assert_equal 1, status.exitstatus, output
        assert_includes output, 'RESTORE_DBには開発DBまたは検証用DBの名前だけを指定してください。'
        assert_not File.exist?(marker), output
      end
    end
  end

  def test_restore_is_atomic_and_reports_success_and_failures
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    env = { 'PGHOST' => config[:host] || ENV.fetch('PGHOST', nil), 'PGPORT' => config[:port].to_s,
            'PGUSER' => config[:username] || ENV.fetch('PGUSER', nil),
            'PGPASSWORD' => config[:password] || ENV.fetch('PGPASSWORD', nil) }
    begin
      check_postgresql_clients(env)
      connection = PG.connect(host: env['PGHOST'], port: env['PGPORT'], user: env['PGUSER'],
                              password: env['PGPASSWORD'], dbname: 'postgres')
      connection.close
    rescue Errno::ENOENT, PG::ConnectionBad => e
      skip "PostgreSQLが利用できません: #{e.message}"
    end

    database = "touhou_music_discover_restore_check_#{SecureRandom.hex(8)}"
    output, status = Open3.capture2e(env, 'createdb', '--template=template0', database)

    assert_predicate status, :success?, output

    begin
      connection = PG.connect(host: env['PGHOST'], port: env['PGPORT'], user: env['PGUSER'],
                              password: env['PGPASSWORD'], dbname: database)
      Dir.mktmpdir('db-restore-', Rails.root.join('tmp')) do |directory|
        backup = File.join(directory, 'normal backup.bak')
        broken = File.join(directory, 'broken.bak')
        invalid = File.join(directory, 'invalid.bak')
        File.write(invalid, 'not a PostgreSQL archive')
        connection.exec("CREATE TABLE restore_probe (value text); INSERT INTO restore_probe VALUES ('backup')")
        output, status = Open3.capture2e(env, 'pg_dump', '-Fc', '--compress=gzip:6', '--no-owner',
                                         '-d', database, '-t', 'restore_probe', '-f', backup)

        assert_predicate status, :success?, output

        # FK の参照先をダンプから除外し、DROP・CREATE・COPY の後で確実に失敗させる。
        connection.exec(<<~SQL.squish)
          CREATE TABLE restore_parent (value text PRIMARY KEY);
          INSERT INTO restore_parent VALUES ('backup');
          ALTER TABLE restore_probe ADD FOREIGN KEY (value) REFERENCES restore_parent;
        SQL
        output, status = Open3.capture2e(env, 'pg_dump', '-Fc', '--compress=gzip:6', '--no-owner',
                                         '-d', database, '-t', 'restore_probe', '-f', broken)

        assert_predicate status, :success?, output
        connection.exec("DROP TABLE restore_parent CASCADE; UPDATE restore_probe SET value = 'before'")

        restore_env = env.merge('RESTORE_DB' => database, 'BACKUP_FILE' => broken)
        output, status = Open3.capture2e(restore_env, SCRIPT)

        assert_equal 1, status.exitstatus, output
        assert_includes output, 'restore_parent'
        assert_includes output, 'リストア失敗'
        assert_equal [['before']], connection.exec('SELECT value FROM restore_probe').values

        [File.join(directory, 'missing.bak'), invalid].each do |file|
          output, status = Open3.capture2e(restore_env.merge('BACKUP_FILE' => file), SCRIPT)

          assert_equal 1, status.exitstatus, output
          assert_includes output, 'リストア失敗'
        end
        output, status = Open3.capture2e(restore_env.merge('BACKUP_FILE' => backup, 'PGUSER' => database), SCRIPT)

        assert_equal 1, status.exitstatus, output
        assert_includes output, 'リストア失敗'
        assert_equal [['before']], connection.exec('SELECT value FROM restore_probe').values

        File.chmod(0o000, backup)
        output, status = Open3.capture2e(restore_env.merge('BACKUP_FILE' => backup), SCRIPT)

        assert_equal 1, status.exitstatus, output
        assert_includes output, '読み取る権限がありません'
        File.chmod(0o600, backup)

        output, status = Open3.capture2e(restore_env.merge('BACKUP_FILE' => backup), SCRIPT)

        assert_predicate status, :success?, output
        assert_includes output, "接続先: PGHOST=#{env['PGHOST']} PGPORT=#{env['PGPORT']}"
        assert_includes output, "復元先DB: #{database}"
        assert_includes output, "バックアップファイル: #{backup}"
        assert_includes output, 'リストア成功'
        assert_equal [['backup']], connection.exec('SELECT value FROM restore_probe').values
      end
    ensure
      connection&.close unless connection&.finished?
      output, status = Open3.capture2e(env, 'dropdb', database)

      assert_predicate status, :success?, output
    end
  end

  def test_older_dump_or_restore_client_skips_integration_test
    server_major = ActiveRecord::Base.connection.raw_connection.server_version / 10_000
    Dir.mktmpdir('db-clients-', Rails.root.join('tmp')) do |directory|
      %w[pg_dump pg_restore].each do |older_client|
        CLIENT_COMMANDS.each do |command|
          major = command == older_client ? server_major - 1 : server_major + 1
          client = File.join(directory, command)
          File.write(client, "#!/bin/sh\nprintf '%s\\n' '#{command} (PostgreSQL) #{major}.0'\n")
          File.chmod(0o700, client)
        end

        error = assert_raises(Minitest::Skip) { check_postgresql_clients('PATH' => directory) }

        assert_includes error.message, "#{older_client}のメジャーバージョン#{server_major - 1}"
        assert_includes error.message, "サーバーの#{server_major}未満"
      end
    end
  end

  private

  def check_postgresql_clients(env)
    server_major = ActiveRecord::Base.connection.raw_connection.server_version / 10_000
    CLIENT_COMMANDS.each do |command|
      output, status = Open3.capture2e(env, command, '--version')
      skip "PostgreSQLクライアント#{command}が利用できません: #{output}" unless status.success?
      next unless %w[pg_dump pg_restore].include?(command)

      client_major = output[/\(PostgreSQL\) (\d+)/, 1]&.to_i
      skip "#{command}のメジャーバージョンを確認できません: #{output}" unless client_major
      next if client_major >= server_major

      skip "#{command}のメジャーバージョン#{client_major}がサーバーの#{server_major}未満です。"
    end
  rescue Errno::ENOENT => e
    skip "PostgreSQLクライアントがありません: #{e.message}"
  end
end
