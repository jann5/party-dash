"""Local bridge between the repo and Roblox Studio (used via the Studio MCP execute_luau tool).

GET  /ping                      -> "pong"
GET  /tree?root=<abs repo path> -> JSON tree of src/ using Rojo naming rules (see default.project.json)
POST /save?path=<abs file path> -> writes the request body to that file (used to export data out of Studio)

Run:  python3 tools/devserver.py   (listens on 127.0.0.1:8765)
Studio side: tools/studio_pull.luau (paste the file's content into execute_luau, with ROOT set).
"""
import http.server, json, os, sys, urllib.parse

PORT = int(os.environ.get('DEVSERVER_PORT', '8765'))
CONTAINERS = {  # repo dir -> Studio location
    'src/shared': 'ReplicatedStorage/Shared',
    'src/server': 'ServerScriptService/Server',
    'src/client': 'StarterPlayer/StarterPlayerScripts/Client',
}
EXTS = [('.server.luau', 'Script'), ('.server.lua', 'Script'), ('.client.luau', 'LocalScript'),
        ('.client.lua', 'LocalScript'), ('.luau', 'ModuleScript'), ('.lua', 'ModuleScript')]


def classify(fname):
    for ext, cls in EXTS:
        if fname.endswith(ext):
            return fname[: -len(ext)], cls
    return None, None


def build(path, name):
    """Return a node for a directory (Folder, or script if it has an init file)."""
    node = {'name': name, 'class': 'Folder', 'children': []}
    for fname in sorted(os.listdir(path)):
        if fname.startswith('.'):
            continue
        full = os.path.join(path, fname)
        if os.path.isdir(full):
            node['children'].append(build(full, fname))
            continue
        base, cls = classify(fname)
        if cls is None:
            continue
        src = open(full, encoding='utf-8').read()
        if base == 'init':
            node['class'], node['source'] = cls, src
        else:
            node['children'].append({'name': base, 'class': cls, 'source': src, 'children': []})
    return node


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body, ctype='text/plain'):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == '/ping':
            return self.reply(200, 'pong')
        if u.path == '/tree':
            root = q.get('root', [None])[0]
            if not root or not os.path.isdir(os.path.join(root, 'src')):
                return self.reply(400, f'bad root: {root}')
            out = []
            for rel, dest in CONTAINERS.items():
                d = os.path.join(root, rel)
                if os.path.isdir(d):
                    out.append({'dest': dest, 'node': build(d, dest.split('/')[-1])})
            return self.reply(200, json.dumps(out), 'application/json')
        self.reply(404, 'not found')

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == '/save':
            p = q.get('path', [None])[0]
            if not p or not os.path.isabs(p):
                return self.reply(400, 'need absolute path')
            n = int(self.headers.get('Content-Length', 0))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'wb') as f:
                f.write(self.rfile.read(n))
            return self.reply(200, f'saved {n}')
        self.reply(404, 'not found')


if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
