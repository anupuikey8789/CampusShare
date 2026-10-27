#include "crow.h"
#include <curl/curl.h>
#include <fstream>
#include <string>

std::string supabaseUrl;
std::string supabaseKey;

size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* output)
{
    output->append(static_cast<char*>(contents), size * nmemb);
    return size * nmemb;
}

bool LoadConfig()
{
    std::ifstream config("E:/CampusShare/config.txt");

    if (!config.is_open())
        return false;

    std::string line;

    while (std::getline(config, line))
    {
        if (line.find("SUPABASE_URL=") == 0)
            supabaseUrl = line.substr(13);

        else if (line.find("SUPABASE_KEY=") == 0)
            supabaseKey = line.substr(13);
    }

    return !supabaseUrl.empty() && !supabaseKey.empty();
}

int main()
{
    if (!LoadConfig())
    {
        std::cout << "Failed to load Supabase configuration.\n";
        return 1;
    }

    crow::SimpleApp app;

    CROW_ROUTE(app, "/api/test")
        ([]()
        {
        return "Crow routes are working";
        });

    CROW_ROUTE(app, "/api/health")
    ([]()
    {
        crow::json::wvalue response;
        response["status"] = "success";
        response["message"] = "CampusShare backend is running";
        return response;
    });

    CROW_ROUTE(app, "/api/categories")
    ([]()
    {
        CURL* curl = curl_easy_init();

        if (curl == nullptr)
            return crow::response(500, "Failed to initialize libcurl");

        std::string apiUrl = supabaseUrl + "/rest/v1/categories";
        std::string responseBody;

        struct curl_slist* headers = nullptr;
        headers = curl_slist_append(
            headers, ("apikey: " + supabaseKey).c_str());

        curl_easy_setopt(curl, CURLOPT_URL, apiUrl.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &responseBody);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "CampusShare/1.0");

        CURLcode result = curl_easy_perform(curl);

        long statusCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        if (result != CURLE_OK)
            return crow::response(502, "Supabase request failed");

        crow::response response(
            static_cast<int>(statusCode), responseBody);

        response.set_header("Content-Type", "application/json");
        return response;
    });

    app.port(18080).multithreaded().run();

    return 0;
}