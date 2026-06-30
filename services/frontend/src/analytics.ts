// Env-gated umami snippet. Unset VITE_UMAMI_* → no-op, so the template runs with
// no analytics. Set both → inject umami's tracking <script> at runtime.

export function umamiAttrs(): { src: string; websiteId: string } | null {
  const src = import.meta.env.VITE_UMAMI_SRC
  const websiteId = import.meta.env.VITE_UMAMI_WEBSITE_ID
  if (!src || !websiteId) return null
  return { src, websiteId }
}

export function initAnalytics(): boolean {
  const a = umamiAttrs()
  if (!a) return false
  const s = document.createElement('script')
  s.async = true
  s.defer = true
  s.src = a.src
  s.setAttribute('data-website-id', a.websiteId)
  document.head.appendChild(s)
  return true
}
