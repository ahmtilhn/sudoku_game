#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "set"
require "uri"

class AppStoreConnect
  API_ROOT = "https://api.appstoreconnect.apple.com"

  def initialize
    @issuer_id = required_env("ASC_ISSUER_ID")
    @key_id = required_env("ASC_KEY_ID")
    @key_path = required_env("ASC_KEY_FILEPATH")
    abort("App Store Connect key not found: #{@key_path}") unless File.exist?(@key_path)

    @token = create_token
  end

  def get(path)
    request(Net::HTTP::Get, path)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body)
  end

  def patch(path, body)
    request(Net::HTTP::Patch, path, body)
  end

  def paged(path)
    items = []
    next_path = path
    while next_path
      body = get(next_path)
      items.concat(body.fetch("data", []))
      next_link = body.dig("links", "next")
      next_path = next_link ? URI(next_link).request_uri : nil
    end
    items
  end

  private

  def required_env(name)
    value = ENV[name].to_s.strip
    abort("Set #{name}.") if value.empty?
    value
  end

  def create_token
    key = OpenSSL::PKey.read(File.read(@key_path))
    now = Time.now.to_i
    encode = ->(value) { Base64.urlsafe_encode64(value.to_json, padding: false) }
    unsigned = [
      encode.call({ alg: "ES256", kid: @key_id, typ: "JWT" }),
      encode.call({ iss: @issuer_id, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })
    ].join(".")

    der_signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(unsigned))
    asn1 = OpenSSL::ASN1.decode(der_signature)
    r = asn1.value[0].value.to_s(2).rjust(32, "\0")[-32, 32]
    s = asn1.value[1].value.to_s(2).rjust(32, "\0")[-32, 32]
    "#{unsigned}.#{Base64.urlsafe_encode64(r + s, padding: false)}"
  end

  def request(klass, path, body = nil)
    uri = URI("#{API_ROOT}#{path}")
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{@token}"
    req["Content-Type"] = "application/json" if body
    req.body = JSON.generate(body) if body

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    parsed = begin
      res.body.to_s.empty? ? {} : JSON.parse(res.body)
    rescue JSON::ParserError
      { "raw" => res.body }
    end
    return parsed if res.code.to_i.between?(200, 299)

    errors = parsed.fetch("errors", []).map do |error|
      [error["status"], error["code"], error["title"], error["detail"]].compact.join(" | ")
    end
    raise "#{req.method} #{path} failed (#{res.code}): #{errors.empty? ? parsed.inspect : errors.join("; ")}"
  end
end

APP_ID = ENV.fetch("ASC_APP_ID", "6795243950")
APP_BUNDLE_ID = ENV.fetch("ASC_APP_BUNDLE_ID", "com.devovia.sudokuduel")
APP_NAME = ENV.fetch("ASC_APP_NAME", "Sudoku Duel - Online")
APP_VERSION = ENV.fetch("ASC_APP_VERSION", "1.0")
SUPPORT_URL = ENV["ASC_SUPPORT_URL"].to_s.strip
PRIVACY_URL = ENV["ASC_PRIVACY_URL"].to_s.strip
CONTACT_PHONE = ENV["ASC_CONTACT_PHONE"].to_s.strip
PRICE_TERRITORY = ENV.fetch("ASC_PRICE_TERRITORY", "NLD")
IAP_REVIEW_SCREENSHOT = ENV["ASC_IAP_REVIEW_SCREENSHOT"].to_s.strip
TEST_GROUP_NAME = ENV.fetch("ASC_TEST_GROUP_NAME", "Sudoku Duel Testers")
TESTER_EMAILS = ENV.fetch(
  "ASC_TESTER_EMAILS",
  "salihaebrarilhan@gmail.com,ilhanahmet246@gmail.com"
).split(",").map(&:strip).reject(&:empty?)

