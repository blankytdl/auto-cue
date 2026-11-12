$ErrorActionPreference = "Stop"

# Patch the pinned AutoCua checkout so its existing Ollama provider can also
# discover and call a llama.cpp / llama-prism OpenAI-compatible server.
$servicePath = Join-Path $PSScriptRoot "..\AutoCua\AutoCua\llm_provider\ollama\service.py"
if (!(Test-Path -LiteralPath $servicePath)) {
    throw "AutoCua Ollama provider source was not found: $servicePath"
}

$source = [System.IO.File]::ReadAllText($servicePath)
if ($source.Contains("LLAMA_PRISM_OPENAI_COMPAT")) {
    Write-Host "Llama Prism compatibility patch already applied."
    exit 0
}

$pattern = '(?ms)^def reachable\(timeout: float = 1\.0\) -> bool:.*?(?=^class OllamaProvider:)'

$replacement = @'
def reachable(timeout: float = 1.0) -> bool:
    """True when Ollama or a llama.cpp/llama-prism server answers."""
    url = base_url()
    try:
        with _session(url, _key()) as session:
            # Native Ollama discovery.
            try:
                if session.get(f"{url}/api/version", timeout=(0.5, timeout)).ok:
                    return True
            except requests.exceptions.RequestException:
                pass

            # LLAMA_PRISM_OPENAI_COMPAT: llama.cpp and llama-prism expose
            # OpenAI's model-list route, not Ollama's /api/version route.
            try:
                response = session.get(f"{url}/v1/models", timeout=(0.5, timeout))
                if not response.ok:
                    return False
                body = response.json()
                return isinstance(body, dict) and isinstance(body.get("data"), list)
            except (requests.exceptions.RequestException, ValueError, AttributeError):
                return False
    except requests.exceptions.RequestException:
        return False


def pulled_models(timeout: float = 2.0) -> list:
    """Return models from Ollama /api/tags or llama.cpp /v1/models."""
    url = base_url()
    with _session(url, _key()) as session:
        # Native Ollama: preserve its capability checks and model ordering.
        try:
            r = session.get(f"{url}/api/tags", timeout=(0.5, timeout))
            if r.ok:
                payload = r.json()
                ollama_models = payload.get("models") if isinstance(payload, dict) else None
                if isinstance(ollama_models, list):
                    models = []
                    for m in ollama_models:
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

        # LLAMA_PRISM_OPENAI_COMPAT: /v1/models returns OpenAI model objects
        # shaped as {"data": [{"id": "<model-id>", ...}]}.
        r = session.get(f"{url}/v1/models", timeout=(0.5, timeout))
        r.raise_for_status()
        payload = r.json()
        entries = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(entries, list):
            raise ValueError("The local server's /v1/models response has no data list")
        models = []
        seen = set()
        for entry in entries:
            name = entry.get("id") if isinstance(entry, dict) else None
            if name and name not in seen:
                # OpenAI-compatible servers do not expose Ollama's
                # /api/show capabilities. Keep caps=None so AutoCua lets the
                # server/model decide whether tools and image input are usable.
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

[System.IO.File]::WriteAllText($servicePath, $patched, [System.Text.UTF8Encoding]::new($false))
Write-Host "Applied Llama Prism compatibility to AutoCua's local provider."
