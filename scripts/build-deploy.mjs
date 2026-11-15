import { mkdirSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
const root = fileURLToPath(new URL('../',import.meta.url));
const build = join(root,'artifacts','deploy'); mkdirSync(build,{recursive:true});
const key = readFileSync(join(process.env.USERPROFILE,'.ssh','id_ed25519_llm_security_lab.pub'),'utf8').trim();
if (!/^ssh-ed25519 [A-Za-z0-9+/]+={0,2} codex-llm-security-lab$/.test(key)) throw new Error('Invalid PUBLIC key');
const files=['app','verifier','hermes','compose.yaml','scripts/start-lab.sh','scripts/firewall.sh','scripts/isolation.py','scripts/baseline.mjs','scripts/run-experiments.sh'];
const packed=spawnSync('tar',['-czf',join(build,'project.tgz'),'-C',root,...files],{stdio:'inherit'});
if(packed.status!==0) throw new Error('Packaging failed');
const archive=readFileSync(join(build,'project.tgz')).toString('base64');
const cloud = `#cloud-config
hostname: llm-security-lab
manage_etc_hosts: true
ssh_pwauth: false
disable_root: true
users:
  - name: labadmin
    groups: [sudo]
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${key}
package_update: true
packages: [qemu-guest-agent, docker.io, docker-compose-v2, curl, python3]
write_files:
  - path: /opt/llm-security-lab/project.tgz
    permissions: '0600'
    encoding: b64
    content: ${archive}
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
  - [bash, -c, 'cd /opt/llm-security-lab && tar -xzf project.tgz && bash scripts/start-lab.sh > /var/log/llm-lab-bootstrap.log 2>&1']
`;
writeFileSync(join(build,'guest-cloud-config.yaml'),cloud);
for(const f of ['provision.sh','host-before.sha256','image.sha256']) copyFileSync(join(root,'deploy',f),join(build,f));
console.log('Deployment bundle built; only the PUBLIC SSH key is included.');