PRODUCTS = [
  ["coins_100", "100 Coins", "CONSUMABLE", "100 virtual Coins. No cash value.", "0.99"],
  ["coins_500", "500 Coins", "CONSUMABLE", "500 virtual Coins. No cash value.", "3.99"],
  ["coins_1000", "1,000 Coins", "CONSUMABLE", "1,000 virtual Coins. No cash value.", "6.99"],
  ["coins_5000", "5,000 Coins", "CONSUMABLE", "5,000 virtual Coins. No cash value.", "24.99"],
  ["coins_10000", "10,000 Coins", "CONSUMABLE", "10,000 virtual Coins. No cash value.", "39.99"],
  ["coins_50000", "50,000 Coins", "CONSUMABLE", "50,000 virtual Coins. No cash value.", "149.99"],
  ["coins_100000", "100,000 Coins", "CONSUMABLE", "100,000 virtual Coins. No cash value.", "249.99"],
  ["sudoku_duel_no_ads", "Remove Ads", "NON_CONSUMABLE", "Removes optional reward ad offers.", "4.99"]
].map do |product_id, name, type, description, eur_price|
  {
    product_id: product_id,
    name: name,
    type: type,
    description: description,
    eur_price: eur_price
  }
end

LEADERBOARDS = [
  ["global", "Highest Global ELO", "Peak ranked ELO across all Sudoku Duel matches."],
  ["beginner", "Highest Beginner ELO", "Peak Beginner difficulty ranked ELO."],
  ["easy", "Highest Easy ELO", "Peak Easy difficulty ranked ELO."],
  ["medium", "Highest Medium ELO", "Peak Medium difficulty ranked ELO."],
  ["hard", "Highest Hard ELO", "Peak Hard difficulty ranked ELO."],
  ["expert", "Highest Expert ELO", "Peak Expert difficulty ranked ELO."]
].map do |key, name, description|
  {
    key: key,
    vendor_id: "#{APP_BUNDLE_ID}.leaderboard.#{key}_peak_elo",
    name: name,
    description: description
  }
end

ACHIEVEMENT = {
  vendor_id: "#{APP_BUNDLE_ID}.achievement.first_win",
  reference_name: "First Online Win",
  name: "First Online Win",
  before: "Win your first ranked online Sudoku Duel match.",
  after: "Won the first ranked online Sudoku Duel match.",
  points: 10
}

def relationship(type, id)
  { data: { type: type, id: id } }
end

def create_or_update_app_metadata(asc)
  app_infos = asc.get("/v1/apps/#{APP_ID}/appInfos?include=appInfoLocalizations,primaryCategory,secondaryCategory&limit=10")
  app_info = app_infos.fetch("data").first
  raise "No appInfo found for app #{APP_ID}." unless app_info

  asc.patch(
    "/v1/appInfos/#{app_info.fetch("id")}",
    {
      data: {
        type: "appInfos",
        id: app_info.fetch("id"),
        relationships: {
          primaryCategory: relationship("appCategories", "GAMES"),
          primarySubcategoryOne: relationship("appCategories", "GAMES_PUZZLE"),
          primarySubcategoryTwo: relationship("appCategories", "GAMES_BOARD")
        }
      }
    }
  )
  puts "Configured app categories: Games / Puzzle / Board"

  localization = app_infos.fetch("included", []).find do |item|
    item["type"] == "appInfoLocalizations" && item.dig("attributes", "locale") == "en-US"
  end
  attrs = {
    name: APP_NAME,
    subtitle: "Online Sudoku Battles"
  }
  attrs[:privacyPolicyUrl] = PRIVACY_URL unless PRIVACY_URL.empty?
  attrs[:privacyChoicesUrl] = PRIVACY_URL unless PRIVACY_URL.empty?

  if localization
    asc.patch(
      "/v1/appInfoLocalizations/#{localization.fetch("id")}",
      { data: { type: "appInfoLocalizations", id: localization.fetch("id"), attributes: attrs } }
    )
    puts "Updated app info localization en-US"
  else
    asc.post(
      "/v1/appInfoLocalizations",
      {
        data: {
          type: "appInfoLocalizations",
          attributes: attrs.merge(locale: "en-US"),
          relationships: { appInfo: relationship("appInfos", app_info.fetch("id")) }
        }
      }
    )
    puts "Created app info localization en-US"
  end

  update_age_rating(asc, app_info.fetch("id"))
