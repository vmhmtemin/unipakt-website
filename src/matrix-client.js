import * as sdk from 'matrix-js-sdk';

// Matrix client used by panel.html (UniPakt Instant Messages). Every chat is a
// private 1:1 room between two panel accounts (club ↔ club or club ↔ UniPakt).
//
// End-to-end encryption is turned OFF for now: messages travel over HTTPS and
// are stored readable on chat.unipakt.com. This keeps history visible on every
// device and lets a club receive messages before it has ever opened the chat.
// Rooms created while encryption was on cannot be decrypted without crypto,
// so they are hidden from the list and never reused.
//
// The panel subscribes with onChange(); event types it receives:
//   message  – a new or updated message (incl. local echo status changes)
//   rooms    – rooms or memberships changed
//   typing   – someone started/stopped typing
//   receipt  – a read receipt arrived ("görüldü")
//   sync     – a sync round finished

let client = null;
let activeSession = null;
let syncPrepared = false;
const listeners = new Set();
const publish = (type, detail = {}) => listeners.forEach((fn) => fn({ type, ...detail }));

const isTextMessage = (event) =>
  event.getType?.() === sdk.EventType.RoomMessage && event.getContent?.()?.msgtype === 'm.text';

// Only plain (unencrypted) rooms are usable without the crypto module.
const isPlainRoom = (room) => !room.hasEncryptionStateEvent();

// The person on the other side of a 1:1 room (joined or still invited).
const peerOf = (room) => {
  const me = client?.getUserId();
  return room.getMembers().find((m) => m.userId !== me && ['join', 'invite'].includes(m.membership)) || null;
};

// Accept every pending invite. Registration and federation are closed on
// chat.unipakt.com, so invites can only come from other UniPakt panel accounts.
const joining = new Set();
const joinPendingInvites = async () => {
  if (!client) return;
  const invites = client.getRooms().filter((room) => room.getMyMembership() === 'invite' && !joining.has(room.roomId));
  for (const room of invites) {
    joining.add(room.roomId);
    try { await client.joinRoom(room.roomId); }
    catch (error) { console.warn('Matrix invite could not be accepted', room.roomId, error?.errcode || error); }
    finally { joining.delete(room.roomId); }
  }
  if (invites.length) publish('rooms');
};

export async function connect(session) {
  if (client && syncPrepared && activeSession?.user_id === session.user_id && activeSession?.device_id === session.device_id) return client;
  await disconnect();
  try {
    client = sdk.createClient({
      baseUrl: session.base_url,
      userId: session.user_id,
      deviceId: session.device_id,
      accessToken: session.access_token,
    });
    activeSession = { user_id: session.user_id, device_id: session.device_id };

    client.on(sdk.RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
      if (toStartOfTimeline || !room || !isPlainRoom(room)) return;
      if (isTextMessage(event)) publish('message', { roomId: room.roomId });
    });
    // Our own message moved from "sending" to "sent" (or failed).
    client.on(sdk.RoomEvent.LocalEchoUpdated, (_event, room) => publish('message', { roomId: room?.roomId }));
    client.on(sdk.RoomEvent.Receipt, (_event, room) => publish('receipt', { roomId: room?.roomId }));
    client.on(sdk.RoomMemberEvent.Typing, (_event, member) => publish('typing', { roomId: member?.roomId }));
    client.on(sdk.RoomMemberEvent.Membership, () => publish('rooms'));
    client.on(sdk.ClientEvent.Sync, (state) => {
      // Someone started a chat with us while we are online → accept it.
      if (syncPrepared) joinPendingInvites();
      publish('sync', { state });
    });

    const prepared = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { client?.off(sdk.ClientEvent.Sync, onSync); reject(new Error('Sohbetler yüklenemedi.')); }, 25000);
      function onSync(state) {
        if (state !== sdk.SyncState.Prepared && state !== sdk.SyncState.Syncing) return;
        clearTimeout(timer);
        client?.off(sdk.ClientEvent.Sync, onSync);
        resolve();
      }
      client.on(sdk.ClientEvent.Sync, onSync);
    });
    await client.startClient({ initialSyncLimit: 30 });
    await prepared;
    syncPrepared = true;
    // Invites that arrived while we were offline.
    await joinPendingInvites();
    return client;
  } catch (error) {
    await disconnect();
    throw error;
  }
}

