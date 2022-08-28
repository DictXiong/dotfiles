#!/usr/bin/env python3
import os, uuid, socket, argparse, logging

namespace = uuid.UUID("cc23b903-1993-44eb-9c90-48bd841eeac3")
logging.basicConfig(level=logging.INFO, format="[%(filename)s:%(lineno)d][%(levelname)s] %(message)s")

try:
    import requests
except ImportError:
    logging.critical("Please install requests module")
    exit(1)


def get_uuid_raw() -> str:
    possible_uuid_files = [
        "/var/lib/dbus/machine-id",
        "/etc/machine-id",
        os.path.join(os.path.expanduser('~'), ".config/dotfiles/uuid"),
    ]
    for i in possible_uuid_files:
        if os.path.exists(i):
            with open(i, "r") as f:
                return f.read().strip()
    if not os.path.exists(os.path.dirname(possible_uuid_files[-1])):
        os.makedirs(os.path.dirname(possible_uuid_files[-1]))
    with open(possible_uuid_files[-1], 'w') as f:
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
    content=content.strip()
    if not content:
        logging.error("empty log content")
        exit(0)
    resp = post_log(url, hostname, uuid, content)
    if resp.status_code == 200:
        logging.info("200 ok")
        exit(0)
    elif resp.status_code == 403:
        logging.error("403 forbidden")
        logging.info("you may need to register your hostname and uuid")
        logging.info(f"hostname: {hostname}, uuid: {uuid}")
        exit(0)
    else:
        logging.critical("unknown error ")
        logging.error(f"{resp.status_code}: {resp.text}")
        exit(1)