end

def update_age_rating(asc, app_info_id)
  body = asc.get("/v1/appInfos/#{app_info_id}/ageRatingDeclaration")
  age_rating = body["data"]
  return puts("No age rating declaration found yet; skipped age rating update") unless age_rating

  asc.patch(
    "/v1/ageRatingDeclarations/#{age_rating.fetch("id")}",
    {
      data: {
        type: "ageRatingDeclarations",
        id: age_rating.fetch("id"),
        attributes: {
          advertising: true,
          alcoholTobaccoOrDrugUseOrReferences: "NONE",
          contests: "NONE",
          gambling: false,
          gamblingSimulated: "NONE",
          gunsOrOtherWeapons: "NONE",
          healthOrWellnessTopics: false,
          lootBox: false,
          medicalOrTreatmentInformation: "NONE",
          messagingAndChat: false,
          parentalControls: false,
          profanityOrCrudeHumor: "NONE",
          ageAssurance: false,
          sexualContentGraphicAndNudity: "NONE",
          sexualContentOrNudity: "NONE",
          socialMedia: false,
          socialMediaAgeRestricted: false,
          horrorOrFearThemes: "NONE",
          matureOrSuggestiveThemes: "NONE",
          unrestrictedWebAccess: false,
          userGeneratedContent: false,
          violenceCartoonOrFantasy: "NONE",
          violenceRealistic: "NONE",
          violenceRealisticProlongedGraphicOrSadistic: "NONE"
        }
      }
    }
  )
  puts "Updated age rating declaration"
end

