#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "openssl"
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

  def delete(path)
    request(Net::HTTP::Delete, path)
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

REPO_ROOT = File.expand_path("..", __dir__)
APP_ID = ENV.fetch("ASC_APP_ID", "6795243950")
APP_BUNDLE_ID = ENV.fetch("ASC_APP_BUNDLE_ID", "com.devovia.sudokuduel")
LOCALE = ENV.fetch("ASC_LOCALE", "en-US")
OUTPUT_DIR = ENV.fetch(
  "ASC_ASSET_OUTPUT_DIR",
  File.join(REPO_ROOT, "build", "app_store_connect_assets")
)
VALIDATE_ONLY = ENV["ASC_VALIDATE_ASSETS_ONLY"] == "1"
REPLACE_GAME_CENTER_IMAGES = ENV["ASC_REPLACE_GAME_CENTER_IMAGES"] == "1"
REPLACE_IAP_IMAGES = ENV["ASC_REPLACE_IAP_IMAGES"] == "1"

PRODUCTS = [
  ["coins_100", "100 Coins", "100 virtual Coins. No cash value."],
  ["coins_500", "500 Coins", "500 virtual Coins. No cash value."],
  ["coins_1000", "1,000 Coins", "1,000 virtual Coins. No cash value."],
  ["coins_5000", "5,000 Coins", "5,000 virtual Coins. No cash value."],
  ["coins_10000", "10,000 Coins", "10,000 virtual Coins. No cash value."],
  ["coins_50000", "50,000 Coins", "50,000 virtual Coins. No cash value."],
  ["coins_100000", "100,000 Coins", "100,000 virtual Coins. No cash value."],
  ["sudoku_duel_no_ads", "Remove Ads", "Removes optional reward ad offers."]
].map do |product_id, name, description|
  {
    product_id: product_id,
    name: name,
    description: description
  }
end

LEADERBOARDS = [
  ["global", "Highest Global ELO", "Peak ranked ELO across all Sudoku Duel matches.", "eloglobal.png"],
  ["beginner", "Highest Beginner ELO", "Peak Beginner difficulty ranked ELO.", "beginner.png"],
  ["easy", "Highest Easy ELO", "Peak Easy difficulty ranked ELO.", "easy.png"],
  ["medium", "Highest Medium ELO", "Peak Medium difficulty ranked ELO.", "medium.png"],
  ["hard", "Highest Hard ELO", "Peak Hard difficulty ranked ELO.", "hard.png"],
  ["expert", "Highest Expert ELO", "Peak Expert difficulty ranked ELO.", "expert.png"]
].map do |key, name, description, asset|
  {
    key: key,
    vendor_id: "#{APP_BUNDLE_ID}.leaderboard.#{key}_peak_elo",
    name: name,
    description: description,
    source_path: File.join(REPO_ROOT, "assets", "googleplayGameCenterleaderboardicon", asset),
    upload_path: File.join(OUTPUT_DIR, "leaderboards", "#{key}.png"),
    upload_size: 1024,
    upload_format: "png"
  }
end

IAP_IMAGES = {
  "coins_100" => "store_coins_100.png",
  "coins_500" => "store_coins_500.png",
  "coins_1000" => "store_coins_1000.png",
  "coins_5000" => "store_coins_5000.png",
  "coins_10000" => "store_coins_10000.png",
  "coins_50000" => "store_coins_50000.png",
  "coins_100000" => "store_coins_100000.png",
  "sudoku_duel_no_ads" => "store_no_ads.png"
}.transform_values do |file_name|
  File.join(REPO_ROOT, "assets", "images", "ui", file_name)
end

def relationship(type, id)
  { data: { type: type, id: id } }
end

def run_sips(*args)
  stdout, stderr, status = Open3.capture3("sips", *args)
  return if status.success?

  details = [stdout, stderr].join("\n").strip
  raise "sips failed: #{details}"
end

def prepare_square_asset(source_path, output_path, size:, format:)
  raise "Missing source image: #{source_path}" unless File.exist?(source_path)

  FileUtils.mkdir_p(File.dirname(output_path))
  args = ["-Z", size.to_s, "-p", size.to_s, size.to_s, "--padColor", "FFFFFF"]
  args.concat(["-s", "format", format])
  run_sips(*args, source_path, "--out", output_path)
  width, height = image_dimensions(output_path)
  raise "Prepared image has wrong dimensions: #{output_path} #{width}x#{height}" unless width == size && height == size

  output_path
end

def image_dimensions(path)
  stdout, stderr, status = Open3.capture3("sips", "-g", "pixelWidth", "-g", "pixelHeight", path)
  raise "Could not inspect image #{path}: #{stderr}" unless status.success?

  width = stdout[/pixelWidth:\s*(\d+)/, 1].to_i
  height = stdout[/pixelHeight:\s*(\d+)/, 1].to_i
  [width, height]
end

