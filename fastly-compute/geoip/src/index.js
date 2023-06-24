/// <reference types="@fastly/js-compute" />

import {
    getGeolocationForIpAddress
} from "fastly:geolocation"
import {
    ConfigStore
} from "fastly:config-store";

async function app(event) {
    try {
        const configStore = new ConfigStore('geoip_auth')

        // Fetch token from X-Secret header
        var token = event.request.headers.get('X-Secret');
        // Check if the auth token exists in the ConfigStore
        var auth = await configStore.get(token)

        // If the value doesn't exist or is false, return Unauthorized
        if (!auth) {
            let respBody = JSON.stringify({
                Error: "Unauthorized"
            });
            return new Response(respBody, {
                status: 401,
                headers: {
                    'Content-Type': 'application/json'
                }
            });
        }
        let ip = new URL(event.request.url).searchParams.get('ip') || event.client.address
        let geo = getGeolocationForIpAddress(ip);
        let respBody = JSON.stringify({
            geo: {
                city: geo.city,
                continent: geo.continent,
                country_code: geo.country_code,
                country_code3: geo.country_code3,
                country_name: geo.country_name,
                region: geo.region,
            },
        });

        return new Response(respBody, {
            headers: {
                "Content-Type": "application/json",
            },
        });
    } catch (error) {
        console.error(error);
        return new Response("Internal Server Error", {
            status: 500
        });
    }
}

addEventListener("fetch", (event) => event.respondWith(app(event)));