def create_or_update_store_version(asc)
  versions = asc.get("/v1/apps/#{APP_ID}/appStoreVersions?include=appStoreVersionLocalizations,appStoreReviewDetail&limit=20")
  version = versions.fetch("data", []).find { |item| item.dig("attributes", "versionString") == APP_VERSION } ||
            versions.fetch("data", []).first
  unless version
    version = asc.post(
      "/v1/appStoreVersions",
      {
        data: {
          type: "appStoreVersions",
          attributes: { platform: "IOS", versionString: APP_VERSION, releaseType: "AFTER_APPROVAL", reviewType: "APP_STORE" },
          relationships: { app: relationship("apps", APP_ID) }
        }
      }
    ).fetch("data")
    versions = asc.get("/v1/apps/#{APP_ID}/appStoreVersions?include=appStoreVersionLocalizations,appStoreReviewDetail&limit=20")
  end

  asc.patch(
    "/v1/appStoreVersions/#{version.fetch("id")}",
    {
      data: {
        type: "appStoreVersions",
        id: version.fetch("id"),
        attributes: {
          copyright: "2026 Devovia Studio",
          releaseType: "AFTER_APPROVAL",
          reviewType: "APP_STORE"
        }
      }
    }
  )

  localization = versions.fetch("included", []).find do |item|
    item["type"] == "appStoreVersionLocalizations" && item.dig("attributes", "locale") == "en-US"
  end
  localization_attrs = {
    description: <<~TEXT.strip,
      Sudoku Duel turns classic Sudoku into a focused competitive puzzle game. Play 9x9 and 16x16 boards, build a career from beginner to expert, collect Coins through fair rewards, and enter ranked online duels against players on the same difficulty.

      Ranked matches use server-side matchmaking, Coin entry fees, settlement, ELO ratings, leaderboards, friend challenges, rematches, and account recovery through Firebase authentication. Free offline Sudoku remains available even when platform services are unavailable.

      Coins are virtual in-game items. They have no cash value, cannot be transferred, and cannot be redeemed for prizes or real-world value.
    TEXT
    keywords: "sudoku,duel,online,puzzle,brain,logic,leaderboard,ranked,career,coins",
    promotionalText: "Challenge players in ranked Sudoku duels and climb peak ELO leaderboards."
  }
  localization_attrs[:supportUrl] = SUPPORT_URL unless SUPPORT_URL.empty?
  localization_attrs[:marketingUrl] = SUPPORT_URL unless SUPPORT_URL.empty?

  if localization
    asc.patch(
      "/v1/appStoreVersionLocalizations/#{localization.fetch("id")}",
      { data: { type: "appStoreVersionLocalizations", id: localization.fetch("id"), attributes: localization_attrs } }
    )
    puts "Updated app store version localization en-US"
  else
    asc.post(
      "/v1/appStoreVersionLocalizations",
      {
        data: {
          type: "appStoreVersionLocalizations",
          attributes: localization_attrs.merge(locale: "en-US"),
          relationships: { appStoreVersion: relationship("appStoreVersions", version.fetch("id")) }
        }
      }
    )
    puts "Created app store version localization en-US"
  end

  if CONTACT_PHONE.empty?
    puts "Skipped app review contact details: set ASC_CONTACT_PHONE in +country format"
  else
    review_detail = versions.fetch("included", []).find { |item| item["type"] == "appStoreReviewDetails" }
    review_attrs = {
      contactFirstName: "Ahmet",
      contactLastName: "Ilhan",
      contactPhone: CONTACT_PHONE,
      contactEmail: "ilhanahmet246@gmail.com",
      demoAccountRequired: false,
      notes: <<~TEXT.strip
        Sudoku Duel supports free offline Sudoku and optional online features. Paid purchases are virtual Coin consumables and a non-consumable Remove Ads entitlement. Coin purchases require account protection so the wallet can be recovered. Coins have no cash value, cannot be transferred, and cannot be redeemed for prizes. Game Center is used for optional sign-in, friends, achievements, and peak ELO leaderboards; Firebase remains the app account owner.
      TEXT
    }
    if review_detail
      asc.patch(
        "/v1/appStoreReviewDetails/#{review_detail.fetch("id")}",
        { data: { type: "appStoreReviewDetails", id: review_detail.fetch("id"), attributes: review_attrs } }
      )
      puts "Updated app review details"
    else
      asc.post(
        "/v1/appStoreReviewDetails",
        {
          data: {
            type: "appStoreReviewDetails",
            attributes: review_attrs,
            relationships: { appStoreVersion: relationship("appStoreVersions", version.fetch("id")) }
          }
        }
      )
      puts "Created app review details"
    end
  end

  version.fetch("id")
end

