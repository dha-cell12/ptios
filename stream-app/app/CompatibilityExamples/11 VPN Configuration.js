'use strict';

// XXTouch-compatible profile creation from Auto. Replace the placeholders
// before running. Credentials are sent only through a local mode-0600 one-shot
// request and are never written to the script log.
var profile = {
  dispName: 'DemoVPN',
  VPNType: 'L2TP', // PPTP, L2TP, IPSec, or IKEv2
  server: 'vpn.example.com',
  authorization: 'CHANGE_ME',
  password: 'CHANGE_ME',
  secret: 'CHANGE_ME', // Required for L2TP-over-IPSec
  group: '',
  encrypLevel: 1,
  VPNSendAllTraffic: 1
};

if (profile.authorization === 'CHANGE_ME' ||
    profile.password === 'CHANGE_ME' ||
    (profile.VPNType === 'L2TP' && profile.secret === 'CHANGE_ME')) {
  throw new Error('Edit the VPN Configuration example before running it');
}

var success = vpnconf.create(profile);
var result = vpnconf.lastResult();
console.log('vpnconf.create ok=' + success + ' code=' + result.code);
if (!success) {
  throw new Error('VPN profile creation failed: ' + result.code);
}

// Optional: connect the newly selected TLink-owned profile through vpnagent.
// var connect = device.runTask(59, '1;;1');
// console.log('connect ok=' + connect.ok + ' payload=' + connect.payload);

// IKEv2 uses the same API. Its remote identifier defaults to server:
// vpnconf.create({
//   dispName: 'Demo IKEv2', VPNType: 'IKEv2', server: 'vpn.example.com',
//   remoteIdentifier: 'vpn.example.com', authorization: 'user',
//   password: 'password'
// });
