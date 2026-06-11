#!/usr/bin/env python3
"""
OpenHuman Portable — 配置中心 (Config Center)

A self-contained, dependency-free (stdlib-only) local web config panel,
styled consistently with the OpenClaw / Hermes / Claude / Codex portable
config centers.

It reads and writes data/.openhuman/config.json — a simple JSON file
storing provider configurations with API keys, base URLs, and models.

Usage:
  python3 lib/config_server.py            # serve on 127.0.0.1:17600
"""
import json
import secrets
import os
import sys
import time
import uuid
import urllib.request
import urllib.error
import webbrowser
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PORTABLE_ROOT = SCRIPT_DIR.parent if SCRIPT_DIR.name == "lib" else SCRIPT_DIR
DATA_DIR = PORTABLE_ROOT / "data"
OH_DIR = DATA_DIR / ".openhuman"
CONFIG_FILE = OH_DIR / "config.json"


def _read_version():
    vf = PORTABLE_ROOT / "VERSION"
    try:
        return vf.read_text(encoding="utf-8").strip()
    except Exception:
        return "dev"


VERSION = _read_version()

PORT = 17600  # config-center port

# Per-process CSRF token (OpenHuman Portable design).
SERVER_TOKEN = secrets.token_hex(32)

# ── Provider catalog ────────────────────────────────────────────────
# OpenHuman supports any OpenAI-compatible API. Providers below are the
# most popular ones, each with a known base URL.
# Updated 2026-06-11.
PROVIDERS = [
    # ── 海外主流 ──
    {"id": "openai", "name": "OpenAI 官方", "base_url": "https://api.openai.com/v1",
     "models": ["gpt-4.1", "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini",
                "o3", "o3-mini", "o4-mini"],
     "key_hint": "sk-...", "note": "官方直连，GPT-4.1 / o3 最新",
     "tags": ["hot"]},
    {"id": "anthropic", "name": "Anthropic (Claude)", "base_url": "https://api.anthropic.com/v1",
     "models": ["claude-sonnet-4-20250514", "claude-haiku-4-20250514",
                "claude-3.5-sonnet-20241022", "claude-3.5-haiku-20241022"],
     "key_hint": "sk-ant-...", "note": "Claude Sonnet 4 最新，需 Anthropic API Key",
     "tags": ["hot"]},
    {"id": "google", "name": "Google Gemini", "base_url": "https://generativelanguage.googleapis.com/v1beta",
     "models": ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
     "key_hint": "粘贴 Google AI API Key", "note": "Gemini 2.5 最新，支持 OpenAI 兼容端点",
     "tags": ["hot", "free"]},
    {"id": "deepseek", "name": "DeepSeek", "base_url": "https://api.deepseek.com/v1",
     "models": ["deepseek-chat", "deepseek-reasoner", "deepseek-r1"],
     "key_hint": "sk-...", "note": "DeepSeek V3 + R1 推理，性价比极高",
     "tags": ["hot", "cn", "cheap"]},
    {"id": "kimi", "name": "Moonshot / Kimi", "base_url": "https://api.moonshot.cn/v1",
     "models": ["moonshot-v1-128k", "moonshot-v1-32k", "moonshot-v1-8k"],
     "key_hint": "sk-...", "note": "Kimi 长上下文，支持 128K",
     "tags": ["cn", "hot"]},
    {"id": "dashscope", "name": "通义千问 / Qwen", "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
     "models": ["qwen-max", "qwen-plus", "qwen-turbo", "qwen-long"],
     "key_hint": "sk-...", "note": "阿里云，Qwen 系列，Coder 代码专精",
     "tags": ["cn", "hot"]},
    {"id": "doubao", "name": "豆包 / 火山引擎", "base_url": "https://ark.cn-beijing.volces.com/api/v3",
     "models": ["doubao-1.5-pro-256k", "doubao-1.5-lite-32k"],
     "key_hint": "粘贴火山引擎 API Key", "note": "字节跳动豆包大模型",
     "tags": ["cn", "cheap"]},
    {"id": "zhipu", "name": "智谱 GLM", "base_url": "https://open.bigmodel.cn/api/paas/v4",
     "models": ["glm-4-flash", "glm-4", "glm-3-turbo"],
     "key_hint": "粘贴智谱 API Key", "note": "GLM 系列，全系列 OpenAI 兼容",
     "tags": ["cn", "hot"]},
    {"id": "minimax", "name": "MiniMax (海螺)", "base_url": "https://api.minimax.chat/v1",
     "models": ["abab6.5-chat", "abab6.5s-chat", "abab5.5-chat"],
     "key_hint": "粘贴 MiniMax API Key", "note": "MiniMax 海螺 AI，OpenAI 兼容",
     "tags": ["cn"]},
    {"id": "groq", "name": "Groq", "base_url": "https://api.groq.com/openai/v1",
     "models": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant",
                "mixtral-8x7b-32768", "gemma2-9b-it"],
     "key_hint": "gsk_...", "note": "超快推理，Llama 3 / Mixtral",
     "tags": ["fast", "free"]},
    {"id": "openrouter", "name": "OpenRouter (聚合)", "base_url": "https://openrouter.ai/api/v1",
     "models": ["openai/gpt-4o", "anthropic/claude-sonnet-4",
                "google/gemini-2.5-pro", "deepseek/deepseek-chat",
                "meta-llama/llama-3.3-70b-instruct"],
     "key_hint": "sk-or-...", "note": "聚合 100+ 模型，一个 Key 通用",
     "tags": ["hot", "cheap"]},
    {"id": "together", "name": "Together", "base_url": "https://api.together.xyz/v1",
     "models": ["meta-llama/Llama-3.3-70B-Instruct-Turbo",
                "deepseek-ai/DeepSeek-V3",
                "Qwen/Qwen2.5-72B-Instruct-Turbo"],
     "key_hint": "粘贴 Together API Key", "note": "开源模型托管",
     "tags": ["cheap"]},
    {"id": "fireworks", "name": "Fireworks", "base_url": "https://api.fireworks.ai/inference/v1",
     "models": ["accounts/fireworks/models/llama-v3p3-70b-instruct",
                "accounts/fireworks/models/deepseek-v3"],
     "key_hint": "粘贴 Fireworks API Key", "note": "高速推理",
     "tags": ["fast", "cheap"]},
    {"id": "xai", "name": "xAI (Grok)", "base_url": "https://api.x.ai/v1",
     "models": ["grok-3", "grok-3-mini", "grok-2"],
     "key_hint": "xai-...", "note": "Grok 3 最新",
     "tags": ["hot"]},
    {"id": "cerebras", "name": "Cerebras", "base_url": "https://api.cerebras.ai/v1",
     "models": ["llama-3.3-70b", "llama-3.1-8b"],
     "key_hint": "粘贴 Cerebras API Key", "note": "极速推理，免费额度",
     "tags": ["fast", "free"]},
    # ── 自定义 ──
    {"id": "custom", "name": "自定义 / 中转站", "base_url": "",
     "models": [], "custom": True,
     "key_hint": "粘贴中转站 API Key", "note": "填写中转站/自建网关的 base_url",
     "tags": []},
]


