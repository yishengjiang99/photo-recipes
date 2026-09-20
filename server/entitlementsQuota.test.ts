import assert from 'node:assert/strict'
import { describe, it, afterEach } from 'node:test'
import {
  getFreeDailyLimit,
  getUnlimitedEmails,
  getQuotaConfigSnapshot,
} from './entitlements.ts'

describe('free daily quota config', () => {
  const prev = {
    FREE_DAILY_LIMIT: process.env.FREE_DAILY_LIMIT,
    FREE_UNLIMITED_EMAILS: process.env.FREE_UNLIMITED_EMAILS,
  }

  afterEach(() => {
    if (prev.FREE_DAILY_LIMIT === undefined) delete process.env.FREE_DAILY_LIMIT
    else process.env.FREE_DAILY_LIMIT = prev.FREE_DAILY_LIMIT
    if (prev.FREE_UNLIMITED_EMAILS === undefined) delete process.env.FREE_UNLIMITED_EMAILS
    else process.env.FREE_UNLIMITED_EMAILS = prev.FREE_UNLIMITED_EMAILS
  })

  it('defaults to 5 when unset', () => {
    delete process.env.FREE_DAILY_LIMIT
    assert.equal(getFreeDailyLimit(), 5)
  })

  it('reads FREE_DAILY_LIMIT from env', () => {
    process.env.FREE_DAILY_LIMIT = '12'
    assert.equal(getFreeDailyLimit(), 12)
  })

  it('falls back on invalid env', () => {
    process.env.FREE_DAILY_LIMIT = 'nope'
    assert.equal(getFreeDailyLimit(), 5)
  })

  it('always includes owner email', () => {
    delete process.env.FREE_UNLIMITED_EMAILS
    const emails = getUnlimitedEmails()
    assert.ok(emails.has('yisheng.jiang@gmail.com'))
  })

  it('merges FREE_UNLIMITED_EMAILS', () => {
    process.env.FREE_UNLIMITED_EMAILS = 'ops@example.com, Other@Example.COM'
    const emails = getUnlimitedEmails()
    assert.ok(emails.has('yisheng.jiang@gmail.com'))
    assert.ok(emails.has('ops@example.com'))
    assert.ok(emails.has('other@example.com'))
  })

  it('admin snapshot exposes freeDailyLimit', () => {
    process.env.FREE_DAILY_LIMIT = '7'
    const snap = getQuotaConfigSnapshot()
    assert.equal(snap.freeDailyLimit, 7)
    assert.ok(snap.unlimitedEmails.includes('yisheng.jiang@gmail.com'))
  })
})
