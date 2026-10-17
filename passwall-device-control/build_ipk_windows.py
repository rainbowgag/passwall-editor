#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Windows 版 ipk 构建脚本：复刻 build-openwrt.sh 的打包逻辑。
用法：
    python build_ipk_windows.py                # 构建 dist/luci-app-passwall-device_<VERSION>_all.ipk
    python build_ipk_windows.py --notes "..."  # 同时把该说明写入 update.json / update-vps.json 的当前版本
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))


def read_version():
    with open(os.path.join(ROOT, "VERSION"), encoding="utf-8") as f:
        return f.read().strip()


def copy_tree(src, dst):
    for root, _dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        target = dst if rel == "." else os.path.join(dst, rel)
        os.makedirs(target, exist_ok=True)
        for f in files:
            shutil.copy2(os.path.join(root, f), os.path.join(target, f))


def add_tree(tf, src_root, mode_map):
    for root, _dirs, files in os.walk(src_root):
        rel = os.path.relpath(root, src_root).replace("\\", "/")
        base = "" if rel == "." else rel + "/"
        # 目录条目：OpenWrt 的 busybox tar 不会自动创建不存在的父目录，
        # 必须像 build-openwrt.sh（GNU tar -C）一样把目录项写进归档。
        di = tarfile.TarInfo("." if rel == "." else rel)
        di.type = tarfile.DIRTYPE
        di.mode = 0o755
        di.uid = di.gid = 0
        di.uname = di.gname = "root"
        di.mtime = int(0)
        tf.addfile(di)
        for f in files:
            path = os.path.join(root, f)
            arc = base + f
            ti = tf.gettarinfo(path, arcname=arc)
            ti.mode = mode_map.get(arc, 0o644)
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            ti.mtime = int(0)
            with open(path, "rb") as fh:
                tf.addfile(ti, fh)


def make_gz(path, src_root, mode_map):
    with tarfile.open(path, "w:gz") as tf:
        add_tree(tf, src_root, mode_map)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def recover_note(s):
    """把历史清单里被误存成 UTF-8 的 GBK 乱码恢复成中文；恢复失败则原样返回。"""
    if not s:
        return s
    try:
        raw = s.encode("gbk", errors="strict")
        out = raw.decode("utf-8")
        if "\ufffd" in out:
            return s
        return out
    except (UnicodeDecodeError, UnicodeEncodeError):
        return s


def update_manifest(path, version, ipk_url, sha256, notes, published_at):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    old_version = data.get("version", "")
    old_notes = recover_note(data.get("notes", "") or "")
    history = list(data.get("history") or [])
    if old_version and old_version != version and not any(h.get("version") == old_version for h in history):
        history.append({
            "version": old_version,
            "ipk_url": data.get("ipk_url", ""),
            "sha256": data.get("sha256", ""),
            "notes": old_notes or "历史版本（见 GitHub 更新记录）",
        })
    for h in history:
        h["notes"] = recover_note(h.get("notes", ""))
    data["version"] = version
    data["ipk_url"] = ipk_url
    data["sha256"] = sha256
    data["published_at"] = published_at
    data["notes"] = notes
    data["history"] = history
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", default="新增：一键检测全部代理节点连通性；GitHub 更新清单自更新链路。")
    args = parser.parse_args()
    # Windows 命令行传中文参数常被按 GBK 解码成乱码；恢复为正确 UTF-8 中文。
    notes = recover_note(args.notes) or args.notes

    version = read_version()
    build_dir = tempfile.mkdtemp(prefix="pwc-ipk-")
    try:
        control_dir = os.path.join(build_dir, "control")
        data_dir = os.path.join(build_dir, "data")
        archive_dir = os.path.join(build_dir, "archive")
        for d in (control_dir, data_dir, archive_dir):
            os.makedirs(d)

        copy_tree(os.path.join(ROOT, "package", "CONTROL"), control_dir)
        copy_tree(os.path.join(ROOT, "root"), data_dir)

        # 与 build-openwrt.sh 一致：配置文件不直接进 data，落到 default-config
        cfg_src = os.path.join(data_dir, "etc", "config", "passwall_device")
        cfg_dst = os.path.join(data_dir, "usr", "share", "passwall-device", "default-config")
        shutil.copy2(cfg_src, cfg_dst)
        os.remove(cfg_src)

        control_modes = {"postinst": 0o755, "prerm": 0o755}
        data_modes = {
            "etc/init.d/passwall-device": 0o755,
            "usr/share/passwall-device/app.lua": 0o755,
        }
        share_dir = os.path.join(data_dir, "usr", "share", "passwall-device")
        for f in os.listdir(share_dir):
            if f.endswith(".sh"):
                data_modes["usr/share/passwall-device/" + f] = 0o755

        control_tgz = os.path.join(archive_dir, "control.tar.gz")
        data_tgz = os.path.join(archive_dir, "data.tar.gz")
        make_gz(control_tgz, control_dir, control_modes)
        make_gz(data_tgz, data_dir, data_modes)
        debian = os.path.join(archive_dir, "debian-binary")
        with open(debian, "w", encoding="ascii") as f:
            f.write("2.0\n")

        dist_dir = os.path.join(ROOT, "dist")
        os.makedirs(dist_dir, exist_ok=True)
        out = os.path.join(dist_dir, "luci-app-passwall-device_%s_all.ipk" % version)
        with tarfile.open(out, "w:gz") as tf:
            for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
                ti = tf.gettarinfo(os.path.join(archive_dir, name), arcname=name)
                ti.uid = ti.gid = 0
                ti.uname = ti.gname = "root"
                ti.mtime = int(0)
                with open(os.path.join(archive_dir, name), "rb") as fh:
                    tf.addfile(ti, fh)

        sha = sha256_of(out)
        print("OK  %s" % out)
        print("SHA %s" % sha)

        published = datetime.datetime.now().strftime("%Y-%m-%d")
        gh_url = ("https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/"
                  "passwall-device-control/dist/luci-app-passwall-device_%s_all.ipk" % version)
        vps_url = "http://m.yaml.uk:25532/luci-app-passwall-device_%s_all.ipk" % version
        update_manifest(os.path.join(ROOT, "update.json"), version, gh_url, sha,
                        notes, published)
        update_manifest(os.path.join(ROOT, "update-vps.json"), version, vps_url, sha,
                        notes, published)
        print("OK  update.json / update-vps.json 已更新为 %s" % version)
        return 0
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
