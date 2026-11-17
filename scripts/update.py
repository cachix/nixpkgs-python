import requests
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
import json
import base64
import hashlib
import os
import sys
from packaging.specifiers import SpecifierSet
from packaging.version import Version


EXCLUDED_RELEASES = {
    SpecifierSet("<2.7"): "Python 2 series before 2.7 are unsupported",
    SpecifierSet(">=2.7,<2.7.6"): "Unsupported OpenSSL and missing distutils patch",
    SpecifierSet(">=3,<3.3"): "Python 3 series before 3.3 are unsupported",
    SpecifierSet("==3.3.0"): "Patches fail to apply",
    SpecifierSet("==3.9.0"): "Patches fail to apply",
}


def create_session_with_retries():
    session = requests.Session()
    retry_strategy = Retry(
        total=5,
        backoff_factor=1,
        status_forcelist=list(range(500, 600)),  # All 5xx errors
        allowed_methods=["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "TRACE"],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


def source(version):
    # Before 3.3, Python.org omitted the patch zero from initial release archives.
    archive_version = version
    if version.endswith(".0") and Version(version) < Version("3.3"):
        archive_version = version.removesuffix(".0")
    return f"https://www.python.org/ftp/python/{archive_version}/Python-{archive_version}.tgz"


def activestate_source(tag):
    return f"https://github.com/ActiveState/cpython/archive/refs/tags/{tag}.tar.gz"


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


def add_release(versions, cycle, version, url, session):
    release_version = Version(version)
    if any(release_version in specifier for specifier in EXCLUDED_RELEASES):
        return

    if not versions["releases"].get(version, {}).get("hash"):
        print(f"Downloading {url}")
        response = session.get(url)
        if response.status_code == 404:
            print(f"Skipping Python {version} (HTTP 404 at {url})", file=sys.stderr)
            return
        response.raise_for_status()
        versions["releases"][version] = {
            "hash": calculate_sha256(response.content),
            "url": url,
        }

    versions["latest"][cycle] = max(
        version, versions["latest"].get(cycle, version), key=Version
    )


def get_all_releases(response, versions, session):
    for entry in response.json():
        cycle = entry["cycle"]
        latest_version = entry["latest"]
        latest_version_split = latest_version.split(".")
        latest_patch = int(latest_version_split[-1])

        for i in range(0, latest_patch + 1):
            version = f"{cycle}.{i}"
            add_release(versions, cycle, version, source(version), session)
    return versions


def get_activestate_releases(response, versions, session):
    for entry in response.json():
        tag = entry["tag_name"]
        version = tag.lstrip("v")
        cycle = ".".join(version.split(".")[:2])

        if cycle != "2.7" or entry["prerelease"]:
            continue

        add_release(versions, cycle, version, activestate_source(tag), session)
    return versions


def calculate_sha256(contents):
    return base64.b64encode(hashlib.sha256(contents).digest()).decode("utf-8")


if __name__ == "__main__":
    versions = get_versions()
    session = create_session_with_retries()

    # TODO: pypy: https://downloads.python.org/pypy/versions.json
    response = session.get("https://endoflife.date/api/python.json")
    response.raise_for_status()

    versions = get_all_releases(response, versions, session)

    headers = {}
    if gh_token := os.getenv("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {gh_token}"

    activestate_response = session.get(
        "https://api.github.com/repos/ActiveState/cpython/releases", headers=headers
    )

    activestate_response.raise_for_status()

    versions = get_activestate_releases(activestate_response, versions, session)

    with open("versions.json", "w") as f:
        json.dump(versions, f, indent=4)
