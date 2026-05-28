#!/usr/bin/env python3
import argparse
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen


MEAL_KEYS = ("breakfast", "lunch", "dinner")
KST = timezone(timedelta(hours=9))
ANGLE_NOTE_TITLES = {
    "위 메뉴외에도 다양한 메뉴가 준비되어 있습니다",
    "뷔페 특성상 메뉴의 조기품절 가능성이 있으니 양해 부탁드립니다",
}
FIXED_ONLY_CAFETERIA_IDS = {
    "engineering_snack",
    "building_75_1_food_court",
    "building_220",
}
DORM_EXTRA_CAFETERIA_IDS = {
    "ourhome_901",
}
FIXED_SECTION_TITLES_BY_CAFETERIA = {
    "dure_midam": {"주문식 메뉴"},
}
FIXED_SECTION_TITLE_OVERRIDES_BY_CAFETERIA = {
    "dure_midam": {"주문식 메뉴": "general"},
    "engineering_snack": {"메뉴": "general"},
}
DAILY_SECTION_TITLE_OVERRIDES_BY_CAFETERIA = {
    "arts_cafeteria": {"A코너": "general", "B코너": "general", "C코너": "general"},
}
DAILY_NOTE_EXCLUDES_BY_CAFETERIA = {
    "dure_midam": {"주문식"},
}

CAFETERIA_IDS = {
    "학생회관식당": "student_center",
    "자하연식당 3층": "jahayeon_3f",
    "자하연식당 2층": "jahayeon_2f",
    "예술계식당": "arts_cafeteria",
    "두레미담": "dure_midam",
    "동원관식당": "dongwon",
    "기숙사식당": "dormitory",
    "3식당": "third_cafeteria",
    "302동식당": "building_302",
    "301동식당": "building_301",
    "아워홈": "ourhome_901",
    "생협기숙사": "dormitory",
    "공대간이식당": "engineering_snack",
    "75-1동 4층 푸드코트": "building_75_1_food_court",
    "220동식당": "building_220",
    "버거운버거": "burgerun_burger",
}

STATIC_CAFETERIAS = [
    {
        "id": "burgerun_burger",
        "name": "버거운버거",
        "phone": "878-9288",
    },
]


@dataclass
class CafeteriaName:
    raw: str
    name: str
    phone: str | None


class MenuTableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_menu_table = False
        self.table_depth = 0
        self.row = None
        self.cell = None
        self.rows = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "table" and "menu-table" in attrs.get("class", "").split():
            self.in_menu_table = True
            self.table_depth = 1
            return

        if not self.in_menu_table:
            return

        if tag == "table":
            self.table_depth += 1
        elif tag == "tr":
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []
        elif tag == "br" and self.cell is not None:
            self.cell.append("\n")

    def handle_endtag(self, tag):
        if not self.in_menu_table:
            return

        if tag in ("td", "th") and self.cell is not None:
            text = "".join(self.cell)
            text = re.sub(r"[ \t\r\f\v]+", " ", text)
            text = re.sub(r" *\n *", "\n", text)
            text = re.sub(r"\n{3,}", "\n\n", text)
            self.row.append(unescape(text).strip())
            self.cell = None
        elif tag == "tr" and self.row is not None:
            if any(self.row):
                self.rows.append(self.row)
            self.row = None
        elif tag == "table":
            self.table_depth -= 1
            if self.table_depth == 0:
                self.in_menu_table = False

    def handle_data(self, data):
        if self.in_menu_table and self.cell is not None:
            self.cell.append(data)


def fetch_html(date: str) -> tuple[str, str]:
    source_url = f"https://snuco.snu.ac.kr/foodmenu/?date={date}&orderby=DESC"
    req = Request(source_url, headers={"User-Agent": "Mozilla/5.0 snu-meal-crawler/1.0"})
    with urlopen(req, timeout=20) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace"), source_url


def fetch_dorm_html(date: str) -> tuple[str, str]:
    source_url = f"https://snudorm.snu.ac.kr/foodmenu/?date={date}&orderby=DESC"
    req = Request(source_url, headers={"User-Agent": "Mozilla/5.0 snu-meal-crawler/1.0"})
    with urlopen(req, timeout=20) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace"), source_url


