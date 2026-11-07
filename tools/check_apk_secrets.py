"""Check a local APK against private server credentials without printing values."""
import argparse
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("apk", type=Path)
parser.add_argument("--client-config", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
private = root / ".private" / "linqo-cloud"
needles = []
provider = private / "google-provider.json"
if provider.exists():
    secret = json.loads(provider.read_text(encoding="utf-8-sig")).get("clientSecret")
    if secret:
        needles.append(secret.encode())
secrets_file = private / "secrets.json"
if secrets_file.exists():
    secrets = json.loads(secrets_file.read_text(encoding="utf-8-sig"))
    for key, value in secrets.items():
        if key == "ENTITLEMENT_PRIVATE_JWK":
            value = json.loads(value).get("d")
        if value:
            needles.append(value.encode())
if not needles:
    raise ValueError("No private server values available for this check.")
overlap = max(map(len, needles)) - 1
required = {}
if args.client_config:
    config = json.loads(args.client_config.read_text(encoding="utf-8-sig"))
    for field in ("LINQO_FIREBASE_PROJECT_ID", "LINQO_FIREBASE_API_KEY", "LINQO_FIREBASE_APP_ID", "LINQO_GOOGLE_WEB_CLIENT_ID", "LINQO_CLOUD_URL"):
        if not config.get(field):
            raise ValueError("Missing required client configuration field: " + field)
        required[field] = str(config[field]).encode()
    overlap = max(overlap, max(map(len, required.values())) - 1)
found = set()
entries = 0
with zipfile.ZipFile(args.apk) as archive:
    for info in archive.infolist():
        if info.is_dir():
            continue
        entries += 1
        with archive.open(info) as stream:
            tail = b""
            while chunk := stream.read(1024 * 1024):
                window = tail + chunk
                if any(value in window for value in needles):
                    raise ValueError("A private server credential was found in the APK. Do not distribute it.")
                found.update(field for field, value in required.items() if value in window)
                tail = window[-overlap:] if overlap else b""
print(f"Checked {entries} APK entries: no private server credential values found.")
if required:
    missing = set(required) - found
    if missing:
        raise ValueError("APK is missing expected client configuration fields: " + ", ".join(sorted(missing)))
    print("Expected Firebase client configuration is present in the APK; values were not printed.")
