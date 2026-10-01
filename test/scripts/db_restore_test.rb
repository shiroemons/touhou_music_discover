# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'tmpdir'

class DbRestoreTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join('scripts/db_restore').to_s

  def test_missing_backup_reports_default_target_without_connecting
    Dir.mktmpdir('db-restore-', Rails.root.join('tmp')) do |directory|
      output, status = Open3.capture2e({ 'RESTORE_DB' => nil, 'BACKUP_FILE' => nil }, SCRIPT, chdir: directory)

      assert_equal 1, status.exitstatus, output
      assert_includes output, '復元先DB: touhou_music_discover_development'
      assert_includes output, 'リストア失敗'
    end
  end

  def test_restore_is_atomic_and_reports_success_and_failures
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    env = { 'PGHOST' => config[:host] || ENV.fetch('PGHOST', nil), 'PGPORT' => config[:port].to_s,
            'PGUSER' => config[:username] || ENV.fetch('PGUSER', nil),
            'PGPASSWORD' => config[:password] || ENV.fetch('PGPASSWORD', nil) }
    begin
      output, status = Open3.capture2e(env, 'pg_restore', '--version')
      skip "PostgreSQLクライアントがありません: #{output}" unless status.success?
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
end
