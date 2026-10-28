#include "crow.h"
#include <curl/curl.h>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace
{
struct Config
{
    std::string supabaseUrl;
    std::string supabaseAnonKey;
    std::string host = "127.0.0.1";
    unsigned short port = 18080;
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

bool loadConfig(Config& config)
{
    loadDotEnv();
    config.supabaseUrl = env("SUPABASE_URL");
    config.supabaseAnonKey = env("SUPABASE_ANON_KEY", env("SUPABASE_KEY"));
    config.host = env("SERVER_HOST", config.host);
    const std::string portValue = env("SERVER_PORT", "18080");
    if (!parsePort(portValue, config.port))
    {
        std::cerr << "Invalid SERVER_PORT; expected an integer from 1 to 65535.\n";
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

class SupabaseClient
{
public:
    explicit SupabaseClient(const Config& config) : config_(config) {}

    HttpResult get(const std::string& path) const
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

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
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

private:
    const Config& config_;
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

void applyCors(const crow::request& request, crow::response& response,
               const Config& config)
{
    const std::string origin = request.get_header_value("Origin");
    if (std::find(config.allowedOrigins.begin(), config.allowedOrigins.end(), origin) !=
        config.allowedOrigins.end())
    {
        response.set_header("Access-Control-Allow-Origin", origin);
        response.set_header("Vary", "Origin");
        response.set_header("Access-Control-Allow-Methods", "GET, OPTIONS");
        response.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization");
        response.set_header("Access-Control-Max-Age", "600");
    }
    response.set_header("X-Content-Type-Options", "nosniff");
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

    crow::SimpleApp app;
    app.loglevel(crow::LogLevel::Warning);
    SupabaseClient supabase(config);

    CROW_ROUTE(app, "/api/test")
        ([&](const crow::request& request) {
            crow::json::wvalue body;
            body["status"] = "success";
            body["message"] = "Crow routes are working";
            crow::response response(body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            applyCors(request, response, config);
            return response;
        });

    CROW_ROUTE(app, "/api/health")
        ([&](const crow::request& request) {
            crow::json::wvalue body;
            body["status"] = "ok";
            body["service"] = "CampusShare backend";
            crow::response response(body);
            response.set_header("Content-Type", "application/json; charset=utf-8");
            applyCors(request, response, config);
            return response;
        });

    CROW_ROUTE(app, "/api/categories")
        ([&](const crow::request& request) {
            const HttpResult upstream = supabase.get("/rest/v1/categories?select=*&limit=100");
            crow::response response;
            if (upstream.curlCode != CURLE_OK || upstream.status < 200 || upstream.status >= 300)
            {
                response = jsonError(502, "upstream_error", "Could not retrieve categories.");
                std::cerr << "Categories request failed (curl=" << upstream.curlCode
                          << ", HTTP=" << upstream.status << ").\n";
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
            applyCors(request, response, config);
            return response;
        });

    CROW_ROUTE(app, "/api/<path>").methods(crow::HTTPMethod::Options)
        ([&](const crow::request& request, const std::string&) {
            crow::response response(204);
            applyCors(request, response, config);
            return response;
        });

    std::cout << "CampusShare backend listening on " << config.host << ':'
              << config.port << std::endl;
    app.bindaddr(config.host).port(config.port).concurrency(4).run();
    curl_global_cleanup();
    return 0;
}
