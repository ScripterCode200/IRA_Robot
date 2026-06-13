import urllib.request
import json
import os
import tarfile

url = "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/tts-models"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        assets = data.get('assets', [])
        
        # Find female English and Hindi models
        en_url = next((a['browser_download_url'] for a in assets if 'en_US-kristin-medium.tar.bz2' in a['name']), None)
        hi_url = next((a['browser_download_url'] for a in assets if 'hi_IN-swara-medium.tar.bz2' in a['name']), None)
        if not hi_url:
            hi_url = next((a['browser_download_url'] for a in assets if 'hi_IN-rohan-medium.tar.bz2' in a['name']), None)

        print("English URL:", en_url)
        print("Hindi URL:", hi_url)
        
        os.makedirs("assets/tts", exist_ok=True)
        
        for download_url in [en_url, hi_url]:
            if not download_url: continue
            filename = download_url.split('/')[-1]
            filepath = os.path.join("assets/tts", filename)
            if not os.path.exists(filepath):
                print(f"Downloading {filename}...")
                urllib.request.urlretrieve(download_url, filepath)
                print(f"Extracting {filename}...")
                with tarfile.open(filepath, "r:bz2") as tar:
                    tar.extractall(path="assets/tts")
                print(f"Done extracting {filename}.")
            else:
                print(f"Already have {filename}.")

except Exception as e:
    print("Error:", e)