def ensure_beta_testers(asc)
  groups = asc.paged("/v1/apps/#{APP_ID}/betaGroups?limit=200")
  group = groups.find { |item| item.dig("attributes", "name") == TEST_GROUP_NAME }
  unless group
    group = asc.post(
      "/v1/betaGroups",
      {
        data: {
          type: "betaGroups",
          attributes: {
            name: TEST_GROUP_NAME,
            isInternalGroup: false,
            hasAccessToAllBuilds: true,
            publicLinkEnabled: false,
            feedbackEnabled: true
          },
          relationships: { app: relationship("apps", APP_ID) }
        }
      }
    ).fetch("data")
    puts "Created external beta group: #{TEST_GROUP_NAME}"
  else
    asc.patch(
      "/v1/betaGroups/#{group.fetch("id")}",
      {
        data: {
          type: "betaGroups",
          id: group.fetch("id"),
          attributes: { publicLinkEnabled: false, feedbackEnabled: true }
        }
      }
    )
    puts "Updated external beta group: #{TEST_GROUP_NAME}"
  end

  group_testers = asc.paged("/v1/betaGroups/#{group.fetch("id")}/betaTesters?limit=200")
  existing_ids = group_testers.map { |item| item.fetch("id") }.to_set
  TESTER_EMAILS.each do |email|
    testers = asc.paged("/v1/betaTesters?filter[email]=#{URI.encode_www_form_component(email)}&limit=200")
    tester = testers.find { |item| item.dig("attributes", "email").to_s.downcase == email.downcase }
    unless tester
      tester = asc.post(
        "/v1/betaTesters",
        {
          data: {
            type: "betaTesters",
            attributes: { email: email },
            relationships: { betaGroups: { data: [{ type: "betaGroups", id: group.fetch("id") }] } }
          }
        }
      ).fetch("data")
      existing_ids.add(tester.fetch("id"))
      puts "Created beta tester #{email}"
      next
    end

    if existing_ids.include?(tester.fetch("id"))
      puts "Beta tester already in group: #{email}"
      next
    end

    begin
      asc.post(
        "/v1/betaGroups/#{group.fetch("id")}/relationships/betaTesters",
        { data: [{ type: "betaTesters", id: tester.fetch("id") }] }
      )
      puts "Added beta tester to group: #{email}"
    rescue RuntimeError => error
      puts "Could not attach existing tester #{email}: #{error.message}"
      begin
        asc.post(
          "/v1/betaTesters",
          {
            data: {
              type: "betaTesters",
              attributes: { email: email },
              relationships: { betaGroups: { data: [{ type: "betaGroups", id: group.fetch("id") }] } }
            }
          }
        )
        puts "Created group-scoped beta tester #{email}"
      rescue RuntimeError => create_error
        puts "Skipped beta tester #{email}: #{create_error.message}"
      end
    end
  end
end

def ensure_game_center(asc, app_store_version_id)
  detail = asc.get("/v1/apps/#{APP_ID}/gameCenterDetail")["data"]
  unless detail
    detail = asc.post(
      "/v1/gameCenterDetails",
      {
        data: {
          type: "gameCenterDetails",
          relationships: { app: relationship("apps", APP_ID) }
        }
      }
    ).fetch("data")
    puts "Created Game Center detail"
  else
    puts "Game Center detail already exists"
  end

  enabled_versions = asc.paged("/v1/apps/#{APP_ID}/gameCenterEnabledVersions?limit=200")
  unless enabled_versions.any? { |item| item.dig("relationships", "appStoreVersion", "data", "id") == app_store_version_id }
    begin
      asc.post(
        "/v1/gameCenterAppVersions",
        {
          data: {
            type: "gameCenterAppVersions",
            relationships: { appStoreVersion: relationship("appStoreVersions", app_store_version_id) }
          }
        }
      )
      puts "Enabled Game Center for App Store version #{APP_VERSION}"
    rescue RuntimeError => error
      raise unless error.message.include?("DUPLICATE")
      puts "Game Center already enabled for App Store version #{APP_VERSION}"
    end
  end

  detail_id = detail.fetch("id")
  existing_boards = asc.paged("/v1/gameCenterDetails/#{detail_id}/gameCenterLeaderboards?limit=200")
  LEADERBOARDS.each do |board|
    created = existing_boards.find { |item| item.dig("attributes", "vendorIdentifier") == board[:vendor_id] }
    unless created
      created = asc.post(
        "/v1/gameCenterLeaderboards",
        {
          data: {
            type: "gameCenterLeaderboards",
            attributes: {
              defaultFormatter: "INTEGER",
              referenceName: board[:name],
              vendorIdentifier: board[:vendor_id],
              submissionType: "BEST_SCORE",
              scoreSortType: "DESC",
              scoreRangeStart: "100",
              scoreRangeEnd: "3000",
              visibility: "SHOW_FOR_ALL"
            },
            relationships: { gameCenterDetail: relationship("gameCenterDetails", detail_id) }
          }
        }
      ).fetch("data")
      puts "Created leaderboard #{board[:vendor_id]}"
    else
      puts "Leaderboard exists #{board[:vendor_id]}"
    end
    ensure_leaderboard_localization_and_release(asc, detail_id, created.fetch("id"), board)
  end

  achievements = asc.paged("/v1/gameCenterDetails/#{detail_id}/gameCenterAchievements?limit=200")
  achievement = achievements.find { |item| item.dig("attributes", "vendorIdentifier") == ACHIEVEMENT[:vendor_id] }
  unless achievement
    achievement = asc.post(
      "/v1/gameCenterAchievements",
      {
        data: {
          type: "gameCenterAchievements",
          attributes: {
            referenceName: ACHIEVEMENT[:reference_name],
            vendorIdentifier: ACHIEVEMENT[:vendor_id],
            points: ACHIEVEMENT[:points],
            showBeforeEarned: true,
            repeatable: false
          },
          relationships: { gameCenterDetail: relationship("gameCenterDetails", detail_id) }
        }
      }
    ).fetch("data")
    puts "Created achievement #{ACHIEVEMENT[:vendor_id]}"
  else
    puts "Achievement exists #{ACHIEVEMENT[:vendor_id]}"
  end
  ensure_achievement_localization_and_release(asc, detail_id, achievement.fetch("id"))
