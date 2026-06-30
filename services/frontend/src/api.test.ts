import { describe, it, expect, vi, afterEach } from 'vitest'
import { getMe } from './api'

afterEach(() => vi.restoreAllMocks())

describe('getMe', () => {
  it('returns parsed claims on 200', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ({ sub: 'u1' }),
    }))
    expect(await getMe('tok')).toEqual({ sub: 'u1' })
  })

  it('throws (with status) on a non-2xx response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false, status: 401, json: async () => ({ error: 'invalid token' }),
    }))
    await expect(getMe('bad')).rejects.toThrow(/401/)
  })

  it('sends the Bearer token', async () => {
    const f = vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({}) })
    vi.stubGlobal('fetch', f)
    await getMe('abc')
    expect(f).toHaveBeenCalledWith('/api/me', expect.objectContaining({
      headers: expect.objectContaining({ Authorization: 'Bearer abc' }),
    }))
  })
})
