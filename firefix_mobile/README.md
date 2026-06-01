# Karada

Karada is a Flutter emergency reporting app with a dashboard home, a dedicated incident report flow, and a live map for nearby fire and medical responders.

## Mobile app

Run the app with the map backend URL and optional OpenRouteService key:

```bash
flutter run \
  --dart-define=MAP_BACKEND_BASE_URL=https://your-render-service.onrender.com \
  --dart-define=OPENROUTE_API_KEY=your_openroute_key
```

If `MAP_BACKEND_BASE_URL` is not set, the app falls back to direct Overpass and OpenRouteService calls from the device.
By default, the app points at `https://karada-map-backend.onrender.com`.

## Map backend

The deployable backend lives in [`map_backend/`](./map_backend). It exposes:

- `GET /health`
- `GET /facilities?lat=&lng=&radius=`
- `POST /route`

### Render

Use `map_backend/render.yaml` as the Render blueprint. Set:

- `ORS_API_KEY`
- `CORS_ORIGIN`

## Notes

- The dashboard is the default home screen.
- The report flow is available from the bottom navigation and the dashboard hero.
- Nearby responders are sourced from OpenStreetMap and routed with OpenRouteService when available.
