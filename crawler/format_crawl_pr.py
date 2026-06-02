#!/usr/bin/env python3
import json
from pathlib import Path


def latest_log_path() -> Path:
    logs = sorted(Path("data/crawl_runs").glob("*.json"))
    if not logs:
        raise SystemExit("No crawl run logs found")
    return logs[-1]


def source_line(date: str, source: str, status: dict) -> str:
    state = status.get("status")
    if state == "success":
        changed = "changed" if status.get("changed") else "unchanged"
        return f"- {date} {source}: success ({changed})"
    error = status.get("error", "unknown error")
    return f"- {date} {source}: failed - {error}"


def main() -> None:
    log_path = latest_log_path()
    log = json.loads(log_path.read_text(encoding="utf-8"))
    lines = [
        "## Crawl summary",
        "",
        f"- Run date: `{log.get('runDate')}`",
        f"- Started: `{log.get('startedAt')}`",
        f"- Finished: `{log.get('finishedAt')}`",
        f"- Targets: `{', '.join(log.get('targetDates', []))}`",
        "",
        "## Generated files",
        "",
    ]

    generated = log.get("generatedFiles", [])
    if generated:
        lines.extend(f"- `{path}`" for path in generated)
    else:
        lines.append("- No JSON content changes.")

    failures = [
        source_line(date, source, status)
        for date, sources in log.get("sources", {}).items()
        for source, status in sources.items()
        if status.get("status") != "success"
    ]
    if failures:
        lines.extend(["", "## Failures", ""])
        lines.extend(failures)

    new_cafeterias = log.get("newCafeterias", [])
    if new_cafeterias:
        lines.extend(["", "## New cafeterias", ""])
        lines.extend(
            f"- `{item.get('id')}` {item.get('name')} ({item.get('phone')})"
            for item in new_cafeterias
        )

    metadata_changes = log.get("metadataChanges", [])
    if metadata_changes:
        lines.extend(["", "## Metadata changes not auto-applied", ""])
        lines.extend(
            f"- `{item.get('id')}`: `{json.dumps(item.get('fields'), ensure_ascii=False)}`"
            for item in metadata_changes
        )

    validation_errors = log.get("validationErrors", [])
    if validation_errors:
        lines.extend(["", "## Validation errors", ""])
        lines.extend(f"- `{error}`" for error in validation_errors)

    body = "\n".join(lines) + "\n"
    print(body)


if __name__ == "__main__":
    main()