def parse_table_rows(html: str) -> list[list[str]]:
    parser = MenuTableParser()
    parser.feed(html)
    if not parser.rows:
        raise ValueError("menu-table not found")
    header, *rows = parser.rows
    if len(header) < 4:
        raise ValueError(f"unexpected menu-table header: {header}")
    bad_rows = [row for row in rows if len(row) != 4]
    if bad_rows:
        raise ValueError(f"unexpected menu-table rows: {bad_rows}")
    return rows


def parse_cafeteria_name(raw: str) -> CafeteriaName:
    cleaned = raw.lstrip("* ").strip()
    match = re.match(r"^(?P<name>.+?)\s*\((?P<phone>[^)]+)\)$", cleaned)
    if not match:
        return CafeteriaName(raw=raw, name=cleaned, phone=None)
    return CafeteriaName(raw=raw, name=match.group("name").strip(), phone=match.group("phone").strip())


def parse_time_range(text: str, label: str) -> dict[str, str] | None:
    spaced_label = r"\s*".join(label)
    time_pattern = r"(\d{1,2})(?:\s*:\s*(\d{2}))?\s*시?"
    pattern = rf"※\s*{spaced_label}\s*:?\s*[^0-9\n]*{time_pattern}\s*[~\-]\s*{time_pattern}"
    match = re.search(pattern, text)
    if not match:
        return None
    return {
        "start": normalize_time(match.group(1), match.group(2)),
        "end": normalize_time(match.group(3), match.group(4)),
    }


def normalize_time(hour: str, minute: str) -> str:
    return f"{int(hour):02d}:{minute or '00'}"


def parse_items(
    text: str,
    include_unpriced: bool = False,
    cafeteria_id: str | None = None,
) -> list[dict]:
    items = []
    for line in logical_lines(text):
        section_line = parse_section_line(line)
        if section_line:
            line = section_line["content"] or ""
        if not line or line.startswith("※") or normalize_freeform_note_line(line):
            continue
        match = re.match(r"^(?P<name>.+?)\s*[:：]\s*(?P<price>[0-9,]+)\s*[원웡]", line)
        if match:
            name = match.group("name").strip()
            price = int(match.group("price").replace(",", ""))
        elif include_unpriced:
            name = line
            price = None
        else:
            continue
        tags = []
        if "(#)" in name:
            name = name.replace("(#)", "").strip()
            tags.append("NO_MEAT")
        price = normalize_item_price(name, price, cafeteria_id)
        items.append({"name": name, "price": price, "tags": tags})
    return items


def normalize_item_price(name: str, price: int | None, cafeteria_id: str | None = None) -> int | None:
    if cafeteria_id == "student_center" and price == 3000:
        return 1000
    if name == "호구세트" and price == 83000:
        return 8300
    return price


def parse_sections(
    text: str,
    section_notes_enabled: bool = False,
    cafeteria_id: str | None = None,
) -> list[dict]:
    sections = []
    current = None
    general_section = None

    for line in logical_lines(text):
        section_line = parse_section_line(line)
        section_title = section_line["title"] if section_line else None
        if section_title:
            if section_title in ANGLE_NOTE_TITLES:
                current = None
                continue
            current = {"title": section_title, "price": section_line["price"], "rawText": "", "items": [], "notes": []}
            sections.append(current)
            line = section_line["content"]
            if not line:
                continue
        elif current is None and not line.startswith("※"):
            general_section = {"title": "general", "price": None, "rawText": "", "items": [], "notes": []}
            sections.insert(0, general_section)
            current = general_section

        if line.startswith("※") or normalize_freeform_note_line(line):
            if section_notes_enabled and current is not None:
                current["notes"].append(normalize_freeform_note_line(line) or line)
            continue

        if current["rawText"]:
            current["rawText"] += "\n"
        current["rawText"] += line
        current["items"] = parse_items(
            current["rawText"],
            include_unpriced=True,
            cafeteria_id=cafeteria_id,
        )

    return sections


def parse_section_title(line: str) -> str | None:
    section_line = parse_section_line(line)
    return section_line["title"] if section_line else None


