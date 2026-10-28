import * as sdk from 'matrix-js-sdk';

let client = null;
let activeSession = null;
let syncPrepared = false;
const listeners = new Set();
const publish = (type, detail = {}) => listeners.forEach((fn) => fn({ type, ...detail }));

const eventView = (event, room) => {
  const content = event.getContent?.() || {};
  if (event.getType?.() !== sdk.EventType.RoomMessage || content.msgtype !== 'm.text') return null;
  return {
    roomId: room?.roomId || event.getRoomId?.() || '',
    eventId: event.getId?.() || '',
    sender: event.getSender?.() || '',
    body: String(content.body || ''),
    timestamp: Number(event.getTs?.() || Date.now()),
    status: event.getStatus?.() || null,
  };
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
    client.on(sdk.RoomEvent.Timeline, (event, room) => {
      const message = eventView(event, room);
      if (message) publish('message', { message });
    });
    client.on(sdk.ClientEvent.Sync, (state) => publish('sync', { state }));
    await client.startClient({ initialSyncLimit: 30 });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Sohbetler yüklenemedi.')), 25000);
      client.once(sdk.ClientEvent.Sync, (state) => {
        if (state === sdk.SyncState.Prepared) { clearTimeout(timer); resolve(); }
      });
    });
    syncPrepared = true;
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
    .map((room) => ({
      roomId: room.roomId,
      name: room.name || room.getDMInviter?.() || 'Sohbet',
      lastActive: room.getLastActiveTimestamp?.() || 0,
      messages: room.timeline.filter((event) => event.getType?.() === sdk.EventType.RoomMessage)
        .map((event) => eventView(event, room)).filter(Boolean),
    }))
    .sort((a, b) => b.lastActive - a.lastActive);
}

export async function openDirect(peerUserId, roomName) {
  if (!client) throw new Error('Güvenli mesajlaşma başlatılamadı.');
  const existing = client.getRooms().find((room) =>
    room.getMyMembership() === 'join' &&
    room.getJoinedMembers().length === 2 &&
    room.getJoinedMembers().some((member) => member.userId === peerUserId) &&
    room.hasEncryptionStateEvent(),
  );
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
      content: { algorithm: sdk.MegolmAlgorithm || 'm.megolm.v1.aes-sha2' },
    }],
  });
  return result.room_id;
}

export async function sendText(roomId, text) {
  if (!client) throw new Error('Sohbet bağlantısı yok.');
  const body = String(text || '').trim();
  if (!body || body.length > 4000) throw new Error('Mesaj 1–4000 karakter arasında olmalı.');
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
  try { if (previous) await previous.logout(); }
  finally { await disconnect(); }
}
