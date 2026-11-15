// Filme l'IHM web dans Edge sans fenêtre, par le protocole DevTools (WebSocket natif de Node, aucune dépendance).
// IHM_URL=http://127.0.0.1:18080/#code=… node video/tournage/ihm.mjs <actions.json> <sortie>
// Écrit <sortie>.mp4 (1920x1080, 30 i/s) et <sortie>.actions.json ([{action, t}], secondes depuis le début).
// Lancé par ihm.ps1, qui ouvre le tunnel et obtient le code à usage unique : l'URL n'est jamais affichée ni écrite.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const TYPES = ['attendre', 'touche', 'clic', 'attendre_selecteur', 'defiler'];
const INTERDITS = /#entreprise|#attempt|#f-/;   // champs et boutons qui enregistrent sur le serveur (texte entreprise, essais Agent Breaker)

export function verifierActions(actions) {
  for (const a of actions) {
    const type = Object.keys(a).find(k => TYPES.includes(k));
    if (!type) throw new Error(`action inconnue : ${JSON.stringify(a)}`);
    if (typeof a[type] === 'string' && INTERDITS.test(a[type])) throw new Error(`champ enregistré sur le serveur, interdit : ${a[type]}`);
  }
}

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const TOUCHES = { ArrowRight: 39, ArrowLeft: 37, PageDown: 34, PageUp: 33, Enter: 13 };
const dormir = ms => new Promise(r => setTimeout(r, ms));

async function cdp(url) {
  const ws = new WebSocket(url);
  await new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
  let id = 0; const attente = new Map(), ecoute = new Map();
  ws.onmessage = ({ data }) => {
    const m = JSON.parse(data);
    if (m.id && attente.has(m.id)) { const [ok, ko] = attente.get(m.id); attente.delete(m.id); m.error ? ko(new Error(m.error.message)) : ok(m.result); }
    else if (m.method) ecoute.get(m.method)?.(m.params);
  };
  return {
    envoyer: (method, params = {}) => new Promise((ok, ko) => { attente.set(++id, [ok, ko]); ws.send(JSON.stringify({ id, method, params })); }),
    sur: (method, f) => ecoute.set(method, f),
    fermer: () => ws.close(),
  };
}

