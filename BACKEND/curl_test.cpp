#include <iostream>
#include <fstream>
#include <string>
#include <curl/curl.h>

int main()
{
    std::ifstream config("E:/CampusShare/config.txt");

    if (!config.is_open())
    {
        std::cout << "Failed to open config.txt\n";
        return 1;
    }

    std::string line;
    std::string supabaseUrl;
    std::string supabaseKey;

    while (std::getline(config, line))
    {
        if (line.find("SUPABASE_URL=") == 0)
            supabaseUrl = line.substr(13);

        else if (line.find("SUPABASE_KEY=") == 0)
            supabaseKey = line.substr(13);
    }

    config.close();

    if (supabaseUrl.empty() || supabaseKey.empty())
    {
        std::cout << "Supabase URL or key is missing in config.txt\n";
        return 1;
    }

    CURL* curl = curl_easy_init();

    if (curl == nullptr)
    {
        std::cout << "Failed to initialize libcurl\n";
        return 1;
    }

    std::string apiUrl = supabaseUrl + "/rest/v1/categories";

    struct curl_slist* headers = nullptr;

    headers = curl_slist_append(
        headers, ("apikey: " + supabaseKey).c_str());

    curl_easy_setopt(curl, CURLOPT_URL, apiUrl.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, nullptr);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "CampusShare/1.0");

    CURLcode result = curl_easy_perform(curl);

    if (result != CURLE_OK)
    {
        std::cout << "\nRequest failed: "
                  << curl_easy_strerror(result) << '\n';
    }

    long statusCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);

    std::cout << "\nHTTP Status: " << statusCode << '\n';

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return 0;
}