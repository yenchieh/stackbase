import { describe, it, expect, vi, afterEach } from 'vitest'
import { umamiAttrs } from './analytics'

afterEach(() => vi.unstubAllEnvs())

describe('umamiAttrs (env gate)', () => {
  it('returns null when both env vars are unset', () => {
    vi.stubEnv('VITE_UMAMI_SRC', '')
    vi.stubEnv('VITE_UMAMI_WEBSITE_ID', '')
    expect(umamiAttrs()).toBeNull()
  })

  it('returns null when only one is set', () => {
    vi.stubEnv('VITE_UMAMI_SRC', 'https://umami.test/script.js')
    vi.stubEnv('VITE_UMAMI_WEBSITE_ID', '')
    expect(umamiAttrs()).toBeNull()
  })

  it('returns src + websiteId when both are set', () => {
    vi.stubEnv('VITE_UMAMI_SRC', 'https://umami.test/script.js')
    vi.stubEnv('VITE_UMAMI_WEBSITE_ID', 'abc-123')
    expect(umamiAttrs()).toEqual({ src: 'https://umami.test/script.js', websiteId: 'abc-123' })
  })
})
