import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';

test('Compose enforces network and evidence separation without exposing model ports', () => {
  const run=spawnSync('docker',['compose','--profile','attack','--profile','verify','config','--format','json'],{encoding:'utf8',env:{...process.env,LAB_HUMAN_TOKEN:'human-test-placeholder-0000000000000000',LAB_HERMES_TOKEN:'hermes-test-placeholder-000000000000000'}});
  assert.equal(run.status,0,run.stderr);
  const c=JSON.parse(run.stdout), h=c.services.hermes, v=c.services.verifier;
  assert.equal(c.networks.front.internal,true); assert.equal(c.networks.target.internal,true);
  assert.deepEqual(Object.keys(h.networks),['front']); assert.equal(h.user,'10000:10000');
  assert.equal(h.read_only,true); assert.deepEqual(h.cap_drop,['ALL']); assert.ok(h.security_opt.includes('no-new-privileges:true'));
  assert.equal(h.privileged,undefined); assert.equal(h.pid,undefined);
  assert.ok(h.volumes.every(x=>['/opt/data','/task'].includes(x.target)));
  assert.equal(v.network_mode,'none'); assert.equal(v.volumes.find(x=>x.target==='/evidence').read_only,true);
  assert.equal(c.services.api.volumes.find(x=>x.target==='/reports').read_only,true);
  assert.equal(c.services['ollama-target'].ports,undefined); assert.equal(c.services['ollama-attacker'].ports,undefined); assert.equal(h.ports,undefined);
  assert.equal(c.services.api.ports[0].host_ip,'127.0.0.1');
  for (const service of Object.values(c.services)) assert.match(service.image,/@sha256:[a-f0-9]{64}$/);
  const installer=readFileSync('deploy/provision.sh','utf8');
  assert.match(installer,/VMID occupied/); assert.match(installer,/No duplicate address detected/); assert.match(installer,/sha256sum -c host-before.sha256/);
  assert.doesNotMatch(installer,/qm (destroy|stop|shutdown)|pct (destroy|stop|shutdown)|pvesm (add|remove|set)/);
});
