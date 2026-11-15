#include "crow.h"
#include <curl/curl.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <exception>
#include <fstream>
#include <future>
#include <iostream>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#ifndef CAMPUSSHARE_API_VERSION
#define CAMPUSSHARE_API_VERSION "unknown"
#endif
#ifndef CAMPUSSHARE_BUILD_ID
#define CAMPUSSHARE_BUILD_ID "unknown"
#endif

namespace
{
constexpr std::size_t maxMutationBodyBytes = 16 * 1024;

struct Config
{
    std::string supabaseUrl;
    std::string supabaseAnonKey;
    std::string supabaseApiKeySource;
    std::string host = "127.0.0.1";
    unsigned short port = 18080;
    bool useBorrowRequestRpc = false;
    bool useAtomicResourceUpdateRpc = false;
    bool useBorrowStatusRpc = false;
    bool useMarketplaceFeatures = false;
    bool useResourceImages = false;
    bool useCommunicationFeatures = false;
    std::vector<std::string> allowedOrigins = {
        "http://localhost:5500", "http://127.0.0.1:5500",
        "http://localhost:5501", "http://127.0.0.1:5501"};
};

std::string trim(const std::string& value)
{
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return {};
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::optional<std::string> readEnvironmentValue(const char* name);

void loadDotEnv()
{
    std::ifstream file(".env");
    std::string line;
    while (std::getline(file, line))
    {
        line = trim(line);
        if (line.empty() || line[0] == '#')
            continue;
        const auto equals = line.find('=');
        if (equals == std::string::npos)
            continue;
        const std::string name = trim(line.substr(0, equals));
        std::string value = trim(line.substr(equals + 1));
        if (value.size() >= 2 &&
            ((value.front() == '"' && value.back() == '"') ||
             (value.front() == '\'' && value.back() == '\'')))
            value = value.substr(1, value.size() - 2);
        if (!readEnvironmentValue(name.c_str()).has_value())
        {
#ifdef _WIN32
            _putenv_s(name.c_str(), value.c_str());
#else
            setenv(name.c_str(), value.c_str(), 0);
#endif
        }
    }
}

std::optional<std::string> readEnvironmentValue(const char* name)
{
#ifdef _WIN32
    char* value = nullptr;
    std::size_t size = 0;
    if (_dupenv_s(&value, &size, name) != 0 || value == nullptr)
    {
        std::free(value);
        return std::nullopt;
    }
    std::string result(value);
    std::free(value);
    return result;
#else
    const char* value = std::getenv(name);
    if (value == nullptr)
        return std::nullopt;
    return std::string(value);
#endif
}

std::string env(const char* name, const std::string& fallback = {})
{
    const auto value = readEnvironmentValue(name);
    return value.has_value() ? trim(*value) : fallback;
}

bool parsePort(const std::string& value, unsigned short& port)
{
    if (value.empty())
        return false;
    try
    {
        std::size_t consumed = 0;
        const unsigned long parsed = std::stoul(value, &consumed);
        if (consumed != value.size() || parsed == 0 || parsed > 65535)
            return false;
        port = static_cast<unsigned short>(parsed);
        return true;
    }
    catch (...)
    {
        return false;
    }
}

std::optional<bool> parseBooleanFlag(const std::string& value)
{
    std::string normalized = value;
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    if (normalized == "true" || normalized == "1" || normalized == "yes")
        return true;
    if (normalized == "false" || normalized == "0" || normalized == "no")
        return false;
    return std::nullopt;
}

std::optional<std::int64_t> parsePositiveBigint(const std::string& value)
{
    if (value.empty())
        return std::nullopt;
    std::int64_t parsed = 0;
    const auto result = std::from_chars(value.data(), value.data() + value.size(), parsed);
    if (result.ec != std::errc{} || result.ptr != value.data() + value.size() || parsed <= 0)
        return std::nullopt;
    return parsed;
}

int currentUtcYear()
{
    const std::time_t now = std::time(nullptr);
    std::tm utc{};
#ifdef _WIN32
    if (gmtime_s(&utc, &now) != 0) return 1970;
#else
    if (gmtime_r(&now, &utc) == nullptr) return 1970;
#endif
    return utc.tm_year + 1900;
}

std::optional<int> parsePurchaseYear(const crow::json::rvalue& value)
{
    if (value.t() != crow::json::type::Number)
        return std::nullopt;
    if (value.nt() == crow::json::num_type::Signed_integer)
    {
        const auto year = value.i();
        if (year < 1900 || year > currentUtcYear()) return std::nullopt;
        return static_cast<int>(year);
    }
    if (value.nt() == crow::json::num_type::Unsigned_integer)
    {
        const auto year = value.u();
        if (year < 1900 || year > static_cast<std::uint64_t>(currentUtcYear())) return std::nullopt;
        return static_cast<int>(year);
    }
    return std::nullopt;
}

std::vector<std::string> splitOrigins(const std::string& value)
{
    std::vector<std::string> result;
    std::stringstream stream(value);
    std::string origin;
    while (std::getline(stream, origin, ','))
    {
        origin = trim(origin);
        if (!origin.empty())
            result.push_back(origin);
    }
    return result;
}

std::string decodeBase64Url(const std::string& encoded)
{
    static const std::string alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string decoded;
    unsigned int buffer = 0;
    int bits = 0;
    for (const unsigned char ch : encoded)
    {
        if (ch == '=')
            break;
        const auto position = alphabet.find(static_cast<char>(ch));
        if (position == std::string::npos)
            return {};
        buffer = (buffer << 6) | static_cast<unsigned int>(position);
        bits += 6;
        if (bits >= 8)
        {
            bits -= 8;
            decoded.push_back(static_cast<char>((buffer >> bits) & 0xff));
        }
    }
    return decoded;
}

bool isServiceRoleKey(const std::string& key)
{
    if (key.rfind("sb_secret_", 0) == 0)
        return true;
    const auto firstDot = key.find('.');
    const auto secondDot = firstDot == std::string::npos
                               ? std::string::npos
                               : key.find('.', firstDot + 1);
    if (firstDot == std::string::npos || secondDot == std::string::npos)
        return false;
    const std::string payload = decodeBase64Url(
        key.substr(firstDot + 1, secondDot - firstDot - 1));
    const auto role = payload.find("\"role\"");
    if (role == std::string::npos)
        return false;
    const auto colon = payload.find(':', role + 6);
    if (colon == std::string::npos)
        return false;
    const auto quote = payload.find_first_not_of(" \t\r\n", colon + 1);
    return quote != std::string::npos && payload.compare(quote, 14, "\"service_role\"") == 0;
}

bool isPublishableOrAnonKey(const std::string& key)
{
    constexpr char publishablePrefix[] = "sb_publishable_";
    if (key.rfind(publishablePrefix, 0) == 0 && key.size() > sizeof(publishablePrefix) - 1 &&
        key.find_first_of(" \t\r\n") == std::string::npos)
        return true;

    const auto firstDot = key.find('.');
    const auto secondDot = firstDot == std::string::npos
                               ? std::string::npos
                               : key.find('.', firstDot + 1);
    if (firstDot == std::string::npos || secondDot == std::string::npos ||
        key.find('.', secondDot + 1) != std::string::npos)
        return false;
    const std::string payload = decodeBase64Url(
        key.substr(firstDot + 1, secondDot - firstDot - 1));
    const auto parsed = crow::json::load(payload);
    return parsed && parsed.t() == crow::json::type::Object && parsed.has("role") &&
           parsed["role"].t() == crow::json::type::String && parsed["role"].s() == "anon";
}

bool loadConfig(Config& config)
{
    loadDotEnv();
    config.supabaseUrl = env("SUPABASE_URL");
    const std::pair<const char*, std::string> apiKeys[] = {
        {"SUPABASE_ANON_KEY", env("SUPABASE_ANON_KEY")},
        {"SUPABASE_API_KEY", env("SUPABASE_API_KEY")},
        {"SUPABASE_KEY", env("SUPABASE_KEY")}};
    for (const auto& candidate : apiKeys)
    {
        if (candidate.second.empty())
            continue;
        if (config.supabaseAnonKey.empty())
        {
            config.supabaseAnonKey = candidate.second;
            config.supabaseApiKeySource = candidate.first;
        }
        else if (candidate.second != config.supabaseAnonKey)
        {
            std::cerr << "Conflicting Supabase public API key variables are configured. "
                         "Use the same staging publishable/anon key for all configured aliases.\n";
            return false;
        }
    }
    const auto useBorrowRequestRpc = parseBooleanFlag(env("SUPABASE_RPC_CREATE_BORROW_REQUEST", "false"));
    if (!useBorrowRequestRpc.has_value())
    {
        std::cerr << "Invalid SUPABASE_RPC_CREATE_BORROW_REQUEST; expected true or false.\n";
        return false;
    }
    config.useBorrowRequestRpc = *useBorrowRequestRpc;
    const auto useAtomicResourceUpdateRpc = parseBooleanFlag(
        env("SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE", "false"));
    if (!useAtomicResourceUpdateRpc.has_value())
    {
        std::cerr << "Invalid SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE; expected true or false.\n";
        return false;
    }
    config.useAtomicResourceUpdateRpc = *useAtomicResourceUpdateRpc;
    const auto useBorrowStatusRpc = parseBooleanFlag(
        env("SUPABASE_RPC_BORROW_STATUS", "false"));
    if (!useBorrowStatusRpc.has_value())
    {
        std::cerr << "Invalid SUPABASE_RPC_BORROW_STATUS; expected true or false.\n";
        return false;
    }
    config.useBorrowStatusRpc = *useBorrowStatusRpc;
    const auto useMarketplaceFeatures = parseBooleanFlag(
        env("SUPABASE_MARKETPLACE_ENABLED", "false"));
    if (!useMarketplaceFeatures.has_value())
    {
        std::cerr << "Invalid SUPABASE_MARKETPLACE_ENABLED; expected true or false.\n";
        return false;
    }
    config.useMarketplaceFeatures = *useMarketplaceFeatures;
    const auto useResourceImages = parseBooleanFlag(
        env("SUPABASE_RESOURCE_IMAGES_ENABLED", "false"));
    if (!useResourceImages.has_value())
    {
        std::cerr << "Invalid SUPABASE_RESOURCE_IMAGES_ENABLED; expected true or false.\n";
        return false;
    }
    config.useResourceImages = *useResourceImages;
    const auto useCommunicationFeatures = parseBooleanFlag(
        env("SUPABASE_COMMUNICATION_ENABLED", "false"));
    if (!useCommunicationFeatures.has_value())
    {
        std::cerr << "Invalid SUPABASE_COMMUNICATION_ENABLED; expected true or false.\n";
        return false;
    }
    config.useCommunicationFeatures = *useCommunicationFeatures;
    if (config.useBorrowStatusRpc && !config.useAtomicResourceUpdateRpc)
    {
        std::cerr << "SUPABASE_RPC_BORROW_STATUS requires SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true.\n";
        return false;
    }
    config.host = env("SERVER_HOST", config.host);
    std::string portValue = env("SERVER_PORT");
    if (portValue.empty())
    {
        portValue = env("PORT", "18080");
    }
    if (!parsePort(portValue, config.port))
    {
        std::cerr << "Invalid SERVER_PORT or PORT; expected an integer from 1 to 65535.\n";
        return false;
    }
    const std::string origins = env("CORS_ALLOWED_ORIGINS");
    if (!origins.empty())
        config.allowedOrigins = splitOrigins(origins);

    if (config.supabaseUrl.empty() || config.supabaseAnonKey.empty())
    {
        std::cerr << "Missing SUPABASE_URL or SUPABASE_ANON_KEY. Set them in the "
                     "environment or BACKEND/.env. Use only a Supabase publishable/anon key.\n";
        return false;
    }
    if (isServiceRoleKey(config.supabaseAnonKey))
    {
        std::cerr << "A Supabase secret/service_role key is not allowed. Configure a publishable/anon key.\n";
        return false;
    }
    if (!isPublishableOrAnonKey(config.supabaseAnonKey))
    {
        std::cerr << "SUPABASE_ANON_KEY is not a recognized publishable/anon key. "
                     "Replace any placeholder in BACKEND/.env; the key value is never logged.\n";
        return false;
    }
    std::cerr << "Using the Supabase public API key from " << config.supabaseApiKeySource << ".\n";
    while (!config.supabaseUrl.empty() && config.supabaseUrl.back() == '/')
        config.supabaseUrl.pop_back();
    bool localHttp = false;
    if (config.supabaseUrl.rfind("http://", 0) == 0)
    {
        const auto authorityEnd = config.supabaseUrl.find_first_of("/?#", 7);
        const std::string authority = config.supabaseUrl.substr(
            7, authorityEnd == std::string::npos ? std::string::npos : authorityEnd - 7);
        const auto portSeparator = authority.find(':');
        const std::string host = authority.substr(0, portSeparator);
        localHttp = host == "localhost" || host == "127.0.0.1";
    }
    if (config.supabaseUrl.rfind("https://", 0) != 0 && !localHttp)
    {
        std::cerr << "SUPABASE_URL must use HTTPS (HTTP is allowed for local development).\n";
        return false;
    }
    return true;
}

size_t writeBody(char* data, size_t size, size_t count, void* destination)
{
    const size_t bytes = size * count;
    auto* output = static_cast<std::string*>(destination);
    constexpr std::size_t maxResponseBytes = 1024 * 1024;
    if (bytes > maxResponseBytes || output->size() > maxResponseBytes - bytes)
        return 0;
    output->append(data, bytes);
    return bytes;
}

struct HttpResult
{
    CURLcode curlCode = CURLE_FAILED_INIT;
    long status = 0;
    std::string body;
};

struct AuthResult
{
    bool verified = false;
    bool unavailable = false;
    bool rejected = false;
    std::string userId;
};

std::string urlEncode(const std::string& value)
{
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string encoded;
    for (const unsigned char ch : value)
    {
        if (std::isalnum(ch) || ch == '-' || ch == '_' || ch == '.' || ch == '~')
            encoded.push_back(static_cast<char>(ch));
        else
        {
            encoded.push_back('%');
            encoded.push_back(hex[ch >> 4]);
            encoded.push_back(hex[ch & 0x0f]);
        }
    }
    return encoded;
}

bool isSafeBearerToken(const std::string& token)
{
    if (token.empty() || token.size() > 8192)
        return false;
    for (const unsigned char ch : token)
    {
        if (!(std::isalnum(ch) || ch == '.' || ch == '_' || ch == '-'))
            return false;
    }
    return true;
}

bool isUtcTimestamp(const std::string& value)
{
    if (value.size() == 20)
    {
        if (value[4] != '-' || value[7] != '-' ||
            value[10] != 'T' || value[13] != ':' || value[16] != ':' || value[19] != 'Z')
            return false;
        for (std::size_t i = 0; i < value.size(); ++i)
        {
            if (i == 4 || i == 7 || i == 10 || i == 13 || i == 16 || i == 19)
                continue;
            if (!std::isdigit(static_cast<unsigned char>(value[i])))
                return false;
        }
    }
    else if (value.size() == 24)
    {
        if (value[4] != '-' || value[7] != '-' ||
            value[10] != 'T' || value[13] != ':' || value[16] != ':' || value[19] != '.' || value[23] != 'Z')
            return false;
        for (std::size_t i = 0; i < value.size(); ++i)
        {
            if (i == 4 || i == 7 || i == 10 || i == 13 || i == 16 || i == 19 || i == 23)
                continue;
            if (!std::isdigit(static_cast<unsigned char>(value[i])))
                return false;
        }
    }
    else
    {
        return false;
    }
    const int year = std::stoi(value.substr(0, 4));
    const int month = std::stoi(value.substr(5, 2));
    const int day = std::stoi(value.substr(8, 2));
    const int hour = std::stoi(value.substr(11, 2));
    const int minute = std::stoi(value.substr(14, 2));
    const int second = std::stoi(value.substr(17, 2));
    if (year == 0 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59)
        return false;
    const bool leapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    const int daysInMonth[] = {31, leapYear ? 29 : 28, 31, 30, 31, 30,
                               31, 31, 30, 31, 30, 31};
    return day >= 1 && day <= daysInMonth[month - 1];
}

std::string currentUtcTimestamp()
{
    const std::time_t now = std::time(nullptr);
    std::tm utc{};
#ifdef _WIN32
    gmtime_s(&utc, &now);
#else
    gmtime_r(&now, &utc);
#endif
    char buffer[21]{};
    if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &utc) == 0)
        return {};
    return buffer;
}