export function onChange(listener) { listeners.add(listener); return () => listeners.delete(listener); }
export function getClient() { return client; }
export function getCurrentUserId() { return client?.getUserId() || ''; }

// Messages from the other side that we have not read yet.
const unreadCount = (room, me) => {
  let count = 0;
  const events = room.getLiveTimeline().getEvents();
  for (let i = events.length - 1; i >= 0; i -= 1) {
    const event = events[i];
    if (!isTextMessage(event)) continue;
    if (event.getSender() === me || room.hasUserReadEvent(me, event.getId())) break;
    count += 1;
  }
  return count;
};

// Yanıt (Matrix "m.in_reply_to"). Başka istemcilerin eklediği "> <@kişi> alıntı"
// satırları gövdeden atılır; alıntı, yanıtlanan mesajın kendisinden gösterilir.
const replyTargetId = (event) => String(event.getContent()?.['m.relates_to']?.['m.in_reply_to']?.event_id || '');
const stripReplyFallback = (body) => {
  const lines = String(body).split('\n');
  if (!lines[0]?.startsWith('> ')) return String(body);
  let i = 0;
  while (i < lines.length && lines[i].startsWith('>')) i += 1;
  if (lines[i] === '') i += 1;
  return lines.slice(i).join('\n');
};
const replyView = (room, eventId, me) => {
  if (!eventId) return null;
  const target = room.findEventById?.(eventId);
  if (!target) return { eventId, sender: '', mine: false, body: '', missing: true };
  const body = replyTargetId(target) ? stripReplyFallback(target.getContent()?.body || '') : String(target.getContent()?.body || '');
  return { eventId, sender: target.getSender() || '', mine: target.getSender() === me, body, missing: false };
};

const messageView = (event, room, me, peerId) => {
  const mine = event.getSender() === me;
  const status = event.getAssociatedStatus?.() || event.status || null;
  const replyId = replyTargetId(event);
  const rawBody = String(event.getContent()?.body || '');
  return {
    eventId: event.getId() || '',
    sender: event.getSender() || '',
    mine,
    body: replyId ? stripReplyFallback(rawBody) : rawBody,
    replyTo: replyView(room, replyId, me),
    timestamp: Number(event.getTs() || Date.now()),
    // 'sending' | 'failed' | 'sent' | 'read'
    state: status === sdk.EventStatus.NOT_SENT ? 'failed'
      : status && status !== sdk.EventStatus.SENT ? 'sending'
        : mine && peerId && room.hasUserReadEvent(peerId, event.getId()) ? 'read'
          : 'sent',
  };
};

// Everything the chat page needs, newest room first.
export function listRooms() {
  if (!client) return [];
  const me = client.getUserId();
  return client.getRooms()
    .filter((room) => room.getMyMembership() === 'join' && isPlainRoom(room))
    .map((room) => {
      const peer = peerOf(room);
      const messages = room.getLiveTimeline().getEvents()
        .filter(isTextMessage)
        .map((event) => messageView(event, room, me, peer?.userId));
      return {
        roomId: room.roomId,
        peerUserId: peer?.userId || '',
        // Name the room after the other side; the creator-set room name is the
        // recipient's own name and would look wrong on their screen.
        name: peer?.name || room.name || 'Sohbet',
        peerTyping: !!peer?.typing,
        unread: unreadCount(room, me),
        lastActive: messages.length ? messages[messages.length - 1].timestamp : (room.getLastActiveTimestamp?.() || 0),
        // Hidden once the room's very first event (its creation) is loaded.
        canLoadOlder: !!room.getLiveTimeline().getPaginationToken(sdk.EventTimeline.BACKWARDS)
          && !room.getLiveTimeline().getEvents().some((e) => e.getType() === sdk.EventType.RoomCreate),
        messages,
      };
    })
    .sort((a, b) => b.lastActive - a.lastActive);
}