# ═══════════════════════════════════════════════════════════════
#  Config read / write (JSON file)
# ═══════════════════════════════════════════════════════════════
BACKUP_DIR = DATA_DIR / ".backups"
BACKUP_MAX = 5  # rolling backup count


def _atomic_write(path, content):
    """Write file atomically via tmp+fsync+rename with rolling backups."""
    from pathlib import Path
    import shutil
    p = Path(path)
    was_first_write = not p.exists()

    # Cleanup stale uuid tmp files (>1 hour old) from prior crashes
    try:
        import time as _time
        for stale in p.parent.glob(p.stem + ".*.tmp"):
            try:
                if stale.stat().st_mtime < _time.time() - 3600:
                    stale.unlink(missing_ok=True)
            except Exception:
                pass
    except Exception:
        pass

    # Rolling backup: copy current file before overwriting
    if p.exists() and p.stat().st_size > 0:
        try:
            BACKUP_DIR.mkdir(parents=True, exist_ok=True)
            from datetime import datetime
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup = BACKUP_DIR / f"{p.name}.{ts}"
            shutil.copy2(str(p), str(backup))
            # Prune old backups (keep newest BACKUP_MAX)
            backups = sorted(BACKUP_DIR.glob(f"{p.name}.*"),
                             key=lambda f: f.stat().st_mtime, reverse=True)
            for old in backups[BACKUP_MAX:]:
                old.unlink(missing_ok=True)
        except Exception:
            pass  # backup failure should not block writes

    import uuid as _uuid
    tmp = p.with_suffix("." + _uuid.uuid4().hex[:8] + p.suffix + ".tmp")
    # Write with fsync (critical for USB/exFAT)
    # Prevent symlink following (#22: avoid overwriting arbitrary files)
    if p.is_symlink():
        p.unlink()
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, content.encode("utf-8"))
        try:
            os.fsync(fd)
        except OSError as e:
            print(f"[config] fsync failed (eject safely): {e}", file=sys.stderr)
    finally:
        os.close(fd)
    try:
        os.replace(str(tmp), str(p))
    except Exception:
        try:
            tmp.unlink()
        except Exception:
            pass
        raise

    # Seed backup on first write so USB yank recovery has a baseline
    if was_first_write:
        try:
            BACKUP_DIR.mkdir(parents=True, exist_ok=True)
            from datetime import datetime
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup = BACKUP_DIR / f"{p.name}.{ts}"
            shutil.copy2(str(p), str(backup))
        except Exception:
            pass