end

def ensure_leaderboard_localization_and_release(asc, detail_id, leaderboard_id, board)
  localizations = asc.paged("/v1/gameCenterLeaderboards/#{leaderboard_id}/localizations?limit=50")
  unless localizations.any? { |item| item.dig("attributes", "locale") == "en-US" }
    asc.post(
      "/v1/gameCenterLeaderboardLocalizations",
      {
        data: {
          type: "gameCenterLeaderboardLocalizations",
          attributes: {
            locale: "en-US",
            name: board[:name],
            description: board[:description],
            formatterSuffix: "ELO",
            formatterSuffixSingular: "ELO"
          },
          relationships: { gameCenterLeaderboard: relationship("gameCenterLeaderboards", leaderboard_id) }
        }
      }
    )
    puts "  Added leaderboard localization en-US"
  end

  releases = asc.paged("/v1/gameCenterLeaderboards/#{leaderboard_id}/releases?limit=50")
  return unless releases.empty?

  asc.post(
    "/v1/gameCenterLeaderboardReleases",
    {
      data: {
        type: "gameCenterLeaderboardReleases",
        relationships: {
          gameCenterDetail: relationship("gameCenterDetails", detail_id),
          gameCenterLeaderboard: relationship("gameCenterLeaderboards", leaderboard_id)
        }
      }
    }
  )
  puts "  Added leaderboard release"
end

def ensure_achievement_localization_and_release(asc, detail_id, achievement_id)
  localizations = asc.paged("/v1/gameCenterAchievements/#{achievement_id}/localizations?limit=50")
  unless localizations.any? { |item| item.dig("attributes", "locale") == "en-US" }
    asc.post(
      "/v1/gameCenterAchievementLocalizations",
      {
        data: {
          type: "gameCenterAchievementLocalizations",
          attributes: {
            locale: "en-US",
            name: ACHIEVEMENT[:name],
            beforeEarnedDescription: ACHIEVEMENT[:before],
            afterEarnedDescription: ACHIEVEMENT[:after]
          },
          relationships: { gameCenterAchievement: relationship("gameCenterAchievements", achievement_id) }
        }
      }
    )
    puts "  Added achievement localization en-US"
  end

  releases = asc.paged("/v1/gameCenterAchievements/#{achievement_id}/releases?limit=50")
  return unless releases.empty?

  asc.post(
    "/v1/gameCenterAchievementReleases",
    {
      data: {
        type: "gameCenterAchievementReleases",
        relationships: {
          gameCenterDetail: relationship("gameCenterDetails", detail_id),
          gameCenterAchievement: relationship("gameCenterAchievements", achievement_id)
        }
      }
    }
  )
  puts "  Added achievement release"
end

