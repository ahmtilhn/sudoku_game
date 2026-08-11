#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
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

APP_ID = ENV.fetch("ASC_APP_ID", "6795243950")
APP_VERSION = ENV.fetch("ASC_APP_VERSION", "1.0")
LOCALE = ENV.fetch("ASC_LOCALE", "en-US")
DISPLAY_TYPE = ENV.fetch("ASC_SCREENSHOT_DISPLAY_TYPE", "APP_IPHONE_67")
SCREENSHOT_GLOB = ENV.fetch(
  "ASC_SCREENSHOT_GLOB",
  File.join(Dir.home, "Desktop", "Simulator Screenshot - iPhone Air - 2026-08-08 at *.png")
)
REPLACE_SCREENSHOTS = ENV["ASC_REPLACE_SCREENSHOTS"] == "1"

def relationship(type, id)
  { data: { type: type, id: id } }
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

def app_store_version_localization_id(asc)
  versions = asc.get("/v1/apps/#{APP_ID}/appStoreVersions?include=appStoreVersionLocalizations&limit=20")
  version = versions.fetch("data", []).find { |item| item.dig("attributes", "versionString") == APP_VERSION }
  raise "No App Store version #{APP_VERSION} found for app #{APP_ID}." unless version

  localization = versions.fetch("included", []).find do |item|
    item["type"] == "appStoreVersionLocalizations" && item.dig("attributes", "locale") == LOCALE
  end
  raise "No #{LOCALE} localization found for App Store version #{APP_VERSION}." unless localization

  localization.fetch("id")
end

def screenshot_set(asc, localization_id)
  sets = asc.paged(
    "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets?" \
      "filter[screenshotDisplayType]=#{DISPLAY_TYPE}&include=appScreenshots&limit=200&limit[appScreenshots]=50"
  )
  sets.find { |item| item.dig("attributes", "screenshotDisplayType") == DISPLAY_TYPE }
end

def create_screenshot_set(asc, localization_id)
  asc.post(
    "/v1/appScreenshotSets",
    {
      data: {
        type: "appScreenshotSets",
        attributes: { screenshotDisplayType: DISPLAY_TYPE },
        relationships: {
          appStoreVersionLocalization: relationship("appStoreVersionLocalizations", localization_id)
        }
      }
    }
  ).fetch("data")
end

def screenshots_for_set(asc, set_id)
  asc.paged(
    "/v1/appScreenshotSets/#{set_id}/appScreenshots?" \
      "fields[appScreenshots]=fileName,sourceFileChecksum,assetDeliveryState&limit=50"
  )
end

def delete_screenshots(asc, screenshots)
  screenshots.each do |screenshot|
    asc.delete("/v1/appScreenshots/#{screenshot.fetch("id")}")
    puts "Deleted existing screenshot #{screenshot.fetch("id")}"
  end
end

def upload_screenshot(asc, set_id, file_path, index)
  file_name = "sudoku_duel_#{format("%02d", index)}.png"
  screenshot = asc.post(
    "/v1/appScreenshots",
    {
      data: {
        type: "appScreenshots",
        attributes: { fileName: file_name, fileSize: File.size(file_path) },
        relationships: { appScreenshotSet: relationship("appScreenshotSets", set_id) }
      }
    }
  ).fetch("data")
  upload_asset(file_path, screenshot.dig("attributes", "uploadOperations") || [])
  asc.patch(
    "/v1/appScreenshots/#{screenshot.fetch("id")}",
    {
      data: {
        type: "appScreenshots",
        id: screenshot.fetch("id"),
        attributes: {
          sourceFileChecksum: Digest::MD5.file(file_path).hexdigest,
          uploaded: true
        }
      }
    }
  )
  puts "Uploaded #{file_name} from #{File.basename(file_path)}"
end

files = Dir.glob(SCREENSHOT_GLOB).sort.first(10)
raise "No screenshots matched #{SCREENSHOT_GLOB}." if files.empty?

asc = AppStoreConnect.new
localization_id = app_store_version_localization_id(asc)
set = screenshot_set(asc, localization_id) || create_screenshot_set(asc, localization_id)
puts "Screenshot set #{set.fetch("id")} displayType=#{DISPLAY_TYPE}"

existing = screenshots_for_set(asc, set.fetch("id"))
if REPLACE_SCREENSHOTS && !existing.empty?
  delete_screenshots(asc, existing)
  existing = []
end

complete_existing = existing.count do |screenshot|
  screenshot.dig("attributes", "assetDeliveryState", "state") == "COMPLETE"
end
if complete_existing >= files.length
  puts "Store screenshots already uploaded: #{complete_existing}"
  exit
end

files.drop(existing.length).each.with_index(existing.length + 1) do |file_path, index|
  upload_screenshot(asc, set.fetch("id"), file_path, index)
end

puts "Done."
