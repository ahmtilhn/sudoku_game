#!/usr/bin/env python3
"""Repair real translations for every supported iOS String Catalog locale.

The catalog historically contained many locale entries whose values were exact
copies of English. That satisfies presence/coverage checks but still renders an
English UI. This tool translates only missing/English-copy values, preserves
existing curated translations, protects placeholders/brands, and verifies the
result locale by locale.

Translation model: facebook/m2m100_418M (MIT license, 100 languages).
Traditional Chinese is generated from the Chinese translation and converted
with OpenCC (Apache-2.0).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Iterable

CATALOG = Path("assets/localization/Localizable.xcstrings")

LOCALE_TO_M2M = {
    "tr": "tr",
    "de": "de",
    "fr": "fr",
    "es": "es",
    "pt": "pt",
    "it": "it",
    "nl": "nl",
    "pl": "pl",
    "ru": "ru",
    "uk": "uk",
    "ar": "ar",
    "hi": "hi",
    "id": "id",
    "ja": "ja",
    "ko": "ko",
    "zh-Hans": "zh",
    "zh-Hant": "zh",
    "th": "th",
    "vi": "vi",
    "bn": "bn",
    "ur": "ur",
}

# Keep placeholders and product/platform terminology byte-for-byte stable.
TOKEN_RE = re.compile(
    r"(%(?:\d+\$?)?[sd]|%%|\\n|Sudoku Duel|Game Center|Play Games|"
    r"Google Play|ELO|MMR|RP|Coin|9x9|16x16|4x4)",
    re.IGNORECASE,
)
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$?)?[sd]|%%")
LETTER_RE = re.compile(r"[A-Za-z]")

# High-visibility navigation copy is curated so the first screen is an obvious
# proof that the selected locale is active. Remaining strings use M2M100.
CURATED = {
    "tr": {
        "home": "Ana Sayfa",
        "play": "Oyna",
        "compete": "Rekabet",
        "profile": "Profil",
        "settings": "Ayarlar",
        "friends": "Arkadaşlar",
        "shop": "Mağaza",
        "career": "Kariyer",
        "leaderboard": "Liderlik Tablosu",
        "achievements": "Başarımlar",
    },
    "de": {
        "home": "Startseite",
        "play": "Spielen",
        "compete": "Wettkampf",
        "profile": "Profil",
        "settings": "Einstellungen",
        "friends": "Freunde",
        "shop": "Shop",
        "career": "Karriere",
        "leaderboard": "Bestenliste",
        "achievements": "Erfolge",
    },
    "fr": {
        "home": "Accueil",
        "play": "Jouer",
        "compete": "Compétition",
        "profile": "Profil",
        "settings": "Réglages",
        "friends": "Amis",
        "shop": "Boutique",
        "career": "Carrière",
        "leaderboard": "Classement",
        "achievements": "Succès",
    },
    "es": {
        "home": "Inicio",
        "play": "Jugar",
        "compete": "Competir",
        "profile": "Perfil",
        "settings": "Ajustes",
        "friends": "Amigos",
        "shop": "Tienda",
        "career": "Carrera",
        "leaderboard": "Clasificación",
        "achievements": "Logros",
    },
    "pt": {
        "home": "Início",
        "play": "Jogar",
        "compete": "Competir",
        "profile": "Perfil",
        "settings": "Definições",
        "friends": "Amigos",
        "shop": "Loja",
        "career": "Carreira",
        "leaderboard": "Classificação",
        "achievements": "Conquistas",
    },
    "it": {
        "home": "Home",
        "play": "Gioca",
        "compete": "Competi",
        "profile": "Profilo",
        "settings": "Impostazioni",
        "friends": "Amici",
        "shop": "Negozio",
        "career": "Carriera",
        "leaderboard": "Classifica",
        "achievements": "Obiettivi",
    },
    "nl": {
        "home": "Start",
        "play": "Spelen",
        "compete": "Strijd",
        "profile": "Profiel",
        "settings": "Instellingen",
        "friends": "Vrienden",
        "shop": "Winkel",
        "career": "Carrière",
        "leaderboard": "Ranglijst",
        "achievements": "Prestaties",
    },
    "pl": {
        "home": "Strona główna",
        "play": "Graj",
        "compete": "Rywalizuj",
        "profile": "Profil",
        "settings": "Ustawienia",
        "friends": "Znajomi",
        "shop": "Sklep",
        "career": "Kariera",
        "leaderboard": "Ranking",
        "achievements": "Osiągnięcia",
    },
    "ru": {
        "home": "Главная",
        "play": "Играть",
        "compete": "Соревнование",
        "profile": "Профиль",
        "settings": "Настройки",
        "friends": "Друзья",
        "shop": "Магазин",
        "career": "Карьера",
        "leaderboard": "Таблица лидеров",
        "achievements": "Достижения",
    },
    "uk": {
        "home": "Головна",
        "play": "Грати",
        "compete": "Змагання",
        "profile": "Профіль",
        "settings": "Налаштування",
        "friends": "Друзі",
        "shop": "Магазин",
        "career": "Кар’єра",
        "leaderboard": "Таблиця лідерів",
        "achievements": "Досягнення",
    },
    "ar": {
        "home": "الرئيسية",
        "play": "العب",
        "compete": "تنافس",
        "profile": "الملف الشخصي",
        "settings": "الإعدادات",
        "friends": "الأصدقاء",
        "shop": "المتجر",
        "career": "المسيرة",
        "leaderboard": "لوحة الصدارة",
        "achievements": "الإنجازات",
    },
    "hi": {
        "home": "होम",
        "play": "खेलें",
        "compete": "प्रतिस्पर्धा",
        "profile": "प्रोफ़ाइल",
        "settings": "सेटिंग्स",
        "friends": "दोस्त",
        "shop": "दुकान",
        "career": "करियर",
        "leaderboard": "लीडरबोर्ड",
        "achievements": "उपलब्धियाँ",
    },
    "id": {
        "home": "Beranda",
        "play": "Main",
        "compete": "Bersaing",
        "profile": "Profil",
        "settings": "Pengaturan",
        "friends": "Teman",
        "shop": "Toko",
        "career": "Karier",
        "leaderboard": "Papan Peringkat",
        "achievements": "Pencapaian",
    },
    "ja": {
        "home": "ホーム",
        "play": "プレイ",
        "compete": "対戦",
        "profile": "プロフィール",
        "settings": "設定",
        "friends": "フレンド",
        "shop": "ショップ",
        "career": "キャリア",
        "leaderboard": "ランキング",
        "achievements": "実績",
    },
    "ko": {
        "home": "홈",
        "play": "플레이",
        "compete": "경쟁",
        "profile": "프로필",
        "settings": "설정",
        "friends": "친구",
        "shop": "상점",
        "career": "커리어",
        "leaderboard": "순위표",
        "achievements": "업적",
    },
    "zh-Hans": {
        "home": "首页",
        "play": "开始游戏",
        "compete": "竞技",
        "profile": "个人资料",
        "settings": "设置",
        "friends": "好友",
        "shop": "商店",
        "career": "生涯",
        "leaderboard": "排行榜",
        "achievements": "成就",
    },
    "zh-Hant": {
        "home": "首頁",
        "play": "開始遊戲",
        "compete": "競技",
        "profile": "個人資料",
        "settings": "設定",
        "friends": "好友",
        "shop": "商店",
        "career": "生涯",
        "leaderboard": "排行榜",
        "achievements": "成就",
    },
    "th": {
        "home": "หน้าหลัก",
        "play": "เล่น",
        "compete": "แข่งขัน",
        "profile": "โปรไฟล์",
        "settings": "การตั้งค่า",
        "friends": "เพื่อน",
        "shop": "ร้านค้า",
        "career": "เส้นทางอาชีพ",
        "leaderboard": "กระดานผู้นำ",
        "achievements": "ความสำเร็จ",
    },
    "vi": {
        "home": "Trang chủ",
        "play": "Chơi",
        "compete": "Thi đấu",
        "profile": "Hồ sơ",
        "settings": "Cài đặt",
        "friends": "Bạn bè",
        "shop": "Cửa hàng",
        "career": "Sự nghiệp",
        "leaderboard": "Bảng xếp hạng",
        "achievements": "Thành tích",
    },
    "bn": {
        "home": "হোম",
        "play": "খেলুন",
        "compete": "প্রতিযোগিতা",
        "profile": "প্রোফাইল",
        "settings": "সেটিংস",
        "friends": "বন্ধুরা",
        "shop": "দোকান",
        "career": "ক্যারিয়ার",
        "leaderboard": "লিডারবোর্ড",
        "achievements": "অর্জন",
    },
    "ur": {
        "home": "ہوم",
        "play": "کھیلیں",
        "compete": "مقابلہ",
        "profile": "پروفائل",
        "settings": "ترتیبات",
        "friends": "دوست",
        "shop": "دکان",
        "career": "کیریئر",
        "leaderboard": "لیڈر بورڈ",
        "achievements": "کامیابیاں",
    },
}


def value_for(definition: dict, locale: str) -> str:
    value = (
        definition.get("localizations", {})
        .get(locale, {})
        .get("stringUnit", {})
        .get("value", "")
    )
    return value if isinstance(value, str) else ""


def set_value(definition: dict, locale: str, value: str) -> None:
    unit = (
        definition.setdefault("localizations", {})
        .setdefault(locale, {})
        .setdefault("stringUnit", {})
    )
    unit["state"] = "translated"
    unit["value"] = value


def placeholders(value: str) -> list[str]:
    return [token.replace("$", "") for token in PLACEHOLDER_RE.findall(value)]


def protected_parts(source: str) -> list[str]:
    return TOKEN_RE.split(source)


def has_translatable_text(source: str) -> bool:
    for part in protected_parts(source):
        if part and not TOKEN_RE.fullmatch(part) and LETTER_RE.search(part):
            return True
    return False


def rebuild_plan(source: str, segment_store: list[str]) -> list[tuple[str, object]]:
    plan: list[tuple[str, object]] = []
    for part in protected_parts(source):
        if not part:
            continue
        if TOKEN_RE.fullmatch(part) or not LETTER_RE.search(part):
            plan.append(("literal", part))
        else:
            index = len(segment_store)
            segment_store.append(part)
            plan.append(("segment", index))
    return plan


def audit(strings: dict) -> dict[str, tuple[int, int, int]]:
    report: dict[str, tuple[int, int, int]] = {}
    for locale in LOCALE_TO_M2M:
        missing = 0
        english_copy = 0
        translatable_copy = 0
        for definition in strings.values():
            en = value_for(definition, "en")
            target = value_for(definition, locale)
            if not target.strip():
                missing += 1
            elif target == en:
                english_copy += 1
                if has_translatable_text(en):
                    translatable_copy += 1
        report[locale] = (missing, english_copy, translatable_copy)
    return report


def print_audit(title: str, report: dict[str, tuple[int, int, int]]) -> None:
    print(title)
    for locale, (missing, english_copy, translatable_copy) in report.items():
        print(
            f"  {locale:7s} missing={missing:3d} "
            f"english_copy={english_copy:3d} translatable_copy={translatable_copy:3d}"
        )


def translate(strings: dict) -> None:
    import torch
    from opencc import OpenCC
    from transformers import M2M100ForConditionalGeneration, M2M100Tokenizer

    model_name = "facebook/m2m100_418M"
    print(f"Loading multilingual translation model: {model_name}")
    tokenizer = M2M100Tokenizer.from_pretrained(model_name)
    tokenizer.src_lang = "en"
    model = M2M100ForConditionalGeneration.from_pretrained(model_name)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model.to(device)
    model.eval()
    print(f"Translation device: {device}")
    s2t = OpenCC("s2twp")

    for locale, target_lang in LOCALE_TO_M2M.items():
        # Apply curated visible navigation first, even when an old translation exists.
        for key, curated_value in CURATED[locale].items():
            definition = strings.get(key)
            if isinstance(definition, dict):
                set_value(definition, locale, curated_value)

        pending: list[tuple[str, str]] = []
        for key, definition in strings.items():
            if not isinstance(definition, dict):
                continue
            if key in CURATED[locale]:
                continue
            en = value_for(definition, "en")
            target = value_for(definition, locale)
            if not en.strip():
                continue
            if (not target.strip() or target == en) and has_translatable_text(en):
                pending.append((key, en))

        if not pending:
            print(f"{locale}: no English-copy translations need repair")
            continue

        segments: list[str] = []
        plans: list[tuple[str, str, list[tuple[str, object]]]] = []
        for key, source in pending:
            plans.append((key, source, rebuild_plan(source, segments)))

        translated_segments = [""] * len(segments)
        batch_size = 24
        tokenizer.src_lang = "en"
        forced_bos = tokenizer.get_lang_id(target_lang)
        for start in range(0, len(segments), batch_size):
            batch = segments[start : start + batch_size]
            encoded = tokenizer(
                batch,
                return_tensors="pt",
                padding=True,
                truncation=True,
                max_length=256,
            ).to(device)
            with torch.inference_mode():
                generated = model.generate(
                    **encoded,
                    forced_bos_token_id=forced_bos,
                    max_new_tokens=256,
                    num_beams=4,
                    early_stopping=True,
                )
            decoded = tokenizer.batch_decode(generated, skip_special_tokens=True)
            translated_segments[start : start + len(decoded)] = decoded
            print(
                f"{locale}: translated segments "
                f"{min(start + batch_size, len(segments))}/{len(segments)}"
            )

        changed = 0
        for key, source, plan in plans:
            pieces: list[str] = []
            for kind, payload in plan:
                if kind == "literal":
                    pieces.append(str(payload))
                else:
                    pieces.append(translated_segments[int(payload)])
            translated = "".join(pieces).strip()
            if locale == "zh-Hant":
                translated = s2t.convert(translated)
            if not translated:
                raise SystemExit(f"Empty {locale} translation generated for {key}")
            if placeholders(source) != placeholders(translated):
                raise SystemExit(
                    f"Placeholder mismatch {locale}:{key}: "
                    f"{source!r} -> {translated!r}"
                )
            set_value(strings[key], locale, translated)
            changed += 1
        print(f"{locale}: repaired {changed} catalog entries")


def verify(strings: dict) -> None:
    failures: list[str] = []
    total = len(strings)
    for locale in LOCALE_TO_M2M:
        non_english = 0
        translatable = 0
        for key, definition in strings.items():
            if not isinstance(definition, dict):
                continue
            en = value_for(definition, "en")
            target = value_for(definition, locale)
            if not target.strip():
                failures.append(f"{locale}:{key}: missing/empty")
                continue
            if placeholders(en) != placeholders(target):
                failures.append(f"{locale}:{key}: placeholder mismatch")
            if has_translatable_text(en):
                translatable += 1
                if target != en:
                    non_english += 1

        # A locale full of English copies is the exact regression this tool prevents.
        # Legitimately identical short words are allowed, but the overwhelming
        # majority of translatable UI copy must differ from English.
        ratio = non_english / max(translatable, 1)
        print(
            f"{locale}: localized {non_english}/{translatable} "
            f"translatable entries ({ratio:.1%}); total keys={total}"
        )
        if ratio < 0.80:
            failures.append(
                f"{locale}: only {ratio:.1%} of translatable entries differ from English"
            )

        for key, expected in CURATED[locale].items():
            definition = strings.get(key)
            if not isinstance(definition, dict):
                # Curated copy is optional metadata. Removed app keys are ignored here.
                continue
            actual = value_for(definition, locale)
            if actual != expected:
                failures.append(
                    f"{locale}:{key}: expected curated {expected!r}, got {actual!r}"
                )

    if failures:
        raise SystemExit("iOS catalog verification failed:\n" + "\n".join(failures[:100]))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise SystemExit("String Catalog has no 'strings' dictionary")

    print_audit("Before repair:", audit(strings))
    if not args.verify_only:
        translate(strings)
        CATALOG.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print_audit("After repair:", audit(strings))
    verify(strings)


if __name__ == "__main__":
    main()
