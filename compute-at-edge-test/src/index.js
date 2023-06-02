/// <reference types="@fastly/js-compute" />

import { getGeolocationForIpAddress } from "fastly:geolocation"
async function app(event) {
  try {
    let ip = new URL(event.request.url).searchParams.get('ip') || event.client.address
    let geo = getGeolocationForIpAddress(ip);
    let respBody = JSON.stringify({
      geo: {
        city: geo.city,
        continent: geo.continent,
        country_code: geo.country_code,
        country_code3: geo.country_code3,
        country_name: geo.country_name,
        region: null,
      },
})

    return new Response( respBody, {
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
