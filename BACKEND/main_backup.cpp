#include "crow.h"

int main()
{
    crow::SimpleApp app;

    CROW_ROUTE(app, "/api/health")
    ([]()
    {
        crow::json::wvalue response;
        response["status"] = "success";
        response["message"] = "CampusShare backend is running";

        return response;
    });

    app.port(18080).multithreaded().run();

    return 0;
}