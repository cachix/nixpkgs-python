import requests
import json
import base64
import hashlib

source = lambda version: f"https://www.python.org/ftp/python/{version}/Python-{version}.tgz"

# open versions.json and parse json
def get_versions():
    # if versions.json doesn't exist, create it
    try:
        with open("versions.json", "r") as f:
            return json.load(f)
    except FileNotFoundError:
        d = {"releases": {}, "latest": {}}
        with open("versions.json", "w") as f:
            json.dump(d, f)
        return d

def get_all_releases(response, versions):
    for entry in response.json():
        cycle = entry['cycle']
        latest_version = entry['latest']
        latest_version_split = latest_version.split('.')
        latest_patch = int(latest_version_split[-1])

        if cycle == "2.6":
            continue

        versions['latest'][cycle] = latest_version

        
        for i in range(0, latest_patch + 1):
            version = f"{cycle}.{i}"
            # unsupported openssl version & no distutils patch
            if version in [
                    "2.7.0", 
                    "2.7.1", 
                    "2.7.2", 
                    "2.7.3", 
                    "2.7.4", 
                    "2.7.5",
                    "3.2.0", # it's named 3.2 for some reason
                    "3.1.0", # it's named 3.1 for some reason
                    "3.0.0", # it's named 3.0 for some reason
                    # patches fail:
                    "3.3.0",
                    "3.9.0"]:
                continue
            release = versions['releases'].get(version, {})
            if release.get('hash'):
                continue
            else:
                url = source(version)
                print(f'Downloading {url}')
                response = requests.get(url)
                response.raise_for_status()
                versions['releases'][version] = { 
                    "hash": calculate_sha256(response.content), 
                    "url": url
                }
    return versions

def calculate_sha256(contents):
    return base64.b64encode(hashlib.sha256(contents).digest()).decode('utf-8')

if __name__ == "__main__":
    versions = get_versions()
    
    # TODO: pypy: https://downloads.python.org/pypy/versions.json
    response = requests.get("https://endoflife.date/api/python.json")

    versions = get_all_releases(response, versions)
    with open("versions.json", "w") as f:
        json.dump(versions, f, indent=4)
