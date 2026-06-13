import urllib.request
import json

url = "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/tts-models"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        assets = data.get('assets', [])
        en_models = [a['name'] for a in assets if 'en_US' in a['name'] and 'piper' in a['name']]
        hi_models = [a['name'] for a in assets if 'hi_IN' in a['name'] and 'piper' in a['name']]
        print("English Models:", en_models[:3])
        print("Hindi Models:", hi_models[:3])
except Exception as e:
    print("Error:", e)
