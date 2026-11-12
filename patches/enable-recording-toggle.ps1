$ErrorActionPreference = "Stop"

$uiRoot = Join-Path $PSScriptRoot "..\AutoCua\AutoCua\ui"
$servicePath = Join-Path $uiRoot "service.py"
$scriptPath = Join-Path $uiRoot "script.js"
$cssPath = Join-Path $uiRoot "css\style.css"

foreach ($path in @($servicePath, $scriptPath, $cssPath)) {
    if (!(Test-Path -LiteralPath $path)) { throw "AutoCua UI source file not found: $path" }
}
$service = [System.IO.File]::ReadAllText($servicePath)
$script = [System.IO.File]::ReadAllText($scriptPath)
$css = [System.IO.File]::ReadAllText($cssPath)

$marker = "AUTOCUA_RECORDING_DEFAULT_OFF_V1"
if ($service.Contains($marker) -and $script.Contains($marker) -and $css.Contains($marker)) {
    Write-Host "Recording setting patch is already applied."
    return
}

# The setting lives in the existing per-user settings.json. A missing value
# defaults to OFF for every existing installation.
$recordLine = "        record = agent_mode == 'computer' and run_recorder.supported()"
$recordReplacement = @'
        # AUTOCUA_RECORDING_DEFAULT_OFF_V1: videos are opt-in, never automatic.
        record = (agent_mode == 'computer'
                  and read_settings().get('recording_enabled') is True
                  and run_recorder.supported())
'@
if ($service.Contains($recordLine)) {
    $service = $service.Replace($recordLine, $recordReplacement.TrimEnd())
} elseif (!$service.Contains($marker)) {
    throw "Could not locate the automatic recording condition in ui/service.py."
}

$routeAnchor = "@app.route('/api/chrome', methods=['GET'])"
$routes = @'
@app.route('/api/recording-setting', methods=['GET'])
def get_recording_setting():
    """Recording is opt-in. Older installs without the key default to OFF."""
    try:
        return jsonify({'enabled': read_settings().get('recording_enabled') is True})
    except Exception:
        debug_exception("get_recording_setting")
        return jsonify({'enabled': False}), 500


@app.route('/api/recording-setting', methods=['POST'])
def save_recording_setting():
    """Save the user's explicit choice to the existing per-user settings file."""
    from flask import request
    try:
        data = request.get_json(silent=True) or {}
        enabled = data.get('enabled')
        if not isinstance(enabled, bool):
            return jsonify({'error': 'enabled must be a boolean'}), 400
        write_settings({'recording_enabled': enabled})
        if read_settings().get('recording_enabled') is not enabled:
            return jsonify({'error': 'Could not persist recording setting'}), 500
        return jsonify({'enabled': enabled})
    except Exception:
        debug_exception("save_recording_setting")
        return jsonify({'error': 'Failed to save recording setting'}), 500


'@
if (!$service.Contains("@app.route('/api/recording-setting'")) {
    if (!$service.Contains($routeAnchor)) { throw "Could not locate the API route insertion point in ui/service.py." }
    $service = $service.Replace($routeAnchor, $routes + $routeAnchor)
}

# Inject a Settings row from script.js; no React bundle or runtime dependencies
# need to be rebuilt or installed.
$jsAnchor = "    const loadOllamaStatus = () => {"
$jsInsert = @'
    // AUTOCUA_RECORDING_DEFAULT_OFF_V1: user-controlled local Computer Use replay videos.
    if (settingsOverlay && settingsModelView && !document.getElementById('recordingSettingsView')) {
        const section = document.createElement('section');
        section.id = 'recordingSettingsView';
        section.className = 'settings-view settings-recording-view';
        section.innerHTML = [
            '<div class="settings-section-heading">Recording</div>',
            '<div class="settings-recording-row">',
            '  <div class="settings-recording-copy">',
            '    <div class="settings-recording-title">Computer Use recordings</div>',
            '    <div class="settings-recording-description" id="recordingSettingStatus">Off — no Computer Use screen videos are saved.</div>',
            '  </div>',
            '  <label class="settings-recording-switch" title="Save Computer Use run videos locally">',
            '    <input id="recordingEnabledToggle" type="checkbox" role="switch" aria-label="Enable Computer Use screen recordings" disabled>',
            '    <span class="settings-recording-switch-track" aria-hidden="true"></span>',
            '  </label>',
            '</div>'
        ].join('');
        settingsModelView.insertAdjacentElement('afterend', section);
    }

    const recordingToggle = document.getElementById('recordingEnabledToggle');
    const recordingStatus = document.getElementById('recordingSettingStatus');
    const updateRecordingStatus = (enabled) => {
        if (!recordingStatus) return;
        recordingStatus.textContent = enabled
            ? 'On — Computer Use screen videos are saved locally.'
            : 'Off — no Computer Use screen videos are saved.';
        if (recordingToggle) recordingToggle.setAttribute('aria-checked', enabled ? 'true' : 'false');
    };
    const loadRecordingSetting = () => {
        if (!recordingToggle) return;
        recordingToggle.disabled = true;
        if (recordingStatus) recordingStatus.textContent = 'Loading recording preference…';
        fetch('/api/recording-setting')
            .then(response => {
                if (!response.ok) throw new Error('Could not load recording preference');
                return response.json();
            })
            .then(data => {
                recordingToggle.checked = data.enabled === true;
                updateRecordingStatus(recordingToggle.checked);
                recordingToggle.disabled = false;
            })
            .catch(error => {
                recordingToggle.checked = false;
                recordingToggle.disabled = true;
                if (recordingStatus) recordingStatus.textContent = 'Could not load this setting. Close and reopen Settings to retry.';
                console.error('Failed to load recording setting:', error);
            });
    };
    if (recordingToggle) {
        recordingToggle.addEventListener('change', () => {
            const requested = recordingToggle.checked;
            recordingToggle.disabled = true;
            fetch('/api/recording-setting', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ enabled: requested })
            })
                .then(response => {
                    if (!response.ok) throw new Error('Could not save recording preference');
                    return response.json();
                })
                .then(data => {
                    if (data.enabled !== requested) throw new Error('Recording preference was not saved');
                    updateRecordingStatus(data.enabled === true);
                })
                .catch(error => {
                    recordingToggle.checked = !requested;
                    updateRecordingStatus(recordingToggle.checked);
                    console.error('Failed to save recording setting:', error);
                    if (window.showToast) window.showToast('Could not save the recording setting.');
                })
                .finally(() => { recordingToggle.disabled = false; });
        });
    }

