#!/usr/bin/env python3
"""
MalikIA — Iniciador com Cloudflare Tunnel
Execute este script no SEU PC quando quiser atender clientes.

O que faz:
1. Inicia o server.py (Flask + ML)
2. Inicia cloudflared tunnel
3. Captura a URL pública gerada
4. Atualiza o arquivo url.json no GitHub automaticamente
5. Clientes sempre pegam a URL atual ao executar o script deles

Uso:
    python start_server.py

Requisitos:
    - cloudflared instalado (baixado automaticamente se não encontrado)
    - GITHUB_TOKEN no arquivo .env (para atualizar a URL)
"""

import os, sys, json, time, subprocess, threading, logging, re
import urllib.request, urllib.parse, base64
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
log = logging.getLogger("MalikStarter")

# ── Configuração ─────────────────────────────────────────────────
CONFIG_FILE = Path(__file__).parent / "starter_config.json"

def load_config():
    defaults = {
        "github_token":  "",          # ghp_xxxxx — Personal Access Token
        "github_user":   "",          # seu username
        "github_repo":   "",          # nome do repositório
        "github_branch": "main",
        "server_port":   8000,
        "tunnel_method": "cloudflare", # cloudflare ou ngrok
        "ngrok_token":   "",
        "api_key":       "malikia-dev-2025",
    }
    if CONFIG_FILE.exists():
        try:
            saved = json.loads(CONFIG_FILE.read_text())
            defaults.update(saved)
        except: pass
    return defaults

def save_config(cfg):
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


# ════════════════════════════════════════════════════════════════
#  SETUP INTERATIVO (primeira execução)
# ════════════════════════════════════════════════════════════════
def setup_first_run(cfg):
    print("\n" + "="*55)
    print("  MALIKIA — CONFIGURAÇÃO INICIAL")
    print("="*55)
    print("  Preencha uma vez. Salvo em starter_config.json.\n")

    if not cfg["github_user"]:
        cfg["github_user"]  = input("  GitHub username: ").strip()
    if not cfg["github_repo"]:
        cfg["github_repo"]  = input("  Nome do repositório: ").strip()
    if not cfg["github_token"]:
        print("\n  Token do GitHub (Personal Access Token):")
        print("  github.com → Settings → Developer Settings")
        print("  → Personal access tokens → Fine-grained")
        print("  → Permissions: Contents = Read and Write")
        cfg["github_token"] = input("  Token (ghp_...): ").strip()

    api_key = input(f"  API Key [{cfg['api_key']}]: ").strip()
    if api_key:
        cfg["api_key"] = api_key

    save_config(cfg)
    print("\n  Configuração salva!\n")
    return cfg


# ════════════════════════════════════════════════════════════════
#  CLOUDFLARED — download e tunnel
# ════════════════════════════════════════════════════════════════
def get_cloudflared_path() -> str:
    """Retorna o caminho do cloudflared, baixando se necessário."""
    import platform

    # Verificar se já está no PATH
    try:
        subprocess.run(["cloudflared", "--version"],
                      capture_output=True, check=True)
        return "cloudflared"
    except: pass

    # Baixar para a pasta local
    system  = platform.system().lower()
    machine = platform.machine().lower()

    if system == "windows":
        fname = "cloudflared-windows-amd64.exe"
        url   = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{fname}"
        dest  = Path(__file__).parent / "cloudflared.exe"
    elif system == "darwin":
        fname = "cloudflared-darwin-amd64" if "x86" in machine else "cloudflared-darwin-arm64"
        url   = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{fname}"
        dest  = Path(__file__).parent / "cloudflared"
    else:
        fname = "cloudflared-linux-amd64"
        url   = f"https://github.com/cloudflare/cloudflared/releases/latest/download/{fname}"
        dest  = Path(__file__).parent / "cloudflared"

    if dest.exists():
        if system != "windows":
            dest.chmod(0o755)
        return str(dest)

    log.info(f"Baixando cloudflared de {url}...")
    try:
        urllib.request.urlretrieve(url, dest)
        if system != "windows":
            dest.chmod(0o755)
        log.info("cloudflared baixado!")
        return str(dest)
    except Exception as e:
        log.error(f"Falha ao baixar cloudflared: {e}")
        log.error("Baixe manualmente: https://developers.cloudflare.com/cloudflared/install/")
        return None


