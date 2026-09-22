'use strict';
// Browser ceremony pattern informed by Broken Hands' MIT Vapor-PasskeyDemo.
// The transport, state handling and UI below are written for this isolated test.
const base = '/passkeys/test';
const $ = id => document.getElementById(id);
let csrf;
let busy = false;
let available = false;
function decode(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(padded + '='.repeat((4 - padded.length % 4) % 4)), c => c.charCodeAt(0));
}
function encode(value) {
  const bytes = new Uint8Array(value);
  let text = '';
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function controls() {
  for (const id of ['register', 'authenticate', 'signout']) $(id).disabled = busy || !available;
  $('username').disabled = busy;
}
function status(title, message) {
  $('status-title').textContent = title;
  $('status').textContent = message;
}
async function api(path, body) {
  const response = await fetch(base + path, {method: 'POST', credentials: 'same-origin',
    headers: {'Content-Type': 'application/json', 'X-SwiftKey-Test-CSRF': csrf}, body: JSON.stringify(body)});
  const result = await response.json();
  if (!response.ok) {
    if (response.status === 401) { available = false; controls(); }
    throw new Error(response.status === 401 ? 'The test session expired. Reload this page to continue.' :
      `${result.error || 'Verification failed'} (${result.code || response.status}) Start a new request to try again.`);
  }
  return result;
}
function resultDetails(result) {
  const details = $('details'); details.replaceChildren(); details.hidden = false;
  for (const [name, value] of [['Test name', result.username], ['Credential ID', result.credentialID],
    ['Signature counter', result.signCount], ['Backup eligible', result.backupEligible ? 'Yes' : 'No'],
    ['Currently backed up', result.backedUp ? 'Yes' : 'No']]) {
    const dt = document.createElement('dt'); dt.textContent = name;
    const dd = document.createElement('dd'); dd.textContent = String(value);
    details.append(dt, dd);
  }
}
async function perform(kind) {
  if (busy || !available) return;
  busy = true; controls(); $('details').hidden = true;
  status('Waiting for your browser', 'Choose your phone’s passkey provider and complete its verification prompt.');
  try {
    if (kind === 'register') {
      const username = $('username').value.trim();
      if (!username) throw new Error('Enter a test display name first.');
      const start = await api('/registration/options', {username});
      start.publicKey.challenge = decode(start.publicKey.challenge);
      start.publicKey.user.id = decode(start.publicKey.user.id);
      const credential = await navigator.credentials.create({publicKey: start.publicKey});
      if (!credential) throw new Error('No credential was returned by the browser.');
      const result = await api('/registration/verify', {ceremonyID: start.ceremonyID, credential: {
        id: credential.id, rawId: encode(credential.rawId), type: credential.type,
        response: {clientDataJSON: encode(credential.response.clientDataJSON),
          attestationObject: encode(credential.response.attestationObject)}}});
      if (!result.registered || result.authenticated) throw new Error('Unexpected registration result.');
      status('Passkey registered', 'Now sign in to verify a fresh challenge and signature. Registration alone does not sign you in.');
      resultDetails(result);
    } else {
      const start = await api('/authentication/options', {});
      start.publicKey.challenge = decode(start.publicKey.challenge);
      if (start.publicKey.allowCredentials) start.publicKey.allowCredentials = start.publicKey.allowCredentials.map(c => ({...c, id: decode(c.id)}));
      const credential = await navigator.credentials.get({publicKey: start.publicKey});
      if (!credential) throw new Error('No credential was returned by the browser.');
      const result = await api('/authentication/verify', {ceremonyID: start.ceremonyID, credential: {
        id: credential.id, rawId: encode(credential.rawId), type: credential.type,
        response: {clientDataJSON: encode(credential.response.clientDataJSON),
          authenticatorData: encode(credential.response.authenticatorData), signature: encode(credential.response.signature),
          userHandle: credential.response.userHandle === null ? null : encode(credential.response.userHandle)}}});
      if (!result.authenticated) throw new Error('The server did not authenticate this passkey.');
      status('Signature verified', `Signed in to this temporary test as ${result.username}. User verification was required.`);
      $('signout').hidden = false; resultDetails(result);
    }
  } catch (error) {
    status('Test not completed', error.name === 'NotAllowedError' ? 'The browser prompt was cancelled, timed out, or no matching passkey was available. You can try again.' : error.message);
  } finally { busy = false; controls(); }
}
$('register').addEventListener('click', () => perform('register'));
$('authenticate').addEventListener('click', () => perform('authenticate'));
$('signout').addEventListener('click', async () => {
  if (busy) return; busy = true; controls();
  try { await api('/signout', {}); $('signout').hidden = true; $('details').hidden = true;
    status('Test sign-in cleared', 'The saved passkey remains available for another sign-in.');
  } catch (error) { status('Unable to clear test sign-in', error.message); }
  finally { busy = false; controls(); }
});
(async () => {
  try {
    if (!window.isSecureContext || !window.PublicKeyCredential || !navigator.credentials) throw new Error('Open this page in a WebAuthn-capable browser using HTTPS or the configured localhost address.');
    const response = await fetch(base + '/bootstrap', {credentials: 'same-origin'});
    if (!response.ok) throw new Error('Unable to start a test session. Check the configured hostname and reload.');
    const session = await response.json(); csrf = session.csrf;
    $('origin').textContent = `Relying party: ${session.relyingPartyID} · ${session.origin}`;
    available = true; $('signout').hidden = !session.username;
    status(session.username ? 'Test session signed in' : 'Ready to test', session.username ? `Current test name: ${session.username}.` : 'Create a passkey, or sign in with one registered during this server session.');
  } catch (error) { status('Test unavailable', error.message); }
  controls();
})();