'@
if (!$script.Contains("AUTOCUA_RECORDING_DEFAULT_OFF_V1")) {
    if (!$script.Contains($jsAnchor)) { throw "Could not locate the Settings JavaScript insertion point in ui/script.js." }
    $script = $script.Replace($jsAnchor, $jsInsert + $jsAnchor)
}
$openEventAnchor = "        document.addEventListener('open-settings', () => {"
if (!$script.Contains("            loadRecordingSetting();")) {
    if (!$script.Contains($openEventAnchor)) {
        throw "Could not locate the unique Settings open event in ui/script.js."
    }
    $nl = [string][char]10
    $script = $script.Replace($openEventAnchor, $openEventAnchor + $nl + "            loadRecordingSetting();")
}

# Compact switch styling consistent with the existing Settings UI.
$cssAnchor = ".settings-provider-row {"
$cssInsert = @'
/* AUTOCUA_RECORDING_DEFAULT_OFF_V1 — opt-in local screen recording switch. */
.settings-recording-view { gap: clamp(8px, 1vw, 12px); }
.settings-recording-row {
    display: flex; align-items: center; justify-content: space-between;
    gap: 18px; width: 100%;
}
.settings-recording-copy { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
.settings-recording-title {
    color: rgba(80, 80, 80, 0.92);
    font-size: clamp(12px, 1.2vw, 14px); font-weight: 600;
}
.settings-recording-description {
    color: rgba(105, 105, 105, 0.78);
    font-size: clamp(11px, 1.05vw, 12px); line-height: 1.4;
}
.settings-recording-switch {
    position: relative; display: inline-flex; flex: 0 0 auto;
    width: 44px; height: 26px; cursor: pointer;
}
.settings-recording-switch input {
    position: absolute; width: 1px; height: 1px; opacity: 0;
}
.settings-recording-switch-track {
    position: absolute; inset: 0; border-radius: 999px;
    background: rgba(80, 80, 80, 0.2);
    box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.12);
    transition: background 0.18s ease, opacity 0.18s ease;
}
.settings-recording-switch-track::before {
    content: ""; position: absolute; width: 20px; height: 20px;
    left: 3px; top: 3px; border-radius: 50%; background: #fff;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
    transition: transform 0.18s ease;
}
.settings-recording-switch input:checked + .settings-recording-switch-track {
    background: rgba(80, 165, 230, 0.9);
}
.settings-recording-switch input:checked + .settings-recording-switch-track::before {
    transform: translateX(18px);
}
.settings-recording-switch input:focus-visible + .settings-recording-switch-track {
    outline: 2px solid rgba(80, 165, 230, 0.75); outline-offset: 3px;
}
.settings-recording-switch input:disabled + .settings-recording-switch-track {
    opacity: 0.55; cursor: wait;
}

'@
if (!$css.Contains("AUTOCUA_RECORDING_DEFAULT_OFF_V1")) {
    if (!$css.Contains($cssAnchor)) { throw "Could not locate the Settings CSS insertion point in css/style.css." }
    $css = $css.Replace($cssAnchor, $cssInsert + $cssAnchor)
}

[System.IO.File]::WriteAllText($servicePath, $service, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($scriptPath, $script, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($cssPath, $css, [System.Text.UTF8Encoding]::new($false))

if (!$service.Contains($marker) -or !$service.Contains("/api/recording-setting") -or
    !$script.Contains($marker) -or !$script.Contains("loadRecordingSetting();") -or
    !$css.Contains($marker)) {
    throw "Recording switch patch verification failed."
}
Write-Host "Applied opt-in Recording switch. Existing installs default to OFF."
