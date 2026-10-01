# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

class KillOrphanPortsTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join('scripts/kill_orphan_ports').to_s
  TASKFILE = Rails.root.join('Taskfile.yml').to_s
  # macOS の PID 範囲外の値を使い、組み込み kill が実プロセスへ届かないようにする。
  PID = '2147483646'
  REPLACEMENT_PID = '2147483647'

  def setup
    super
    @tmpdir = Dir.mktmpdir('kill-orphan-ports')
    @state_dir = File.join(@tmpdir, 'state')
    @bin_dir = File.join(@tmpdir, 'bin')
    @project_root = File.join(@tmpdir, 'worktree')
    FileUtils.mkdir_p([@state_dir, @bin_dir, @project_root])
    @project_root = File.realpath(@project_root)
    install_doubles
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
    super
  end

  def test_cwd_inside_project_root_with_spaces_is_stopped
    root_alias = File.join(@tmpdir, 'work tree')
    FileUtils.mkdir_p(root_alias)
    root = File.realpath(root_alias)

    status, output = run_script(env: {
                                  'ORPHAN_PROJECT_ROOT' => root,
                                  'ORPHAN_TEST_CWD' => root_alias,
                                  'ORPHAN_TEST_CHANGE_AT' => '3'
                                })

    assert_predicate status, :success?, output
    assert_includes output, '当該プロジェクトの孤児を停止します'
  end

  def test_sibling_worktree_is_kept
    sibling = "#{@project_root}-other"
    FileUtils.mkdir_p(sibling)

    status, output = run_script(env: { 'ORPHAN_TEST_CWD' => sibling })

    assert_predicate status, :success?, output
    assert_includes output, '停止しません'
    assert_not_includes output, '当該プロジェクトの孤児を停止します'
  end

  def test_root_prefix_in_command_does_not_prove_project_ownership
    status, output = run_script(env: {
                                  'ORPHAN_TEST_CWD' => @tmpdir,
                                  'ORPHAN_TEST_COMMAND' => "ruby server #{@project_root}-other"
                                })

    assert_predicate status, :success?, output
    assert_includes output, '停止しません'
    assert_not_includes output, '当該プロジェクトの孤児を停止します'
  end

  def test_unknown_cwd_is_held_on_database_port
    status, output = run_script(port: '5432', env: {
                                  'ORPHAN_TEST_CWD' => '',
                                  'ORPHAN_TEST_COMMAND' => "ruby server #{@project_root}"
                                })

    assert_not status.success?, output
    assert_includes output, '停止しません'
    assert_not_includes output, '当該プロジェクトの孤児を停止します'
  end

  def test_managed_services_and_unknown_manager_state_block_stopping
    managed_status, managed_output = run_script(env: {
                                                  'ORPHAN_TEST_CWD' => @project_root,
                                                  'ORPHAN_TEST_MANAGER' => 'running'
                                                })
    failed_status, failed_output = run_script(port: '5432', env: {
                                                'ORPHAN_TEST_CWD' => @project_root,
                                                'ORPHAN_TEST_MANAGER' => 'fail'
                                              })

    assert_not managed_status.success?, managed_output
    assert_includes managed_output, '管理中または判定保留:'
    assert_not_includes managed_output, '当該プロジェクトの孤児を停止します'
    assert_not failed_status.success?, failed_output
    assert_includes failed_output, '管理状態を確認できない'
    assert_not_includes failed_output, '当該プロジェクトの孤児を停止します'
  end

  def test_new_pid_after_term_is_reported_and_not_escalated
    status, output = run_script(env: {
                                  'ORPHAN_TEST_CWD' => @project_root,
                                  'ORPHAN_TEST_REPLACEMENT_PID' => REPLACEMENT_PID,
                                  'ORPHAN_TEST_CHANGE_AT' => '3',
                                  'ORPHAN_TEST_LISTENERS_AFTER_CHANGE' => REPLACEMENT_PID
                                })

    assert_predicate status, :success?, output
    assert_includes output, "新しいPIDのため停止しません: PID=#{REPLACEMENT_PID}"
    assert_not_includes output, '強制停止します'
  end

  def test_reused_pid_with_changed_start_time_is_not_escalated
    status, output = run_script(env: {
                                  'ORPHAN_TEST_CWD' => @project_root,
                                  'ORPHAN_TEST_START_CHANGE_AT' => '3',
                                  'ORPHAN_TEST_START_AFTER' => 'Tue Sep 30 15:20:12 2025'
                                })

    assert_predicate status, :success?, output
    assert_includes output, '開始時刻が変わったため強制停止しません'
    assert_not_includes output, '強制停止します'
  end

  def test_manager_state_is_rechecked_before_force_stop
    status, output = run_script(env: {
                                  'ORPHAN_TEST_CWD' => @project_root,
                                  'ORPHAN_TEST_MANAGER' => 'running_after_second'
                                })

    assert_not status.success?
    assert_includes output, '管理状態が変わったため強制停止しません'
    assert_not_includes output, '強制停止します'
  end

  def test_rails_only_listener_does_not_block_recover_force
    skip 'task コマンドが PATH にありません' unless system('/bin/sh', '-c', 'command -v task >/dev/null 2>&1')

    status, output = run_recover_force(env: {
                                         'ORPHAN_TEST_CWD' => @tmpdir,
                                         'ORPHAN_TEST_COMMAND' => 'ruby another-project/server'
                                       })

    assert_predicate status, :success?, output
    assert_includes output, '他プロジェクトまたは判定不能のため停止しません'
    assert_includes output, 'devboxサービスをバックグラウンドで起動します'
    assert_includes File.read(File.join(@state_dir, 'devbox.log')), 'services up'
  end

  def test_foreign_database_listener_still_blocks_recovery
    status, output = run_script(port: '6379', env: { 'ORPHAN_TEST_CWD' => @tmpdir })

    assert_not status.success?, output
    assert_includes output, '必須サービスのポート占有が残っています'
  end

  private

  def run_script(port: '41000', env: {})
    capture(script_env(port).merge(env), '/bin/sh', SCRIPT, chdir: Rails.root.to_s)
  end

  def run_recover_force(env: {})
    capture(script_env('41000').merge(env), 'task', '--taskfile', TASKFILE, 'recover-force', chdir: Rails.root.to_s)
  end

  def script_env(port)
    {
      'PATH' => "#{@bin_dir}:#{ENV.fetch('PATH', '')}",
      'ORPHAN_PROJECT_ROOT' => @project_root,
      'ORPHAN_PORTS' => port,
      'ORPHAN_TEST_PORT' => port,
      'ORPHAN_TEST_STATE_DIR' => @state_dir,
      'ORPHAN_TEST_PID' => PID,
      'ORPHAN_TEST_REPLACEMENT_PID' => '',
      'ORPHAN_TEST_LISTENERS_AFTER_CHANGE' => '',
      'ORPHAN_TEST_CHANGE_AT' => '999999',
      'ORPHAN_TEST_CWD' => @project_root,
      'ORPHAN_TEST_COMMAND' => 'ruby bin/rails server',
      'ORPHAN_TEST_MANAGER' => 'stopped',
      'ORPHAN_TEST_START' => 'Tue Sep 30 15:20:11 2025',
      'ORPHAN_TEST_START_AFTER' => '',
      'ORPHAN_TEST_START_CHANGE_AT' => '999999',
      'ORPHAN_TEST_DEVBOX_LOG' => File.join(@state_dir, 'devbox.log'),
      'RAILS_PORT_FILE' => File.join(@tmpdir, 'server.port'),
      'PORT' => '41000'
    }
  end

  def capture(env, *command, chdir:)
    stdout, stderr, status = Open3.capture3(env, *command, chdir:)
    [status, stdout + stderr]
  end

  def install_doubles
    write_executable('lsof', <<~'SH')
      #!/bin/sh
      case " $* " in
        *" -d cwd "*)
          pid=""
          previous=""
          for arg do
            if [ "$previous" = "-p" ]; then pid="$arg"; break; fi
            previous="$arg"
          done
          if [ -n "${ORPHAN_TEST_CWD:-}" ]; then
            printf 'p%s\nfcwd\nn%s\n' "$pid" "$ORPHAN_TEST_CWD"
          fi
          exit 0
          ;;
      esac

      port=""
      for arg do
        case "$arg" in -tiTCP:*) port="${arg#-tiTCP:}" ;; esac
      done
      [ "$port" = "${ORPHAN_TEST_PORT:-}" ] || exit 0

      count_file="$ORPHAN_TEST_STATE_DIR/lsof-$port"
      count=0
      if [ -r "$count_file" ]; then IFS= read -r count < "$count_file"; fi
      count=$((count + 1))
      printf '%s\n' "$count" > "$count_file"
      if [ "$count" -ge "${ORPHAN_TEST_CHANGE_AT:-999999}" ]; then
        for pid in ${ORPHAN_TEST_LISTENERS_AFTER_CHANGE:-}; do printf '%s\n' "$pid"; done
      else
        for pid in ${ORPHAN_TEST_PID:-}; do printf '%s\n' "$pid"; done
      fi
    SH

    write_executable('ps', <<~'SH')
      #!/bin/sh
      pid=""
      format=""
      previous=""
      for arg do
        if [ "$previous" = "-p" ]; then pid="$arg"; previous=""; continue; fi
        if [ "$previous" = "-o" ]; then format="$arg"; previous=""; continue; fi
        case "$arg" in -p|-o) previous="$arg" ;; esac
      done

      case "$format" in
        command=) printf '%s\n' "${ORPHAN_TEST_COMMAND:-ruby server}" ;;
        lstart=)
          count_file="$ORPHAN_TEST_STATE_DIR/ps-start-$pid"
          count=0
          if [ -r "$count_file" ]; then IFS= read -r count < "$count_file"; fi
          count=$((count + 1))
          printf '%s\n' "$count" > "$count_file"
          if [ "$count" -ge "${ORPHAN_TEST_START_CHANGE_AT:-999999}" ] && [ -n "${ORPHAN_TEST_START_AFTER:-}" ]; then
            printf '%s\n' "$ORPHAN_TEST_START_AFTER"
          else
            printf '%s\n' "${ORPHAN_TEST_START:-Tue Sep 30 15:20:11 2025}"
          fi
          ;;
      esac
    SH

    write_executable('devbox', <<~'SH')
      #!/bin/sh
      printf '%s\n' "$*" >> "$ORPHAN_TEST_DEVBOX_LOG"
      count_file="$ORPHAN_TEST_STATE_DIR/devbox-count"
      count=0
      if [ -r "$count_file" ]; then IFS= read -r count < "$count_file"; fi
      count=$((count + 1))
      printf '%s\n' "$count" > "$count_file"

      case "${ORPHAN_TEST_MANAGER:-stopped}" in
        fail) echo 'stub manager unavailable' >&2; exit 1 ;;
        running) echo 'Services running in process-compose' ;;
        running_after_second)
          if [ "$count" -ge 3 ]; then echo 'Services running in process-compose'; else echo 'No services are running'; fi
          ;;
        *) echo 'No services are running' ;;
      esac
    SH

    write_executable('sleep', "#!/bin/sh\nexit 0\n")
    write_executable('curl', <<~'SH')
      #!/bin/sh
      case " $* " in
        *" -w "*) printf '  status=200 time=0.001s\n' ;;
      esac
      exit 0
    SH
  end

  def write_executable(name, content)
    path = File.join(@bin_dir, name)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end
end
