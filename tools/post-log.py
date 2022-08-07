#!/usr/bin/env python3

try:
    import requests
except ImportError:
    print("Please install requests module")
    exit(1)
import os, uuid, socket, argparse

namespace = uuid.UUID("cc23b903-1993-44eb-9c90-48bd841eeac3")

def get_uuid_raw() -> str:
    possible_files = [
        "/var/lib/dbus/machine-id",
        "/etc/machine-id",
        os.path.join(os.path.expanduser('~'), ".uuid"),
    ]
    for i in possible_files:
        if os.path.exists(i):
            with open(i, "r") as f:
                return f.read().strip()
    with open(possible_files[-1], 'w') as f:
        ans = str(uuid.uuid4())
        f.write(ans)
        return ans


def get_uuid() -> str:
    return str(uuid.uuid5(namespace, get_uuid_raw()))


def get_hostname() -> str:
    ans = socket.gethostname()
    if '-' not in ans:
        ans += "-ibd-ink"
    return ans


def post_log(url:str, hostname:str, uuid:str, content:str):
    ans = requests.post(url, params={"hostname": hostname, "uuid": uuid}, data=content)
    return ans


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="post log to server")
    parser.add_argument("-u", "--url", help="url to post to", default="https://api.beardic.cn/post-log")
    parser.add_argument("content")
    args = parser.parse_args()
    url = args.url
    content = args.content
    hostname = get_hostname()
    uuid = get_uuid()
    resp = post_log(url, hostname, uuid, content)
    if resp.status_code == 200:
        print("200 ok")
        exit(0)
    elif resp.status_code == 403:
        print("403 forbidden")
        print("you may need to register your hostname and uuid")
        print(f"hostname: {hostname}, uuid: {uuid}")
    else:
        print("unknown error")
        print(f"{resp.status_code}: {resp.text}")
    exit(1)
