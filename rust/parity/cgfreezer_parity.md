# cgfreezer: C → Rust honest parity audit (r550)

| metric | C | Rust | missing / bad |
|---|---:|---:|---:|
| bytes | 126231 | 138941 | - |
| lines | 2874 | 2858 | - |
| commands | 38 | 74 | 0 |
| marker prefixes | 56 | 56 | 0 |
| implementation function names | 112 | 140 | 41 |
| empty stub functions | - | 0 | 0 |

## Missing commands

- none

## Missing marker prefixes

- none

## Missing implementation function names

- `build_freeze_path_from_pid`
- `cache_add`
- `cache_contains`
- `cache_remove`
- `cgroup_kill_probe_reason`
- `cmd_wchan_pid_list`
- `cmd_wchan_uid`
- `daemon_class_from_line`
- `handle_daemon_command_line`
- `handle_daemon_parent_command`
- `is_package_process`
- `is_pkg_char`
- `is_valid_pkg_name`
- `now_ms`
- `on_signal`
- `parent_tokenize`
- `parse_int_arg`
- `parse_scan_csv_item`
- `parse_status_uid`
- `parse_unified_path`
- `pidfd_open_compat`
- `pidfd_send_signal_compat`
- `print_binder_fields`
- `print_kill_target_fields`
- `print_wchan_entry`
- `proc_pid_exists`
- `proc_state_char`
- `read_cmdline`
- `read_file`
- `read_oom_score_adj`
- `read_proc_wchan`
- `read_u32_le`
- `same_kill_target`
- `sanitize_print`
- `scan_package`
- `skip_bytes`
- `sleep_ms`
- `token_list_contains`
- `tokenize_line`
- `user_id_from_uid`
- `write_file`

## Empty stubs detected

- none
