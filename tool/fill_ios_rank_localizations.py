#!/usr/bin/env python3
"""Fill the five pre-existing ranked strings across every shipped iOS locale."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets" / "localization" / "Localizable.xcstrings"

TRANSLATIONS: dict[str, dict[str, str]] = {
    "ranked_ladder": {
        "en": "Ranked ladder",
        "tr": "Dereceli sıralama",
        "de": "Gewertete Rangliste",
        "fr": "Classement compétitif",
        "es": "Clasificación competitiva",
        "pt": "Classificação competitiva",
        "it": "Classifica competitiva",
        "nl": "Competitieve ranglijst",
        "pl": "Ranking rywalizacyjny",
        "ru": "Рейтинговая таблица",
        "uk": "Рейтингова таблиця",
        "ar": "سلم التصنيف",
        "hi": "रैंक्ड लीडरबोर्ड",
        "id": "Peringkat kompetitif",
        "ja": "ランク戦ランキング",
        "ko": "랭크 순위표",
        "zh-Hans": "排位排行榜",
        "zh-Hant": "排位排行榜",
        "th": "อันดับการแข่งขัน",
        "vi": "Bảng xếp hạng cạnh tranh",
        "bn": "র‍্যাঙ্কড লিডারবোর্ড",
        "ur": "رینکڈ لیڈر بورڈ",
    },
    "ranked_progress_title": {
        "en": "Ranked Progress",
        "tr": "Dereceli İlerleme",
        "de": "Gewerteter Fortschritt",
        "fr": "Progression compétitive",
        "es": "Progreso competitivo",
        "pt": "Progresso competitivo",
        "it": "Progressi competitivi",
        "nl": "Competitieve voortgang",
        "pl": "Postęp rankingowy",
        "ru": "Рейтинговый прогресс",
        "uk": "Рейтинговий прогрес",
        "ar": "تقدم التصنيف",
        "hi": "रैंक्ड प्रगति",
        "id": "Progres peringkat",
        "ja": "ランク進捗",
        "ko": "랭크 진행도",
        "zh-Hans": "排位进度",
        "zh-Hant": "排位進度",
        "th": "ความคืบหน้าอันดับ",
        "vi": "Tiến trình xếp hạng",
        "bn": "র‍্যাঙ্কড অগ্রগতি",
        "ur": "رینکڈ پیش رفت",
    },
    "rank_progression": {
        "en": "Rank progression",
        "tr": "Rütbe ilerlemesi",
        "de": "Rangfortschritt",
        "fr": "Progression de rang",
        "es": "Progresión de rango",
        "pt": "Progressão de rank",
        "it": "Progressione grado",
        "nl": "Rangvoortgang",
        "pl": "Postęp rangi",
        "ru": "Прогресс ранга",
        "uk": "Прогрес рангу",
        "ar": "تقدم الرتبة",
        "hi": "रैंक प्रगति",
        "id": "Perkembangan rank",
        "ja": "ランクの進行",
        "ko": "랭크 진행",
        "zh-Hans": "段位进度",
        "zh-Hant": "段位進度",
        "th": "ความคืบหน้าแรงก์",
        "vi": "Tiến trình hạng",
        "bn": "র‍্যাঙ্ক অগ্রগতি",
        "ur": "رینک کی پیش رفت",
    },
    "global_rp_leaderboard": {
        "en": "Global RP leaderboard",
        "tr": "Küresel RP liderlik tablosu",
        "de": "Globale RP-Bestenliste",
        "fr": "Classement RP mondial",
        "es": "Clasificación global de RP",
        "pt": "Ranking global de RP",
        "it": "Classifica RP globale",
        "nl": "Wereldwijde RP-ranglijst",
        "pl": "Globalny ranking RP",
        "ru": "Глобальная таблица RP",
        "uk": "Глобальна таблиця RP",
        "ar": "لوحة صدارة RP العالمية",
        "hi": "वैश्विक RP लीडरबोर्ड",
        "id": "Papan peringkat RP global",
        "ja": "グローバルRPランキング",
        "ko": "글로벌 RP 순위표",
        "zh-Hans": "全球 RP 排行榜",
        "zh-Hant": "全球 RP 排行榜",
        "th": "กระดานผู้นำ RP ทั่วโลก",
        "vi": "BXH RP toàn cầu",
        "bn": "গ্লোবাল RP লিডারবোর্ড",
        "ur": "عالمی RP لیڈر بورڈ",
    },
    "current_elo_summary": {
        "en": "%1d ELO · %2d games · %3dW %4dL",
        "tr": "%1d ELO · %2d oyun · %3dW %4dL",
        "de": "%1d ELO · %2d Spiele · %3dW %4dL",
        "fr": "%1d ELO · %2d parties · %3dW %4dL",
        "es": "%1d ELO · %2d partidas · %3dW %4dL",
        "pt": "%1d ELO · %2d partidas · %3dW %4dL",
        "it": "%1d ELO · %2d partite · %3dW %4dL",
        "nl": "%1d ELO · %2d spellen · %3dW %4dL",
        "pl": "%1d ELO · %2d gier · %3dW %4dL",
        "ru": "%1d ELO · %2d игр · %3dW %4dL",
        "uk": "%1d ELO · %2d ігор · %3dW %4dL",
        "ar": "%1d ELO · %2d مباريات · %3dW %4dL",
        "hi": "%1d ELO · %2d गेम · %3dW %4dL",
        "id": "%1d ELO · %2d game · %3dW %4dL",
        "ja": "%1d ELO · %2dゲーム · %3dW %4dL",
        "ko": "%1d ELO · %2d게임 · %3dW %4dL",
        "zh-Hans": "%1d ELO · %2d 局 · %3dW %4dL",
        "zh-Hant": "%1d ELO · %2d 場 · %3dW %4dL",
        "th": "%1d ELO · %2d เกม · %3dW %4dL",
        "vi": "%1d ELO · %2d trận · %3dW %4dL",
        "bn": "%1d ELO · %2d গেম · %3dW %4dL",
        "ur": "%1d ELO · %2d گیمز · %3dW %4dL",
    },
}


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})

    for key, translations in TRANSLATIONS.items():
        entry = strings.setdefault(key, {})
        localizations = entry.setdefault("localizations", {})
        for locale, value in translations.items():
            localizations[locale] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value,
                }
            }

    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("Filled 5 ranked strings across 22 iOS catalog locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
