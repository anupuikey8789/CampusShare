#include <iostream>
#include <string>
#include <curl/curl.h>
#include <cstdlib>

static size_t WriteCallback(char* data, size_t size, size_t count, void* output)
{
    const size_t bytes = size * count;
    static_cast<std::string*>(output)->append(data, bytes);
    return bytes;
}

int main()
{
    const char* urlValue = std::getenv("SUPABASE_URL");
    const char* keyValue = std::getenv("SUPABASE_ANON_KEY");
    if (keyValue == nullptr)
        keyValue = std::getenv("SUPABASE_KEY"); // legacy alias
    const std::string supabaseUrl = urlValue == nullptr ? "" : urlValue;
    const std::string supabaseKey = keyValue == nullptr ? "" : keyValue;

    if (supabaseUrl.empty() || supabaseKey.empty())
    {
        std::cerr << "Set SUPABASE_URL and SUPABASE_ANON_KEY in the environment.\n";
        return 1;
    }

    if (supabaseKey.rfind("sb_secret_", 0) == 0)
    {
        std::cerr << "Do not use a Supabase secret key in this utility.\n";
        return 1;
    }

    CURL* curl = curl_easy_init();

    if (curl == nullptr)
    {
        std::cout << "Failed to initialize libcurl\n";
        return 1;
    }

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
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 5L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);

    CURLcode result = curl_easy_perform(curl);

    if (result != CURLE_OK)
    {
        std::cout << "\nRequest failed: "
                  << curl_easy_strerror(result) << '\n';
    }

    long statusCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);

    std::cout << "\nHTTP Status: " << statusCode << '\n' << responseBody << '\n';

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return 0;
}
