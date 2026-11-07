#!/usr/bin/env bash
# Linux thin-client launcher. JSON stdout; WM_DELETE_WINDOW only (never signal 1C).
# Dependencies: python3, python3-xlib, Xvfb, xdotool, xdpyinfo, ss, import or xwd.
# Example: start --version 8.3.27.2130 --connect '/S"onec-dev-server:2541\testbase"'
# An Xvfb started here stays running for reuse; stop closes only the 1C window.
exec python3 - "$@" <<'PY'
import argparse, datetime, fcntl, json, os, pathlib, re, shutil, subprocess, sys, time


def run(*args, **kw):
    return subprocess.run(args, text=True, capture_output=True, **kw)


def identity(pid):
    try:
        raw = pathlib.Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        if raw[0] == 'Z':
            return None
        return [os.readlink(f'/proc/{pid}/exe'), raw[19],
                pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                os.readlink(f'/proc/{pid}/ns/pid')]
    except (OSError, IndexError):
        return None


def main():
    class Parser(argparse.ArgumentParser):
        def error(self, message):
            raise ValueError(message)
    p = Parser()
    p.add_argument('action', choices=['start', 'status', 'capture', 'stop'])
    p.add_argument('--connect', default=os.getenv('QA_TC_CONNECT', ''))
    p.add_argument('--version', default=os.getenv('QA_TC_VERSION', ''))
    p.add_argument('--platforms', default=os.getenv('QA_TC_PLATFORMS', '/opt/1cv8/x86_64'))
    p.add_argument('--port', type=int, default=int(os.getenv('QA_TC_PORT', '1538')))
    p.add_argument('--display', default=os.getenv('QA_TC_DISPLAY', ':99'))
    p.add_argument('--user', default=os.getenv('QA_TC_USER', ''))
    p.add_argument('--out')
    p.add_argument('--timeout', type=int, default=30)
    a = p.parse_args()
    if not 1 <= a.port <= 65535 or not 1 <= a.timeout <= 300:
        raise ValueError('port must be 1..65535; timeout must be 1..300')
    os.umask(0o077)
    folder = pathlib.Path(os.getenv('XDG_STATE_HOME', str(pathlib.Path.home()/'.local/state')))/'mcp_qa_testclient'
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = open(folder/'lock', 'a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    statefile = folder/'state.json'
    state = json.loads(statefile.read_text()) if statefile.exists() else {}
    def alive():
        return bool(state.get('identity') and identity(state['pid']) == state['identity'])
    def save():
        tmp = folder/'state.tmp'
        tmp.write_text(json.dumps(state))
        tmp.replace(statefile)
    def listening(port, pid=None):
        result = run('ss', '-ltnpH')
        if result.returncode:
            raise RuntimeError('ss failed')
        return any(line.split()[3].endswith(':'+str(port)) and
                   (pid is None or f'pid={pid},' in line)
                   for line in result.stdout.splitlines())
    env = dict(os.environ, DISPLAY=state.get('display', a.display))
    if a.action == 'status':
        return dict(ok=True, action=a.action, running=alive(), pid=state.get('pid'),
                    display=state.get('display'), port=state.get('port'),
                    listening=bool(alive() and state.get('port') and listening(state['port'], state['pid'])))
    if a.action == 'capture':
        if not state or not alive():
            raise RuntimeError('no tracked live test client')
        out = pathlib.Path(a.out) if a.out else folder/'capture.png'
        if shutil.which('import'):
            result = run('import', '-window', 'root', str(out), env=env)
        else:
            out = out.with_suffix('.xwd')
            result = run('xwd', '-root', '-silent', '-out', str(out), env=env)
        if result.returncode:
            raise RuntimeError('screen capture failed')
        return dict(ok=True, action=a.action, path=str(out), display=env['DISPLAY'])
    if a.action == 'stop':
        if not alive():
            return dict(ok=True, action=a.action, was_running=False)
        # xdotool locates visible windows; python-xlib delivers WM_DELETE_WINDOW
        # even under bare Xvfb without a window manager. windowclose destroys a
        # window; windowkill and process signals are deliberately never used.
        from Xlib import X, display, protocol
        ids = run('xdotool', 'search', '--onlyvisible', '--pid', str(state['pid']), env=env)
        d = display.Display(env['DISPLAY'])
        candidates = []
        for wid in ids.stdout.split():
            w = d.create_resource_object('window', int(wid))
            g = w.get_geometry()
            if d.intern_atom('WM_DELETE_WINDOW') in (w.get_wm_protocols() or []):
                candidates.append((g.width*g.height, w))
        if not candidates:
            raise RuntimeError('no closable visible client window; process left running')
        w = max(candidates, key=lambda item: item[0])[1]
        if not alive():
            raise RuntimeError('client identity changed; no close sent')
        w.send_event(protocol.event.ClientMessage(window=w, client_type=d.intern_atom('WM_PROTOCOLS'),
            data=(32, [d.intern_atom('WM_DELETE_WINDOW'), X.CurrentTime, 0, 0, 0])), event_mask=X.NoEventMask)
        d.sync()
        deadline = time.monotonic()+a.timeout
        while alive() and time.monotonic() < deadline:
            time.sleep(.25)
        if alive():
            raise RuntimeError('close requested; client still running (check confirmation dialog); no signal sent')
        statefile.unlink(missing_ok=True)
        return dict(ok=True, action=a.action, stopped=True, method='WM_DELETE_WINDOW')
    if alive():
        ready = listening(state['port'], state['pid'])
        return dict(ok=ready, action=a.action, already_running=True, pid=state['pid'],
                    listening=ready)
    if not re.fullmatch(r'8\.\d+\.\d+\.\d+', a.version):
        raise ValueError('explicit --version matching the server build is required')
    if not a.connect.startswith(('/S', '/F')) or any(c in a.connect for c in '\r\n'):
        raise ValueError('--connect must be a single /S or /F parameter')
    for dep in ('Xvfb', 'xdpyinfo', 'ss', 'xdotool'):
        if not shutil.which(dep):
            raise RuntimeError('missing dependency: '+dep)
    from Xlib import display  # stop capability must exist before starting 1C
    binary = pathlib.Path(a.platforms)/a.version/'1cv8c'
    if not os.access(binary, os.X_OK):
        raise RuntimeError('client executable missing')
    if listening(a.port):
        raise RuntimeError('test-client port already in use')
    env['DISPLAY'] = a.display
    if run('xdpyinfo', env=env).returncode:
        with open(folder/'xvfb.log', 'a') as log:
            subprocess.Popen(['Xvfb', a.display, '-screen', '0', '1600x1000x24', '-nolisten', 'tcp'],
                             stdout=log, stderr=log, start_new_session=True)
        for _ in range(50):
            if not run('xdpyinfo', env=env).returncode:
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Xvfb failed; see private xvfb.log')
    # Pass connection as one argv element; do not ask a shell to parse it.
    # Passwords are intentionally entered in the client login dialog.
    conn = a.connect[2:]
    if conn.startswith('"') and conn.endswith('"'):
        conn = conn[1:-1]
    params = [a.connect[:2]+conn, '/TestClient', '-TPort'+str(a.port), '/DisableStartupDialogs', '/DisableStartupMessages']
    if a.user:
        params.append('/N'+a.user)
    with open(folder/'1cv8c.log', 'a') as log:
        proc = subprocess.Popen([str(binary), 'ENTERPRISE']+params, env=env,
                                stdout=log, stderr=log, start_new_session=True)
    state = dict(pid=proc.pid, identity=identity(proc.pid), port=a.port, display=a.display, version=a.version)
    save()
    for _ in range(90):
        if proc.poll() is not None:
            raise RuntimeError('client exited; see private 1cv8c.log')
        if listening(a.port, proc.pid):
            return dict(ok=True, action=a.action, pid=proc.pid, port=a.port, display=a.display, listening=True)
        time.sleep(1)
    raise RuntimeError('client still running but port not ready; inspect display; no signal sent')

try:
    result = main()
except Exception as exc:
    result = dict(ok=False, error=str(exc))
print(json.dumps(result, ensure_ascii=False))
sys.exit(0 if result['ok'] else 1)
PY