def parse_section_line(line: str) -> dict | None:
    stripped = line.strip()
    angle_match = re.fullmatch(r"<\s*(?P<title>[^<>]+?)\s*>\s*(?P<rest>.*)", stripped)
    if angle_match:
        title = normalize_section_title(angle_match.group("title"))
        rest = angle_match.group("rest").strip()
        price_match = re.fullmatch(r"(?P<price>[0-9,]+)\s*[원웡]", rest)
        return {
            "title": title,
            "price": int(price_match.group("price").replace(",", "")) if price_match else None,
            "content": None if not rest or price_match else rest,
        }

    star_match = re.fullmatch(r"\*\s*(?P<title>[^*]+?)\s*\*", stripped)
    if not star_match:
        return None
    return {
        "title": normalize_section_title(star_match.group("title")),
        "price": None,
        "content": None,
    }


def normalize_section_title(title: str) -> str:
    normalized = re.sub(r"\s+", " ", title).strip()
    if normalized == "+세미뷔페":
        return "세미뷔페"
    if normalized == "메 뉴":
        return "메뉴"
    if normalized == "사 이 드":
        return "사이드"
    return normalized


def logical_lines(text: str) -> list[str]:
    lines = compact_lines(text)
    merged = []
    pending = None

    for line in lines:
        if pending is not None:
            pending += " " + line
            if ">" in line:
                merged.append(pending)
                pending = None
            continue

        if line.startswith("<") and ">" not in line:
            pending = line
        else:
            merged.append(line)

    if pending is not None:
        merged.append(pending)
    return merged


def compact_lines(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if line.strip()]


def parse_notes(text: str, section_notes_enabled: bool = False) -> list[str]:
    notes = []
    current_section = None
    for line in logical_lines(text):
        section_title = parse_section_title(line)
        if section_title:
            current_section = None if section_title in ANGLE_NOTE_TITLES else section_title
            if section_title in ANGLE_NOTE_TITLES:
                notes.append(f"※ {section_title}")
            continue
        if line.startswith("※"):
            if is_structured_time_note(line):
                continue
            if not (section_notes_enabled and current_section):
                notes.append(line)
            continue
        freeform_note = normalize_freeform_note_line(line)
        if freeform_note and not (section_notes_enabled and current_section):
            notes.append(freeform_note)
    return notes


def normalize_freeform_note_line(line: str) -> str | None:
    stripped = line.strip()
    parenthesized = re.fullmatch(r"\(\s*(?P<content>[^()]+?)\s*\)", stripped)
    if parenthesized:
        stripped = parenthesized.group("content").strip()
    compact = re.sub(r"\s+", " ", stripped)
    if re.search(r"break\s*time", compact, re.IGNORECASE):
        return f"※ {compact}"
    return None


def is_structured_time_note(line: str) -> bool:
    normalized = re.sub(r"\s+", "", line)
    return normalized.startswith("※운영시간") or normalized.startswith("※혼잡시간")


def build_meal(
    text: str,
    section_notes_enabled: bool = False,
    cafeteria_id: str | None = None,
    include_section_titles: set[str] | None = None,
    exclude_section_titles: set[str] | None = None,
    keep_time_fields: bool = True,
) -> dict:
    sections = parse_sections(text, section_notes_enabled, cafeteria_id)
    if include_section_titles is not None:
        sections = [section for section in sections if section["title"] in include_section_titles]
    if exclude_section_titles is not None:
        sections = [section for section in sections if section["title"] not in exclude_section_titles]
    sections = merge_sections_by_title(sections)
    return {
        "rawText": text,
        "sections": sections,
        "hours": parse_time_range(text, "운영시간") if keep_time_fields else None,
        "busyHours": parse_time_range(text, "혼잡시간") if keep_time_fields else None,
        "notes": parse_notes(text, section_notes_enabled),
    }