// The existing 1:1 room with this peer, if any (even if they have not joined yet).
export function findDirect(peerUserId) {
  if (!client) return '';
  const me = client.getUserId();
  const room = client.getRooms().find((r) => {
    if (r.getMyMembership() !== 'join' || !isPlainRoom(r)) return false;
    const active = r.getMembers().filter((m) => ['join', 'invite'].includes(m.membership));
    return active.length === 2 && active.some((m) => m.userId === peerUserId) && active.some((m) => m.userId === me);
  });
  return room?.roomId || '';
}

export async function openDirect(peerUserId, roomName) {
  if (!client) throw new Error('Sohbet başlatılamadı.');
  const existing = findDirect(peerUserId);
  if (existing) return existing;
  const result = await client.createRoom({
    name: roomName,
    invite: [peerUserId],
    is_direct: true,
    visibility: 'private',
    preset: 'trusted_private_chat',
  });
  // Wait until our own sync has the new room *and* the peer's invite, so the
  // room is listed and a second click on the same club reuses it.
  const ready = () => {
    const room = client?.getRoom(result.room_id);
    return !!room && ['join', 'invite'].includes(room.getMember(peerUserId)?.membership);
  };
  if (!ready()) {
    await new Promise((resolve) => {
      const timer = setTimeout(done, 10000);
      function done() { clearTimeout(timer); client?.off(sdk.ClientEvent.Sync, check); resolve(); }
      function check() { if (ready()) done(); }
      client.on(sdk.ClientEvent.Sync, check);
    });
  }
  return result.room_id;
}

// replyToEventId: yanıtlanan mesajın kimliği (isteğe bağlı).
export async function sendText(roomId, text, replyToEventId = '') {
  if (!client) throw new Error('Sohbet bağlantısı yok.');
  const body = String(text || '').trim();
  if (!body || body.length > 4000) throw new Error('Mesaj 1–4000 karakter arasında olmalı.');
  setTyping(roomId, false);
  const content = { msgtype: 'm.text', body };
  if (/^\$/.test(String(replyToEventId || ''))) content['m.relates_to'] = { 'm.in_reply_to': { event_id: replyToEventId } };
  await client.sendMessage(roomId, content);
}

// "yazıyor…" — tell the other side we are typing. The panel calls this on every
// keystroke; it is throttled here and expires on its own after a few seconds.
const typingState = new Map();   // roomId → { on, sentAt }
export function setTyping(roomId, on) {
  if (!client || !roomId) return;
  const now = Date.now();
  const prev = typingState.get(roomId) || { on: false, sentAt: 0 };
  if (on && prev.on && now - prev.sentAt < 3000) return;
  if (!on && !prev.on) return;
  typingState.set(roomId, { on, sentAt: now });
  client.sendTyping(roomId, on, on ? 6000 : undefined).catch(() => {});
}

// "görüldü" — mark everything in the room as read up to its newest message.
export async function markRead(roomId) {
  if (!client || !roomId) return;
  const room = client.getRoom(roomId);
  if (!room) return;
  const me = client.getUserId();
  const events = room.getLiveTimeline().getEvents();
  const last = [...events].reverse().find((e) => isTextMessage(e) && e.getSender() !== me && e.getId()?.startsWith('$'));
  if (!last || room.hasUserReadEvent(me, last.getId())) return;
  try { await client.sendReadReceipt(last); } catch (_) {}
  publish('receipt', { roomId });
}

// Load older messages of a room ("Daha eski mesajlar").
export async function loadOlder(roomId) {
  const room = client?.getRoom(roomId);
  if (!room) return;
  await client.scrollback(room, 30);
  publish('message', { roomId });
}

export async function disconnect() {
  if (client) {
    const previous = client;
    client = null; activeSession = null; syncPrepared = false;
    try { previous.stopClient(); } catch (_) {}
  }
  typingState.clear();
  listeners.clear();
}

export async function logout() {
  const previous = client;
  try { if (previous) await previous.logout(true); }
  finally {
    await disconnect();
    try { if (previous) await previous.clearStores(); } catch (_) {}
  }
}
