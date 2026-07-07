"""Remove garbled S3 extension duplicate (hash AAAA...) from DEV infobase."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

DUP_HASH = "AAAAAAAAAAAAAAAAAAAAAAAAAAA="


def read_dotenv(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def resolve_ib(project_root: Path, dotenv: dict[str, str]) -> str:
    ib_path = dotenv["INFOBASE_PATH"]
    ib = Path(ib_path)
    if not ib.is_absolute():
        ib = project_root / ib
    return str(ib)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        text=True,
        encoding="utf-8",
        errors="replace",
        **kwargs,
    )


def list_extensions(ibcmd: str, ib: str, user: str, password: str) -> str:
    return subprocess.check_output(
        [
            ibcmd,
            "infobase",
            "config",
            "extension",
            "list",
            f"--db-path={ib}",
            f"--user={user}",
            f"--password={password}",
        ],
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def find_duplicate_name(list_out: str) -> str | None:
    blocks = re.findall(
        r'name\s+:\s+"([^"]+)".*?hash-sum\s+:\s+"([^"]+)"',
        list_out,
        re.S,
    )
    for name, hash_sum in blocks:
        if hash_sum == DUP_HASH:
            return name
    return None


def delete_via_ibcmd(ibcmd: str, ib: str, user: str, password: str, name: str) -> int:
    proc = run(
        [
            ibcmd,
            "infobase",
            "config",
            "extension",
            "delete",
            f"--db-path={ib}",
            f"--name={name}",
            f"--user={user}",
            f"--password={password}",
        ],
        input="y\n",
        capture_output=True,
    )
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    return proc.returncode


def delete_via_designer(v8: str, ib: str, user: str, password: str, name: str) -> int:
    proc = run(
        [
            v8,
            "DESIGNER",
            f"/F{ib}",
            f"/N{user}",
            f"/P{password}",
            "/DeleteCfg",
            f"-Extension{name}",
            "/DisableStartupDialogs",
        ],
        capture_output=True,
    )
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    return proc.returncode


def main() -> int:
    project_root = Path(__file__).resolve().parents[2]
    env_file = project_root / ".dev.env"
    dotenv = read_dotenv(env_file)

    platform_bin = Path(dotenv["PLATFORM_PATH"]) / "bin"
    ibcmd = str(platform_bin / "ibcmd.exe")
    v8 = str(platform_bin / "1cv8.exe")
    ib = resolve_ib(project_root, dotenv)
    user = dotenv["IB_USER"]
    password = dotenv["IB_PASSWORD"]

    list_out = list_extensions(ibcmd, ib, user, password)
    dup = find_duplicate_name(list_out)
    if not dup:
        print("OK: duplicate with AAAA hash not found")
        return 0

    print(f"Deleting duplicate: {dup!r}")

    code = delete_via_ibcmd(ibcmd, ib, user, password, dup)
    if code != 0:
        print("ibcmd delete failed, trying DESIGNER /DeleteCfg ...")
        code = delete_via_designer(v8, ib, user, password, dup)

    if code != 0:
        return code

    if find_duplicate_name(list_extensions(ibcmd, ib, user, password)):
        print("FAIL: duplicate still present", file=sys.stderr)
        return 1

    print("OK: duplicate removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
