import * as sdk from 'matrix-js-sdk';

// Matrix client used by panel.html. Every UniPakt chat is a private, encrypted
// 1:1 room between two panel accounts (club ↔ club or club ↔ UniPakt).

const MEGOLM = 'm.megolm.v1.aes-sha2';

let client = null;
let activeSession = null;
let syncPrepared = false;
const listeners = new Set();
const publish = (type, detail = {}) => listeners.forEach((fn) => fn({ type, ...detail }));

// Turn a timeline event into the small shape the panel renders.
// Encrypted events that could not be decrypted are shown as a placeholder
// instead of silently disappearing.
const eventView = (event, room) => {
  const base = {
    roomId: room?.roomId || event.getRoomId?.() || '',
    eventId: event.getId?.() || '',
    sender: event.getSender?.() || '',
    timestamp: Number(event.getTs?.() || Date.now()),
    status: event.getStatus?.() || null,
  };
  if (event.isDecryptionFailure?.()) return { ...base, body: 'Bu mesaj bu cihazda çözülemedi.', undecryptable: true };
  if (event.getType?.() !== sdk.EventType.RoomMessage) return null;
  const content = event.getContent?.() || {};
  if (content.msgtype !== 'm.text') return null;
  return { ...base, body: String(content.body || '') };
};

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

export async function connect(session, callbacks = {}) {
  if (client && syncPrepared && activeSession?.user_id === session.user_id && activeSession?.device_id === session.device_id) return client;
  await disconnect();
  try {
    client = sdk.createClient({
      baseUrl: session.base_url,
      userId: session.user_id,
      deviceId: session.device_id,
      accessToken: session.access_token,
      cryptoCallbacks: callbacks.cryptoCallbacks || {},
    });
    await client.initRustCrypto();
    activeSession = { user_id: session.user_id, device_id: session.device_id };

    client.on(sdk.RoomEvent.Timeline, (event, room, toStartOfTimeline) => {
      if (toStartOfTimeline) return;
      const message = eventView(event, room);
      if (message) publish('message', { message });
    });
    // Incoming messages arrive encrypted first and are decrypted a moment later.
    client.on(sdk.MatrixEventEvent.Decrypted, (event) => {
      const message = eventView(event, client?.getRoom(event.getRoomId()));
      if (message) publish('message', { message });
    });
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

export function listRooms() {
  if (!client) return [];
  return client.getRooms()
    .filter((room) => room.getMyMembership() === 'join')
    .map((room) => {
      const peer = peerOf(room);
      return {
        roomId: room.roomId,
        peerUserId: peer?.userId || '',
        // Name the room after the other side; the creator-set room name is the
        // recipient's own name and would look wrong on their screen.
        name: peer?.name || room.name || 'Sohbet',
        lastActive: room.getLastActiveTimestamp?.() || 0,
        messages: room.getLiveTimeline().getEvents()
          .map((event) => eventView(event, room)).filter(Boolean),
      };
    })
    .sort((a, b) => b.lastActive - a.lastActive);
}

export async function openDirect(peerUserId, roomName) {
  if (!client) throw new Error('Güvenli mesajlaşma başlatılamadı.');
  const me = client.getUserId();
  // Reuse an existing 1:1 room with this peer, even if they have not joined yet.
  const existing = client.getRooms().find((room) => {
    if (room.getMyMembership() !== 'join' || !room.hasEncryptionStateEvent()) return false;
    const active = room.getMembers().filter((m) => ['join', 'invite'].includes(m.membership));
    return active.length === 2 && active.some((m) => m.userId === peerUserId) && active.some((m) => m.userId === me);
  });
  if (existing) return existing.roomId;
  const result = await client.createRoom({
    name: roomName,
    invite: [peerUserId],
    is_direct: true,
    visibility: 'private',
    preset: 'trusted_private_chat',
    initial_state: [{
      type: sdk.EventType.RoomEncryption,
      state_key: '',
      content: { algorithm: MEGOLM },
    }],
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

export async function sendText(roomId, text) {
  if (!client) throw new Error('Sohbet bağlantısı yok.');
  const body = String(text || '').trim();
  if (!body || body.length > 4000) throw new Error('Mesaj 1–4000 karakter arasında olmalı.');
  // An encrypted message can only be read by devices that exist when it is
  // sent. If the other side has never opened the panel there is no device yet,
  // and the message would stay unreadable forever — so stop and say so.
  const room = client.getRoom(roomId);
  const peer = room ? peerOf(room) : null;
  if (peer) {
    const devices = await client.getCrypto().getUserDeviceInfo([peer.userId], true);
    if (!devices.get(peer.userId)?.size) {
      throw new Error(`${peer.name || 'Karşı taraf'} sohbeti henüz hiç açmadı. Panele bir kez girdikten sonra mesaj gönderebilirsin.`);
    }
  }
  await client.sendTextMessage(roomId, body);
}

export async function ensureRecoveryBackup(createSecretStorageKey) {
  if (!client) throw new Error('Sohbet bağlantısı yok.');
  const crypto = client.getCrypto();
  const hasBackup = await crypto.checkKeyBackupAndEnable();
  if (hasBackup) return { created: false };
  await crypto.bootstrapCrossSigning({ setupNewCrossSigning: true });
  const recovery = await crypto.createRecoveryKeyFromPassphrase();
  await crypto.bootstrapSecretStorage({
    setupNewSecretStorage: true,
    setupNewKeyBackup: true,
    createSecretStorageKey: createSecretStorageKey || (async () => recovery),
  });
  return { created: true, recoveryKey: recovery.encodedPrivateKey || '' };
}

export async function requestOwnDeviceVerification() {
  if (!client) throw new Error('Sohbet bağlantısı yok.');
  return await client.getCrypto().requestOwnUserVerification();
}

export async function disconnect() {
  if (client) {
    const previous = client;
    client = null; activeSession = null; syncPrepared = false;
    try { previous.stopClient(); } catch (_) {}
  }
  listeners.clear();
}

export async function logout() {
  const previous = client;
  try { if (previous) await previous.logout(true); }
  finally {
    await disconnect();
    // The Matrix device is deleted on logout, so its local encryption keys must
    // go too; otherwise a later login with a fresh device would trip over them.
    try { if (previous) await previous.clearStores(); } catch (_) {}
  }
}
