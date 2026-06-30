// Tiny API client. Calls are relative to /api; Traefik (prod/integrated) or the
// Vite dev proxy (standalone) routes them to the Go api.
const BASE = '/api'

async function getJSON(path: string, init?: RequestInit): Promise<unknown> {
  const res = await fetch(`${BASE}${path}`, init)
  if (!res.ok) {
    throw new Error(`${path} failed: ${res.status}`)
  }
  return res.json()
}

export function getHealth(): Promise<unknown> {
  return getJSON('/healthz')
}

export function getMe(token: string): Promise<unknown> {
  return getJSON('/me', { headers: { Authorization: `Bearer ${token}` } })
}