def prepare_assets
  LEADERBOARDS.each do |board|
    prepare_square_asset(
      board[:source_path],
      board[:upload_path],
      size: board[:upload_size],
      format: board[:upload_format]
    )
  end

  PRODUCTS.each do |product|
    source_path = IAP_IMAGES.fetch(product[:product_id])
    upload_path = File.join(OUTPUT_DIR, "in_app_purchases", "#{product[:product_id]}.png")
    product[:source_path] = source_path
    product[:upload_path] = upload_path
    prepare_square_asset(source_path, upload_path, size: 1024, format: "png")
  end
end

def upload_asset(file_path, operations)
  raise "No upload operations returned for #{file_path}." if operations.empty?

  bytes = File.binread(file_path)
  operations.each do |operation|
    uri = URI(operation.fetch("url"))
    request = Net::HTTPGenericRequest.new(operation.fetch("method").upcase, true, true, uri)
    operation.fetch("requestHeaders", []).each do |header|
      request[header.fetch("name")] = header.fetch("value")
    end
    request.body = bytes.byteslice(operation.fetch("offset"), operation.fetch("length"))

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end
    next if response.code.to_i.between?(200, 299)

    raise "Asset upload failed for #{File.basename(file_path)} (#{response.code}): #{response.body}"
  end
end

def commit_asset(asc, endpoint, type, id, file_path, include_checksum:)
  attributes = { uploaded: true }
  attributes[:sourceFileChecksum] = Digest::MD5.file(file_path).hexdigest if include_checksum
  asc.patch(
    "#{endpoint}/#{id}",
    {
      data: {
        type: type,
        id: id,
        attributes: attributes
      }
    }
  )
end

def get_related(asc, path)
  asc.get(path)["data"]
rescue RuntimeError => error
  raise unless error.message.include?("404")

  nil
end

def ensure_game_center_assets(asc)
  detail = asc.get("/v1/apps/#{APP_ID}/gameCenterDetail")["data"]
  raise "Game Center detail does not exist for app #{APP_ID}. Run scripts/asc_prepare_ios_release.rb first." unless detail

  detail_id = detail.fetch("id")
  existing_boards = asc.paged("/v1/gameCenterDetails/#{detail_id}/gameCenterLeaderboards?limit=200")

  LEADERBOARDS.each do |board|
    leaderboard = existing_boards.find { |item| item.dig("attributes", "vendorIdentifier") == board[:vendor_id] }
    raise "Leaderboard not found: #{board[:vendor_id]}. Run scripts/asc_prepare_ios_release.rb first." unless leaderboard

    localization = ensure_leaderboard_localization(asc, leaderboard.fetch("id"), board)
    ensure_leaderboard_image(asc, localization.fetch("id"), board)
  end
end

def ensure_leaderboard_localization(asc, leaderboard_id, board)
  localizations = asc.paged("/v1/gameCenterLeaderboards/#{leaderboard_id}/localizations?limit=50")
  localization = localizations.find { |item| item.dig("attributes", "locale") == LOCALE }
  return localization if localization

  asc.post(
    "/v1/gameCenterLeaderboardLocalizations",
    {
      data: {
        type: "gameCenterLeaderboardLocalizations",
        attributes: {
          locale: LOCALE,
          name: board[:name],
          description: board[:description],
          formatterSuffix: "ELO",
          formatterSuffixSingular: "ELO"
        },
        relationships: { gameCenterLeaderboard: relationship("gameCenterLeaderboards", leaderboard_id) }
      }
    }
  ).fetch("data")
end

