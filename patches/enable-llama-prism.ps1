$ErrorActionPreference = "Stop"

# Patch the pinned AutoCua checkout so its existing Ollama provider can also
# discover and call a llama.cpp / llama-prism OpenAI-compatible server.
$servicePath = Join-Path $PSScriptRoot "..\AutoCua\AutoCua\llm_provider\ollama\service.py"
if (!(Test-Path -LiteralPath $servicePath)) {
    throw "AutoCua Ollama provider source was not found: $servicePath"
}

$source = [System.IO.File]::ReadAllText($servicePath)
if ($source.Contains("LLAMA_PRISM_OPENAI_COMPAT_V2")) {
    Write-Host "Llama Prism compatibility patch v2 already applied."
    return
}

# AutoCua keeps its .env in its own data directory. load_dotenv() alone does
# not necessarily load that file in the packaged Windows app. Read it through
# AutoCua's public helper when OLLAMA_HOST is not already in the process env.
$hostLine = 'raw = (os.getenv("OLLAMA_HOST") or "").strip().strip("\\"''")'
$hostReplacement = @'
raw = (os.getenv("OLLAMA_HOST") or "").strip().strip("\\"''")
    if not raw:
        try:
            from AutoCua import read_env
            raw = (read_env().get("OLLAMA_HOST") or "").strip().strip("\\"''")
        except Exception:
            pass
'@
if (!$source.Contains($hostLine)) {
    throw "Could not locate OLLAMA_HOST lookup in base_url(); refusing to patch an unexpected upstream version."
}
$source = $source.Replace($hostLine, $hostReplacement.TrimEnd())

$pattern = '(?ms)^def reachable\(timeout: float = 1\.0\) -> bool:.*?(?=^class OllamaProvider:)'
$replacement = @'
def reachable(timeout: float = 1.0) -> bool:
    """True when Ollama or a llama.cpp/llama-prism server answers."""
    url = base_url()
    try:
        with _session(url, _key()) as session:
            try:
                if session.get(f"{url}/api/version", timeout=(0.5, timeout)).ok:
                    return True
            except requests.exceptions.RequestException:
                pass
            # LLAMA_PRISM_OPENAI_COMPAT_V2: llama.cpp has no /api/version.
            try:
                response = session.get(f"{url}/v1/models", timeout=(0.5, timeout))
                if not response.ok:
                    return False
                body = response.json()
                entries = body.get("data") if isinstance(body, dict) else None
                return isinstance(entries, list)
            except (requests.exceptions.RequestException, ValueError, AttributeError):
                return False
    except requests.exceptions.RequestException:
        return False


def pulled_models(timeout: float = 2.0) -> list:
    """Return Ollama models or OpenAI-compatible llama.cpp model IDs."""
    url = base_url()
    with _session(url, _key()) as session:
        # Native Ollama discovery first.
        try:
            r = session.get(f"{url}/api/tags", timeout=(0.5, timeout))
            if r.ok:
                payload = r.json()
                entries = payload.get("models") if isinstance(payload, dict) else None
                if isinstance(entries, list):
                    models = []
                    for m in entries:
                        name = isinstance(m, dict) and (m.get("name") or m.get("model"))
                        if not name:
                            continue
                        try:
                            shown = session.post(
                                f"{url}/api/show", json={"model": name},
                                timeout=(0.5, timeout)
                            )
                            caps = shown.json().get("capabilities") if shown.ok else None
                        except (requests.exceptions.RequestException, ValueError, AttributeError):
                            caps = None
                        caps = caps if isinstance(caps, list) else None
                        if caps is None or "tools" in caps:
                            models.append((name, caps))
                    return models
        except (requests.exceptions.RequestException, ValueError, AttributeError):
            pass

        # LLAMA_PRISM_OPENAI_COMPAT_V2: /v1/models returns {"data":[{"id":...}]}.
        r = session.get(f"{url}/v1/models", timeout=(0.5, timeout))
        r.raise_for_status()
        payload = r.json()
        entries = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(entries, list):
            raise ValueError("The local server's /v1/models response has no data list")
        models, seen = [], set()
        for entry in entries:
            name = entry.get("id") if isinstance(entry, dict) else None
            if name and name not in seen:
                # Capabilities are unknown on llama.cpp; None keeps the model
                # visible and lets its own template determine tool/vision use.
                models.append((name, None))
                seen.add(name)
        return models


'@

$patched = [regex]::Replace(
    $source,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement },
    1
)
if ($patched -eq $source) {
    throw "Could not locate AutoCua's Ollama discovery functions; upstream layout changed."
}
if (!$patched.Contains("LLAMA_PRISM_OPENAI_COMPAT_V2") -or
    !$patched.Contains('read_env().get("OLLAMA_HOST")')) {
    throw "Llama Prism patch verification failed."
}

[System.IO.File]::WriteAllText($servicePath, $patched, [System.Text.UTF8Encoding]::new($false))
Write-Host "Applied Llama Prism compatibility v2, including AutoCua .env lookup."