def _safe_read(path):
    """Read config with fallback to newest backup on failure."""
    from pathlib import Path
    p = Path(path)
    try:
        if p.exists():
            return p.read_text(encoding="utf-8")
    except Exception:
        pass
    # Fallback: try newest backup
    try:
        backups = sorted(BACKUP_DIR.glob(f"{p.name}.*"),
                         key=lambda f: f.stat().st_mtime, reverse=True)
        if backups:
            return backups[0].read_text(encoding="utf-8")
    except Exception:
        pass
    return None


def _load_config():
    """Load config from JSON file, return dict with providers list."""
    raw = _safe_read(CONFIG_FILE)
    if raw:
        try:
            data = json.loads(raw)
            if isinstance(data, dict) and "providers" in data:
                return data
        except Exception:
            pass
    return {"providers": [], "version": 1}


def _save_config(cfg):
    """Save config dict to JSON file atomically."""
    with _CONFIG_LOCK:
        OH_DIR.mkdir(parents=True, exist_ok=True)
        _atomic_write(CONFIG_FILE, json.dumps(cfg, ensure_ascii=False, indent=2))


def read_current():
    """Return the currently-active provider as a dict, or None."""
    cfg = _load_config()
    for p in cfg.get("providers", []):
        if p.get("active"):
            return {
                "name": p.get("name", ""),
                "base_url": (p.get("base_url") or "").strip(),
                "api_key": (p.get("api_key") or "").strip(),
                "model": (p.get("model") or "").strip(),
            }
    return None


def list_providers():
    """Return list of saved providers (without api_key)."""
    cfg = _load_config()
    out = []
    for p in cfg.get("providers", []):
        out.append({
            "id": p.get("id", ""),
            "name": p.get("name", ""),
            "active": bool(p.get("active")),
        })
    return out


def save_provider(name, base_url, api_key, model):
    """Insert/replace a provider and mark it active."""
    base_url = (base_url or "").strip().rstrip("/")
    api_key = (api_key or "").strip()
    model = (model or "").strip()
    if not base_url or not api_key:
        raise ValueError("base_url 和 api_key 不能为空")

    cfg = _load_config()
    # Deactivate all existing providers
    for p in cfg.get("providers", []):
        p["active"] = False

    # Check if a provider with the same base_url exists, replace it
    existing_idx = None
    for i, p in enumerate(cfg.get("providers", [])):
        if p.get("base_url") == base_url:
            existing_idx = i
            break

    new_entry = {
        "id": str(uuid.uuid4()),
        "name": name or "Custom",
        "base_url": base_url,
        "api_key": api_key,
        "model": model,
        "active": True,
    }

    if existing_idx is not None:
        cfg["providers"][existing_idx] = new_entry
    else:
        cfg.setdefault("providers", []).append(new_entry)

    cfg["version"] = 1
    _save_config(cfg)
    return new_entry["id"]


