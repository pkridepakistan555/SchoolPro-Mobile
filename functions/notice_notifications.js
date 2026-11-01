'use strict';

// A notice is announced exactly once: when it is created already published,
// or when an existing draft transitions to published. Edits to a published
// notice and event retries must not recreate/reset inbox notifications.
function isNewlyPublishedNotice(before, after) {
  return Boolean(after && after.status === 'published' && (!before || before.status !== 'published'));
}

async function createMissingNoticeNotifications({ db, parents, noticeId, notice, serverTimestamp }) {
  const activeParents = parents.filter((parent) => parent && parent.status === 'active');
  for (let offset = 0; offset < activeParents.length; offset += 450) {
    const chunk = activeParents.slice(offset, offset + 450);
    await db.runTransaction(async (transaction) => {
      const refs = chunk.map((parent) => db.collection('notifications').doc(`notice_${noticeId}_${parent.id}`));
      const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
      // Read every target before writing. Existing docs are deliberately left
      // untouched so a read notification can never be reset to unread.
      snapshots.forEach((snapshot, index) => {
        if (snapshot.exists) return;
        const parent = chunk[index];
        transaction.create(refs[index], {
          recipientUid: parent.id,
          type: 'notice',
          title: String(notice.title || 'School announcement'),
          body: String(notice.body || notice.message || 'A new school notice has been published.'),
          relatedId: noticeId,
          isRead: false,
          createdAt: serverTimestamp(),
        });
      });
    });
  }
}

module.exports = { isNewlyPublishedNotice, createMissingNoticeNotifications };
