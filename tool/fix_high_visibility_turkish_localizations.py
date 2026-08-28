#!/usr/bin/env python3
"""Keep high-visibility competitive/profile copy genuinely Turkish.

The Flutter presentation layer already routes these surfaces through AppStrings,
but Android's native string bridge needs values-tr resources and newly-added iOS
String Catalog keys can otherwise remain English fallback copies. This script
updates both platform localization sources from one curated Turkish dictionary.
"""

from __future__ import annotations

import json
import re
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/localization/Localizable.xcstrings"
ANDROID_TR = ROOT / "android/app/src/main/res/values-tr/strings.xml"

TR: dict[str, str] = {
    # Online matchmaking / ready flow.
    "searching_opponent": "Rakip aranıyor…",
    "finding_opponent_title": "Rakip Bulunuyor",
    "searching_similar_opponents": "Seviyene yakın rakipler aranıyor...",
    "searching_opponent_short": "Aranıyor",
    "opponent_search": "Rakip arama",
    "opponent_search_body": "Rekabet seviyene yakın uygun bir oyuncu arıyoruz. Eşleştirme etkin olduğu sürece bu ekranı açık tut.",
    "matchmaking_info": "Eşleştirme bilgisi",
    "matchmaking_cancelling_search": "Arama iptal ediliyor...",
    "opponent_found": "Rakip bulundu",
    "matchmaking_searching_opponent": "Rakip aranıyor...",
    "matchmaking_looking_near_rank": "Rütbene yakın bir oyuncu aranıyor",
    "matchmaking_leaving_queue": "Eşleştirme kuyruğundan çıkılıyor...",
    "matchmaking_preparing_duel": "Düello hazırlanıyor...",
    "matchmaking_may_take_seconds": "Bu işlem birkaç saniye sürebilir.",
    "matchmaking_tip": "İpucu:",
    "matchmaking_keep_open": "Arama sürerken bu ekranı açık tut.",
    "cancel": "İptal",
    "cancel_search": "Aramayı iptal et",
    "find_opponent": "Rakip bul",
    "match_found": "Eşleşme bulundu",
    "opponent_matched_near_level": "%1s, rekabet seviyene yakın bir rakiple eşleşti.",
    "waiting_for_ranked_opponent": "Dereceli eşleştirme kuyruğundasın. Uygulama birkaç saniyede bir eşleşme kontrolü yapar.",
    "same_difficulty_match": "Yalnızca aynı zorluk seviyesini seçen oyuncularla eşleşirsin.",
    "difficulty_queue": "%1s zorluk kuyruğu",
    "searching_for_opponent_multiline": "Rakip\naranıyor",
    "quick_duel": "Hızlı Düello",
    "quick_duel_body": "Seçtiğin zorluk seviyesinde dereceli bir rakip bul.",
    "ready_question": "Hazır mısın?",
    "ready_when_opponent_ready": "Her iki oyuncu da hazır olduğunda oyun başlar.",
    "waiting_opponent_ready": "Rakibin bekleniyor...",
    "match_ready_prompt": "Hazır olduğunda hazır düğmesine dokun.",
    "you_ready_waiting_opponent": "Hazırsın. Rakibin bekleniyor.",
    "opponent_ready_waiting_you": "Rakibin hazır. Seni bekliyor.",
    "everyone_ready_starting": "Herkes hazır. Oyun başlıyor...",
    "get_ready": "Hazırlan",
    "connecting_players": "Oyuncular bağlanıyor",
    "opponent_connecting": "Rakip bağlanıyor",
    "opponent_opening_game": "Rakip oyunu açıyor",
    "opponent_ready": "Rakip hazır",

    # Profile customization.
    "profile_customization": "Profil özelleştirme",
    "refresh_profile": "Profili yenile",
    "avatars": "Avatarlar",
    "frames": "Çerçeveler",
    "badges": "Rozetler",
    "titles": "Unvanlar",
    "country": "Ülke",
    "country_flag": "Ülke bayrağı",
    "country_flag_info": "Ülke bayrağın, istersen oyuncu adının önünde gösterilir.",
    "profile_reconnecting_preview": "Çevrimiçi profile yeniden bağlanılıyor. Tüm profil seçeneklerini önizlemeye devam edebilirsin.",
    "profile_server_unavailable_preview": "Profil sunucusuna ulaşılamıyor. Yeniden bağlanana kadar önizleme yalnızca bu cihazda kalır.",
    "profile_settings_saved": "Profil ayarları kaydedildi.",
    "profile_save_ready_info": "Avatarlar yalnızca uygulamadaki avatar koleksiyonundan seçilir. Rütbe kozmetikleri oynayarak kazanılır.",
    "profile_preview_reconnect": "Önizleme modu · değişiklikleri kaydetmek için yeniden bağlan.",
    "preview": "Önizleme",
    "saving": "Kaydediliyor",
    "sudoku_player": "Sudoku Oyuncusu",
    "avatar_number": "Avatar %1s",
    "lifetime_rank_coins": "%1d toplam Rütbe Coini",
    "rank_frames_info": "Her kademenin kendine ait bir çerçevesi vardır. Rütbe ödülleri yalnızca ilk kez kazanılır; düşüp yeniden yükselerek tekrar toplanamaz.",
    "auto_current_rank": "Otomatik · mevcut rütbe",
    "frame_follows_current_rank": "Çerçeve mevcut rütbeni otomatik olarak takip eder.",
    "permanently_unlocked_rp": "%1d RP'de kalıcı olarak açıldı.",
    "unlock_reaching_rp": "%1d RP'ye ulaşınca açılır.",
    "three_achievement_slots": "3 başarım rozeti yuvası",
    "achievement_badges_info": "Açtığın başarım rozetlerinden en fazla 3 tanesini rütbe çerçevene ekleyebilirsin.",
    "max_three_frame_badges": "Çerçevene en fazla 3 rozet takabilirsin.",
    "prestige_titles": "Prestij unvanları",
    "prestige_titles_info": "Master ve Master I unvanları kalıcı hesap ödülleridir. Gerçek mevcut rütben ayrıca gösterilmeye devam eder.",
    "no_title": "Unvan yok",
    "choose_country": "Ülke seç",
    "no_country_flag_until_chosen": "Bir ülke seçene kadar ülke bayrağı gösterilmez.",
    "flag_before_player_name": "Bayrağın oyuncu adının önünde gösterilebilir.",
    "clear_country": "Ülkeyi temizle",
    "show_flag_ranked_ladder": "Dereceli sıralamada bayrağı göster",
    "choose_country_first": "Önce bir ülke seç.",
    "flag_only_before_name": "Adının önünde yalnızca bayrak görünür; ülke kısaltması gösterilmez.",
    "country_saved_flag_hidden": "Ülken kayıtlı kalır ancak bayrak sıralamada gizlenir.",
    "search_country": "Ülke ara",
    "no_country_found": "Ülke bulunamadı.",
    "rarity_common": "YAYGIN",
    "rarity_rare": "NADİR",
    "rarity_epic": "EPİK",
    "rarity_legendary": "EFSANEVİ",
    "profile_style": "Profil stili",
    "profile_style_subtitle": "Avatar, rütbe çerçevesi, rozetler ve ülke",
    "profile_avatar_count": "%1d avatar",
    "profile_badge_policy": "Rütbe çerçeveleri ve başarım rozetleri satın alınmaz, kazanılır. Çerçevene en fazla 3 kazanılmış rozet takabilirsin. Şu anda %1d/3 rozet yuvası kullanılıyor.",
    "quick_emotes_profile_subtitle": "8 hızlı düello ifadeni seç ve sırala",
    "quick_emote_slots_count": "%1d yuva",
    "retry": "Tekrar dene",

    # Achievement badges shown inside Profile Customization.
    "rank_decoration_giant_slayer_title": "Dev Avcısı",
    "rank_decoration_giant_slayer_body": "Senden en az 251 MMR yüksek dereceli bir rakibi yen.",
    "rank_decoration_perfect_ranked_win_title": "Kusursuz Düello",
    "rank_decoration_perfect_ranked_win_body": "Hata veya zaman aşımı yapmadan dereceli bir düello kazan.",
    "rank_decoration_perfect_ranked_wins_10_title": "Kusursuz Onlu",
    "rank_decoration_perfect_ranked_wins_10_body": "Hata veya zaman aşımı yapmadan 10 dereceli düello kazan.",
    "rank_decoration_rank_gold_title": "Altın Rakip",
    "rank_decoration_rank_gold_body": "İlk kez Gold III rütbesine ulaş.",
    "rank_decoration_rank_master_title": "Master Rakip",
    "rank_decoration_rank_master_body": "İlk kez Master III rütbesine ulaş.",
    "rank_decoration_rank_master_i_title": "Master I",
    "rank_decoration_rank_master_i_body": "İlk kez Master I rütbesine ulaş.",
    "rank_decoration_rank_platinum_title": "Platinum Rakip",
    "rank_decoration_rank_platinum_body": "İlk kez Platinum III rütbesine ulaş.",
    "rank_decoration_rank_silver_title": "Gümüş Rakip",
    "rank_decoration_rank_silver_body": "İlk kez Silver III rütbesine ulaş.",
    "rank_decoration_ranked_veteran_100_title": "Dereceli Veteran",
    "rank_decoration_ranked_veteran_100_body": "100 dereceli düello tamamla.",
    "rank_decoration_ranked_veteran_500_title": "Elit Veteran",
    "rank_decoration_ranked_veteran_500_body": "500 dereceli düello tamamla.",
    "rank_decoration_ranked_veteran_1000_title": "Efsanevi Veteran",
    "rank_decoration_ranked_veteran_1000_body": "1000 dereceli düello tamamla.",
    "rank_decoration_undefeated_10_title": "10 Maç Yenilmez",
    "rank_decoration_undefeated_10_body": "Arka arkaya 10 dereceli düelloyu yenilmeden tamamla.",
    "rank_decoration_undefeated_25_title": "25 Maç Yenilmez",
    "rank_decoration_undefeated_25_body": "Arka arkaya 25 dereceli düelloyu yenilmeden tamamla.",
    "rank_decoration_undefeated_50_title": "50 Maç Yenilmez",
    "rank_decoration_undefeated_50_body": "Arka arkaya 50 dereceli düelloyu yenilmeden tamamla.",
    "rank_decoration_win_streak_5_title": "5 Galibiyet Serisi",
    "rank_decoration_win_streak_5_body": "Arka arkaya 5 dereceli düello kazan.",
    "rank_decoration_win_streak_10_title": "10 Galibiyet Serisi",
    "rank_decoration_win_streak_10_body": "Arka arkaya 10 dereceli düello kazan.",
    "rank_decoration_win_streak_25_title": "25 Galibiyet Serisi",
    "rank_decoration_win_streak_25_body": "Arka arkaya 25 dereceli düello kazan.",

    # Emote loadout and collection.
    "emotes": "İfadeler",
    "restore_default_emotes": "Varsayılan ifadeleri geri yükle",
    "default_emotes_restored": "Varsayılan ifadeler geri yüklendi.",
    "emote_selection_load_failed": "İfade seçimi yüklenemedi.",
    "emote_change_failed": "Bu ifade değiştirilemedi.",
    "quick_emotes_limit": "En fazla 8 hızlı ifade takabilirsin. Önce birini kaldır.",
    "keep_one_quick_emote": "En az bir hızlı ifade takılı kalmalı.",
    "your_loadout": "DİZİLİMİN",
    "quick_emotes": "Hızlı İfadeler",
    "quick_emotes_reorder_body": "Düello sırasında ifadeleri açtığında aynı 4 × 2 düzen kullanılır. Sıralamak için basılı tutup sürükle.",
    "collection": "KOLEKSİYON",
    "choose_reactions": "Tepkilerini seç",
    "choose_reactions_body": "Düelloda hızlıca kullanmak istediğin ifadeleri seç.",
    "empty_quick_emote_slot": "Boş hızlı ifade yuvası %1d",
    "quick_emote_slot_label": "%1s, hızlı ifade yuvası %2d",
    "all": "Tümü",
    "reactions": "Tepkiler",
    "taunts": "Kışkırtmalar",
    "status": "Durum",
    "emote_smile": "Gülümse",
    "emote_laugh": "Kahkaha",
    "emote_smug": "Kendinden emin",
    "emote_bored": "Sıkılmış",
    "emote_fire": "Ateş",
    "emote_crown": "Taç",
    "emote_shocked": "Şaşkın",
    "emote_respect": "Saygı",
    "emote_angry": "Kızgın",
    "emote_clap": "Yavaş Alkış",
    "emote_facepalm": "Yüzünü Kapatma",
    "emote_eye_roll": "Göz Devirme",
    "emote_shush": "Şşşt",
    "emote_salty_cry": "Ağlama",
    "emote_love": "Sevgi",
    "emote_plotting": "Plan Yapıyor",
    "emote_dizzy": "Sersem",
    "emote_victory": "Zafer",
    "emote_gg": "GG",
    "emote_ez": "EZ",
    "emote_noob": "NOOB",
    "emote_oops": "HOPPALA",
    "emote_rekt": "REKT",
    "emote_bruh": "BRUH",
    "emote_one_v_one": "1V1",
    "emote_clutch": "CLUTCH",
    "emote_afk": "AFK",
    "emote_lag": "LAG",

    # Visible RP leaderboard / rank progression.
    "ranked_ladder": "Dereceli sıralama",
    "ranked_progress_title": "Dereceli İlerleme",
    "rank_progression": "Rütbe ilerlemesi",
    "global_rp_leaderboard": "Global RP sıralaması",
    "visible_rp_rank_info": "Görünen RP, gösterilen rütbeni belirler. Eşleştirme beceri puanı gizli kalır.",
    "global_upper": "GLOBAL",
    "top_rank": "En üst rütbe",
    "rp_to_rank": "%2s için %1d RP",
    "rp_above_master_i": "Master I üzerinde %1d RP",
    "rp_progress_fraction": "%1d/%2d RP",
    "leaderboard_server_unavailable": "Liderlik tablosu sunucusuna ulaşılamıyor.",
    "no_ranked_players_yet": "Henüz dereceli oyuncu yok.",
    "leaderboard_offline_body": "Mevcut rütben cihazda görünmeye devam eder. Sunucu yeniden bağlandıktan sonra aşağı çek veya yenile düğmesine dokun.",
    "leaderboard_empty_ranked_body": "RP sıralamasına girmek için bir dereceli düello tamamla.",
    "ranked_top_division_body": "En üst kademedesin. En yüksek RP değerini ve sıralamadaki yerini geliştirmek için dereceli düellolara devam et.",
    "ranked_next_division_body": "%2s için %1d RP kaldı. Dereceli düellolar görünen RP değerini değiştirir ve rekabetçi kademeni belirler.",
    "rank_points": "Rütbe Puanı",
    "rank_points_division_progress": "Rütbe Puanı ve kademe ilerlemesi",
    "rank_name_label": "%1s rütbesi",
}