def merge_sections_by_title(sections: list[dict]) -> list[dict]:
    merged = []
    by_title = {}
    for section in sections:
        existing = by_title.get(section["title"])
        if existing is None:
            merged.append(section)
            by_title[section["title"]] = section
            continue
        if section["rawText"]:
            if existing["rawText"]:
                existing["rawText"] += "\n"
            existing["rawText"] += section["rawText"]
        existing["items"].extend(section["items"])
        existing["notes"].extend(section["notes"])
        if existing["price"] is None:
            existing["price"] = section["price"]
    return merged


def slug_for_unknown(name: str) -> str:
    ascii_slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return ascii_slug or f"cafeteria_{abs(hash(name))}"


def build_payload(date: str, source_url: str, rows: list[list[str]]) -> tuple[dict, list[dict], list[dict]]:
    cafeterias = []
    menu_entries = []
    fixed_entries = [build_burgerun_fixed_menu()]

    for row in rows:
        parsed_name = parse_cafeteria_name(row[0])
        cafeteria_id = CAFETERIA_IDS.get(parsed_name.name) or slug_for_unknown(parsed_name.name)

        cafeterias.append(
            {
                "id": cafeteria_id,
                "name": parsed_name.name,
                "phone": parsed_name.phone,
            }
        )

        meals = {
            meal_key: build_meal(
                row[index + 1],
                section_notes_enabled=cafeteria_id == "building_301",
                cafeteria_id=cafeteria_id,
                keep_time_fields=cafeteria_id != "building_301",
            )
            for index, meal_key in enumerate(MEAL_KEYS)
        }
        normalize_daily_section_titles(cafeteria_id, meals)

        if cafeteria_id == "burgerun_burger":
            continue

        if cafeteria_id in FIXED_ONLY_CAFETERIA_IDS:
            normalize_fixed_section_titles(cafeteria_id, meals)
            apply_cafeteria_meal_overrides(cafeteria_id, meals)
            fixed_entries.append(
                {
                    "cafeteriaId": cafeteria_id,
                    "name": parsed_name.name,
                    "meals": meals,
                }
            )
            continue

        fixed_section_titles = FIXED_SECTION_TITLES_BY_CAFETERIA.get(cafeteria_id)
        if fixed_section_titles is not None:
            fixed_meals = {
                meal_key: build_meal(
                    row[index + 1],
                    cafeteria_id=cafeteria_id,
                    include_section_titles=fixed_section_titles,
                )
                for index, meal_key in enumerate(MEAL_KEYS)
            }
            normalize_fixed_section_titles(cafeteria_id, fixed_meals)
            apply_cafeteria_meal_overrides(cafeteria_id, fixed_meals)
            fixed_entries.append(
                {
                    "cafeteriaId": cafeteria_id,
                    "name": parsed_name.name,
                    "meals": fixed_meals,
                }
            )
            meals = {
                meal_key: build_meal(
                    row[index + 1],
                    cafeteria_id=cafeteria_id,
                    exclude_section_titles=fixed_section_titles,
                )
                for index, meal_key in enumerate(MEAL_KEYS)
            }

        filter_daily_notes(cafeteria_id, meals)

        menu_entries.append(
            {
                "cafeteriaId": cafeteria_id,
                "meals": meals,
            }
        )

    payload = {
        "schemaVersion": 1,
        "date": date,
        "updatedAt": datetime.now(KST).isoformat(timespec="seconds"),
        "sourceUrl": source_url,
        "cafeterias": menu_entries,
    }
    return payload, merge_cafeterias(cafeterias), fixed_entries


def extra_dorm_rows(rows: list[list[str]]) -> list[list[str]]:
    filtered = []
    for row in rows:
        parsed_name = parse_cafeteria_name(row[0])
        cafeteria_id = CAFETERIA_IDS.get(parsed_name.name) or slug_for_unknown(parsed_name.name)
        if cafeteria_id in DORM_EXTRA_CAFETERIA_IDS:
            filtered.append(row)
    return filtered


def apply_cafeteria_meal_overrides(cafeteria_id: str, meals: dict[str, dict]) -> None:
    if cafeteria_id == "engineering_snack":
        meals["lunch"]["hours"] = {"start": "11:00", "end": "14:30"}
        meals["dinner"]["hours"] = {"start": "15:30", "end": "18:30"}
        for meal in meals.values():
            meal["notes"] = [note for note in meal["notes"] if "브레이크타임" not in note]
    elif cafeteria_id == "building_220":
        for meal_key, meal in meals.items():
            if meal_key != "dinner":
                meal["notes"] = [note for note in meal["notes"] if "라스트" not in note]