def ensure_iaps(asc)
  existing = asc.paged("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")
  territories = asc.paged("/v1/territories?limit=200").map { |item| { type: "territories", id: item.fetch("id") } }
  raise "No App Store territories returned." if territories.empty?

  PRODUCTS.each do |product|
    iap = existing.find { |item| item.dig("attributes", "productId") == product[:product_id] }
    unless iap
      iap = asc.post(
        "/v2/inAppPurchases",
        {
          data: {
            type: "inAppPurchases",
            attributes: {
              productId: product[:product_id],
              name: product[:name],
              inAppPurchaseType: product[:type],
              reviewNote: "Virtual in-game Sudoku Duel product. The app sends StoreKit transaction data to the backend for server-side verification and idempotent grant.",
              familySharable: product[:type] == "NON_CONSUMABLE"
            },
            relationships: { app: relationship("apps", APP_ID) }
          }
        }
      ).fetch("data")
      puts "Created IAP #{product[:product_id]}"
    else
      puts "IAP exists #{product[:product_id]} state=#{iap.dig("attributes", "state")}"
    end

    ensure_iap_localization(asc, iap.fetch("id"), product)
    ensure_iap_availability(asc, iap.fetch("id"), territories)
    ensure_iap_price(asc, iap.fetch("id"), product)
    ensure_iap_review_screenshot(asc, iap.fetch("id"), product)
  end
end

def ensure_iap_localization(asc, iap_id, product)
  localizations = asc.paged("/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations?limit=50")
  if localizations.any? { |item| item.dig("attributes", "locale") == "en-US" }
    return
  end

  asc.post(
    "/v1/inAppPurchaseLocalizations",
    {
      data: {
        type: "inAppPurchaseLocalizations",
        attributes: {
          locale: "en-US",
          name: product[:name],
          description: product[:description]
        },
        relationships: { inAppPurchaseV2: relationship("inAppPurchases", iap_id) }
      }
    }
  )
  puts "  Added IAP localization en-US"
end

def ensure_iap_availability(asc, iap_id, territories)
  availability = begin
    asc.get("/v2/inAppPurchases/#{iap_id}/inAppPurchaseAvailability")["data"]
  rescue RuntimeError => error
    raise unless error.message.include?("404")
    nil
  end
  return puts("  IAP availability exists") if availability

  asc.post(
    "/v1/inAppPurchaseAvailabilities",
    {
      data: {
        type: "inAppPurchaseAvailabilities",
        attributes: { availableInNewTerritories: true },
        relationships: {
          inAppPurchase: relationship("inAppPurchases", iap_id),
          availableTerritories: { data: territories }
        }
      }
    }
  )
  puts "  Added IAP availability for #{territories.length} territories"
end

def ensure_iap_price(asc, iap_id, product)
  schedule = begin
    asc.get("/v2/inAppPurchases/#{iap_id}/iapPriceSchedule")["data"]
  rescue RuntimeError => error
    raise unless error.message.include?("404")
    nil
  end
  if schedule && ENV["ASC_FORCE_PRICE"] != "1"
    return puts("  IAP price schedule exists")
  end

  price_points = asc.paged(
    "/v2/inAppPurchases/#{iap_id}/pricePoints?filter[territory]=#{PRICE_TERRITORY}&fields[inAppPurchasePricePoints]=customerPrice&limit=8000"
  )
  price_point = price_points.find { |item| item.dig("attributes", "customerPrice").to_s == product[:eur_price] }
  available = price_points.map { |item| item.dig("attributes", "customerPrice") }.compact.uniq.first(20)
  raise "No #{PRICE_TERRITORY} price point #{product[:eur_price]} found for #{product[:product_id]}. First points: #{available.join(", ")}" unless price_point

  inline_id = "${price-#{product[:product_id]}}"
  asc.post(
    "/v1/inAppPurchasePriceSchedules",
    {
      data: {
        type: "inAppPurchasePriceSchedules",
        relationships: {
          inAppPurchase: relationship("inAppPurchases", iap_id),
          baseTerritory: relationship("territories", PRICE_TERRITORY),
          manualPrices: { data: [{ type: "inAppPurchasePrices", id: inline_id }] }
        }
      },
      included: [
        {
          type: "inAppPurchasePrices",
          id: inline_id,
          attributes: { startDate: nil, endDate: nil },
          relationships: {
            inAppPurchaseV2: relationship("inAppPurchases", iap_id),
            inAppPurchasePricePoint: relationship("inAppPurchasePricePoints", price_point.fetch("id"))
          }
        }
      ]
    }
  )
  puts "  Added EUR price #{product[:eur_price]} from #{PRICE_TERRITORY}"
