// Feasibility test K0 (#52): public Nostr relays (rendezvous only, encrypted signalling) and STUN servers.
// Exchangeable without code change; the CSP in index.html must list the same relay hosts in connect-src.
window.K0_CONFIG = {
  relays: ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'],
  stun: ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
};