bool isValidUuid(const std::string& value)
{
    if (value.size() != 36)
        return false;
    for (std::size_t i = 0; i < 36; ++i)
    {
        if (i == 8 || i == 13 || i == 18 || i == 23)
        {
            if (value[i] != '-')
                return false;
        }
        else
        {
            if (!std::isxdigit(static_cast<unsigned char>(value[i])))
                return false;
        }
    }
    return true;
}

struct CachedAuthToken
{
    AuthResult auth;
    std::chrono::steady_clock::time_point expiresAt;
};

class SupabaseClient
{
public:
    explicit SupabaseClient(const Config& config) : config_(config) {}

    HttpResult request(const std::string& method, const std::string& path,
                       const std::string& bearerToken = {}, const std::string& body = {},
                       const std::string& prefer = {}) const
    {
        HttpResult result;
        CURL* curl = curl_easy_init();
        if (curl == nullptr)
            return result;

        const std::string url = config_.supabaseUrl + path;
        struct curl_slist* headers = nullptr;
        const std::string apiKeyHeader = "apikey: " + config_.supabaseAnonKey;
        headers = curl_slist_append(headers, apiKeyHeader.c_str());
        headers = curl_slist_append(headers, "Accept: application/json");
        if (!bearerToken.empty())
        {
            const std::string authorization = "Authorization: Bearer " + bearerToken;
            headers = curl_slist_append(headers, authorization.c_str());
        }
        if (!body.empty())
            headers = curl_slist_append(headers, "Content-Type: application/json");
        if (!prefer.empty())
        {
            const std::string preferHeader = "Prefer: " + prefer;
            headers = curl_slist_append(headers, preferHeader.c_str());
        }

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method.c_str());
        if (!body.empty())
        {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(body.size()));
        }
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeBody);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &result.body);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "CampusShare/1.0");
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 5L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        result.curlCode = curl_easy_perform(curl);
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &result.status);

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return result;
    }

    AuthResult verifyAccessToken(const std::string& authorizationHeader) const
    {
        AuthResult auth;
        constexpr char prefix[] = "Bearer ";
        if (authorizationHeader.size() <= sizeof(prefix) - 1 ||
            authorizationHeader.compare(0, sizeof(prefix) - 1, prefix) != 0)
        {
            std::cerr << "[auth] Request has no well-formed Bearer token.\n";
            return auth;
        }

        const std::string token = authorizationHeader.substr(sizeof(prefix) - 1);
        if (!isSafeBearerToken(token))
        {
            std::cerr << "[auth] Malformed Bearer token rejected before Supabase verification.\n";
            return auth;
        }

        {
            std::lock_guard<std::mutex> lock(authCacheMutex_);
            const auto now = std::chrono::steady_clock::now();
            auto it = authCache_.find(token);
            if (it != authCache_.end())
            {
                if (now < it->second.expiresAt)
                {
                    return it->second.auth;
                }
                authCache_.erase(it);
            }
        }

        const HttpResult result = request("GET", "/auth/v1/user", token);
        if (result.curlCode != CURLE_OK || result.status == 0 ||
            result.status == 429 || result.status >= 500)
        {
            std::cerr << "[auth] Supabase Auth verification unavailable (transport code "
                      << static_cast<int>(result.curlCode) << ", HTTP " << result.status << ").\n";
            auth.unavailable = true;
            return auth;
        }
        if (result.status != 200)
        {
            std::cerr << "[auth] Supabase Auth rejected the token or API key (HTTP "
                      << result.status << ").\n";
            auth.rejected = true;
            return auth;
        }

        const auto parsed = crow::json::load(result.body);
        if (!parsed || parsed.t() != crow::json::type::Object || !parsed.has("id") ||
            parsed["id"].t() != crow::json::type::String || !parsed.has("is_anonymous") ||
            (parsed["is_anonymous"].t() != crow::json::type::True &&
             parsed["is_anonymous"].t() != crow::json::type::False))
        {
            std::cerr << "[auth] Supabase Auth returned an invalid user response (HTTP 200).\n";
            return auth;
        }

        if (parsed["is_anonymous"].b())
        {
            std::cerr << "[auth] Anonymous Supabase Auth users are not permitted for CampusShare student APIs.\n";
            auth.rejected = true;
            return auth;
        }

        auth.userId = parsed["id"].s();
        auth.verified = !auth.userId.empty();
        if (auth.verified)
        {
            std::lock_guard<std::mutex> lock(authCacheMutex_);
            // Cache verified token for 45 seconds to avoid hammering Supabase Auth
            authCache_[token] = CachedAuthToken{ auth, std::chrono::steady_clock::now() + std::chrono::seconds(45) };
        }
        return auth;
    }

    HttpResult get(const std::string& path) const
    {
        return request("GET", path);
    }

    HttpResult postgrest(const std::string& method, const std::string& path,
                         const std::string& bearerToken, const std::string& body = {},
                         const std::string& prefer = {}) const
    {
        return request(method, "/rest/v1/" + path, bearerToken, body, prefer);
    }

    HttpResult removeResourceImageObject(const std::string& storagePath,
                                         const std::string& bearerToken) const
    {
        crow::json::wvalue body;
        crow::json::wvalue::list prefixes;
        prefixes.emplace_back(storagePath);
        body["prefixes"] = std::move(prefixes);
        return request("DELETE", "/storage/v1/object/campusshare-resource-images",
                       bearerToken, body.dump());
    }

    HttpResult rpc(const std::string& functionName, const std::string& bearerToken,
                   const std::string& parameters) const
    {
        if (functionName.empty() || !std::all_of(functionName.begin(), functionName.end(), [](unsigned char ch) {
                return std::islower(ch) || std::isdigit(ch) || ch == '_';
            }))
        {
            HttpResult invalid;
            invalid.curlCode = CURLE_URL_MALFORMAT;
            return invalid;
        }
        return request("POST", "/rest/v1/rpc/" + functionName, bearerToken, parameters,
                       "return=representation");
    }

private:
    const Config& config_;
    mutable std::mutex authCacheMutex_;
    mutable std::unordered_map<std::string, CachedAuthToken> authCache_;
};

crow::response jsonError(int status, const std::string& code,
                         const std::string& message)
{
    crow::json::wvalue body;
    body["error"]["code"] = code;
    body["error"]["message"] = message;
    crow::response response(status, body);
    response.set_header("Content-Type", "application/json; charset=utf-8");
    return response;
}

struct CorsMiddleware
{
    struct context
    {
    };

    std::vector<std::string> allowedOrigins;

    void before_handle(crow::request&, crow::response&, context&) {}

    void after_handle(crow::request& request, crow::response& response, context&)
    {
        const std::string origin = request.get_header_value("Origin");
        if (std::find(allowedOrigins.begin(), allowedOrigins.end(), origin) != allowedOrigins.end())
        {
            response.set_header("Access-Control-Allow-Origin", origin);
            response.set_header("Vary", "Origin");
            response.set_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
            response.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization");
            response.set_header("Access-Control-Max-Age", "600");
        }
        response.set_header("X-Content-Type-Options", "nosniff");
    }
};

