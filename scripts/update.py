import requests
import json
import base64
import hashlib
import os


def source(version):
    return f"https://www.python.org/ftp/python/{version}/Python-{version}.tgz"


def activestate_source(version):
    return f"https://github.com/ActiveState/cpython/archive/refs/tags/v{version}.tar.gz"


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
        cycle = entry["cycle"]
        latest_version = entry["latest"]
        latest_version_split = latest_version.split(".")
        latest_patch = int(latest_version_split[-1])

        if cycle in ["2.6", "3.0", "3.1", "3.2"]:
            continue

        versions["latest"][cycle] = latest_version

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
                # patches fail:
                "3.3.0",
                "3.9.0",
            ]:
                continue
            release = versions["releases"].get(version, {})
            if release.get("hash"):
                continue
            else:
                url = source(version)
                print(f"Downloading {url}")
                response = requests.get(url)
                response.raise_for_status()
                versions["releases"][version] = {
                    "hash": calculate_sha256(response.content),
                    "url": url,
                }
    return versions


def get_activestate_releases(response, versions):
    for entry in response.json():
        version = entry["tag_name"].lstrip("v")
        cycle = ".".join(version.split(".")[:2])
        release = versions["releases"].get(version, {})

        if cycle != "2.7":
            continue

        versions["latest"][cycle] = max(version, versions["latest"].get(cycle, ""))

        if release.get("hash"):
            continue
        else:
            url = activestate_source(version)
            print(f"Downloading {url}")
            response = requests.get(url)
            response.raise_for_status()
            versions["releases"][version] = {
                "hash": calculate_sha256(response.content),
                "url": url,
            }
    return versions


def calculate_sha256(contents):
    return base64.b64encode(hashlib.sha256(contents).digest()).decode("utf-8")


if __name__ == "__main__":
    versions = get_versions()

    # TODO: pypy: https://downloads.python.org/pypy/versions.json
    response = requests.get("https://endoflife.date/api/python.json")

    versions = get_all_releases(response, versions)

    headers = {}
    if gh_token := os.getenv("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {gh_token}"

    activestate_response = requests.get(
        "https://api.github.com/repos/ActiveState/cpython/releases", headers=headers
    )

    activestate_response.raise_for_status()

    versions = get_activestate_releases(activestate_response, versions)

    with open("versions.json", "w") as f:
        json.dump(versions, f, indent=4)
