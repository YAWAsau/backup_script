#!/usr/bin/env python3
import os, socket, subprocess, sys, tempfile, threading
BIN = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else './unixsock')

def run_unix(response, expected_rc, expected_body):
    root = tempfile.mkdtemp(prefix='unixsock_selftest_')
    path, header = os.path.join(root, 'sock'), os.path.join(root, 'header')
    request = b'cmd\nuser\npass\nurl\nextra\n0\n'
    received = []
    def server():
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(path); s.listen(1)
        c, _ = s.accept(); data = bytearray()
        while True:
            part = c.recv(65536)
            if not part: break
            data.extend(part)
        received.append(bytes(data)); c.sendall(response); c.close(); s.close()
    t = threading.Thread(target=server); t.start()
    while not os.path.exists(path): pass
    p = subprocess.run([BIN, 'relay-unix', path, '--header-file', header], input=request, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    t.join(); assert p.returncode == expected_rc, (p.returncode, p.stderr)
    assert received == [request]
    assert p.stdout == expected_body, (len(p.stdout), len(expected_body))
    return open(header, 'rb').read()

body = bytes((i * 37 + 5) % 256 for i in range(600321))
assert run_unix(f'HTTP 200\n{len(body)}\n'.encode() + body, 0, body) == f'HTTP 200\n{len(body)}\n'.encode()
framed = b'HTTP 200\n-2\n' + f'{len(body):x}\r\n'.encode() + body + b'\r\n0\r\n\r\n'
assert run_unix(framed, 0, body) == b'HTTP 200\n-2\n'
run_unix(b'HTTP 200\n100\n' + b'x' * 50, 5, b'x' * 50)
run_unix(b'HTTP 200\n-2\n100\r\n' + b'x' * 50, 5, b'x' * 50)
print('unixsock self-test: PASS')
