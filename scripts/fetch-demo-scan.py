import json
import os
import struct
import subprocess
import sys
import zlib

DOI = "https://doi.org/10.57760/sciencedb.26465"
URL = ("https://china.scidb.cn/download"
       "?fileId=8e263f7b3391e011251970d5a86c8e2a&dataSetType=personal&version=V2")
ARCHIVE_BYTES = 23534221851
CASE_PREFIX = "Dataset/annotated/image/Meyer/M29/"
ANNOTATION_PREFIX = "Dataset/annotated/mask/Meyer/M29/"
DESTINATION = "App/Seeds/DemoSeries"
ANNOTATION_DESTINATION = "App/Seeds/DemoSeries.roi.json"


def fetch(start, length):
    result = subprocess.run(
        ["curl", "-sS", "--fail", "-m", "600", "-A", "Mozilla/5.0",
         "-r", "%d-%d" % (start, start + length - 1), URL],
        capture_output=True)
    if result.returncode != 0:
        raise RuntimeError("range request failed: %s" % result.stderr[:200])
    return result.stdout


def central_directory():
    tail = fetch(ARCHIVE_BYTES - 65536, 65536)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("end of central directory not found")
    locator = tail.rfind(b"PK\x06\x07", 0, eocd)
    if locator < 0:
        size, offset = struct.unpack_from("<II", tail, eocd + 12)
        return offset, size
    header = fetch(struct.unpack_from("<Q", tail, locator + 8)[0], 56)
    if header[:4] != b"PK\x06\x06":
        raise RuntimeError("zip64 end of central directory not found")
    return struct.unpack_from("<Q", header, 48)[0], struct.unpack_from("<Q", header, 40)[0]


def entries():
    offset, size = central_directory()
    blob = fetch(offset, size)
    found = []
    cursor = 0
    while cursor < len(blob) - 4 and blob[cursor:cursor + 4] == b"PK\x01\x02":
        fields = struct.unpack_from("<HHHHHHIIIHHHHHII", blob, cursor + 4)
        method, compressed, uncompressed = fields[3], fields[7], fields[8]
        name_length, extra_length, comment_length = fields[9], fields[10], fields[11]
        local = fields[15]
        name = blob[cursor + 46:cursor + 46 + name_length].decode("utf-8", "replace")
        extra = blob[cursor + 46 + name_length:cursor + 46 + name_length + extra_length]
        if uncompressed == 0xFFFFFFFF or compressed == 0xFFFFFFFF or local == 0xFFFFFFFF:
            position = 0
            while position + 4 <= len(extra):
                header_id, header_size = struct.unpack_from("<HH", extra, position)
                if header_id == 0x0001:
                    payload = extra[position + 4:position + 4 + header_size]
                    read = 0
                    if uncompressed == 0xFFFFFFFF:
                        uncompressed = struct.unpack_from("<Q", payload, read)[0]
                        read += 8
                    if compressed == 0xFFFFFFFF:
                        compressed = struct.unpack_from("<Q", payload, read)[0]
                        read += 8
                    if local == 0xFFFFFFFF:
                        local = struct.unpack_from("<Q", payload, read)[0]
                    break
                position += 4 + header_size
        found.append({"name": name, "method": method, "compressed": compressed, "local": local})
        cursor += 46 + name_length + extra_length + comment_length
    return found


def data_offset(entry, blob, base):
    header = blob[entry["local"] - base:entry["local"] - base + 30]
    if header[:4] != b"PK\x03\x04":
        raise RuntimeError("bad local header for %s" % entry["name"])
    name_length, extra_length = struct.unpack_from("<HH", header, 26)
    return entry["local"] + 30 + name_length + extra_length


def expand(entry, raw):
    return zlib.decompress(raw, -15) if entry["method"] == 8 else raw


def pull(all_entries, prefix):
    selected = [e for e in all_entries if e["name"].startswith(prefix) and not e["name"].endswith("/")]
    if not selected:
        raise RuntimeError("no entries under %s" % prefix)
    selected.sort(key=lambda e: e["local"])
    low = selected[0]["local"]
    high = selected[-1]["local"] + selected[-1]["compressed"] + 4096
    blob = fetch(low, high - low)
    return [(e["name"], expand(e, blob[data_offset(e, blob, low) - low:][:e["compressed"]])) for e in selected]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    print("reading archive index from %s" % DOI)
    index = entries()
    print("archive holds %d entries" % len(index))

    print("pulling %s" % CASE_PREFIX)
    slices = pull(index, CASE_PREFIX)
    if os.path.isdir(DESTINATION):
        for name in os.listdir(DESTINATION):
            os.remove(os.path.join(DESTINATION, name))
    os.makedirs(DESTINATION, exist_ok=True)
    for name, payload in slices:
        open(os.path.join(DESTINATION, os.path.basename(name)), "wb").write(payload)
    print("wrote %d slices to %s" % (len(slices), DESTINATION))

    print("pulling %s" % ANNOTATION_PREFIX)
    marks = pull(index, ANNOTATION_PREFIX)
    if marks:
        open(ANNOTATION_DESTINATION, "wb").write(marks[0][1])
        print("wrote annotation %s" % ANNOTATION_DESTINATION)


main()