def activate_provider(pid):
    """Activate a provider by id, deactivate all others."""
    cfg = _load_config()
    found = False
    for p in cfg.get("providers", []):
        if p.get("id") == pid:
            p["active"] = True
            found = True
        else:
            p["active"] = False
    if found:
        _save_config(cfg)
    return found


def delete_provider(pid):
    """Delete a provider by id."""
    cfg = _load_config()
    before = len(cfg.get("providers", []))
    cfg["providers"] = [p for p in cfg.get("providers", []) if p.get("id") != pid]
    after = len(cfg.get("providers", []))
    if before != after:
        _save_config(cfg)
    return before - after


def export_config():
    """Export config for backup/sharing."""
    cfg = _load_config()
    # Strip api_keys from export for safety
    safe_providers = []
    for p in cfg.get("providers", []):
        entry = {k: v for k, v in p.items() if k != "api_key"}
        safe_providers.append(entry)
    return {"version": 1, "exported_at": int(time.time()),
            "providers": safe_providers}


def view_config():
    """View current config with masked API key."""
    cur = read_current()
    if not cur:
        return {"configured": False}
    key = cur.get("api_key", "")
    masked = (key[:6] + "…" + key[-4:]) if len(key) > 12 else "***"
    return {
        "configured": True, "name": cur.get("name"),
        "base_url": cur.get("base_url"), "model": cur.get("model"),
        "api_key_masked": masked, "api_key_len": len(key),
    }


def reset_config():
    """Delete all providers and remove config file. Regenerate CSRF token."""
    global SERVER_TOKEN
    SERVER_TOKEN = secrets.token_hex(32)
    removed = 0
    cfg = _load_config()
    removed = len(cfg.get("providers", []))
    _save_config({"providers": [], "version": 1})
    return removed


# ═══════════════════════════════════════════════════════════════
#  API key connectivity test
# ═══════════════════════════════════════════════════════════════
def test_key(base_url, api_key, model):
    """Minimal OpenAI /v1/models probe. Returns (ok, message).

    TLS resilience: portable Pythons sometimes ship without a usable
    system trust store. Try certifi first if available, then default."""
    import ssl
    base_url = (base_url or "").strip().rstrip("/")
    api_key = (api_key or "").strip()
    if not base_url or not api_key:
        return False, "缺少 base_url 或 api_key"
    url = base_url + "/models"
    req = urllib.request.Request(url, method="GET", headers={
        "authorization": f"Bearer {api_key}",
        "user-agent": "OpenHumanPortable/ConfigCenter",
    })
    contexts = []
    try:
        import certifi  # type: ignore
        contexts.append(ssl.create_default_context(cafile=certifi.where()))
    except Exception:
        pass
    # macOS Homebrew/system Python often lacks root certs in the OpenSSL
    # bundle.  Try loading from the macOS System keychain via Security
    # framework, then fall back to an unverified context as last resort.
    try:
        import platform
        if platform.system() == "Darwin":
            import subprocess, tempfile
            pem = subprocess.check_output(
                ["security", "find-certificate", "-a", "-p",
                 "/System/Library/Keychains/SystemRootCertificates.keychain"],
                timeout=5, stderr=subprocess.DEVNULL)
            with tempfile.NamedTemporaryFile(suffix=".pem", delete=False) as f:
                f.write(pem)
                mac_ca = f.name
            ctx = ssl.create_default_context(cafile=mac_ca)
            contexts.append(ctx)
            os.unlink(mac_ca)
    except Exception:
        pass
    # Also try default context
    contexts.append(ssl.create_default_context())

    last_err = "无法连接"
    for ctx in contexts:
        try:
            kwargs = {"timeout": 15}
            if ctx is not None:
                kwargs["context"] = ctx
            with urllib.request.urlopen(req, **kwargs) as resp:
                if 200 <= resp.status < 300:
                    body = resp.read(2000).decode("utf-8", "replace")
                    count = ""
                    try:
                        data = json.loads(body)
                        if isinstance(data, dict) and "data" in data:
                            count = f" ({len(data['data'])} 个模型)"
                    except Exception:
                        pass
                    return True, f"连接成功{count}"
                return False, f"HTTP {resp.status}"
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                return False, "API Key 无效或无权限 (HTTP %d)" % e.code
            if e.code in (400, 404):
                return True, "端点可达 (HTTP %d)" % e.code
            try:
                detail = e.read(300).decode("utf-8", "replace")
            except Exception:
                detail = ""
            return False, f"HTTP {e.code} {detail[:120]}"
        except Exception as e:
            last_err = f"无法连接: {str(e)[:120]}"
            continue
    return False, last_err