def _android_value(value: str) -> str:
    # Android resources use positional printf markers; Flutter's formatter accepts
    # these unchanged through the native bridge.
    value = re.sub(r"%(\d+)([sd])", r"%\1$\2", value)
    value = value.replace("'", "\\'")
    return escape(value, quote=False)


def update_catalog() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise SystemExit("String Catalog has no 'strings' dictionary")

    missing: list[str] = []
    for key, value in TR.items():
        definition = strings.get(key)
        if not isinstance(definition, dict):
            missing.append(key)
            continue
        unit = (
            definition.setdefault("localizations", {})
            .setdefault("tr", {})
            .setdefault("stringUnit", {})
        )
        unit["state"] = "translated"
        unit["value"] = value

    if missing:
        raise SystemExit("Catalog is missing requested keys: " + ", ".join(missing))

    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def update_android() -> None:
    ANDROID_TR.parent.mkdir(parents=True, exist_ok=True)
    lines = ["<?xml version='1.0' encoding='utf-8'?>", "<resources>"]
    for key in sorted(TR):
        value = _android_value(TR[key])
        formatted = ' formatted="false"' if "%" in TR[key] else ""
        lines.append(f'    <string name="{key}"{formatted}>{value}</string>')
    lines.append("</resources>")
    ANDROID_TR.write_text("\n".join(lines) + "\n", encoding="utf-8")


def verify() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    failures: list[str] = []
    for key, expected in TR.items():
        actual = (
            strings.get(key, {})
            .get("localizations", {})
            .get("tr", {})
            .get("stringUnit", {})
            .get("value")
        )
        if actual != expected:
            failures.append(f"iOS catalog {key}: {actual!r} != {expected!r}")

    android = ANDROID_TR.read_text(encoding="utf-8")
    for key in TR:
        if f'name="{key}"' not in android:
            failures.append(f"Android values-tr missing {key}")

    if failures:
        raise SystemExit("High-visibility Turkish localization verification failed:\n" + "\n".join(failures))
    print(f"Verified {len(TR)} high-visibility Turkish strings for iOS and Android.")


def main() -> None:
    update_catalog()
    update_android()
    verify()


if __name__ == "__main__":
    main()