def start_cloudflare_tunnel(port: int) -> str:
    """Inicia tunnel e retorna a URL pública."""
    cf_path = get_cloudflared_path()
    if not cf_path:
        return None

    log.info("Iniciando Cloudflare Tunnel...")

    proc = subprocess.Popen(
        [cf_path, "tunnel", "--url", f"http://localhost:{port}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    url = None
    # Capturar a URL da saída do cloudflared
    for line in proc.stdout:
        line = line.strip()
        # cloudflared imprime a URL no formato: https://xxxx.trycloudflare.com
        match = re.search(r'https://[a-z0-9\-]+\.trycloudflare\.com', line)
        if match:
            url = match.group(0)
            log.info(f"Tunnel ativo: {url}")
            break
        # Timeout após 30 linhas sem URL
        if proc.poll() is not None:
            break

    # Continuar lendo saída em background para manter o processo vivo
    def drain(p):
        for _ in p.stdout: pass
    threading.Thread(target=drain, args=(proc,), daemon=True).start()

    return url, proc


# ════════════════════════════════════════════════════════════════
#  NGROK — alternativa
# ════════════════════════════════════════════════════════════════
def start_ngrok_tunnel(port: int, token: str) -> tuple:
    try:
        import ngrok
        listener = ngrok.forward(port, authtoken=token)
        url = listener.url()
        log.info(f"Ngrok tunnel: {url}")
        return url, listener
    except ImportError:
        log.error("ngrok não instalado: pip install ngrok")
        return None, None


# ════════════════════════════════════════════════════════════════
#  ATUALIZAR URL NO GITHUB
#  Salva em url.json no repositório — loader.ps1 lê este arquivo
# ════════════════════════════════════════════════════════════════
def update_github_url(cfg: dict, public_url: str) -> bool:
    if not cfg["github_token"] or not cfg["github_user"] or not cfg["github_repo"]:
        log.warning("GitHub não configurado — URL não será publicada automaticamente")
        return False

    api_base = "https://api.github.com"
    headers  = {
        "Authorization": f"token {cfg['github_token']}",
        "Accept":        "application/vnd.github.v3+json",
        "Content-Type":  "application/json",
        "User-Agent":    "MalikIA-Starter",
    }

    url_data = {
        "malikia_url": public_url,
        "api_key":     cfg["api_key"],
        "updated_at":  time.strftime("%Y-%m-%d %H:%M:%S"),
        "status":      "online",
    }
    content_b64 = base64.b64encode(json.dumps(url_data, indent=2).encode()).decode()

    # Verificar se arquivo já existe (para pegar o SHA atual)
    file_path = "MalikIA/url.json"
    get_url   = f"{api_base}/repos/{cfg['github_user']}/{cfg['github_repo']}/contents/{file_path}"

    sha = None
    try:
        req = urllib.request.Request(get_url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            existing = json.loads(resp.read())
            sha = existing.get("sha")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            log.warning(f"GitHub GET falhou: {e.code}")

    # Criar ou atualizar o arquivo
    body = {
        "message": f"MalikIA online — {time.strftime('%Y-%m-%d %H:%M')}",
        "content": content_b64,
        "branch":  cfg["github_branch"],
    }
    if sha:
        body["sha"] = sha

    try:
        data = json.dumps(body).encode()
        req  = urllib.request.Request(get_url, data=data, headers=headers, method="PUT")
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            log.info(f"GitHub atualizado: {file_path} → {public_url}")
            return True
    except Exception as e:
        log.error(f"Falha ao atualizar GitHub: {e}")
        return False


def update_github_offline(cfg: dict):
    """Marca servidor como offline no GitHub."""
    if not cfg.get("github_token"):
        return

    api_base = "https://api.github.com"
    headers  = {
        "Authorization": f"token {cfg['github_token']}",
        "Accept":        "application/vnd.github.v3+json",
        "Content-Type":  "application/json",
        "User-Agent":    "MalikIA-Starter",
    }

    url_data = {
        "malikia_url": "",
        "status":      "offline",
        "updated_at":  time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    content_b64 = base64.b64encode(json.dumps(url_data, indent=2).encode()).decode()

    file_path = "MalikIA/url.json"
    get_url   = f"{api_base}/repos/{cfg['github_user']}/{cfg['github_repo']}/contents/{file_path}"

    sha = None
    try:
        req = urllib.request.Request(get_url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as resp:
            sha = json.loads(resp.read()).get("sha")
    except: pass

    if sha:
        body = {
            "message": "MalikIA offline",
            "content": content_b64,
            "sha":     sha,
            "branch":  cfg["github_branch"],
        }
        try:
            req = urllib.request.Request(
                get_url,
                data=json.dumps(body).encode(),
                headers=headers, method="PUT"
            )
            urllib.request.urlopen(req, timeout=5)
            log.info("GitHub atualizado: servidor marcado como offline")
        except: pass


# ════════════════════════════════════════════════════════════════
#  INICIAR FLASK SERVER
# ════════════════════════════════════════════════════════════════
def start_flask_server(port: int, api_key: str) -> subprocess.Popen:
    server_script = Path(__file__).parent / "server.py"
    if not server_script.exists():
        log.error(f"server.py não encontrado em {server_script}")
        return None

    env = os.environ.copy()
    env["MALIKIA_KEY"] = api_key
    env["PORT"]        = str(port)

    proc = subprocess.Popen(
        [sys.executable, str(server_script)],
        env=env,
        cwd=str(server_script.parent),
    )
    log.info(f"Flask iniciando (PID {proc.id if hasattr(proc,'id') else proc.pid})...")

    # Aguardar subir
    for i in range(15):
        time.sleep(1)
        try:
            urllib.request.urlopen(f"http://localhost:{port}/health", timeout=1)
            log.info(f"Flask online em http://localhost:{port}")
            return proc
        except: pass

    log.error("Flask não respondeu em 15s")
    return proc


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════
def main():
    print("\n" + "="*55)
    print("  MALIKIA SERVER STARTER")
    print("="*55 + "\n")

    cfg = load_config()

    # Setup na primeira vez
    needs_setup = not cfg["github_user"] or not cfg["github_repo"]
    if needs_setup:
        cfg = setup_first_run(cfg)

    port    = cfg["server_port"]
    api_key = cfg["api_key"]

    processes = []

    try:
        # 1. Iniciar Flask
        log.info("─── Iniciando Flask + ML ───")
        flask_proc = start_flask_server(port, api_key)
        if flask_proc:
            processes.append(flask_proc)
        else:
            log.error("Falha ao iniciar Flask. Verifique server.py.")
            sys.exit(1)

        # 2. Iniciar tunnel
        log.info("─── Iniciando Cloudflare Tunnel ───")
        public_url, tunnel_proc = start_cloudflare_tunnel(port)

        if not public_url and cfg.get("ngrok_token"):
            log.info("Cloudflare falhou, tentando ngrok...")
            public_url, tunnel_proc = start_ngrok_tunnel(port, cfg["ngrok_token"])

        if tunnel_proc:
            processes.append(tunnel_proc)

        if not public_url:
            log.warning("Tunnel não iniciou — clientes precisam do seu IP local")
            public_url = f"http://localhost:{port}"

        # 3. Publicar URL no GitHub
        log.info("─── Atualizando URL no GitHub ───")
        github_ok = update_github_url(cfg, public_url)

        # 4. Status final
        print("\n" + "="*55)
        print("  MALIKIA ONLINE")
        print("="*55)
        print(f"  URL pública   : {public_url}")
        print(f"  API Key       : {api_key}")
        print(f"  GitHub        : {'✓ URL publicada' if github_ok else '✗ não configurado'}")
        print(f"  Porta local   : {port}")
        print("\n  Clientes conectando automaticamente via loader.ps1")
        print("  CTRL+C para encerrar\n")

        # 5. Manter vivo + heartbeat periódico no GitHub
        heartbeat_interval = 600  # 10 minutos
        last_heartbeat     = time.time()

        while True:
            time.sleep(10)

            # Verificar se Flask ainda está rodando
            if flask_proc.poll() is not None:
                log.error("Flask encerrou inesperadamente. Reiniciando...")
                flask_proc = start_flask_server(port, api_key)
                if flask_proc:
                    processes.append(flask_proc)

            # Heartbeat no GitHub (atualiza timestamp)
            if github_ok and time.time() - last_heartbeat > heartbeat_interval:
                update_github_url(cfg, public_url)
                last_heartbeat = time.time()
                log.info("Heartbeat GitHub enviado")

    except KeyboardInterrupt:
        print("\n\n  Encerrando MalikIA...")
        update_github_offline(cfg)
        for p in processes:
            try:
                if hasattr(p, 'terminate'):
                    p.terminate()
                elif hasattr(p, 'close'):
                    p.close()
            except: pass
        print("  Servidor encerrado. GitHub atualizado como offline.\n")
        sys.exit(0)


if __name__ == "__main__":
    main()
