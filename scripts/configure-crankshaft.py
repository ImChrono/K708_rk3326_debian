#!/usr/bin/env python3
"""Apply USB video/touch bring-up settings to the installed upstream config."""
import json
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "etc/crankshaft/crankshaft.json"
config = json.loads(path.read_text())
config["core"]["android_auto"]["channels"].update({
    "all_enabled": False, "video_enabled": True, "input_enabled": True,
    "sensor_enabled": True, "bluetooth_enabled": False,
    "microphone_enabled": False, "telephony_audio_enabled": False,
    "media_audio_enabled": False, "system_audio_enabled": False,
    "speech_audio_enabled": False})
path.write_text(json.dumps(config, indent=2) + "\n")