# ═══════════════════════════════════════════════════════════════
#  Embedded UI. Styled for OpenHuman Portable
#  portable config centers: warm dark theme, cards, tabs.
#  Loaded from lib/config_ui.html.
# ═══════════════════════════════════════════════════════════════
_UI_FILE = SCRIPT_DIR / "config_ui.html"


def _load_page():
    try:
        html = _UI_FILE.read_text(encoding="utf-8")
        return html.replace("__VERSION__", VERSION)
    except Exception:
        return ("<html><body style='font-family:sans-serif;padding:40px'>"
                "<h2>配置中心 UI 文件缺失</h2><p>lib/config_ui.html 未找到。"
                "请重新下载发布包。</p></body></html>")


PAGE = _load_page()


# ═══════════════════════════════════════════════════════════════
#  HTTP handler
# ═══════════════════════════════════════════════════════════════
class Handler(BaseHTTPRequestHandler):
    timeout = 30

    def _host_ok(self):
        host = self.headers.get("Host", "")
        try:
            port = self.server.server_address[1]
        except Exception:
            port = PORT
        return host in (f"127.0.0.1:{port}", f"localhost:{port}")

    def _reject_host(self):
        if self._host_ok():
            return False
        self.send_response(421)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"error":"Host mismatch"}')
        return True

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(body)

    def _html(self, html):
        html = html.replace("__CC_TOKEN__", SERVER_TOKEN)
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy",
                         "default-src 'self' 'unsafe-inline'; img-src 'self' data:")
        self.end_headers()
        self.wfile.write(body)

    def _csrf_ok(self):
        tok = self.headers.get("X-CC-Token", "")
        return secrets.compare_digest(tok, SERVER_TOKEN)

    def log_message(self, *a):
        pass

    def parse_request(self):
        """Override to check raw request line BEFORE path normalization.
        Only blocks null bytes and backslashes here — '..' traversal is
        handled by _path_safe() which checks the normalized path portion
        (after query string is stripped), avoiding false positives on
        query parameter values that happen to contain '..'.
        """
        raw = getattr(self, 'raw_requestline', b'')
        if isinstance(raw, bytes):
            raw = raw.decode('utf-8', 'replace')
        if '\\' in raw or '\x00' in raw:
            self.requestline = raw.strip()
            self.request_version = 'HTTP/1.1'
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"invalid path"}')
            return False
        return super().parse_request()

    def _path_safe(self):
        """Defense-in-depth: also check normalized path."""
        p = self.path.split("?")[0]
        if ".." in p or "\\" in p or "\0" in p:
            self._json({"error": "invalid path"}, 400)
            return False
        return True

    def do_GET(self):
        if self._reject_host():
            return
        if not self._path_safe():
            return
        try:
            if self.path in ("/", "/index.html"):
                self._html(PAGE)
            elif self.path == "/api/state":
                cur = read_current()
                if cur:
                    cur = {k: v for k, v in cur.items() if k != "api_key"}
                self._json({
                    "providers_catalog": PROVIDERS,
                    "current": cur,
                    "saved": list_providers(),
                    "has_config": cur is not None,
                })
            elif self.path == "/api/heartbeat":
                self._json({"alive": True})
            elif self.path == "/api/view":
                self._json(view_config())
            elif self.path == "/api/list":
                self._json({"providers": list_providers()})
            elif self.path == "/api/logs":
                import glob as _glob
                log_dir = str(DATA_DIR / "logs")
                log_files = sorted(_glob.glob(os.path.join(log_dir, "*.log")), reverse=True)
                if log_files:
                    try:
                        with open(log_files[0], "r", errors="replace") as lf:
                            lines = lf.readlines()[-100:]
                        self._json({"ok": True, "file": os.path.basename(log_files[0]), "content": "".join(lines)})
                    except Exception as e:
                        self._json({"ok": True, "file": "", "content": f"无法读取日志: {e}"})
                else:
                    self._json({"ok": True, "file": "", "content": "暂无日志"})
            elif self.path == "/api/diagnose":
                import shutil, socket
                checks = []
                bin_ok = os.path.exists(str(PORTABLE_ROOT / "bin"))
                checks.append({"label": "二进制目录", "ok": bin_ok})
                data_dir = str(OH_DIR)
                try:
                    os.makedirs(data_dir, exist_ok=True)
                    test_f = os.path.join(data_dir, ".write_test")
                    with open(test_f, "w") as tf: tf.write("ok")
                    os.remove(test_f)
                    writable = True
                except Exception:
                    writable = False
                checks.append({"label": "数据目录可写", "ok": writable})
                try:
                    usage = shutil.disk_usage(str(PORTABLE_ROOT))
                    free_mb = usage.free // (1024*1024)
                    checks.append({"label": "磁盘空间", "ok": free_mb > 500, "detail": f"{free_mb}MB"})
                except Exception:
                    checks.append({"label": "磁盘空间", "ok": False})
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                try:
                    sock.bind(("127.0.0.1", PORT))
                    port_ok = True
                except OSError:
                    port_ok = False
                finally:
                    sock.close()
                checks.append({"label": "端口可用", "ok": port_ok})
                cfg = _load_config()
                checks.append({"label": "配置有效", "ok": len(cfg.get("providers", [])) > 0})
                self._json({"ok": True, "checks": checks})
            else:
                self._json({"error": "not found"}, 404)
        except Exception as e:
            self._json({"error": str(e)[:200]}, 500)

    def do_POST(self):
        if self._reject_host():
            return
        if not self._path_safe():
            return
        if not self._csrf_ok():
            self._json({"ok": False, "error": "missing or invalid token"}, 403)
            return
        # Layer 3: require JSON Content-Type on writes (defense-in-depth)
        ct = (self.headers.get("Content-Type", "")).split(";")[0].strip().lower()
        if ct != "application/json":
            self._json({"ok": False, "error": "Unsupported Media Type"}, 415)
            return
        try:
            n = min(int(self.headers.get("Content-Length", 0)), 65_536)
            raw = self.rfile.read(n) if n else b"{}"
            data = json.loads(raw or b"{}")
        except Exception:
            self._json({"ok": False, "error": "bad request body"}, 400)
            return
        try:
            if self.path == "/api/save":
                save_provider(data.get("name", ""), data.get("base_url", ""),
                              data.get("api_key", ""), data.get("model", ""))
                self._json({"ok": True})
            elif self.path == "/api/test":
                # SSRF protection: validate URL before testing
                import urllib.parse
                _url = data.get("base_url", "")
                _parsed = urllib.parse.urlparse(_url)
                _ok = True
                if _parsed.scheme not in ("https", "http"):
                    _ok = False
                else:
                    _host = (_parsed.hostname or "").lower()
                    _blocked = ("127.", "0.", "localhost", "169.254.", "10.",
                                "172.16.", "172.17.", "172.18.", "172.19.",
                                "172.20.", "172.21.", "172.22.", "172.23.",
                                "172.24.", "172.25.", "172.26.", "172.27.",
                                "172.28.", "172.29.", "172.30.", "172.31.",
                                "192.168.", "0.0.0.0", "[::1]", "100.64.")
                    for b in _blocked:
                        if _host.startswith(b) or _host == b.rstrip("."):
                            _ok = False; break
                # DNS resolution check (#20+#21: IPv4-mapped IPv6 + DNS rebinding)
                if _ok and _parsed.hostname:
                    import socket
                    _ip_blocked = ("127.", "0.", "10.", "169.254.",
                                   "172.16.", "172.17.", "172.18.", "172.19.",
                                   "172.20.", "172.21.", "172.22.", "172.23.",
                                   "172.24.", "172.25.", "172.26.", "172.27.",
                                   "172.28.", "172.29.", "172.30.", "172.31.",
                                   "192.168.", "100.64.", "::ffff:", "::1", "fe80:")
                    try:
                        for fam, _, _, _, addr in socket.getaddrinfo(_parsed.hostname, None):
                            rip = addr[0]
                            for bip in _ip_blocked:
                                if rip.startswith(bip):
                                    _ok = False; break
                            if not _ok: break
                    except Exception:
                        _ok = False  # DNS failure = reject
                if not _ok:
                    self._json({"ok": False, "error": "URL not allowed (only public http/https)"}, 400)
                else:
                    ok, msg = test_key(_url, data.get("api_key", ""), data.get("model", ""))
                    self._json({"ok": ok, "message": msg})
            elif self.path == "/api/activate":
                found = activate_provider(data.get("id", ""))
                self._json({"ok": found})
            elif self.path == "/api/delete":
                removed = delete_provider(data.get("id", ""))
                self._json({"ok": removed > 0, "removed": removed})
            elif self.path == "/api/reset":
                removed = reset_config()
                self._json({"ok": True, "removed": removed, "new_token": SERVER_TOKEN})
            elif self.path == "/api/export":
                self._json(export_config())
            elif self.path == "/api/import":
                imported = 0
                cfg = _load_config()
                for p in data.get("providers", []):
                    base_url = (p.get("base_url") or "").strip().rstrip("/")
                    api_key = (p.get("api_key") or "").strip()
                    model = (p.get("model") or "").strip()
                    name = (p.get("name") or "Custom").strip()
                    if not base_url or not api_key:
                        continue
                    new_entry = {"id": str(uuid.uuid4()), "name": name,
                                 "base_url": base_url, "api_key": api_key,
                                 "model": model, "active": False}
                    existing_idx = next((i for i, x in enumerate(cfg.get("providers", []))
                                        if x.get("base_url") == base_url), None)
                    if existing_idx is not None:
                        cfg["providers"][existing_idx] = new_entry
                    else:
                        cfg.setdefault("providers", []).append(new_entry)
                    imported += 1
                if cfg.get("providers"):
                    for p in cfg["providers"]:
                        p["active"] = False
                    cfg["providers"][-1]["active"] = True
                cfg["version"] = 1
                _save_config(cfg)
                self._json({"ok": True, "imported": imported})
            elif self.path == "/api/unbind":
                lock_file = str(DATA_DIR / ".lock")
                lock_file2 = str(DATA_DIR / ".running")
                removed = 0
                for lf in [lock_file, lock_file2]:
                    if os.path.exists(lf):
                        try:
                            os.remove(lf)
                            removed += 1
                        except Exception:
                            pass
                self._json({"ok": True, "removed": removed})
            elif self.path == "/api/shutdown":
                self._json({"ok": True, "message": "配置中心即将关闭"})
                import threading
                threading.Thread(target=self.server.shutdown, daemon=True).start()
            else:
                self._json({"ok": False, "error": "not found"}, 404)
        except Exception as e:
            self._json({"ok": False, "error": str(e)[:200]}, 400)


def main():
    server = None
    actual = PORT
    for p in range(PORT, PORT + 10):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", p), Handler)
            actual = p
            break
        except OSError:
            continue
    if server is None:
        print(f"  [!] 端口 {PORT}-{PORT+9} 都被占用", file=sys.stderr)
        sys.exit(1)
    url = f"http://127.0.0.1:{actual}"
    print(f"  配置中心: {url}")

    # Write runtime.json so launcher knows the actual port
    runtime = {"config_port": actual, "config_url": url,
               "pid": os.getpid()}  # token excluded — never read by launchers
    try:
        OH_DIR.mkdir(parents=True, exist_ok=True)
        _atomic_write(OH_DIR / "runtime.json",
                      json.dumps(runtime, indent=2))
    except Exception:
        pass

    if not os.environ.get("OPENHUMAN_BROWSER_OPENED"):
        try:
            webbrowser.open(url)
        except Exception:
            pass

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print("  配置中心已关闭")


if __name__ == "__main__":
    main()