end

def ensure_iap_review_screenshot(asc, iap_id, product)
  if IAP_REVIEW_SCREENSHOT.empty?
    return puts("  Skipped IAP review screenshot: set ASC_IAP_REVIEW_SCREENSHOT")
  end
  unless File.exist?(IAP_REVIEW_SCREENSHOT)
    return puts("  Skipped IAP review screenshot: file not found #{IAP_REVIEW_SCREENSHOT}")
  end

  existing = begin
    asc.get("/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot")["data"]
  rescue RuntimeError => error
    raise unless error.message.include?("404")
    nil
  end
  if existing
    state = existing.dig("attributes", "assetDeliveryState", "state")
    return puts("  IAP review screenshot exists#{state ? " state=#{state}" : ""}")
  end

  file_size = File.size(IAP_REVIEW_SCREENSHOT)
  file_name = "#{product[:product_id]}_review.png"
  screenshot = asc.post(
    "/v1/inAppPurchaseAppStoreReviewScreenshots",
    {
      data: {
        type: "inAppPurchaseAppStoreReviewScreenshots",
        attributes: { fileName: file_name, fileSize: file_size },
        relationships: { inAppPurchaseV2: relationship("inAppPurchases", iap_id) }
      }
    }
  ).fetch("data")

  upload_asset(IAP_REVIEW_SCREENSHOT, screenshot.dig("attributes", "uploadOperations") || [])
  checksum = Digest::MD5.file(IAP_REVIEW_SCREENSHOT).hexdigest
  asc.patch(
    "/v1/inAppPurchaseAppStoreReviewScreenshots/#{screenshot.fetch("id")}",
    {
      data: {
        type: "inAppPurchaseAppStoreReviewScreenshots",
        id: screenshot.fetch("id"),
        attributes: { sourceFileChecksum: checksum, uploaded: true }
      }
    }
  )
  puts "  Uploaded IAP review screenshot"
end

def upload_asset(file_path, operations)
  raise "No upload operations returned for #{file_path}." if operations.empty?

  bytes = File.binread(file_path)
  operations.each do |operation|
    uri = URI(operation.fetch("url"))
    method = operation.fetch("method").upcase
    request = Net::HTTPGenericRequest.new(method, true, true, uri)
    operation.fetch("requestHeaders", []).each do |header|
      request[header.fetch("name")] = header.fetch("value")
    end
    offset = operation.fetch("offset")
    length = operation.fetch("length")
    request.body = bytes.byteslice(offset, length)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end
    next if response.code.to_i.between?(200, 299)

    raise "Asset upload failed (#{response.code}): #{response.body}"
  end
end

asc = AppStoreConnect.new
app = asc.get("/v1/apps/#{APP_ID}")["data"]
raise "App #{APP_ID} was not found." unless app
actual_bundle = app.dig("attributes", "bundleId")
raise "Expected bundle #{APP_BUNDLE_ID}, got #{actual_bundle}." unless actual_bundle == APP_BUNDLE_ID

create_or_update_app_metadata(asc)
app_store_version_id = create_or_update_store_version(asc)
ensure_beta_testers(asc)
ensure_game_center(asc, app_store_version_id)
ensure_iaps(asc)

puts
puts "Game Center leaderboard IDs:"
LEADERBOARDS.each { |board| puts "#{board[:key]}=#{board[:vendor_id]}" }
puts "achievement_first_win=#{ACHIEVEMENT[:vendor_id]}"
puts "Done."