async function main([fichierActions, sortie]) {
  const url = process.env.IHM_URL;
  if (!url || !fichierActions || !sortie) throw new Error('usage : IHM_URL=… node ihm.mjs <actions.json> <sortie>');
  const actions = JSON.parse(readFileSync(fichierActions, 'utf8'));
  verifierActions(actions);
  if (existsSync(sortie + '.mp4')) throw new Error(`${sortie}.mp4 existe déjà : choisir un autre nom de prise`);
  const profil = mkdtempSync(join(tmpdir(), 'ihm-edge-')), images = join(profil, 'images');
  mkdirSync(images);
  const edge = spawn(EDGE, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profil}`, '--window-size=1536,864',
    '--hide-scrollbars', '--mute-audio', '--no-first-run', '--no-default-browser-check', 'about:blank'], { stdio: 'ignore' });
  try {
    let port;
    for (let i = 0; i < 100 && !port; i++) { await dormir(200); try { port = readFileSync(join(profil, 'DevToolsActivePort'), 'utf8').split('\n')[0]; } catch {} }
    if (!port) throw new Error('Edge ne démarre pas');
    const page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page');
    const c = await cdp(page.webSocketDebuggerUrl);
    const evaluer = async expr => (await c.envoyer('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;
    await c.envoyer('Page.enable');
    await c.envoyer('Emulation.setDeviceMetricsOverride', { width: 1536, height: 864, deviceScaleFactor: 1.25, mobile: false });
    await c.envoyer('Page.navigate', { url });
    for (let i = 0; ; i++) {   // connecté quand les scénarios sont chargés ; le dialogue de jeton ouvert veut dire refusé
      await dormir(250);
      if (await evaluer(`document.getElementById('login')?.open`)) throw new Error('IHM : connexion refusée (code expiré ou déjà utilisé)');
      if (await evaluer(`document.querySelectorAll('#scenarios button').length > 0`)) break;
      if (i > 80) throw new Error('IHM : les scénarios ne se chargent pas');
    }
    await dormir(800);

    const cadres = [], journal = [];
    let n = 0;
    c.sur('Page.screencastFrame', ({ data, metadata, sessionId }) => {
      const f = join(images, `${String(n++).padStart(6, '0')}.jpg`);
      writeFileSync(f, Buffer.from(data, 'base64'));
      cadres.push({ f, ts: metadata.timestamp });
      c.envoyer('Page.screencastFrameAck', { sessionId }).catch(() => {});
    });
    const t0 = Date.now() / 1000;
    const premier = await c.envoyer('Page.captureScreenshot', { format: 'jpeg', quality: 92 });   // image de départ, la page peut rester immobile
    writeFileSync(join(images, 'depart.jpg'), Buffer.from(premier.data, 'base64'));
    cadres.push({ f: join(images, 'depart.jpg'), ts: t0 });
    await c.envoyer('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });

    for (const a of actions) {
      const type = Object.keys(a).find(k => TYPES.includes(k)), v = a[type];
      journal.push({ action: type, valeur: v, t: +(Date.now() / 1000 - t0).toFixed(2) });
      if (type === 'attendre') await dormir(v);
      else if (type === 'touche') {
        const code = TOUCHES[v];
        if (!code) throw new Error(`touche non prévue : ${v}`);
        for (const t of ['keyDown', 'keyUp']) await c.envoyer('Input.dispatchKeyEvent', { type: t, key: v, code: v, windowsVirtualKeyCode: code });
      } else if (type === 'clic') {
        const p = await evaluer(`(() => { const e = document.querySelector(${JSON.stringify(v)}); if (!e) return null;
          e.scrollIntoView({ block: 'center' }); const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`);
        if (!p) throw new Error(`élément absent : ${v}`);
        await c.envoyer('Input.dispatchMouseEvent', { type: 'mouseMoved', x: p.x, y: p.y });
        await dormir(250);
        for (const t of ['mousePressed', 'mouseReleased']) await c.envoyer('Input.dispatchMouseEvent', { type: t, x: p.x, y: p.y, button: 'left', clickCount: 1 });
      } else if (type === 'attendre_selecteur') {
        const fin = Date.now() + (a.max ?? 30000);
        while (!(await evaluer(`!!document.querySelector(${JSON.stringify(v)})`))) {
          if (Date.now() > fin) throw new Error(`toujours absent après ${a.max ?? 30000} ms : ${v}`);
          await dormir(200);
        }
      } else if (type === 'defiler') {
        await evaluer(`(() => { const e = ${v === 'page' ? 'document.scrollingElement' : `document.querySelector(${JSON.stringify(v)})`};
          if (!e) throw new Error('absent'); e.scrollBy({ top: ${a.de ?? 600}, behavior: 'smooth' }); })()`);
      }
    }
    await dormir(1000);
    const tFin = Date.now() / 1000;
    await c.envoyer('Page.stopScreencast');
    await c.envoyer('Browser.close').catch(() => {});
    c.fermer();

    // Images horodatées -> vidéo à 30 i/s constants (chaque image dure jusqu'à la suivante)
    cadres.sort((a, b) => a.ts - b.ts);
    const liste = cadres.map((k, i) => `file '${k.f.replaceAll('\\', '/')}'\nduration ${(Math.max((cadres[i + 1]?.ts ?? tFin) - k.ts, 0.001)).toFixed(4)}`);
    liste.push(`file '${cadres.at(-1).f.replaceAll('\\', '/')}'`);
    writeFileSync(join(profil, 'liste.txt'), liste.join('\n'));
    const ffmpeg = spawnSync('python', ['-c', 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())'], { encoding: 'utf8' }).stdout.trim();
    const r = spawnSync(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', join(profil, 'liste.txt'),
      '-t', (tFin - t0).toFixed(3), '-vf', 'fps=30,scale=1920:1080:force_original_aspect_ratio=decrease:out_range=tv,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0xF5F7FB,format=yuv420p',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', sortie + '.mp4'], { encoding: 'utf8' });
    if (r.status) throw new Error('ffmpeg : ' + r.stderr.slice(-800));
    writeFileSync(sortie + '.actions.json', JSON.stringify(journal, null, 1));
    console.log(`ok ${sortie}.mp4 (${(tFin - t0).toFixed(1)} s, ${cadres.length} images)`);
  } finally {
    edge.kill();
    await dormir(500);
    rmSync(profil, { recursive: true, force: true, maxRetries: 5, retryDelay: 300 });   // le jeton de session vit dans ce profil
  }
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  main(process.argv.slice(2)).catch(e => { console.error('erreur :', e.message); process.exit(1); });
}