def ensure_leaderboard_image(asc, localization_id, board)
  existing = get_related(
    asc,
    "/v1/gameCenterLeaderboardLocalizations/#{localization_id}/gameCenterLeaderboardImage"
  )
  if existing && !REPLACE_GAME_CENTER_IMAGES
    state = existing.dig("attributes", "assetDeliveryState", "state")
    return puts("Leaderboard image exists #{board[:key]}#{state ? " state=#{state}" : ""}")
  end

  if existing
    asc.delete("/v1/gameCenterLeaderboardImages/#{existing.fetch("id")}")
    puts "Deleted leaderboard image #{board[:key]}"
  end

  image = asc.post(
    "/v1/gameCenterLeaderboardImages",
    {
      data: {
        type: "gameCenterLeaderboardImages",
        attributes: {
          fileName: File.basename(board[:upload_path]),
          fileSize: File.size(board[:upload_path])
        },
        relationships: {
          gameCenterLeaderboardLocalization: relationship(
            "gameCenterLeaderboardLocalizations",
            localization_id
          )
        }
      }
    }
  ).fetch("data")

  upload_asset(board[:upload_path], image.dig("attributes", "uploadOperations") || [])
  commit_asset(
    asc,
    "/v1/gameCenterLeaderboardImages",
    "gameCenterLeaderboardImages",
    image.fetch("id"),
    board[:upload_path],
    include_checksum: false
  )
  puts "Uploaded leaderboard image #{board[:key]} from #{board[:upload_path]}"
end

def ensure_iap_assets(asc)
  existing = asc.paged("/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=200")

  PRODUCTS.each do |product|
    iap = existing.find { |item| item.dig("attributes", "productId") == product[:product_id] }
    raise "IAP not found: #{product[:product_id]}. Run scripts/asc_prepare_ios_release.rb first." unless iap

    version = ensure_editable_iap_version(asc, iap.fetch("id"), product)
    ensure_iap_version_localization(asc, version.fetch("id"), product)
    ensure_iap_version_image(asc, version.fetch("id"), product)
  end
end

def ensure_editable_iap_version(asc, iap_id, product)
  # App Store Connect API 4.4.1+ keeps editable metadata/images
  # inside an inAppPurchaseVersion. Reuse the existing inflight
  # version instead of attempting to create a duplicate.
  body = asc.get("/v2/inAppPurchases/#{iap_id}?include=versions")

  versions = body.fetch("included", []).select do |item|
    item["type"] == "inAppPurchaseVersions"
  end

  version = versions.find do |item|
    %w[
      PREPARE_FOR_SUBMISSION
      READY_FOR_REVIEW
      WAITING_FOR_REVIEW
      IN_REVIEW
      REJECTED
    ].include?(item.dig("attributes", "state"))
  end

  version ||= versions.first

  if version
    state = version.dig("attributes", "state")
    puts "Using existing IAP version #{product[:product_id]} id=#{version.fetch("id")}#{state ? " state=#{state}" : ""}"
    return version
  end

  version = asc.post(
    "/v1/inAppPurchaseVersions",
    {
      data: {
        type: "inAppPurchaseVersions",
        relationships: {
          inAppPurchase: relationship("inAppPurchases", iap_id)
        }
      }
    }
  ).fetch("data")

  puts "Created IAP version for #{product[:product_id]}"
  version
end

def ensure_iap_version_localization(asc, version_id, product)
  localizations = asc.paged("/v1/inAppPurchaseVersions/#{version_id}/localizations?limit=50")
  return if localizations.any? { |item| item.dig("attributes", "locale") == LOCALE }

  asc.post(
    "/v2/inAppPurchaseLocalizations",
    {
      data: {
        type: "inAppPurchaseLocalizations",
        attributes: {
          locale: LOCALE,
          name: product[:name],
          description: product[:description]
        },
        relationships: { version: relationship("inAppPurchaseVersions", version_id) }
      }
    }
  )
  puts "Added IAP localization #{product[:product_id]} #{LOCALE}"
end

def ensure_iap_version_image(asc, version_id, product)
  existing = get_related(asc, "/v1/inAppPurchaseVersions/#{version_id}/image")
  if existing && !REPLACE_IAP_IMAGES
    state = existing.dig("attributes", "assetDeliveryState", "state")
    return puts("IAP image exists #{product[:product_id]}#{state ? " state=#{state}" : ""}")
  end

  if existing
    asc.delete("/v2/inAppPurchaseImages/#{existing.fetch("id")}")
    puts "Deleted IAP image #{product[:product_id]}"
  end

  image = asc.post(
    "/v2/inAppPurchaseImages",
    {
      data: {
        type: "inAppPurchaseImages",
        attributes: {
          fileName: File.basename(product[:upload_path]),
          fileSize: File.size(product[:upload_path])
        },
        relationships: { version: relationship("inAppPurchaseVersions", version_id) }
      }
    }
  ).fetch("data")

  upload_asset(product[:upload_path], image.dig("attributes", "uploadOperations") || [])
  commit_asset(
    asc,
    "/v2/inAppPurchaseImages",
    "inAppPurchaseImages",
    image.fetch("id"),
    product[:upload_path],
    include_checksum: false
  )
  puts "Uploaded IAP image #{product[:product_id]} from #{product[:upload_path]}"
end

prepare_assets

puts "Prepared App Store Connect assets:"
LEADERBOARDS.each do |board|
  width, height = image_dimensions(board[:upload_path])
  puts "leaderboard #{board[:key]} -> #{board[:upload_path]} #{width}x#{height}"
end
PRODUCTS.each do |product|
  width, height = image_dimensions(product[:upload_path])
  puts "iap #{product[:product_id]} -> #{product[:upload_path]} #{width}x#{height}"
end

if VALIDATE_ONLY
  puts "Validation only; skipped App Store Connect upload."
  exit
end

asc = AppStoreConnect.new
app = asc.get("/v1/apps/#{APP_ID}")["data"]
raise "App #{APP_ID} was not found." unless app

actual_bundle = app.dig("attributes", "bundleId")
raise "Expected bundle #{APP_BUNDLE_ID}, got #{actual_bundle}." unless actual_bundle == APP_BUNDLE_ID

ensure_game_center_assets(asc)
ensure_iap_assets(asc)

puts "Done."