def normalize_fixed_section_titles(cafeteria_id: str, meals: dict[str, dict]) -> None:
    title_overrides = FIXED_SECTION_TITLE_OVERRIDES_BY_CAFETERIA.get(cafeteria_id)
    if not title_overrides:
        return
    for meal in meals.values():
        for section in meal["sections"]:
            section["title"] = title_overrides.get(section["title"], section["title"])
        meal["sections"] = merge_sections_by_title(meal["sections"])


def normalize_daily_section_titles(cafeteria_id: str, meals: dict[str, dict]) -> None:
    title_overrides = DAILY_SECTION_TITLE_OVERRIDES_BY_CAFETERIA.get(cafeteria_id)
    if not title_overrides:
        return
    for meal in meals.values():
        for section in meal["sections"]:
            section["title"] = title_overrides.get(section["title"], section["title"])
        meal["sections"] = merge_sections_by_title(meal["sections"])


def filter_daily_notes(cafeteria_id: str, meals: dict[str, dict]) -> None:
    excluded_terms = DAILY_NOTE_EXCLUDES_BY_CAFETERIA.get(cafeteria_id)
    if not excluded_terms:
        return
    for meal in meals.values():
        meal["notes"] = [
            note for note in meal["notes"]
            if not any(term in note for term in excluded_terms)
        ]


def build_burgerun_fixed_menu() -> dict:
    meal = {
        "rawText": "",
        "sections": [],
        "imagePath": "assets/menu_images/burger.jpeg",
        "hours": {"start": "09:00", "end": "20:00"},
        "busyHours": None,
        "notes": ["※ 라스트오더 19:40"],
    }
    return {
        "cafeteriaId": "burgerun_burger",
        "name": "버거운버거",
        "meals": {meal_key: meal for meal_key in MEAL_KEYS},
    }


def merge_cafeterias(cafeterias: list[dict]) -> list[dict]:
    merged = {item["id"]: item for item in cafeterias}
    for item in STATIC_CAFETERIAS:
        merged[item["id"]] = item
    return list(merged.values())


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", required=True, help="Menu date, e.g. 2026-05-28")
    parser.add_argument("--output-dir", default="data/menus")
    parser.add_argument("--cafeterias-path", default="data/cafeterias.json")
    parser.add_argument("--fixed-menus-path", default="data/fixed_menus.json")
    parser.add_argument("--html-path", help="Use a saved HTML file instead of fetching")
    parser.add_argument("--dorm-html-path", help="Use a saved dorm HTML file instead of fetching")
    args = parser.parse_args()

    if args.html_path:
        html = Path(args.html_path).read_text(encoding="utf-8")
        source_url = f"https://snuco.snu.ac.kr/foodmenu/?date={args.date}&orderby=DESC"
    else:
        html, source_url = fetch_html(args.date)

    rows = parse_table_rows(html)
    if args.dorm_html_path:
        dorm_html = Path(args.dorm_html_path).read_text(encoding="utf-8")
    else:
        dorm_html, _ = fetch_dorm_html(args.date)
    rows.extend(extra_dorm_rows(parse_table_rows(dorm_html)))

    payload, cafeterias, fixed_entries = build_payload(args.date, source_url, rows)

    output_dir = Path(args.output_dir)
    dated_path = output_dir / f"{args.date}.json"
    latest_path = output_dir / "latest.json"
    write_json(dated_path, payload)
    shutil.copyfile(dated_path, latest_path)
    write_json(Path(args.cafeterias_path), cafeterias)
    write_json(Path(args.fixed_menus_path), fixed_entries)

    print(f"wrote {dated_path}")
    print(f"wrote {latest_path}")
    print(f"wrote {args.cafeterias_path}")
    print(f"wrote {args.fixed_menus_path}")
    print(f"parsed {len(cafeterias)} cafeterias")


if __name__ == "__main__":
    main()