std::string tokenFromRequest(const crow::request& request)
{
    constexpr char prefix[] = "Bearer ";
    const std::string authorization = request.get_header_value("Authorization");
    if (authorization.compare(0, sizeof(prefix) - 1, prefix) != 0)
        return {};
    return authorization.substr(sizeof(prefix) - 1);
}

crow::response authenticationError(const AuthResult& auth)
{
    if (auth.unavailable)
        return jsonError(503, "auth_unavailable", "Authentication verification is temporarily unavailable.");
    if (auth.rejected)
        return jsonError(401, "auth_rejected", "Supabase Auth rejected this session or the backend public API key.");
    return jsonError(401, "unauthorized", "A valid Supabase access token is required.");
}

crow::response upstreamError(const HttpResult& result, const std::string& message)
{
    std::cerr << "Supabase request failed (curl=" << result.curlCode
              << ", HTTP=" << result.status << ").\n";
    if (result.curlCode == CURLE_OK && (result.status == 401 || result.status == 403))
        return jsonError(403, "permission_denied",
                         "Supabase denied this operation. Check the project's grants and row-level security policies.");
    if (result.curlCode == CURLE_OK && result.status == 409)
        return jsonError(409, "conflict",
                         "The operation conflicts with existing data or a database constraint.");
    if (result.curlCode == CURLE_OK && (result.status == 400 || result.status == 422))
        return jsonError(422, "invalid_data",
                         "Supabase rejected the data. Check required fields and database constraints.");
    return jsonError(502, "upstream_error", message);
}

crow::response rpcError(const HttpResult& result, const std::string& fallback)
{
    const auto parsed = crow::json::load(result.body);
    std::string code;
    std::string dbMessage;
    if (parsed && parsed.t() == crow::json::type::Object)
    {
        if (parsed.has("code") && parsed["code"].t() == crow::json::type::String)
            code = parsed["code"].s();
        if (parsed.has("message") && parsed["message"].t() == crow::json::type::String)
            dbMessage = parsed["message"].s();
    }

    if (result.curlCode != CURLE_OK || result.status == 0)
        return jsonError(502, "upstream_error", fallback);

    if (result.status >= 500)
    {
        const std::string upstreamMsg = !dbMessage.empty() ? dbMessage : fallback;
        return jsonError(502, "upstream_error", upstreamMsg);
    }

    if (result.status == 401 || code == "28000")
        return jsonError(401, "unauthorized", "A valid Supabase access token is required.");
    if (result.status == 403 || code == "42501" || dbMessage == "Only the owner may change availability")
        return jsonError(403, "permission_denied", "Supabase denied this operation.");
    if (code == "P0002" || dbMessage == "Resource not found")
        return jsonError(404, "not_found", "The requested record was not found.");
    if (result.status == 409 || code == "P0001" || code == "23505" || code == "23P01" ||
        dbMessage == "Cannot request own resource" || dbMessage == "Resource unavailable" ||
        dbMessage == "Active request exists" || dbMessage == "Approved loan remains active")
    {
        const std::string conflictMsg = !dbMessage.empty() ? dbMessage : "The operation conflicts with the current resource or request state.";
        return jsonError(409, "conflict", conflictMsg);
    }
    if (dbMessage == "Authentication required")
        return jsonError(401, "unauthorized", "A valid Supabase access token is required.");
    if (dbMessage == "due_at precedes request time" || dbMessage == "Invalid availability status" ||
        code == "22023" || code == "22P02" || code == "22007" || code == "23503" || code == "23514")
        return jsonError(400, "invalid_data", "Supabase rejected the supplied value.");
    if (code == "PGRST202")
    {
        if (dbMessage.find("Could not find the function") != std::string::npos)
            return jsonError(502, "rpc_missing", "The required Supabase RPC function is not installed in the database.");
        return jsonError(502, "rpc_unavailable", "The configured Supabase RPC is unavailable or has a different signature.");
    }
    if (code == "PGRST204")
        return jsonError(502, "rpc_signature_mismatch", "The Supabase RPC function signature or parameters do not match.");
    if (result.status == 404)
        return jsonError(404, "not_found", "The requested record was not found.");
    return jsonError(422, "database_rejected", "Supabase rejected the operation.");
}

bool isJsonObject(const crow::json::rvalue& value)
{
    return static_cast<bool>(value) && value.t() == crow::json::type::Object;
}

bool isNonBlank(const std::string& value)
{
    return std::any_of(value.begin(), value.end(), [](unsigned char ch) {
        return !std::isspace(ch);
    });
}
} // namespace

