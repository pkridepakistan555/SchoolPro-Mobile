'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('mocha');
const {
  isNewlyPublishedNotice,
  createMissingNoticeNotifications,
} = require('../functions/notice_notifications');

describe('SchoolPro published-notice notifications', () => {
  it('keeps one mirrored teacherAttendance rule declaration', () => {
    const rootRules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
    const adminRules = fs.readFileSync(path.join(__dirname, '..', 'admin', 'SchoolPro-Admin', 'firestore.rules'), 'utf8');
    assert.equal((rootRules.match(/match \/teacherAttendance\/{id}/g) || []).length, 1);
    assert.equal(adminRules, rootRules);
  });
  it('announces a notice created as published', () => {
    assert.equal(isNewlyPublishedNotice(null, { status: 'published' }), true);
  });

  it('announces a draft only when it transitions to published', () => {
    assert.equal(isNewlyPublishedNotice({ status: 'draft' }, { status: 'published' }), true);
    assert.equal(isNewlyPublishedNotice({ status: 'published' }, { status: 'published' }), false);
    assert.equal(isNewlyPublishedNotice({ status: 'draft' }, { status: 'draft' }), false);
    assert.equal(isNewlyPublishedNotice({ status: 'published' }, null), false);
  });

  it('creates notifications once and preserves existing read state on retries', async () => {
    const records = new Map();
    const db = {
      collection(name) {
        assert.equal(name, 'notifications');
        return { doc(id) { return { id }; } };
      },
      async runTransaction(callback) {
        const writes = [];
        const transaction = {
          async get(ref) {
            const value = records.get(ref.id);
            return { exists: Boolean(value), data: () => value };
          },
          create(ref, value) { writes.push([ref.id, value]); },
        };
        await callback(transaction);
        for (const [id, value] of writes) {
          if (records.has(id)) throw new Error(`already exists: ${id}`);
          records.set(id, value);
        }
      },
    };
    const parents = [
      { id: 'parent-1', status: 'active' },
      { id: 'parent-2', status: 'inactive' },
    ];
    const args = {
      db, parents, noticeId: 'notice-7',
      notice: { title: 'Holiday', body: 'School closed' },
      serverTimestamp: () => 'server-time',
    };

    await createMissingNoticeNotifications(args);
    assert.equal(records.size, 1);
    const id = 'notice_notice-7_parent-1';
    assert.equal(records.get(id).isRead, false);
    assert.equal(records.get(id).recipientUid, 'parent-1');

    records.set(id, { ...records.get(id), isRead: true, createdAt: 'original-time' });
    await createMissingNoticeNotifications(args);
    assert.equal(records.get(id).isRead, true);
    assert.equal(records.get(id).createdAt, 'original-time');
    assert.equal(records.size, 1);
  });
});
