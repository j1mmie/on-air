#!/usr/bin/env python3
"""Discord IPC monitor — writes 'true'/'false' to STATE_FILE based on voice channel."""

import glob
import json
import os
import socket
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

CLIENT_ID     = os.environ.get('ONAIR_DISCORD_CLIENT_ID', '')
CLIENT_SECRET = os.environ.get('ONAIR_DISCORD_CLIENT_SECRET', '')
STATE_FILE    = sys.argv[1] if len(sys.argv) > 1 else '/tmp/on_air_discord_state'
TOKEN_FILE    = Path.home() / '.config' / 'on-air' / 'discord_token.json'


def find_ipc_socket():
    candidates = []
    tmpdir = os.environ.get('TMPDIR', '').rstrip('/')
    if tmpdir:
        candidates.append(f'{tmpdir}/discord-ipc-0')
    candidates.append(os.path.join(tempfile.gettempdir(), 'discord-ipc-0'))
    candidates.append('/tmp/discord-ipc-0')
    candidates.extend(glob.glob('/var/folders/*/*/T/discord-ipc-0'))
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def write_frame(sock, op, data):
    payload = json.dumps(data).encode()
    sock.sendall(struct.pack('<II', op, len(payload)) + payload)


def read_frame(sock):
    buf = b''
    while len(buf) < 8:
        chunk = sock.recv(8 - len(buf))
        if not chunk:
            return None, None
        buf += chunk
    op, length = struct.unpack('<II', buf)
    buf = b''
    while len(buf) < length:
        chunk = sock.recv(length - len(buf))
        if not chunk:
            return None, None
        buf += chunk
    return op, json.loads(buf)


def send_cmd(sock, cmd, args, evt=None):
    obj = {'cmd': cmd, 'args': args, 'nonce': str(time.monotonic())}
    if evt:
        obj['evt'] = evt
    write_frame(sock, 1, obj)


def http_post(url, params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={'Content-Type': 'application/x-www-form-urlencoded'})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def save_token(data):
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    expiry = datetime.now(timezone.utc) + timedelta(seconds=data['expires_in'])
    with open(TOKEN_FILE, 'w') as f:
        json.dump({
            'access_token':  data['access_token'],
            'refresh_token': data['refresh_token'],
            'expires_at':    expiry.isoformat(),
        }, f)
    return data['access_token']


def get_token(sock):
    # Try stored token
    if TOKEN_FILE.exists():
        try:
            with open(TOKEN_FILE) as f:
                stored = json.load(f)
            exp = datetime.fromisoformat(stored['expires_at'])
            if exp > datetime.now(timezone.utc) + timedelta(minutes=5):
                return stored['access_token']
            if stored.get('refresh_token'):
                data = http_post('https://discord.com/api/oauth2/token', {
                    'grant_type':    'refresh_token',
                    'refresh_token': stored['refresh_token'],
                    'client_id':     CLIENT_ID,
                    'client_secret': CLIENT_SECRET,
                })
                return save_token(data)
        except Exception:
            pass

    # Full auth — Discord shows a one-time consent popup
    send_cmd(sock, 'AUTHORIZE', {'client_id': CLIENT_ID, 'scopes': ['rpc']})
    while True:
        _, frame = read_frame(sock)
        if frame is None:
            raise ConnectionError('Socket closed during AUTHORIZE')
        if frame.get('cmd') == 'AUTHORIZE':
            break

    data = http_post('https://discord.com/api/oauth2/token', {
        'grant_type':    'authorization_code',
        'code':          frame['data']['code'],
        'redirect_uri':  'http://localhost',
        'client_id':     CLIENT_ID,
        'client_secret': CLIENT_SECRET,
    })
    return save_token(data)


def set_state(in_call):
    with open(STATE_FILE, 'w') as f:
        f.write('true' if in_call else 'false')


def run():
    path = find_ipc_socket()
    if not path:
        raise FileNotFoundError('Discord IPC socket not found — is Discord running?')

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)

    # Handshake
    write_frame(sock, 0, {'v': 1, 'client_id': CLIENT_ID})
    _, frame = read_frame(sock)
    if not frame or frame.get('evt') != 'READY':
        raise ConnectionError(f'Expected READY, got {frame}')

    # Authenticate
    token = get_token(sock)
    send_cmd(sock, 'AUTHENTICATE', {'access_token': token})
    while True:
        _, frame = read_frame(sock)
        if frame is None:
            raise ConnectionError('Socket closed during AUTHENTICATE')
        if frame.get('cmd') == 'AUTHENTICATE':
            break
    if frame.get('evt') == 'ERROR':
        TOKEN_FILE.unlink(missing_ok=True)
        raise ConnectionError(f"Auth rejected: {frame['data']['message']}")

    # Get initial voice channel state
    send_cmd(sock, 'GET_SELECTED_VOICE_CHANNEL', {})
    while True:
        _, frame = read_frame(sock)
        if frame is None:
            raise ConnectionError('Socket closed during GET_SELECTED_VOICE_CHANNEL')
        if frame.get('cmd') == 'GET_SELECTED_VOICE_CHANNEL':
            break
    set_state(bool(frame.get('data') and frame['data'].get('id')))

    # Subscribe to voice channel changes
    send_cmd(sock, 'SUBSCRIBE', {}, 'VOICE_CHANNEL_SELECT')

    # Event loop
    while True:
        _, frame = read_frame(sock)
        if frame is None:
            break
        if frame.get('evt') == 'VOICE_CHANNEL_SELECT':
            set_state(bool(frame['data'].get('channel_id')))

    sock.close()


def main():
    if not CLIENT_ID or not CLIENT_SECRET:
        print('ONAIR_DISCORD_CLIENT_ID or ONAIR_DISCORD_CLIENT_SECRET not set',
              file=sys.stderr)
        sys.exit(1)

    set_state(False)
    while True:
        try:
            run()
        except Exception as e:
            print(f'Discord IPC: {e}', file=sys.stderr)
        set_state(False)
        time.sleep(5)


if __name__ == '__main__':
    main()