int main()
{
    Config config;
    if (!loadConfig(config))
        return 1;
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    {
        std::cerr << "Failed to initialize libcurl.\n";
        return 1;
    }

    crow::App<CorsMiddleware> app;
    app.get_middleware<CorsMiddleware>().allowedOrigins = config.allowedOrigins;
    app.loglevel(crow::LogLevel::Warning);
    SupabaseClient supabase(config);
    const auto verifyResourceOwner = [&](const crow::request& request,
                                         const std::string& resourceId,
                                         const std::string& userId,
                                         const std::string& customForbidden = {}) -> std::optional<crow::response> {
        const HttpResult upstream = supabase.postgrest(
            "GET", "resources?select=id,owner_id&id=eq." + urlEncode(resourceId) + "&limit=1",
            tokenFromRequest(request));
        if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
            return upstreamError(upstream, "Could not verify resource ownership.");
        const auto rows = crow::json::load(upstream.body);
        if (!rows || rows.t() != crow::json::type::List)
            return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid resource response.");
        if (rows.size() == 0)
            return jsonError(404, "not_found", "Resource not found.");
        if (!rows[0].has("owner_id") || rows[0]["owner_id"].t() != crow::json::type::String)
            return jsonError(502, "invalid_upstream_response", "Supabase returned incomplete resource data.");
        if (rows[0]["owner_id"].s() != userId)
            return jsonError(403, "forbidden", customForbidden.empty() ? "You may change only resources you own." : customForbidden);
        return std::nullopt;
    };

    CROW_ROUTE(app, "/api/test")
        ([]() {
            crow::json::wvalue body;
            body["status"] = "success";
            body["message"] = "Crow routes are working";
            crow::response response(body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/health")
        ([&config]() {
            crow::json::wvalue body;
            body["status"] = "ok";
            body["service"] = "CampusShare backend";
            body["api_version"] = CAMPUSSHARE_API_VERSION;
            body["build_id"] = CAMPUSSHARE_BUILD_ID;
            body["dependencies"]["http_client_initialized"] = true;
            body["dependencies"]["supabase_connectivity"] = "not_probed";
            body["features"]["borrow_request_rpc_enabled"] = config.useBorrowRequestRpc;
            body["features"]["atomic_resource_update_rpc_enabled"] = config.useAtomicResourceUpdateRpc;
            body["features"]["borrow_status_rpc_enabled"] =
                config.useBorrowStatusRpc && config.useAtomicResourceUpdateRpc;
            body["features"]["marketplace_enabled"] = config.useMarketplaceFeatures;
            body["features"]["resource_images_enabled"] = config.useResourceImages;
            crow::response response(body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/categories")
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            const HttpResult upstream = supabase.postgrest(
                "GET", "categories?select=id,name,created_at&limit=100", tokenFromRequest(request));
            crow::response response;
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
            {
                std::cerr << "[api/categories] PostgREST request failed (transport code "
                          << static_cast<int>(upstream.curlCode) << ", HTTP " << upstream.status << ").\n";
                response = upstreamError(upstream, "Could not retrieve categories.");
            }
            else
            {
                const auto parsed = crow::json::load(upstream.body);
                if (!parsed || parsed.t() != crow::json::type::List)
                    response = jsonError(502, "invalid_upstream_response",
                                         "Supabase returned an invalid categories response.");
                else
                {
                    response.code = 200;
                    response.body = upstream.body;
                    response.set_header("Content-Type", "application/json; charset=utf-8");
                }
            }
            return response;
        });

    CROW_ROUTE(app, "/api/resources")
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            const std::string projection = config.useMarketplaceFeatures
                ? "id,title,description,category_id,owner_id,resource_type,availability_status,created_at,listing_mode,borrow_price_kind,borrow_price_amount,sale_original_price,sale_price,item_condition,purchase_year,listing_state"
                : "id,title,description,category_id,owner_id,resource_type,availability_status,created_at";
            const HttpResult upstream = supabase.postgrest(
                "GET", "resources?select=" + projection + "&limit=100", tokenFromRequest(request));
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
                return upstreamError(upstream, "Could not retrieve resources.");
            const auto parsed = crow::json::load(upstream.body);
            if (!parsed || parsed.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid resources response.");
            crow::response response(200, upstream.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& item : parsed)
            {
                const std::string key = static_cast<std::string>(item.key());
                const bool baseField = key == "title" || key == "description" ||
                    key == "category_id" || key == "resource_type" || key == "availability_status";
                const bool marketplaceField = config.useMarketplaceFeatures &&
                    (key == "listing_mode" || key == "borrow_price_kind" ||
                     key == "borrow_price_amount" || key == "sale_original_price" ||
                     key == "sale_price" || key == "item_condition" || key == "purchase_year");
                if (!baseField && !marketplaceField)
                    return jsonError(400, "invalid_request", "The request contains an unsupported field.");
            }
            if (!parsed.has("title") || parsed["title"].t() != crow::json::type::String ||
                !isNonBlank(parsed["title"].s()))
                return jsonError(400, "invalid_request", "A non-empty title is required.");
            if (!parsed.has("category_id") || parsed["category_id"].t() != crow::json::type::String ||
                !parsePositiveBigint(parsed["category_id"].s()).has_value())
                return jsonError(400, "invalid_category_id", "Choose a valid category ID.");
            if (parsed.has("availability_status") &&
                (parsed["availability_status"].t() != crow::json::type::String ||
                 (parsed["availability_status"].s() != "available" &&
                  parsed["availability_status"].s() != "unavailable")))
                return jsonError(400, "invalid_availability_status", "availability_status must be available or unavailable.");
            crow::json::wvalue body;
            body["title"] = parsed["title"].s();
            body["owner_id"] = auth.userId;
            body["category_id"] = *parsePositiveBigint(parsed["category_id"].s());
            const char* stringFields[] = {"description", "resource_type", "availability_status"};
            for (const char* field : stringFields)
            {
                if (!parsed.has(field))
                    continue;
                if (parsed[field].t() != crow::json::type::String)
                    return jsonError(400, "invalid_request", std::string(field) + " must be a string.");
                body[field] = parsed[field].s();
            }
            if (config.useMarketplaceFeatures)
            {
                const std::string listingMode = parsed.has("listing_mode") && parsed["listing_mode"].t() == crow::json::type::String
                    ? static_cast<std::string>(parsed["listing_mode"].s()) : "borrow";
                const std::string priceKind = parsed.has("borrow_price_kind") && parsed["borrow_price_kind"].t() == crow::json::type::String
                    ? static_cast<std::string>(parsed["borrow_price_kind"].s()) : "free";
                if (listingMode != "borrow" && listingMode != "sell" && listingMode != "donate")
                    return jsonError(400, "invalid_listing_mode", "listing_mode must be borrow, sell, or donate.");
                if (priceKind != "free" && priceKind != "fixed" && priceKind != "per_day" && priceKind != "per_week")
                    return jsonError(400, "invalid_price_kind", "borrow_price_kind is not supported.");
                body["listing_mode"] = listingMode;
                body["borrow_price_kind"] = priceKind;
                const auto positiveNumber = [&](const char* field, bool required, double& output) -> bool {
                    if (!parsed.has(field) || parsed[field].t() == crow::json::type::Null) return !required;
                    if (parsed[field].t() != crow::json::type::Number || parsed[field].d() <= 0) return false;
                    output = parsed[field].d();
                    return true;
                };
                double borrowAmount = 0, originalPrice = 0, salePrice = 0;
                const bool paidBorrow = listingMode == "borrow" && priceKind != "free";
                if (!positiveNumber("borrow_price_amount", paidBorrow, borrowAmount) ||
                    !positiveNumber("sale_original_price", listingMode == "sell", originalPrice) ||
                    !positiveNumber("sale_price", listingMode == "sell", salePrice))
                    return jsonError(400, "invalid_price", "Enter positive prices required for the selected listing type.");
                if (paidBorrow) body["borrow_price_amount"] = borrowAmount;
                if (listingMode == "sell")
                {
                    if (!parsed.has("item_condition") || parsed["item_condition"].t() != crow::json::type::String ||
                        (parsed["item_condition"].s() != "new" && parsed["item_condition"].s() != "like_new" &&
                         parsed["item_condition"].s() != "good" && parsed["item_condition"].s() != "fair"))
                        return jsonError(400, "invalid_condition", "Choose New, Like new, Good, or Fair condition for sale listings.");
                    if (salePrice > originalPrice)
                        return jsonError(400, "invalid_price", "The selling price cannot exceed the original purchase price.");
                    body["item_condition"] = parsed["item_condition"].s();
                    body["sale_original_price"] = originalPrice;
                    body["sale_price"] = salePrice;
                    const auto purchaseYear = parsed.has("purchase_year")
                        ? parsePurchaseYear(parsed["purchase_year"]) : std::nullopt;
                    if (!purchaseYear)
                        return jsonError(400, "invalid_purchase_year", "A valid purchase year from 1900 through the current year is required for sale listings.");
                    body["purchase_year"] = *purchaseYear;
                }
                else if ((parsed.has("sale_original_price") && parsed["sale_original_price"].t() != crow::json::type::Null) ||
                         (parsed.has("sale_price") && parsed["sale_price"].t() != crow::json::type::Null) ||
                         (parsed.has("item_condition") && parsed["item_condition"].t() != crow::json::type::Null) ||
                         (parsed.has("purchase_year") && parsed["purchase_year"].t() != crow::json::type::Null))
                    return jsonError(400, "invalid_listing_fields", "Sale pricing, condition, and purchase year are valid only for sell listings.");
                if (listingMode != "borrow" && (priceKind != "free" ||
                    (parsed.has("borrow_price_amount") && parsed["borrow_price_amount"].t() != crow::json::type::Null)))
                    return jsonError(400, "invalid_listing_fields", "Borrow charges are valid only for borrow listings.");
                if (parsed.has("purchase_year"))
                {
                    if (parsed["purchase_year"].t() == crow::json::type::Null) body["purchase_year"] = nullptr;
                    else
                    {
                        const auto purchaseYear = parsePurchaseYear(parsed["purchase_year"]);
                        if (!purchaseYear)
                            return jsonError(400, "invalid_purchase_year", "purchase_year must be between 1900 and the current year.");
                        body["purchase_year"] = *purchaseYear;
                    }
                }
            }
            const std::string createdProjection = config.useMarketplaceFeatures
                ? "id,title,description,category_id,owner_id,resource_type,availability_status,created_at,listing_mode,borrow_price_kind,borrow_price_amount,sale_original_price,sale_price,item_condition,purchase_year,listing_state"
                : "id,title,description,category_id,owner_id,resource_type,availability_status,created_at";
            const HttpResult upstream = supabase.postgrest(
                "POST", "resources?select=" + createdProjection,
                tokenFromRequest(request), body.dump(), "return=representation");
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
                return upstreamError(upstream, "Could not create resource.");
            const auto result = crow::json::load(upstream.body);
            if (!result || result.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid create response.");
            crow::response response(201, upstream.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request, const std::string& id) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            const std::string projection = config.useMarketplaceFeatures
                ? "id,title,description,category_id,owner_id,resource_type,availability_status,created_at,listing_mode,borrow_price_kind,borrow_price_amount,sale_original_price,sale_price,item_condition,purchase_year,listing_state"
                : "id,title,description,category_id,owner_id,resource_type,availability_status,created_at";
            const HttpResult upstream = supabase.postgrest(
                "GET", "resources?select=" + projection + "&id=eq." + urlEncode(id) + "&limit=1",
                tokenFromRequest(request));
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
                return upstreamError(upstream, "Could not retrieve resource.");
            const auto result = crow::json::load(upstream.body);
            if (!result || result.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid resource response.");
            if (result.size() == 0)
                return jsonError(404, "not_found", "Resource not found.");
            crow::response response(200, upstream.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>")
        .methods(crow::HTTPMethod::Patch)
        ([&](const crow::request& request, const std::string& id) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!config.useAtomicResourceUpdateRpc)
            {
                if (auto ownerError = verifyResourceOwner(request, id, auth.userId))
                    return std::move(*ownerError);
            }
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed) || parsed.size() == 0)
                return jsonError(400, "invalid_request", "A non-empty JSON object is required.");
            for (const auto& item : parsed)
            {
                const std::string key = static_cast<std::string>(item.key());
                const bool baseField = key == "title" || key == "description" || key == "category_id" ||
                    key == "resource_type" || key == "availability_status";
                const bool marketplaceField = config.useMarketplaceFeatures &&
                    (key == "listing_mode" || key == "borrow_price_kind" || key == "borrow_price_amount" ||
                     key == "sale_original_price" || key == "sale_price" || key == "item_condition" || key == "purchase_year");
                if (!baseField && !marketplaceField)
                    return jsonError(400, "invalid_request", "The request contains an unsupported field.");
            }
            if (parsed.has("title") &&
                (parsed["title"].t() != crow::json::type::String || !isNonBlank(parsed["title"].s())))
                return jsonError(400, "invalid_request", "title must be a non-empty string.");
            if (parsed.has("availability_status") &&
                (parsed["availability_status"].t() != crow::json::type::String ||
                 (parsed["availability_status"].s() != "available" &&
                  parsed["availability_status"].s() != "unavailable")))
                return jsonError(400, "invalid_availability_status", "availability_status must be available or unavailable.");
            if (parsed.has("category_id") && parsed["category_id"].t() != crow::json::type::Null &&
                (parsed["category_id"].t() != crow::json::type::String ||
                 !parsePositiveBigint(parsed["category_id"].s()).has_value()))
                return jsonError(400, "invalid_category_id", "category_id must be a positive bigint or null.");

            crow::json::wvalue body;
            const char* stringFields[] = {"title", "description", "category_id", "resource_type", "availability_status"};
            for (const char* field : stringFields)
            {
                if (!parsed.has(field))
                    continue;
                if (parsed[field].t() == crow::json::type::Null &&
                    (std::string(field) == "description" || std::string(field) == "category_id"))
                {
                    body[field] = nullptr;
                    continue;
                }
                if (parsed[field].t() != crow::json::type::String)
                    return jsonError(400, "invalid_request", std::string(field) + " must be a string.");
                if (std::string(field) == "category_id")
                    body[field] = *parsePositiveBigint(parsed[field].s());
                else
                    body[field] = parsed[field].s();
            }

            if (config.useMarketplaceFeatures)
            {
                const char* marketplaceStrings[] = {"listing_mode", "borrow_price_kind", "item_condition"};
                for (const char* field : marketplaceStrings)
                {
                    if (!parsed.has(field)) continue;
                    if (parsed[field].t() != crow::json::type::String)
                        return jsonError(400, "invalid_request", std::string(field) + " must be a string.");
                    const std::string value = parsed[field].s();
                    if ((std::string(field) == "listing_mode" && value != "borrow" && value != "sell" && value != "donate") ||
                        (std::string(field) == "borrow_price_kind" && value != "free" && value != "fixed" && value != "per_day" && value != "per_week") ||
                        (std::string(field) == "item_condition" && value != "new" && value != "like_new" && value != "good" && value != "fair"))
                        return jsonError(400, "invalid_request", std::string(field) + " has an unsupported value.");
                    body[field] = value;
                }
                const char* marketplaceNumbers[] = {"borrow_price_amount", "sale_original_price", "sale_price"};
                for (const char* field : marketplaceNumbers)
                {
                    if (!parsed.has(field)) continue;
                    if (parsed[field].t() == crow::json::type::Null) body[field] = nullptr;
                    else if (parsed[field].t() == crow::json::type::Number && parsed[field].d() > 0)
                        body[field] = parsed[field].d();
                    else return jsonError(400, "invalid_price", std::string(field) + " must be a positive number or null.");
                }
                if (parsed.has("purchase_year"))
                {
                    if (parsed["purchase_year"].t() == crow::json::type::Null) body["purchase_year"] = nullptr;
                    else
                    {
                        const auto purchaseYear = parsePurchaseYear(parsed["purchase_year"]);
                        if (!purchaseYear)
                            return jsonError(400, "invalid_purchase_year", "purchase_year must be between 1900 and the current year or null.");
                        body["purchase_year"] = *purchaseYear;
                    }
                }
            }

            if (config.useMarketplaceFeatures || config.useAtomicResourceUpdateRpc)
            {
                const auto numericResourceId = parsePositiveBigint(id);
                if (!numericResourceId.has_value())
                    return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
                crow::json::wvalue parameters;
                parameters["p_resource_id"] = *numericResourceId;
                parameters["p_changes"] = crow::json::wvalue(crow::json::load(body.dump()));
                const HttpResult rpcResult = supabase.rpc(
                    config.useMarketplaceFeatures ? "update_marketplace_resource_atomic" : "update_resource_atomic",
                    tokenFromRequest(request), parameters.dump());
                if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                    return rpcError(rpcResult, "Could not update resource.");
                const auto rpcRows = crow::json::load(rpcResult.body);
                if (!rpcRows || rpcRows.t() != crow::json::type::List || rpcRows.size() != 1 ||
                    rpcRows[0].t() != crow::json::type::Object)
                    return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid atomic update response.");
                crow::response response(200, rpcResult.body);
                response.set_header("Content-Type", "application/json; charset=utf-8");
                return response;
            }

            const HttpResult upstream = supabase.postgrest(
                "PATCH", "resources?id=eq." + urlEncode(id) +
                             "&select=id,title,description,category_id,owner_id,resource_type,availability_status,created_at",
                tokenFromRequest(request), body.dump(), "return=representation");
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
                return upstreamError(upstream, "Could not update resource.");
            const auto result = crow::json::load(upstream.body);
            if (!result || result.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid update response.");
            if (result.size() == 0)
                return jsonError(404, "not_found", "Resource not found.");
            crow::response response(200, upstream.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>")
        .methods(crow::HTTPMethod::Delete)
        ([&](const crow::request& request, const std::string& id) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto ownerError = verifyResourceOwner(request, id, auth.userId, "Only the owner can delete this resource."))
                return std::move(*ownerError);

            const auto numericId = parsePositiveBigint(id);
            if (!numericId.has_value())
                return jsonError(400, "invalid_request", "resource id must be a positive bigint.");

            // 1. Try atomic RPC if available in database
            crow::json::wvalue rpcParams;
            rpcParams["p_resource_id"] = *numericId;
            const HttpResult rpcResult = supabase.rpc("delete_resource_atomic", tokenFromRequest(request), rpcParams.dump());
            if (rpcResult.curlCode == CURLE_OK && rpcResult.status >= 200 && rpcResult.status < 300)
            {
                return crow::response(204);
            }
            if (rpcResult.status >= 400 && rpcResult.status < 500 && rpcResult.body.find("on an active loan") != std::string::npos)
            {
                return rpcError(rpcResult, "This resource is currently on an active loan. Please confirm its return before deleting.");
            }

            // Fallback: direct PostgREST delete
            // 2. Check for ACTIVE ongoing loans (approved or return_requested)
            const HttpResult activeLoanCheck = supabase.postgrest(
                "GET", "borrow_requests?select=id,status&resource_id=eq." + urlEncode(id) +
                       "&status=in.(approved,return_requested)&limit=1",
                tokenFromRequest(request));
            if (activeLoanCheck.curlCode == CURLE_OK && activeLoanCheck.status >= 200 && activeLoanCheck.status < 300)
            {
                const auto aRows = crow::json::load(activeLoanCheck.body);
                if (aRows && aRows.t() == crow::json::type::List && aRows.size() > 0)
                {
                    return jsonError(409, "active_loan_exists",
                                     "This resource is currently on an active loan. Please confirm its return before deleting.");
                }
            }

            // 3. Cancel any pending borrow requests for this listing
            crow::json::wvalue cancelPayload;
            cancelPayload["status"] = "cancelled";
            supabase.postgrest("PATCH", "borrow_requests?resource_id=eq." + urlEncode(id) + "&status=eq.pending",
                               tokenFromRequest(request), cancelPayload.dump(), "return=minimal");

            // 4. Cancel any pending transfer requests (buy / donate)
            if (config.useMarketplaceFeatures)
            {
                supabase.postgrest("PATCH", "resource_transfer_requests?resource_id=eq." + urlEncode(id) + "&status=eq.pending",
                                   tokenFromRequest(request), cancelPayload.dump(), "return=minimal");
            }

            // 5. Remove dependent auxiliary records that have RESTRICT foreign keys
            supabase.postgrest("DELETE", "resource_handover_details?resource_id=eq." + urlEncode(id),
                               tokenFromRequest(request), {}, "return=minimal");
            supabase.postgrest("DELETE", "resource_images?resource_id=eq." + urlEncode(id),
                               tokenFromRequest(request), {}, "return=minimal");

            // 6. Delete the resource row from resources
            const HttpResult upstream = supabase.postgrest(
                "DELETE", "resources?id=eq." + urlEncode(id), tokenFromRequest(request), {}, "return=minimal");
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
            {
                // If hard delete is rejected by PostgreSQL foreign key constraint (e.g. past completed/returned loans),
                // fall back to safe withdrawal / soft delete as mandated by lifecycle rules
                if (upstream.status == 409 || upstream.status == 400)
                {
                    // Try update_marketplace_resource_atomic first (SECURITY DEFINER with owner authorization)
                    crow::json::wvalue atomicParams;
                    atomicParams["p_resource_id"] = *numericId;
                    atomicParams["p_changes"]["availability_status"] = "unavailable";
                    const HttpResult atomicWithdraw = supabase.rpc(
                        "update_marketplace_resource_atomic", tokenFromRequest(request), atomicParams.dump());
                    if (atomicWithdraw.curlCode == CURLE_OK && atomicWithdraw.status >= 200 && atomicWithdraw.status < 300)
                    {
                        return crow::response(204);
                    }

                    crow::json::wvalue withdrawPayload;
                    withdrawPayload["availability_status"] = "unavailable";
                    withdrawPayload["listing_state"] = "withdrawn";
                    const HttpResult patchResult = supabase.postgrest(
                        "PATCH", "resources?id=eq." + urlEncode(id),
                        tokenFromRequest(request), withdrawPayload.dump(), "return=minimal");
                    if (patchResult.curlCode == CURLE_OK && patchResult.status >= 200 && patchResult.status < 300)
                    {
                        return crow::response(204);
                    }
                }
                return upstreamError(upstream, "Could not delete resource.");
            }
            return crow::response(204);
        });

    const auto marketplaceGate = [&]() -> std::optional<crow::response> {
        if (!config.useMarketplaceFeatures)
            return jsonError(503, "marketplace_disabled",
                             "Marketplace features are disabled until the staging migration and backend cutover are reviewed.");
        return std::nullopt;
    };
    const auto resourceImagesGate = [&]() -> std::optional<crow::response> {
        if (!config.useResourceImages)
            return jsonError(503, "resource_images_disabled",
                             "Resource image APIs are disabled until the staging image schema and Storage policies are reviewed.");
        return std::nullopt;
    };
    const auto communicationGate = [&]() -> std::optional<crow::response> {
        if (!config.useCommunicationFeatures)
            return jsonError(503, "communication_disabled",
                             "Borrowing communication features are disabled until the staging migration is deployed and reviewed.");
        return std::nullopt;
    };
    const auto marketplaceRpc = [&](const crow::request& request, const std::string& function,
                                    crow::json::wvalue parameters, int successStatus,
                                    const std::string& fallback) -> crow::response {
        const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
        if (!auth.verified) return authenticationError(auth);
        if (auto disabled = marketplaceGate()) return std::move(*disabled);
        const HttpResult result = supabase.rpc(function, tokenFromRequest(request), parameters.dump());
        if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
            return rpcError(result, fallback);
        const auto rows = crow::json::load(result.body);
        if (!rows || rows.t() != crow::json::type::List || rows.size() != 1 ||
            rows[0].t() != crow::json::type::Object)
            return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid marketplace RPC response.");
        crow::response response(successStatus, result.body);
        response.set_header("Content-Type", "application/json; charset=utf-8");
        return response;
    };

    CROW_ROUTE(app, "/api/marketplace/transfer-requests")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            const HttpResult result = supabase.postgrest(
                "GET", "resource_transfer_requests?select=id,resource_id,owner_id,requester_id,request_type,status,requested_at,completed_at&limit=100",
                tokenFromRequest(request));
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not retrieve transfer requests.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid transfer-request response.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>/transfer-requests")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            const auto numericId = parsePositiveBigint(resourceId);
            if (!numericId) return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto body = crow::json::load(request.body);
            if (!isJsonObject(body) || body.size() != 1 || !body.has("request_type") ||
                body["request_type"].t() != crow::json::type::String ||
                (body["request_type"].s() != "sell" && body["request_type"].s() != "donate"))
                return jsonError(400, "invalid_request", "request_type must be sell or donate.");
            crow::json::wvalue parameters;
            parameters["p_resource_id"] = *numericId;
            parameters["p_request_type"] = body["request_type"].s();
            return marketplaceRpc(request, "create_resource_transfer_request", std::move(parameters),
                                  201, "Could not create transfer request.");
        });

    const auto invokeTransferStatus = [&](const crow::request& request, const std::string& requestId,
                                          const std::string& function) -> crow::response {
        const auto numericId = parsePositiveBigint(requestId);
        if (!numericId) return jsonError(400, "invalid_request", "transfer request id must be a positive bigint.");
        crow::json::wvalue parameters;
        parameters["p_request_id"] = *numericId;
        return marketplaceRpc(request, function, std::move(parameters), 200,
                              "Could not update transfer request.");
    };
    CROW_ROUTE(app, "/api/marketplace/transfer-requests/<string>/cancel")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& id) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!request.body.empty()) {
                const auto body = crow::json::load(request.body);
                if (!isJsonObject(body) || body.size() != 0)
                    return jsonError(400, "invalid_request", "An empty JSON object is required.");
            }
            return invokeTransferStatus(request, id, "cancel_resource_transfer_request");
        });
    CROW_ROUTE(app, "/api/marketplace/transfer-requests/<string>/approve")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& id) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!request.body.empty()) {
                const auto body = crow::json::load(request.body);
                if (!isJsonObject(body) || body.size() != 0)
                    return jsonError(400, "invalid_request", "An empty JSON object is required.");
            }
            return invokeTransferStatus(request, id, "approve_resource_transfer_request");
        });
    CROW_ROUTE(app, "/api/marketplace/transfer-requests/<string>/reject")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& id) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!request.body.empty()) {
                const auto body = crow::json::load(request.body);
                if (!isJsonObject(body) || body.size() != 0)
                    return jsonError(400, "invalid_request", "An empty JSON object is required.");
            }
            return invokeTransferStatus(request, id, "reject_resource_transfer_request");
        });
    CROW_ROUTE(app, "/api/marketplace/transfer-requests/<string>/complete-sale")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& id) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!request.body.empty()) {
                const auto body = crow::json::load(request.body);
                if (!isJsonObject(body) || body.size() != 0)
                    return jsonError(400, "invalid_request", "An empty JSON object is required.");
            }
            return invokeTransferStatus(request, id, "complete_resource_sale");
        });
    CROW_ROUTE(app, "/api/marketplace/transfer-requests/<string>/complete-donation")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& id) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            if (!request.body.empty()) {
                const auto body = crow::json::load(request.body);
                if (!isJsonObject(body) || body.size() != 0)
                    return jsonError(400, "invalid_request", "An empty JSON object is required.");
            }
            return invokeTransferStatus(request, id, "complete_resource_donation");
        });

    CROW_ROUTE(app, "/api/resources/<string>/images")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = resourceImagesGate()) return std::move(*disabled);
            const auto numericId = parsePositiveBigint(resourceId);
            if (!numericId) return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            const HttpResult result = supabase.postgrest(
                "GET", "resource_images?select=id,resource_id,storage_path,alt_text,sort_order,created_at&resource_id=eq." + std::to_string(*numericId) + "&order=sort_order.asc",
                tokenFromRequest(request));
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not retrieve resource images.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid image response.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>/images")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = resourceImagesGate()) return std::move(*disabled);
            const auto numericId = parsePositiveBigint(resourceId);
            if (!numericId) return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto body = crow::json::load(request.body);
            if (!isJsonObject(body) || body.size() != 1 || !body.has("images") ||
                body["images"].t() != crow::json::type::List || body["images"].size() == 0 || body["images"].size() > 10)
                return jsonError(400, "invalid_request", "images must contain between one and ten image metadata records.");
            crow::json::wvalue::list records;
            const std::string prefix = auth.userId + "/" + std::to_string(*numericId) + "/";
            std::vector<std::string> submittedPaths;
            std::vector<int> submittedOrders;
            for (const auto& image : body["images"])
            {
                if (!isJsonObject(image) || !image.has("storage_path") || image["storage_path"].t() != crow::json::type::String)
                    return jsonError(400, "invalid_image", "Each image must include a storage_path.");
                for (const auto& field : image)
                {
                    const std::string key = static_cast<std::string>(field.key());
                    if (key != "storage_path" && key != "alt_text" && key != "sort_order")
                        return jsonError(400, "invalid_image", "Image metadata contains an unsupported field.");
                }
                const std::string path = image["storage_path"].s();
                const std::string filename = path.rfind(prefix, 0) == 0 ? path.substr(prefix.size()) : std::string{};
                const auto dot = filename.rfind('.');
                std::string extension = dot == std::string::npos ? "" : filename.substr(dot + 1);
                std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char ch) {
                    return static_cast<char>(std::tolower(ch));
                });
                const bool safeFilename = !filename.empty() && filename.size() <= 180 &&
                    filename.find('/') == std::string::npos && filename.find('\\') == std::string::npos &&
                    filename.find("..") == std::string::npos &&
                    std::all_of(filename.begin(), filename.end(), [](unsigned char ch) {
                        return std::isalnum(ch) || ch == '-' || ch == '_' || ch == '.';
                    });
                if (path.rfind(prefix, 0) != 0 || path.size() > 500 || !safeFilename ||
                    (extension != "jpg" && extension != "jpeg" && extension != "png" && extension != "webp") ||
                    std::find(submittedPaths.begin(), submittedPaths.end(), path) != submittedPaths.end())
                    return jsonError(400, "invalid_image_path", "Image storage_path must belong to this user and resource.");
                submittedPaths.push_back(path);
                crow::json::wvalue record;
                record["storage_path"] = path;
                if (image.has("alt_text"))
                {
                    if (image["alt_text"].t() != crow::json::type::String || image["alt_text"].s().size() > 200)
                        return jsonError(400, "invalid_image", "alt_text must be a string of at most 200 characters.");
                    record["alt_text"] = static_cast<std::string>(image["alt_text"].s());
                }
                int sortOrder = static_cast<int>(records.size());
                if (image.has("sort_order"))
                {
                    if (image["sort_order"].t() != crow::json::type::Number)
                        return jsonError(400, "invalid_image", "sort_order must be an integer between 0 and 9.");
                    const auto numberType = image["sort_order"].nt();
                    if (numberType == crow::json::num_type::Signed_integer)
                    {
                        if (image["sort_order"].i() < 0 || image["sort_order"].i() > 9)
                            return jsonError(400, "invalid_image", "sort_order must be an integer between 0 and 9.");
                        sortOrder = static_cast<int>(image["sort_order"].i());
                    }
                    else if (numberType == crow::json::num_type::Unsigned_integer)
                    {
                        if (image["sort_order"].u() > 9)
                            return jsonError(400, "invalid_image", "sort_order must be an integer between 0 and 9.");
                        sortOrder = static_cast<int>(image["sort_order"].u());
                    }
                    else return jsonError(400, "invalid_image", "sort_order must be an integer between 0 and 9.");
                }
                if (std::find(submittedOrders.begin(), submittedOrders.end(), sortOrder) != submittedOrders.end())
                    return jsonError(400, "invalid_image", "Each image must use a distinct sort_order.");
                submittedOrders.push_back(sortOrder);
                record["sort_order"] = sortOrder;
                records.emplace_back(std::move(record));
            }
            const HttpResult existingResult = supabase.postgrest(
                "GET", "resource_images?select=id,sort_order&resource_id=eq." + std::to_string(*numericId) + "&limit=100",
                tokenFromRequest(request));
            if (existingResult.curlCode != CURLE_OK || existingResult.status < 200 || existingResult.status >= 300)
                return upstreamError(existingResult, "Could not validate the current image list.");
            const auto existingRows = crow::json::load(existingResult.body);
            if (!existingRows || existingRows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid current image list.");
            if (existingRows.size() + records.size() > 10)
                return jsonError(409, "image_limit", "A resource can have no more than 10 photos.");
            std::vector<int> existingOrders;
            for (const auto& row : existingRows)
            {
                if (!isJsonObject(row) || !row.has("sort_order") || row["sort_order"].t() != crow::json::type::Number)
                    return jsonError(502, "invalid_upstream_response", "Supabase returned invalid image ordering data.");
                const auto type = row["sort_order"].nt();
                int order = -1;
                if (type == crow::json::num_type::Signed_integer && row["sort_order"].i() >= 0 && row["sort_order"].i() <= 9)
                    order = static_cast<int>(row["sort_order"].i());
                else if (type == crow::json::num_type::Unsigned_integer && row["sort_order"].u() <= 9)
                    order = static_cast<int>(row["sort_order"].u());
                if (order < 0)
                    return jsonError(502, "invalid_upstream_response", "Supabase returned out-of-range image ordering data.");
                existingOrders.push_back(order);
            }
            for (const int order : submittedOrders)
                if (std::find(existingOrders.begin(), existingOrders.end(), order) != existingOrders.end())
                    return jsonError(409, "image_order_conflict", "Remove or reorder existing photos before uploading these images.");
            crow::json::wvalue parameters;
            parameters["p_resource_id"] = *numericId;
            parameters["p_images"] = std::move(records);
            const HttpResult result = supabase.rpc("register_resource_images", tokenFromRequest(request), parameters.dump());
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return rpcError(result, "Could not verify uploaded objects and save image metadata.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List || rows.size() != submittedPaths.size())
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid image metadata response.");
            crow::response response(201, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>/images/reorder")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = resourceImagesGate()) return std::move(*disabled);
            const auto numericResourceId = parsePositiveBigint(resourceId);
            if (!numericResourceId) return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto input = crow::json::load(request.body);
            if (!isJsonObject(input) || input.size() != 1 || !input.has("image_ids") ||
                input["image_ids"].t() != crow::json::type::List || input["image_ids"].size() > 10)
                return jsonError(400, "invalid_request", "image_ids must be an array of at most 10 saved image IDs.");
            crow::json::wvalue::list ids;
            std::vector<std::int64_t> seen;
            for (const auto& value : input["image_ids"]) {
                std::optional<std::int64_t> id;
                if (value.t() == crow::json::type::String) id = parsePositiveBigint(value.s());
                else if (value.t() == crow::json::type::Number && value.nt() == crow::json::num_type::Signed_integer && value.i() > 0)
                    id = value.i();
                else if (value.t() == crow::json::type::Number && value.nt() == crow::json::num_type::Unsigned_integer && value.u() > 0 && value.u() <= static_cast<std::uint64_t>(INT64_MAX))
                    id = static_cast<std::int64_t>(value.u());
                if (!id || std::find(seen.begin(), seen.end(), *id) != seen.end())
                    return jsonError(400, "invalid_image_order", "Image IDs must be unique positive integers.");
                seen.push_back(*id);
                ids.emplace_back(*id);
            }
            crow::json::wvalue parameters;
            parameters["p_resource_id"] = *numericResourceId;
            parameters["p_image_ids"] = std::move(ids);
            const HttpResult result = supabase.rpc("reorder_resource_images", tokenFromRequest(request), parameters.dump());
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return rpcError(result, "Could not reorder resource images.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List || rows.size() != seen.size())
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid image reorder response.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resource-images/<string>")
        .methods(crow::HTTPMethod::Delete)
        ([&](const crow::request& request, const std::string& imageId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = resourceImagesGate()) return std::move(*disabled);
            if (!parsePositiveBigint(imageId))
                return jsonError(400, "invalid_request", "image id must be a positive bigint.");
            const std::string token = tokenFromRequest(request);
            const HttpResult lookup = supabase.postgrest(
                "GET", "resource_images?select=id,resource_id,storage_path&id=eq." + urlEncode(imageId) + "&limit=1", token);
            if (lookup.curlCode != CURLE_OK || lookup.status < 200 || lookup.status >= 300)
                return upstreamError(lookup, "Could not verify image ownership before deletion.");
            const auto imageRows = crow::json::load(lookup.body);
            if (!imageRows || imageRows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned invalid image metadata.");
            if (imageRows.size() == 0)
                return jsonError(404, "not_found", "Image metadata was not found or is not owned by this student.");
            const auto& image = imageRows[0];
            if (!image.has("resource_id") || !image.has("storage_path") ||
                image["storage_path"].t() != crow::json::type::String)
                return jsonError(502, "invalid_upstream_response", "Supabase returned incomplete image metadata.");
            std::optional<std::uint64_t> resourceId;
            if (image["resource_id"].t() == crow::json::type::String)
                resourceId = parsePositiveBigint(image["resource_id"].s());
            else if (image["resource_id"].t() == crow::json::type::Number &&
                     image["resource_id"].nt() == crow::json::num_type::Unsigned_integer)
                resourceId = image["resource_id"].u();
            const std::string storagePath = image["storage_path"].s();
            const std::string resourceIdText = resourceId ? std::to_string(*resourceId) : std::string{};
            if (!resourceId || storagePath.size() > 500)
                return jsonError(403, "permission_denied", "The image path does not identify this resource.");
            if (auto ownerError = verifyResourceOwner(request, resourceIdText, auth.userId))
                return std::move(*ownerError);
            const auto firstSlash = storagePath.find('/');
            const auto secondSlash = firstSlash == std::string::npos ? std::string::npos : storagePath.find('/', firstSlash + 1);
            const auto lastSlash = storagePath.rfind('/');
            const std::string pathOwner = firstSlash == std::string::npos ? std::string{} : storagePath.substr(0, firstSlash);
            const std::string pathResource = firstSlash == std::string::npos || secondSlash == std::string::npos
                ? std::string{} : storagePath.substr(firstSlash + 1, secondSlash - firstSlash - 1);
            const std::string filename = secondSlash == std::string::npos ? std::string{} : storagePath.substr(secondSlash + 1);
            const auto dot = filename.rfind('.');
            std::string extension = dot == std::string::npos ? "" : filename.substr(dot + 1);
            std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char ch) {
                return static_cast<char>(std::tolower(ch));
            });
            const bool safePathOwner = !pathOwner.empty() && pathOwner.size() <= 64 &&
                std::all_of(pathOwner.begin(), pathOwner.end(), [](unsigned char ch) {
                    return std::isalnum(ch) || ch == '-';
                });
            const bool safeFilename = !filename.empty() && filename.size() <= 180 &&
                filename.find('/') == std::string::npos && filename.find('\\') == std::string::npos &&
                filename.find("..") == std::string::npos &&
                std::all_of(filename.begin(), filename.end(), [](unsigned char ch) {
                    return std::isalnum(ch) || ch == '-' || ch == '_' || ch == '.';
                });
            if (!safePathOwner || pathResource != resourceIdText || secondSlash != lastSlash || !safeFilename ||
                (extension != "jpg" && extension != "jpeg" && extension != "png" && extension != "webp"))
                return jsonError(403, "permission_denied", "The image path does not identify this resource.");

            const HttpResult storageDelete = supabase.removeResourceImageObject(storagePath, token);
            if (storageDelete.curlCode != CURLE_OK || storageDelete.status < 200 || storageDelete.status >= 300)
                return upstreamError(storageDelete, "Could not remove the image from private Storage.");

            crow::json::wvalue parameters;
            parameters["p_image_id"] = *parsePositiveBigint(imageId);
            const HttpResult result = supabase.rpc("delete_resource_image_metadata", token, parameters.dump());
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return rpcError(result, "Storage removed the image, but metadata cleanup failed; retry the removal.");
            return crow::response(204);
        });

    CROW_ROUTE(app, "/api/resources/<string>/handover")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            if (!parsePositiveBigint(resourceId))
                return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            const HttpResult result = supabase.postgrest(
                "GET", "resource_handover_details?select=resource_id,pickup_location,meeting_point,preferred_pickup_time,instructions,updated_at&resource_id=eq." + urlEncode(resourceId) + "&limit=1",
                tokenFromRequest(request));
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not retrieve private handover details.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid handover response.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>/handover")
        .methods(crow::HTTPMethod::Put)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            if (!parsePositiveBigint(resourceId))
                return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto input = crow::json::load(request.body);
            if (!isJsonObject(input)) return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& item : input)
            {
                const std::string key = item.key();
                if (key != "pickup_location" && key != "meeting_point" && key != "preferred_pickup_time" && key != "instructions")
                    return jsonError(400, "invalid_request", "Only handover detail fields may be supplied.");
            }
            if (!input.has("pickup_location") || input["pickup_location"].t() != crow::json::type::String ||
                !isNonBlank(input["pickup_location"].s()) || input["pickup_location"].s().size() > 160)
                return jsonError(400, "invalid_handover", "A public campus pickup location of at most 160 characters is required.");
            if (!input.has("meeting_point") || input["meeting_point"].t() != crow::json::type::String ||
                !isNonBlank(input["meeting_point"].s()) || input["meeting_point"].s().size() > 160)
                return jsonError(400, "invalid_handover", "A separate campus meeting point of at most 160 characters is required.");
            crow::json::wvalue payload;
            payload["resource_id"] = resourceId;
            payload["pickup_location"] = input["pickup_location"].s();
            payload["meeting_point"] = input["meeting_point"].s();
            const char* optionalFields[] = {"preferred_pickup_time", "instructions"};
            for (const char* field : optionalFields)
            {
                if (!input.has(field) || input[field].t() == crow::json::type::Null) { payload[field] = nullptr; continue; }
                if (input[field].t() != crow::json::type::String)
                    return jsonError(400, "invalid_handover", std::string(field) + " must be a string or null.");
                const std::string value = input[field].s();
                const std::size_t maximum = std::string(field) == "instructions" ? 1000 : 160;
                if (value.size() > maximum)
                    return jsonError(400, "invalid_handover", std::string(field) + " is too long.");
                payload[field] = value;
            }
            const HttpResult result = supabase.postgrest(
                "POST", "resource_handover_details?on_conflict=resource_id&select=resource_id,pickup_location,meeting_point,preferred_pickup_time,instructions,updated_at",
                tokenFromRequest(request), payload.dump(), "resolution=merge-duplicates,return=representation");
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not save private handover details.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List || rows.size() != 1)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid handover update response.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/resources/<string>/reports")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& resourceId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            const auto id = parsePositiveBigint(resourceId);
            if (!id) return jsonError(400, "invalid_request", "resource id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto input = crow::json::load(request.body);
            if (!isJsonObject(input)) return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& item : input)
            {
                const std::string key = item.key();
                if (key != "reason" && key != "details")
                    return jsonError(400, "invalid_request", "Only a report reason and optional details may be supplied.");
            }
            if (!input.has("reason") || input["reason"].t() != crow::json::type::String)
                return jsonError(400, "invalid_report", "Choose a report reason.");
            const std::string reason = input["reason"].s();
            const std::vector<std::string> reasons = {"misleading_original_price","unreasonable_selling_price","incorrect_description","suspicious_listing","other"};
            if (std::find(reasons.begin(), reasons.end(), reason) == reasons.end())
                return jsonError(400, "invalid_report", "The selected report reason is not supported.");
            crow::json::wvalue payload;
            payload["resource_id"] = *id;
            payload["reporter_id"] = auth.userId;
            payload["reason"] = reason;
            payload["status"] = "pending";
            payload["moderator_notes"] = nullptr;
            if (input.has("details"))
            {
                if (input["details"].t() != crow::json::type::String || input["details"].s().size() > 2000)
                    return jsonError(400, "invalid_report", "details must be a string up to 2000 characters.");
                payload["details"] = input["details"].s();
            }
            const HttpResult result = supabase.postgrest(
                "POST", "resource_listing_reports?select=id,resource_id,reporter_id,reason,details,status,created_at",
                tokenFromRequest(request), payload.dump(), "return=representation");
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not submit listing report.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List || rows.size() != 1)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid report response.");
            crow::response response(201, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/marketplace/reports")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            const HttpResult result = supabase.postgrest(
                "GET", "resource_listing_reports?select=id,resource_id,reporter_id,reason,details,status,created_at&order=created_at.desc&limit=100",
                tokenFromRequest(request));
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not retrieve your listing reports.");
            const auto rows = crow::json::load(result.body);
            if (!rows || rows.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid report list.");
            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/marketplace/reports/<string>/review")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& reportId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified) return authenticationError(auth);
            if (auto disabled = marketplaceGate()) return std::move(*disabled);
            const auto numericId = parsePositiveBigint(reportId);
            if (!numericId) return jsonError(400, "invalid_request", "report id must be a positive bigint.");
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto input = crow::json::load(request.body);
            if (!isJsonObject(input)) return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& field : input) {
                const std::string key = field.key();
                if (key != "outcome" && key != "notes")
                    return jsonError(400, "invalid_request", "Only a moderation outcome and notes may be supplied.");
            }
            if (!input.has("outcome") || input["outcome"].t() != crow::json::type::String ||
                (input["outcome"].s() != "resolved" && input["outcome"].s() != "dismissed"))
                return jsonError(400, "invalid_report_review", "outcome must be resolved or dismissed.");
            crow::json::wvalue parameters;
            parameters["p_report_id"] = *numericId;
            parameters["p_outcome"] = input["outcome"].s();
            if (input.has("notes")) {
                if (input["notes"].t() == crow::json::type::Null) parameters["p_notes"] = nullptr;
                else if (input["notes"].t() == crow::json::type::String && input["notes"].s().size() <= 1000)
                    parameters["p_notes"] = input["notes"].s();
                else return jsonError(400, "invalid_report_review", "notes must be a string up to 1000 characters or null.");
            } else parameters["p_notes"] = nullptr;
            return marketplaceRpc(request, "review_resource_listing_report", std::move(parameters), 200,
                                  "Could not review listing report.");
        });

    CROW_ROUTE(app, "/api/borrow-requests")
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            const HttpResult upstream = supabase.postgrest(
                "GET", "borrow_requests?select=id,resource_id,borrower_id,requested_at,due_at,returned_at,status&limit=100",
                tokenFromRequest(request));
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
                return upstreamError(upstream, "Could not retrieve borrowing requests.");
            const auto result = crow::json::load(upstream.body);
            if (!result || result.t() != crow::json::type::List)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid borrowing requests response.");
            crow::response response(200, upstream.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/borrow-requests")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& item : parsed)
            {
                const std::string key = static_cast<std::string>(item.key());
                if (key != "resource_id" && key != "due_at")
                    return jsonError(400, "invalid_request", "The request contains an unsupported field.");
            }
            if (!parsed.has("resource_id") ||
                (parsed["resource_id"].t() != crow::json::type::String &&
                 parsed["resource_id"].t() != crow::json::type::Number))
                return jsonError(400, "invalid_request", "resource_id is required.");

            const auto& resourceValue = parsed["resource_id"];
            std::string resourceId;
            if (resourceValue.t() == crow::json::type::String)
                resourceId = static_cast<std::string>(resourceValue.s());
            else if (resourceValue.nt() == crow::json::num_type::Signed_integer)
                resourceId = std::to_string(resourceValue.i());
            else if (resourceValue.nt() == crow::json::num_type::Unsigned_integer)
                resourceId = std::to_string(resourceValue.u());
            if (resourceId.empty())
                return jsonError(400, "invalid_request", "resource_id must be a non-empty integer ID.");

            std::string dueAt;
            if (parsed.has("due_at") && parsed["due_at"].t() != crow::json::type::Null)
            {
                if (parsed["due_at"].t() != crow::json::type::String ||
                    !isUtcTimestamp(static_cast<std::string>(parsed["due_at"].s())))
                    return jsonError(400, "invalid_date", "due_at must be null or a valid UTC timestamp.");
                dueAt = static_cast<std::string>(parsed["due_at"].s());
                if (dueAt.size() == 24)
                    dueAt = dueAt.substr(0, 19) + "Z";
            }

            const std::string currentTime = currentUtcTimestamp();
            if (currentTime.empty())
                return jsonError(500, "internal_error", "Could not validate the due date.");
            if (!dueAt.empty() && dueAt < currentTime)
                return jsonError(400, "invalid_date", "due_at must not be earlier than the current time.");

            const auto numericResourceId = parsePositiveBigint(resourceId);
            if (!numericResourceId.has_value())
                return jsonError(400, "invalid_request", "resource_id must be a positive bigint ID.");
            if (!config.useBorrowRequestRpc)
                return jsonError(503, "borrow_requests_pending",
                                 "Borrow request submission is disabled until the secure Supabase RPC is installed and verified in staging.");

            crow::json::wvalue parameters;
            parameters["p_resource_id"] = *numericResourceId;
            if (dueAt.empty())
                parameters["p_due_at"] = nullptr;
            else
                parameters["p_due_at"] = dueAt;
            const HttpResult rpcResult = supabase.rpc(
                "create_borrow_request", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not create borrowing request.");
            const auto rpcRows = crow::json::load(rpcResult.body);
            if (!rpcRows || rpcRows.t() != crow::json::type::List || rpcRows.size() != 1 ||
                rpcRows[0].t() != crow::json::type::Object)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid RPC response.");
            crow::response response(201, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    const auto invokeBorrowStatusRpc = [&](const crow::request& request,
                                           const std::string& requestId,
                                           const std::string& functionName,
                                           crow::json::wvalue parameters) -> crow::response {
        const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
        if (!auth.verified)
            return authenticationError(auth);
        if (!config.useBorrowStatusRpc || !config.useAtomicResourceUpdateRpc)
            return jsonError(503, "borrow_status_pending",
                             "Borrow request status actions are disabled until the staging RPC package is deployed and verified.");
        const auto numericRequestId = parsePositiveBigint(requestId);
        if (!numericRequestId.has_value())
            return jsonError(400, "invalid_request", "request id must be a positive bigint.");
        parameters["p_request_id"] = *numericRequestId;
        const HttpResult rpcResult = supabase.rpc(
            functionName, tokenFromRequest(request), parameters.dump());
        if (rpcResult.curlCode == CURLE_OK && rpcResult.status >= 200 && rpcResult.status < 300)
        {
            const auto rows = crow::json::load(rpcResult.body);
            if (!rows || rows.t() != crow::json::type::List || rows.size() != 1 ||
                rows[0].t() != crow::json::type::Object)
                return jsonError(502, "invalid_upstream_response", "Supabase returned an invalid status update response.");
            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        }

        // If functionName is return_borrowed_resource and RPC failed (e.g. unassigned variable bug or missing RPC in Supabase),
        // execute direct verified PostgREST return fallback
        if (functionName == "return_borrowed_resource")
        {
            // 1. Fetch borrow request to check status and resource_id
            const HttpResult reqCheck = supabase.postgrest(
                "GET", "borrow_requests?id=eq." + urlEncode(requestId) + "&select=id,resource_id,borrower_id,status,requested_at,due_at,returned_at&limit=1",
                tokenFromRequest(request));
            if (reqCheck.curlCode == CURLE_OK && reqCheck.status >= 200 && reqCheck.status < 300)
            {
                const auto rRows = crow::json::load(reqCheck.body);
                if (rRows && rRows.t() == crow::json::type::List && rRows.size() > 0)
                {
                    const auto& bReq = rRows[0];
                    const std::string bStatus = bReq.has("status") ? static_cast<std::string>(bReq["status"].s()) : "";
                    if (bStatus == "returned")
                    {
                        return jsonError(409, "already_returned", "This request has already been returned.");
                    }
                    if (bStatus != "approved" && bStatus != "return_requested")
                    {
                        return jsonError(409, "invalid_state", "Request is not active.");
                    }

                    const std::string resId = bReq.has("resource_id") ? std::to_string(bReq["resource_id"].i()) : "";
                    // 2. Fetch resource to verify that authenticated user is the owner
                    const HttpResult resCheck = supabase.postgrest(
                        "GET", "resources?id=eq." + urlEncode(resId) + "&select=id,owner_id,availability_status&limit=1",
                        tokenFromRequest(request));
                    if (resCheck.curlCode == CURLE_OK && resCheck.status >= 200 && resCheck.status < 300)
                    {
                        const auto resRows = crow::json::load(resCheck.body);
                        if (resRows && resRows.t() == crow::json::type::List && resRows.size() > 0)
                        {
                            const std::string ownerId = resRows[0].has("owner_id") ? static_cast<std::string>(resRows[0]["owner_id"].s()) : "";
                            if (ownerId != auth.userId)
                            {
                                return jsonError(403, "forbidden", "Only the resource owner may return this request");
                            }

                            // 3. Mark borrow request as returned
                            crow::json::wvalue retPayload;
                            retPayload["status"] = "returned";
                            const std::string stamp = currentUtcTimestamp();
                            if (!stamp.empty())
                                retPayload["returned_at"] = stamp;

                            const HttpResult patchReq = supabase.postgrest(
                                "PATCH", "borrow_requests?id=eq." + urlEncode(requestId) + "&status=in.(approved,return_requested)",
                                tokenFromRequest(request), retPayload.dump(), "return=representation");

                            // 4. Mark resource as available again
                            crow::json::wvalue availPayload;
                            availPayload["availability_status"] = "available";
                            supabase.postgrest(
                                "PATCH", "resources?id=eq." + urlEncode(resId),
                                tokenFromRequest(request), availPayload.dump(), "return=minimal");

                            if (patchReq.curlCode == CURLE_OK && patchReq.status >= 200 && patchReq.status < 300)
                            {
                                crow::response resp(200, patchReq.body);
                                resp.set_header("Content-Type", "application/json; charset=utf-8");
                                return resp;
                            }
                        }
                    }
                }
            }
        }

        return rpcError(rpcResult, "Could not update borrowing request status.");
    };

    CROW_ROUTE(app, "/api/borrow-requests/<string>/approve")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& requestId) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");
            for (const auto& item : parsed)
            {
                if (static_cast<std::string>(item.key()) != "due_at")
                    return jsonError(400, "invalid_request", "Only due_at may be supplied when approving a request.");
            }
            crow::json::wvalue parameters;
            if (parsed.has("due_at") && parsed["due_at"].t() != crow::json::type::Null)
            {
                if (parsed["due_at"].t() != crow::json::type::String ||
                    !isUtcTimestamp(static_cast<std::string>(parsed["due_at"].s())))
                    return jsonError(400, "invalid_date", "due_at must be null or a valid UTC timestamp.");
                std::string approvedDue = static_cast<std::string>(parsed["due_at"].s());
                if (approvedDue.size() == 24)
                    approvedDue = approvedDue.substr(0, 19) + "Z";
                parameters["p_due_at"] = std::move(approvedDue);
            }
            else
                parameters["p_due_at"] = nullptr;
            return invokeBorrowStatusRpc(request, requestId, "approve_borrow_request",
                                         std::move(parameters));
        });

    CROW_ROUTE(app, "/api/borrow-requests/<string>/reject")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& requestId) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed) || parsed.size() != 0)
                return jsonError(400, "invalid_request", "An empty JSON object is required.");
            return invokeBorrowStatusRpc(request, requestId, "reject_borrow_request", {});
        });

    CROW_ROUTE(app, "/api/borrow-requests/<string>/return")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& requestId) {
            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");
            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed) || parsed.size() != 0)
                return jsonError(400, "invalid_request", "An empty JSON object is required.");
            return invokeBorrowStatusRpc(request, requestId, "return_borrowed_resource", {});
        });

    CROW_ROUTE(app, "/api/conversations")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            const HttpResult rpcResult = supabase.rpc("get_my_conversations", tokenFromRequest(request), "{}");
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not retrieve conversations.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/conversations/<string>/messages")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request, const std::string& conversationId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(conversationId))
                return jsonError(400, "invalid_request", "conversation_id must be a valid UUID.");

            crow::json::wvalue parameters;
            parameters["p_conversation_id"] = conversationId;
            const HttpResult rpcResult = supabase.rpc("get_conversation_messages", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not retrieve message history.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/conversations/<string>/messages")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& conversationId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(conversationId))
                return jsonError(400, "invalid_request", "conversation_id must be a valid UUID.");

            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");

            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");

            if (!parsed.has("content") || parsed["content"].t() != crow::json::type::String)
                return jsonError(400, "invalid_request", "content is required and must be a string.");

            if (!parsed.has("client_idempotency_key") || parsed["client_idempotency_key"].t() != crow::json::type::String)
                return jsonError(400, "invalid_request", "client_idempotency_key is required and must be a string.");

            const std::string content = trim(static_cast<std::string>(parsed["content"].s()));
            const std::string idempotencyKey = trim(static_cast<std::string>(parsed["client_idempotency_key"].s()));

            if (content.empty() || content.size() > 2000)
                return jsonError(400, "invalid_request", "content must be between 1 and 2000 characters.");

            if (idempotencyKey.size() < 8 || idempotencyKey.size() > 128)
                return jsonError(400, "invalid_request", "client_idempotency_key must be between 8 and 128 characters.");

            crow::json::wvalue parameters;
            parameters["p_conversation_id"] = conversationId;
            parameters["p_content"] = content;
            parameters["p_idempotency_key"] = idempotencyKey;

            const HttpResult rpcResult = supabase.rpc("send_message", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not send message.");

            crow::response response(201, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/conversations/<string>/meetings")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request, const std::string& conversationId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(conversationId))
                return jsonError(400, "invalid_request", "conversation_id must be a valid UUID.");

            crow::json::wvalue parameters;
            parameters["p_conversation_id"] = conversationId;
            const HttpResult rpcResult = supabase.rpc("get_conversation_proposals", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not retrieve meeting proposals.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/conversations/<string>/meetings")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& conversationId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(conversationId))
                return jsonError(400, "invalid_request", "conversation_id must be a valid UUID.");

            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");

            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");

            if (!parsed.has("meeting_date") || parsed["meeting_date"].t() != crow::json::type::String ||
                !parsed.has("meeting_time") || parsed["meeting_time"].t() != crow::json::type::String ||
                !parsed.has("location") || parsed["location"].t() != crow::json::type::String)
                return jsonError(400, "invalid_request", "meeting_date, meeting_time, and location are required.");

            std::string meetingType = "handover";
            if (parsed.has("meeting_type") && parsed["meeting_type"].t() == crow::json::type::String)
                meetingType = static_cast<std::string>(parsed["meeting_type"].s());

            if (meetingType != "handover" && meetingType != "return")
                return jsonError(400, "invalid_request", "meeting_type must be handover or return.");

            const std::string meetingDate = trim(static_cast<std::string>(parsed["meeting_date"].s()));
            const std::string meetingTime = trim(static_cast<std::string>(parsed["meeting_time"].s()));
            const std::string location = trim(static_cast<std::string>(parsed["location"].s()));

            if (meetingDate.size() != 10 || meetingDate[4] != '-' || meetingDate[7] != '-')
                return jsonError(400, "invalid_request", "meeting_date must be in YYYY-MM-DD format.");

            if (meetingTime.size() != 5 || meetingTime[2] != ':')
                return jsonError(400, "invalid_request", "meeting_time must be in HH:MM format.");

            if (location.size() < 2 || location.size() > 255)
                return jsonError(400, "invalid_request", "location must be between 2 and 255 characters.");

            crow::json::wvalue parameters;
            parameters["p_conversation_id"] = conversationId;
            parameters["p_meeting_type"] = meetingType;
            parameters["p_meeting_date"] = meetingDate;
            parameters["p_meeting_time"] = meetingTime;
            parameters["p_location"] = location;

            if (parsed.has("notes") && parsed["notes"].t() == crow::json::type::String)
            {
                const std::string notes = trim(static_cast<std::string>(parsed["notes"].s()));
                if (notes.size() > 500)
                    return jsonError(400, "invalid_request", "notes must not exceed 500 characters.");
                parameters["p_notes"] = notes;
            }
            else
            {
                parameters["p_notes"] = nullptr;
            }

            const HttpResult rpcResult = supabase.rpc("propose_meeting", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not propose meeting.");

            crow::response response(201, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/meetings/<string>/respond")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& proposalId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(proposalId))
                return jsonError(400, "invalid_request", "proposal_id must be a valid UUID.");

            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");

            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed) || !parsed.has("action") || parsed["action"].t() != crow::json::type::String)
                return jsonError(400, "invalid_request", "action is required ('accept', 'decline', or 'cancel').");

            const std::string action = static_cast<std::string>(parsed["action"].s());
            if (action != "accept" && action != "decline" && action != "cancel")
                return jsonError(400, "invalid_request", "action must be accept, decline, or cancel.");

            crow::json::wvalue parameters;
            parameters["p_proposal_id"] = proposalId;
            parameters["p_action"] = action;

            const HttpResult rpcResult = supabase.rpc("respond_to_meeting_proposal", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not update meeting proposal.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/notifications")
        .methods(crow::HTTPMethod::Get)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            const HttpResult result = supabase.postgrest(
                "GET", "notifications?select=id,user_id,type,title,body,reference_id,is_read,created_at&order=created_at.desc&limit=50",
                tokenFromRequest(request));
            if (result.curlCode != CURLE_OK || result.status < 200 || result.status >= 300)
                return upstreamError(result, "Could not retrieve notifications.");

            crow::response response(200, result.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/notifications/mark-read")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");

            const auto parsed = crow::json::load(request.body);
            if (!isJsonObject(parsed))
                return jsonError(400, "invalid_request", "A JSON object is required.");

            crow::json::wvalue parameters;
            if (parsed.has("mark_all") && parsed["mark_all"].t() == crow::json::type::True)
            {
                parameters["p_mark_all"] = true;
                parameters["p_notification_ids"] = nullptr;
            }
            else if (parsed.has("ids") && parsed["ids"].t() == crow::json::type::List)
            {
                std::vector<std::string> ids;
                for (const auto& item : parsed["ids"])
                {
                    if (item.t() == crow::json::type::String && isValidUuid(static_cast<std::string>(item.s())))
                        ids.push_back(static_cast<std::string>(item.s()));
                }
                parameters["p_mark_all"] = false;
                parameters["p_notification_ids"] = std::move(ids);
            }
            else
            {
                parameters["p_mark_all"] = false;
                parameters["p_notification_ids"] = nullptr;
            }

            const HttpResult rpcResult = supabase.rpc("mark_notifications_read", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not mark notifications as read.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/conversations/<string>/return-request")
        .methods(crow::HTTPMethod::Post)
        ([&](const crow::request& request, const std::string& conversationId) {
            const AuthResult auth = supabase.verifyAccessToken(request.get_header_value("Authorization"));
            if (!auth.verified)
                return authenticationError(auth);
            if (auto disabled = communicationGate())
                return std::move(*disabled);

            if (!isValidUuid(conversationId))
                return jsonError(400, "invalid_request", "conversation_id must be a valid UUID.");

            if (request.body.size() > maxMutationBodyBytes)
                return jsonError(413, "payload_too_large", "Request body exceeds the 16 KiB limit.");

            crow::json::wvalue parameters;
            parameters["p_conversation_id"] = conversationId;

            const HttpResult rpcResult = supabase.rpc("request_return", tokenFromRequest(request), parameters.dump());
            if (rpcResult.curlCode != CURLE_OK || rpcResult.status < 200 || rpcResult.status >= 300)
                return rpcError(rpcResult, "Could not request resource return.");

            crow::response response(200, rpcResult.body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            return response;
        });

    CROW_ROUTE(app, "/api/<path>")
        .methods(crow::HTTPMethod::Get, crow::HTTPMethod::Post,
                 crow::HTTPMethod::Put, crow::HTTPMethod::Patch,
                 crow::HTTPMethod::Delete, crow::HTTPMethod::Options)
        ([&](const crow::request& request, const std::string&) {
            if (request.method == crow::HTTPMethod::Options)
                return crow::response(204);
            return jsonError(404, "not_found", "API route not found.");
        });

    try
    {
        auto server = app.bindaddr(config.host).port(config.port).concurrency(4).run_async();
        const auto startupStatus = app.wait_for_server_start(std::chrono::seconds(5));
        if (startupStatus != std::cv_status::no_timeout || !app.is_bound())
        {
            if (server.wait_for(std::chrono::milliseconds(0)) == std::future_status::ready)
            {
                server.get();
            }
            else
            {
                app.stop();
                server.wait();
                server.get();
            }
            std::cerr << "CampusShare backend failed to become ready on "
                      << config.host << ':' << config.port
                      << " within 5 seconds. Check the bind address and whether the port is available.\n";
            curl_global_cleanup();
            return 1;
        }

        std::cout << "CampusShare backend listening on " << config.host << ':'
                  << config.port << std::endl;
        server.get();
    }
    catch (const std::exception& error)
    {
        std::cerr << "CampusShare backend startup/runtime error: "
                  << error.what() << '\n';
        curl_global_cleanup();
        return 1;
    }
    catch (...)
    {
        std::cerr << "CampusShare backend startup/runtime error: unknown failure.\n";
        curl_global_cleanup();
        return 1;
    }
    curl_global_cleanup();
    return 0;
}
