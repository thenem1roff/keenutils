#!/usr/bin/env python3
"""Flowseal -> nfqws2 strategy manager for KeenUtils.

Stage 1: convert and save strategies only. Never alters an installed nfqws2
configuration, its lists/blobs, or the running service.
MIT conversion core: Sxlenium/zapret-keenetic-converter (see LICENSE).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from zapret_keenetic.converter import ConversionError, ConverterSettings, convert

HOME = Path(os.environ.get("KEENUTILS_FLOWSEAL_HOME", "/opt/etc/keenutils/flowseal"))
STRATEGIES = HOME / "strategies"
HISTORY = HOME / "history"
TEMP = HOME / "tmp"
NFQWS2_CONF = Path("/opt/etc/nfqws2/nfqws2.conf")
RELEASE_API = "https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest"
USER_AGENT = "KeenUtils-Flowseal-Converter/0.1"
MAX_ARCHIVE_BYTES = 20 * 1024 * 1024
MAX_SINGLE_FILE = 8 * 1024 * 1024
MAX_TOTAL_EXTRACTED = 48 * 1024 * 1024


class ManagerError(RuntimeError):
    """Recoverable error shown to the user."""


def prompt(message: str) -> str:
    try:
        return input(message).strip()
    except (EOFError, KeyboardInterrupt):
        print()
        raise SystemExit(0)


def ask_yes(message: str) -> bool:
    while True:
        value = prompt(f"{message} [Y/n]: ").lower()
        if value in {"", "y", "yes"}:
            return True
        if value in {"n", "no"}:
            return False
        print("Введите Y или n.")


def http_open(url: str, timeout: int = 35):
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    )
    return urllib.request.urlopen(req, timeout=timeout)


def release_info() -> tuple[str, str]:
    """Read current official release; pin the zip URL to its version."""
    try:
        with http_open(RELEASE_API) as response:
            data = json.load(response)
    except (OSError, ValueError) as error:
        raise ManagerError(f"Не удалось получить выпуск Flowseal: {error}") from error
    version = str(data.get("tag_name", "")).removeprefix("v")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        raise ManagerError("Неизвестный формат версии Flowseal.")
    for asset in data.get("assets", []):
        name = str(asset.get("name", ""))
        url = str(asset.get("browser_download_url", ""))
        parsed = urllib.parse.urlsplit(url)
        if (
            name.lower().endswith(".zip")
            and name.lower().startswith("zapret-discord-youtube-")
            and parsed.scheme == "https"
            and parsed.netloc == "github.com"
            and parsed.path.startswith(
                f"/Flowseal/zapret-discord-youtube/releases/download/"
            )
        ):
            return version, url
    raise ManagerError("В последнем выпуске Flowseal не найден официальный ZIP-архив.")


def download_release(url: str, destination: Path) -> str:
    """Download bounded ZIP, returning SHA256 for provenance."""
    digest = hashlib.sha256()
    total = 0
    try:
        with http_open(url, timeout=60) as source, destination.open("xb") as target:
            while True:
                block = source.read(128 * 1024)
                if not block:
                    break
                total += len(block)
                if total > MAX_ARCHIVE_BYTES:
                    raise ManagerError("Размер архива Flowseal превышает безопасный предел.")
                digest.update(block)
                target.write(block)
    except (OSError, urllib.error.URLError) as error:
        raise ManagerError(f"Ошибка загрузки Flowseal: {error}") from error
    if not zipfile.is_zipfile(destination):
        raise ManagerError("Полученный архив не является ZIP.")
    return digest.hexdigest()


def safe_members(archive: zipfile.ZipFile) -> list[tuple[zipfile.ZipInfo, tuple[str, ...]]]:
    """Only materialize strategy bat files, text lists and binary templates."""
    items: list[tuple[zipfile.ZipInfo, tuple[str, ...]]] = []
    seen: set[tuple[str, ...]] = set()
    total = 0
    for info in archive.infolist():
        if info.is_dir():
            continue
        raw = PurePosixPath(info.filename)
        parts = raw.parts
        if not parts or any(part in {"", ".", ".."} for part in parts):
            raise ManagerError("В архиве обнаружен небезопасный путь.")
        if parts[0].lower().startswith("zapret-discord-youtube-"):
            parts = parts[1:]
        if not parts:
            continue
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_ISLNK(mode):
            raise ManagerError("Архив содержит символические ссылки.")
        if len(parts) == 1:
            allowed = parts[0].lower().startswith("general") and parts[0].lower().endswith(".bat")
        elif len(parts) == 2 and parts[0].lower() == "lists":
            allowed = parts[1].lower().endswith((".txt", ".txt.backup"))
        elif len(parts) == 2 and parts[0].lower() == "bin":
            allowed = parts[1].lower().endswith(".bin")
        else:
            allowed = False
        if not allowed:
            continue
        normalized = tuple(parts)
        if normalized in seen or info.file_size > MAX_SINGLE_FILE:
            raise ManagerError("Дубликат или слишком большой файл в архиве Flowseal.")
        seen.add(normalized)
        total += info.file_size
        if total > MAX_TOTAL_EXTRACTED:
            raise ManagerError("Слишком большой объём файлов в архиве Flowseal.")
        items.append((info, normalized))
    return items


def extract_release(archive_path: Path, source_dir: Path) -> list[str]:
    """Never call extractall: filter paths and ignore Windows executables."""
    profiles: list[str] = []
    with zipfile.ZipFile(archive_path) as archive:
        for info, parts in safe_members(archive):
            dest = source_dir.joinpath(*parts)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as src, dest.open("xb") as out:
                shutil.copyfileobj(src, out)
            if len(parts) == 1:
                profiles.append(parts[0])
    if not profiles:
        raise ManagerError("В архиве Flowseal не найдены профили general*.bat.")
    return sorted(profiles, key=lambda n: n.casefold())


def display_name(profile: str) -> str:
    stem = profile[:-4] if profile.lower().endswith(".bat") else profile
    match = re.fullmatch(r"general(?: \(([^)]+)\))?", stem, flags=re.IGNORECASE)
    return (match.group(1) if match and match.group(1) else "GENERAL") if match else stem


def strategy_id(version: str, profile: str) -> str:
    name = display_name(profile).casefold()
    slug = re.sub(r"[^a-z0-9]+", "-", name).strip("-")
    if not slug:
        raise ManagerError("Не удалось создать идентификатор стратегии.")
    return f"flowseal-{version}-{slug}"


def read_info(directory: Path) -> dict[str, object] | None:
    if directory.is_symlink() or not directory.is_dir():
        return None
    try:
        info = json.loads((directory / "info.json").read_text(encoding="utf-8"))
        return info if isinstance(info, dict) and info.get("source") == "Flowseal" else None
    except (OSError, ValueError):
        return None


def saved_strategies() -> list[tuple[Path, dict[str, object]]]:
    results = []
    if STRATEGIES.is_dir():
        for path in sorted(STRATEGIES.iterdir(), key=lambda p: p.name):
            info = read_info(path)
            if info:
                results.append((path, info))
    return results


def config_hash(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    except OSError:
        return None


def is_active(path: Path) -> bool:
    saved = config_hash(path / "nfqws2.conf")
    return saved is not None and saved == config_hash(NFQWS2_CONF)


def choose_profile(profiles: list[str], version: str) -> str | None:
    print(f"\nFlowseal {version} — доступные стратегии:")
    for i, name in enumerate(profiles, 1):
        print(f" {i:>2}. {display_name(name)}")
    print("  0. Назад")
    while True:
        answer = prompt("Выберите стратегию: ")
        if answer in {"", "0", "00"}:
            return None
        if answer.isdecimal() and 1 <= int(answer) <= len(profiles):
            return profiles[int(answer) - 1]
        print("Неверный номер.")


def add_strategy() -> None:
    print("\nПолучение последнего выпуска Flowseal...")
    version, download_url = release_info()
    TEMP.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".import-", dir=TEMP) as temp_name:
        working = Path(temp_name)
        archive = working / "flowseal.zip"
        source = working / "source"
        source.mkdir()
        zip_sha256 = download_release(download_url, archive)
        profiles = extract_release(archive, source)
        profile = choose_profile(profiles, version)
        if profile is None:
            return
        name = display_name(profile)
        if not ask_yes(f"Конвертировать {name} (Flowseal {version})?"):
            return
        games = ask_yes("Добавить игровые порты TCP/UDP?")
        identifier = strategy_id(version, profile)
        destination = STRATEGIES / identifier
        if destination.is_symlink():
            raise ManagerError("Символическая ссылка вместо папки стратегии: операция отменена.")
        if destination.exists() and not ask_yes("Такая стратегия уже есть. Пересоздать её?"):
            return

        output = working / "converted"
        print("Конвертация...")
        try:
            result = convert(
                ConverterSettings(
                    source=source,
                    profile=profile,
                    output=output,
                    target="keenetic",
                    game_filter="all" if games else "disabled",
                    strict=False,
                )
            )
        except (ConversionError, OSError) as error:
            raise ManagerError(f"Конвертация не удалась: {error}") from error
        metadata = {
            "source": "Flowseal",
            "name": name,
            "version": version,
            "profile": profile,
            "game_ports": games,
            "release_url": download_url,
            "archive_sha256": zip_sha256,
            "profile_sha256": hashlib.sha256((source / profile).read_bytes()).hexdigest(),
            "converted_at": datetime.now(timezone.utc).isoformat(),
            "target": "nfqws2-keenetic",
            "state": "saved_only",
        }
        (output / "info.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        # Atomic handoff of a fully prepared output directory on the same filesystem.
        if destination.exists():
            if is_active(destination):
                raise ManagerError("Сохранённая стратегия совпадает с рабочей: замена запрещена.")
            HISTORY.mkdir(parents=True, exist_ok=True)
            backup_name = identifier + "-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
            destination.rename(HISTORY / backup_name)
            try:
                output.rename(destination)
            except OSError:
                (HISTORY / backup_name).rename(destination)
                raise
        else:
            output.rename(destination)

        print(f"\nСохранена: {name} — Flowseal {version}")
        print(f"Каталог: {destination}")
        print(f"Игровые порты: {'включены' if games else 'выключены'}")
        print(f"Перенесено профилей: {result.profiles_written}/{result.profiles_read}")
        print(f"Предупреждения конвертера: {result.warning_count}")
        for item in result.diagnostics:
            if item.level == "warning":
                print(f"  Внимание: {item.message}")
        print("Конфигурация nfqws2 сохранена, но НЕ применена к роутеру.")
        print("Адаптация штатных LIST/BIN и безопасное применение — следующий этап.")


def show_strategy(directory: Path, info: dict[str, object]) -> None:
    while True:
        label = f"{info.get('name')} — Flowseal {info.get('version')}"
        print(f"\n{label}")
        print(f"Статус: {'совпадает с рабочей' if is_active(directory) else 'сохранена'}")
        print(" 1. Информация и предупреждения")
        print(" 2. Показать nfqws2.conf")
        print(" 3. Удалить сохранённую стратегию")
        print(" 0. Назад")
        choice = prompt("Выберите действие: ")
        if choice in {"", "0", "00"}:
            return
        if choice == "1":
            print(json.dumps(info, ensure_ascii=False, indent=2))
            report = directory / "REPORT.md"
            if report.is_file():
                print(report.read_text(encoding="utf-8"))
        elif choice == "2":
            conf = directory / "nfqws2.conf"
            if conf.is_file():
                print(conf.read_text(encoding="utf-8"))
            else:
                print("Конфигурация отсутствует.")
        elif choice == "3":
            if is_active(directory):
                print("Удалять конфигурацию, совпадающую с рабочей, запрещено.")
                continue
            if ask_yes(f"Удалить {label} со всеми её сохранёнными файлами?"):
                if directory.is_symlink() or not directory.is_dir():
                    raise ManagerError("Небезопасный путь стратегии.")
                shutil.rmtree(directory)
                print("Стратегия удалена.")
                return
        else:
            print("Неизвестный пункт.")


def my_strategies() -> None:
    while True:
        entries = saved_strategies()
        print("\nМои стратегии:")
        if not entries:
            print("  Пока нет сохранённых стратегий.")
        else:
            for i, (directory, info) in enumerate(entries, 1):
                status = " [СОВПАДАЕТ С РАБОЧЕЙ]" if is_active(directory) else ""
                print(f" {i:>2}. {info.get('name')} — Flowseal {info.get('version')}{status}")
        print("  0. Назад")
        choice = prompt("Выберите стратегию: ")
        if choice in {"", "0", "00"}:
            return
        if choice.isdecimal() and 1 <= int(choice) <= len(entries):
            directory, info = entries[int(choice) - 1]
            show_strategy(directory, info)
        else:
            print("Неверный номер.")


def main() -> int:
    STRATEGIES.mkdir(parents=True, exist_ok=True)
    if STRATEGIES.is_symlink():
        raise ManagerError("Папка стратегий не должна быть символической ссылкой.")
    while True:
        print("\n======== KeenUtils | Flowseal → nfqws2 ========")
        print(" 1. Добавить стратегию")
        print(" 2. Мои стратегии")
        print(" 0. Назад в KeenUtils")
        print(" Стадия разработки: конвертация и хранение, без применения.")
        choice = prompt("Выберите действие: ")
        if choice in {"", "0", "00"}:
            return 0
        try:
            if choice == "1":
                add_strategy()
            elif choice == "2":
                my_strategies()
            else:
                print("Неизвестный пункт.")
        except (ManagerError, OSError, zipfile.BadZipFile) as error:
            print(f"Ошибка: {error}", file=sys.stderr)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ManagerError as error:
        print(f"Ошибка: {error}", file=sys.stderr)
        sys.exit(1)
