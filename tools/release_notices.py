"""Regenerate accompanying notices from a built APK, retaining native attributions."""
import argparse
import gzip
from pathlib import Path
import zipfile
import zlib

parser = argparse.ArgumentParser()
parser.add_argument("apk", type=Path)
parser.add_argument("--version", required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
destination = root / "THIRD_PARTY_LICENSES.txt"
marker = "Flutter-generated dependency notices"
existing = destination.read_text(encoding="utf-8")
if marker not in existing:
    raise ValueError("Native-attribution prefix not found; refusing to discard existing notices.")
prefix = existing.split(marker, 1)[0]
prefix = "Linqo " + args.version + " — accompanying dependency and native-runtime notices\n" + prefix.split("\n", 1)[1]
with zipfile.ZipFile(args.apk) as archive:
    compressed = archive.read("assets/flutter_assets/NOTICES.Z")
try:
    notices = gzip.decompress(compressed)
except gzip.BadGzipFile:
    notices = zlib.decompress(compressed)
text = notices.decode("utf-8")
for package in ("firebase_auth", "firebase_core", "google_sign_in", "cryptography"):
    if package not in text:
        raise ValueError(f"Expected dependency attribution missing: {package}")
combined = (prefix + marker + "\n\n" + text).replace("\r\n", "\n").replace("\r", "\n")
combined = "\n".join(line.rstrip(" \t") for line in combined.split("\n"))
destination.write_text(combined, encoding="utf-8", newline="\n")
print(f"Regenerated {destination.name} from the APK; native runtime attributions preserved.")
