import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';

const app = express();
const port = Number(process.env.PORT || 3000);
const openRouteApiKey = process.env.ORS_API_KEY || '';
const allowedOrigin = process.env.CORS_ORIGIN || '*';
const overpassUrl = 'https://overpass-api.de/api/interpreter';
const openRouteBaseUrl = 'https://api.openrouteservice.org';

app.use(helmet());
app.use(
  cors({
    origin: allowedOrigin === '*' ? '*' : allowedOrigin.split(',').map((item) => item.trim()),
  }),
);
app.use(express.json({ limit: '200kb' }));
app.use(morgan('combined'));

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'karada-map-backend' });
});

app.get('/facilities', async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const radius = Number(req.query.radius || 10000);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ error: 'lat and lng are required' });
  }

  try {
    const facilities = await fetchFacilities({ lat, lng, radius });
    res.json({ facilities });
  } catch (error) {
    console.warn('Falling back to seeded facilities:', error);
    res.json({ facilities: seedFacilities({ lat, lng }) });
  }
});

app.post('/route', async (req, res) => {
  const from = req.body?.from;
  const to = req.body?.to;

  if (!from || !to) {
    return res.status(400).json({ error: 'from and to are required' });
  }

  const start = toPoint(from);
  const end = toPoint(to);
  if (!start || !end) {
    return res.status(400).json({ error: 'from and to must include lat and lng' });
  }

  if (!openRouteApiKey) {
    return res.json({ route: estimateRoute(start, end) });
  }

  try {
    const response = await fetch(`${openRouteBaseUrl}/v2/directions/driving-car/geojson`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: openRouteApiKey,
      },
      body: JSON.stringify({
        coordinates: [
          [start.lng, start.lat],
          [end.lng, end.lat],
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenRouteService returned ${response.status}`);
    }

    const data = await response.json();
    const feature = data.features?.[0];
    const geometry = feature?.geometry;
    const summary = feature?.properties?.summary;

    if (!feature || !geometry || !summary) {
      throw new Error('Invalid route payload');
    }

    const points = (geometry.coordinates || []).map((point) => ({
      lng: Number(point[0]),
      lat: Number(point[1]),
    }));

    res.json({
      route: {
        points,
        distanceMeters: Number(summary.distance),
        durationSeconds: Number(summary.duration),
        isEstimated: false,
      },
    });
  } catch (error) {
    res.json({ route: estimateRoute(start, end) });
  }
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(port, () => {
  console.log(`karada-map-backend listening on ${port}`);
});

async function fetchFacilities({ lat, lng, radius }) {
  const query = `
[out:json][timeout:25];
(
  node["amenity"="fire_station"](around:${radius},${lat},${lng});
  way["amenity"="fire_station"](around:${radius},${lat},${lng});
  relation["amenity"="fire_station"](around:${radius},${lat},${lng});
  node["amenity"~"hospital|clinic|doctors"](around:${radius},${lat},${lng});
  way["amenity"~"hospital|clinic|doctors"](around:${radius},${lat},${lng});
  relation["amenity"~"hospital|clinic|doctors"](around:${radius},${lat},${lng});
  node["healthcare"~"hospital|clinic|doctor"](around:${radius},${lat},${lng});
  way["healthcare"~"hospital|clinic|doctor"](around:${radius},${lat},${lng});
  relation["healthcare"~"hospital|clinic|doctor"](around:${radius},${lat},${lng});
  node["emergency"="ambulance_station"](around:${radius},${lat},${lng});
  way["emergency"="ambulance_station"](around:${radius},${lat},${lng});
  relation["emergency"="ambulance_station"](around:${radius},${lat},${lng});
);
out center tags;
`;

  const response = await fetch(overpassUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: query,
  });

  if (!response.ok) {
    throw new Error(`Overpass returned ${response.status}`);
  }

  const data = await response.json();
  const seen = new Set();
  return (data.elements || [])
    .map((element) => normalizeFacility(element, { lat, lng }))
    .filter(Boolean)
    .filter((facility) => {
      const key = facility.name.toLowerCase().trim();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((a, b) => a.distanceMeters - b.distanceMeters)
    .slice(0, 30);
}

function seedFacilities(origin) {
  const seeds = [
    {
      id: 'seed-fire-1',
      name: 'Nairobi Central Fire Station',
      type: 'fire',
      lat: -1.2833,
      lng: 36.8167,
      address: 'Central Business District, Nairobi',
      phone: '0800723999',
    },
    {
      id: 'seed-fire-2',
      name: 'Eastlands Fire Station',
      type: 'fire',
      lat: -1.3102,
      lng: 36.8303,
      address: 'Eastlands, Nairobi',
      phone: '0800723999',
    },
    {
      id: 'seed-med-1',
      name: 'Kenyatta National Hospital',
      type: 'medical',
      lat: -1.3032,
      lng: 36.8078,
      address: 'Hospital Road, Nairobi',
      phone: '+254202720630',
    },
    {
      id: 'seed-med-2',
      name: 'Mbagathi Hospital',
      type: 'medical',
      lat: -1.3184,
      lng: 36.7897,
      address: 'Mbagathi Way, Nairobi',
      phone: '+254202755453',
    },
  ];

  return seeds
    .map((item) => ({
      ...item,
      distanceMeters: haversineMeters(origin.lat, origin.lng, item.lat, item.lng),
    }))
    .sort((a, b) => a.distanceMeters - b.distanceMeters);
}

function normalizeFacility(element, origin) {
  const lat = element.lat ?? element.center?.lat;
  const lng = element.lon ?? element.center?.lon;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;

  const tags = element.tags || {};
  const type = tags.amenity === 'fire_station' ? 'fire' : 'medical';
  const name = typeof tags.name === 'string' && tags.name.trim() ? tags.name.trim() : fallbackName(type);
  const distanceMeters = haversineMeters(origin.lat, origin.lng, lat, lng);
  const address = [
    tags['addr:street'],
    tags['addr:suburb'],
    tags['addr:city'],
  ]
    .filter((item) => typeof item === 'string' && item.trim())
    .join(', ') || null;

  return {
    id: `${element.type}-${element.id}`,
    name,
    type,
    lat,
    lng,
    phone: typeof tags.phone === 'string' ? tags.phone : null,
    address,
    distanceMeters,
  };
}

function fallbackName(type) {
  return type === 'fire' ? 'Unnamed fire station' : 'Unnamed medical facility';
}

function toPoint(point) {
  const lat = Number(point.lat);
  const lng = Number(point.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function estimateRoute(start, end) {
  const distanceMeters = haversineMeters(start.lat, start.lng, end.lat, end.lng);
  const durationSeconds = Math.max(90, distanceMeters / 7.5);
  return {
    points: [
      { lat: start.lat, lng: start.lng },
      { lat: end.lat, lng: end.lng },
    ],
    distanceMeters,
    durationSeconds,
    isEstimated: true,
  };
}

function haversineMeters(lat1, lng1, lat2, lng2) {
  const radius = 6371000;
  const toRad = (value) => (value * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * radius * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
