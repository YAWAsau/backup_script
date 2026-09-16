# unixsock: C → Rust honest parity audit (r550)

| metric | C | Rust | missing / bad |
|---|---:|---:|---:|
| bytes | 15677 | 23544 | - |
| lines | 479 | 611 | - |
| commands | 5 | 7 | 0 |
| marker prefixes | 0 | 0 | 0 |
| implementation function names | 16 | 32 | 9 |
| empty stub functions | - | 0 | 0 |

## Missing commands

- none

## Missing marker prefixes

- none

## Missing implementation function names

- `consume_crlf`
- `copy_exact_response`
- `copy_fd`
- `parse_body_mode`
- `read_exact_discard_or_stdout`
- `read_header_line`
- `relay_daemon_chunks`
- `write_all`
- `write_stdout`

## Empty stubs detected

- none
