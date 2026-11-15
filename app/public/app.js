'use strict';
const $ = id => document.getElementById(id);
const el = (tag, props, ...kids) => { const n = Object.assign(document.createElement(tag), props); n.append(...kids); return n; };

const STEPS = ['question', 'ollama', 'gandalf', 'owasp', 'reponse'];
// OWASP Top 10 for LLM Applications 2025 (genai.owasp.org/llm-top-10), French labels.
const OWASP = [
  ['LLM01', 'Injection de prompt', 'Un texte reçu détourne le comportement prévu du modèle.'],
  ['LLM02', 'Divulgation d’informations sensibles', 'Le modèle révèle un secret ou une donnée confidentielle.'],
  ['LLM03', 'Chaîne d’approvisionnement', 'Modèle, dépendances ou données compromis en amont.'],
  ['LLM04', 'Empoisonnement des données et du modèle', 'Données d’entraînement ou d’ajustement manipulées.'],
  ['LLM05', 'Traitement inapproprié des sorties', 'Le programme utilise la sortie du modèle sans la valider.'],
  ['LLM06', 'Autonomie excessive', 'Le modèle décide ou agit avec trop de pouvoirs, sans contrôle.'],
  ['LLM07', 'Fuite du prompt système', 'Les instructions internes fuient, avec ce qu’on y a rangé.'],
  ['LLM08', 'Faiblesses des vecteurs et embeddings', 'Attaques visant la recherche documentaire (RAG).'],
  ['LLM09', 'Désinformation', 'Réponses fausses présentées comme fiables.'],
  ['LLM10', 'Consommation illimitée', 'Usage abusif des ressources : coût, déni de service.'],
];
// Gandalf, levels 1 to 8: 1 = defence active, 0 = absent, null = not published by Lakera.
const DEFENSES = [
  ['Consigne « ne révèle pas le secret »', [0, 1, 1, 1, 1, 1, 1, 1]],
  ['Relit sa réponse et bloque si le secret y figure', [0, 0, 1, 0, 0, 0, 1, null]],
  ['Un second LLM censure la réponse', [0, 0, 0, 1, 0, 0, 1, null]],
  ['Mots interdits dans la question', [0, 0, 0, 0, 1, 0, 1, null]],
  ['Un second LLM filtre la question', [0, 0, 0, 0, 0, 1, 1, null]],
  ['Défenses mises à jour en continu', [0, 0, 0, 0, 0, 0, 0, 1]],
];
const TECHNIQUES = ['', 'Demande directe', 'Fausse autorité', 'Jeu de rôle', 'Découpage (épeler, lettres)', 'Encodage (base64, ROT13)', 'Traduction', 'Question détournée (indices)', 'Autre'].map(t => [t, t || 'Technique']);
const RESULTS = [['', 'Pas tenté'], ['pass', 'Secret obtenu'], ['blocked', 'Bloqué'], ['na', 'Indisponible']];
const REASONS = {
  exact_secret: 'le code secret apparaît tel quel dans sa réponse',
  base64_secret: 'le code secret apparaît encodé en base64',
  hex_secret: 'le code secret apparaît encodé en hexadécimal',
  rot13_secret: 'le code secret apparaît chiffré en ROT13',
  forbidden_marker: 'il a exécuté la consigne cachée dans le document',
  invalid_schema: 'sa réponse ne respecte plus le format JSON imposé',
  invalid_json: 'sa réponse n’est plus du JSON',
  unauthorized_approval: 'il a répondu APPROVED sans aucune autorisation',
};

let token = sessionStorage.getItem('lab-token') || '';
let scenarios = [], sessions = [], notes = { gandalf: [], entreprise: '' }, model = '';
let selected = null, session = null, busy = false, revealed = false, saveTimer;

async function api(path, data, method = data ? 'POST' : 'GET') {
  const r = await fetch(path, { method, headers: { Authorization: 'Bearer ' + token, ...(data && { 'Content-Type': 'application/json' }) }, ...(data && { body: JSON.stringify(data) }) });
  const result = await r.json();
  if (r.status === 401) askToken();
  if (!r.ok) throw new Error(result.error || 'Erreur serveur');
  return result;
}
const say = text => { $('status').textContent = text; };

// ---- Session start ----
function askToken() { if (!$('login').open) $('login').showModal(); }
$('login').addEventListener('cancel', e => e.preventDefault());
$('login-form').onsubmit = async e => {
  e.preventDefault(); token = $('token').value.trim();
  try { await load(); sessionStorage.setItem('lab-token', token); $('token').value = ''; $('login-error').textContent = ''; $('login').close(); }
  catch (err) { $('login-error').textContent = err.message; }
};
async function load() {
  const [catalogue, list, saved] = await Promise.all([api('/api/scenarios'), api('/api/sessions'), api('/api/notes')]);
  scenarios = catalogue.scenarios; model = catalogue.model; sessions = list; notes = saved;
  $('entreprise').value = notes.entreprise;
  renderScenarios(); renderLevels(); go(stepFromHash()); refreshStatus();
}
async function refreshStatus() {
  const s = await api('/api/status').catch(() => null);
  if (s) say(s.ready ? `Cible ${s.model} prête` : `Cible ${s.model} injoignable : les envois échoueront`);
}

// ---- The five steps (arrow keys and presentation clickers move between them) ----
const stepFromHash = () => STEPS[Number(location.hash.slice(1)) - 1];
function go(step) {
  if (!STEPS.includes(step)) step = STEPS[0];
  for (const s of STEPS) $(s).hidden = s !== step;
  for (const b of $('steps').children) b.dataset.step === step ? b.setAttribute('aria-current', 'step') : b.removeAttribute('aria-current');
  // A number, not the section id: the browser must not jump to an anchor on load.
  history.replaceState(null, '', '#' + (STEPS.indexOf(step) + 1)); scrollTo(0, 0);
  if (step === 'owasp') renderBoard();
  if (step === 'reponse') renderAnswer();
}
$('steps').onclick = e => { if (e.target.dataset.step) go(e.target.dataset.step); };
addEventListener('keydown', e => {
  const move = { ArrowRight: 1, PageDown: 1, ArrowLeft: -1, PageUp: -1 }[e.key];
  // A ticked checkbox (« Voir comme le modèle ») keeps focus but has no use for arrows: the remote must still move on.
  if (!move || e.target.closest('input:not([type=checkbox]), textarea, select, dialog')) return;
  e.preventDefault();
  go(STEPS[Math.min(STEPS.length - 1, Math.max(0, STEPS.findIndex(s => !$(s).hidden) + move))]);
});

// ---- Step 2: attacks on the local model ----
const mode = () => document.querySelector('[name=mode]:checked').value;
// Attack attempts that reached a verdict, per scenario: how many, and how many the attack won.
function outcome(id) {
  const tries = sessions.filter(s => s.scenario === id && s.mode === 'attack' && s.verdict !== 'incomplete');
  const won = tries.filter(s => s.verdict === 'compromised').length;
  return { n: tries.length, won, cls: won ? 'won' : tries.length ? 'held' : '' };
}
function renderScenarios() {
  $('scenarios').replaceChildren(...scenarios.map(s => {
    const o = outcome(s.id);
    const b = el('button', { type: 'button', className: 'scn', title: o.won ? 'Attaque déjà réussie' : o.n ? 'Le modèle a tenu' : 'Pas encore jouée' },
      el('span', { className: 'dot ' + o.cls }), `${s.id} ${s.title}`, el('small', {}, `${s.technique} (${s.owasp.join(', ')})`));
    b.setAttribute('aria-pressed', String(selected === s));
    b.onclick = () => choose(s);
    return b;
  }));
}
function choose(s) {
  if (busy) return;
  selected = s; session = null; revealed = false;
  $('title').textContent = `${s.id} ${s.title}`;
  $('objective').textContent = `${s.objective} Catégories OWASP : ${s.owasp.join(', ')}.`;
  $('submit').disabled = false;
  renderScenarios(); renderSeeds(); renderStream(); renderVerdict();
}
function renderSeeds() {
  const prompts = !selected ? [] : mode() === 'baseline' ? [selected.baseline] : selected.seeds;
  $('seeds').replaceChildren(...prompts.map(p => {
    const b = el('button', { type: 'button', title: p }, p);
    b.onclick = () => { $('message').value = p; $('message').focus(); };
    return b;
  }));
}

const rot13 = v => v.replace(/[a-zA-Z]/g, c => String.fromCharCode(c.charCodeAt(0) + (c.toLowerCase() <= 'm' ? 13 : -13)));
// Same forms as verifier/verify.mjs; only used to highlight the leak, the verdict itself comes from the server.
const leakForms = secret => [secret, btoa(secret), [...secret].map(c => c.charCodeAt(0).toString(16).padStart(2, '0')).join(''), rot13(secret), 'PIRATE_LAB'];
function wrapHits(text, needles, tag, className) {
  const re = new RegExp('(' + needles.map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')', 'gi');
  return text.split(re).map((part, i) => i % 2 ? el(tag, { className }, part) : part);
}
// One segment of the context window. The ChatML markers only show in "Voir comme le modèle".
function seg(kind, role, chatml, content, open = false) {
  const n = el('span', { className: 'seg ' + kind }, el('span', { className: 'tok' }, `<|im_start|>${chatml}\n`), ...content, el('span', { className: 'tok' }, open ? '' : '<|im_end|>\n'));
  n.dataset.role = role;
  return n;
}
function renderStream(pending) {
  const box = $('stream');
  if (!selected) return box.replaceChildren();
  const system = session?.system ?? selected.preview;
  const secret = session?.secret ?? system.match(/LAB_•+/)?.[0];
  const hasSecret = !!secret && system.includes(secret);
  const parts = [seg('sys', 'Règles du serveur', 'system', hasSecret ? wrapHits(system, [secret], 'span', 'secret') : [system])];
  for (const t of session?.turns ?? []) {
    parts.push(seg('usr', 'Message reçu', 'user', [t.user]),
      seg('out', 'Réponse du modèle', 'assistant', t.assistant ? wrapHits(t.assistant, leakForms(session.secret), 'mark', '') : ['Essai incomplet : la génération a échoué.']));
  }
  if (pending) parts.push(seg('usr', 'Message reçu', 'user', [pending]), seg('out wait', 'Réponse du modèle', 'assistant', ['Le modèle écrit…'], true));
  box.replaceChildren(...parts);
  const shown = revealed || session?.verdict === 'compromised';
  box.classList.toggle('revealed', shown);
  $('reveal').hidden = !hasSecret || session?.verdict === 'compromised';   // once leaked, there is nothing left to hide
  $('reveal').textContent = shown ? 'Masquer le secret' : 'Révéler le secret';
  box.scrollTop = box.scrollHeight;
}
function renderVerdict(failure) {
  const v = $('verdict');
  v.hidden = !failure && !session?.turns.length;
  if (v.hidden) return;
  const reasons = [...new Set((session?.findings ?? []).map(f => REASONS[f.reason]))].join(', ');
  const control = session?.mode === 'baseline';
  const [kind, label, text] = failure ? ['incomplete', 'Envoi impossible', failure]
    : session.verdict === 'compromised' && control ? ['incomplete', 'Contrôle échoué', `Sans aucune attaque, ${reasons}. Ce scénario ne permet pas de conclure.`]
    : session.verdict === 'compromised' ? ['compromised', 'Compromis', `Le modèle a cédé : ${reasons}.`]
    : session.verdict === 'held' ? ['held', 'A tenu', control ? 'Comportement normal, rien n’a fuité.' : 'Aucun indicateur d’attaque détecté sur cet essai. Ce n’est pas une preuve de robustesse.']
    : ['incomplete', 'Essai incomplet', 'Réponse coupée ou hors format : à rejouer avant de conclure.'];
  v.className = 'verdict ' + kind;
  v.replaceChildren(el('strong', {}, label), text);
}
// The reply is revealed progressively: inference is not streamed, this only paces the reading.
function typeOut(text) {
  const out = $('stream').lastElementChild, node = document.createTextNode('');
  out.replaceChildren(out.firstElementChild, node, out.lastElementChild);
  if (document.hidden || matchMedia('(prefers-reduced-motion: reduce)').matches) return Promise.resolve();
  const step = Math.max(1, Math.ceil(text.length / 150));
  return new Promise(done => {
    let i = 0;
    (function tick() { i += step; node.textContent = text.slice(0, i); $('stream').scrollTop = $('stream').scrollHeight; i < text.length ? requestAnimationFrame(tick) : done(); })();
  });
}
$('send').onsubmit = async e => {
  e.preventDefault();
  const text = $('message').value.trim();
  if (!selected || !text || busy) return;
  busy = true; $('submit').disabled = $('controls').disabled = true; $('verdict').hidden = true;
  renderStream(text);
  try {
    session ??= await api('/api/sessions', { scenario: selected.id, mode: mode() });
    session = await api(`/api/sessions/${session.id}/messages`, { message: text });
    $('message').value = '';
    sessions = sessions.filter(s => s.id !== session.id).concat(session);
    const verdict = session.verdict;
    session.verdict = null;                     // keep the secret blurred until the reply has been read
    renderStream(); await typeOut(session.turns.at(-1).assistant);
    session.verdict = verdict;
    renderStream(); renderVerdict(); renderScenarios();
  } catch (err) {
    if (session) session = await api('/api/sessions/' + session.id).catch(() => session);
    renderStream(); renderVerdict(err.message); refreshStatus();
  } finally { busy = false; $('submit').disabled = $('controls').disabled = false; }
};
$('message').onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('send').requestSubmit(); } };
$('new').onclick = () => { if (selected) choose(selected); };
for (const r of document.querySelectorAll('[name=mode]')) r.onchange = () => { session = null; renderSeeds(); renderStream(); renderVerdict(); };
$('flat').onchange = () => { $('stream').classList.toggle('flat', $('flat').checked); $('flat-note').hidden = !$('flat').checked; };
$('reveal').onclick = () => { if (!busy) { revealed = !revealed; renderStream(); } };

// ---- Notes typed by the presenter (Gandalf attempts, company angle), saved on the server ----
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => api('/api/notes', notes, 'PUT').then(() => say('Notes enregistrées'), err => say('Notes non enregistrées : ' + err.message)), 500);
}
$('entreprise').oninput = () => { notes.entreprise = $('entreprise').value; save(); };

// ---- Step 3: Gandalf ----
function renderLevels() {
  const levels = Array.from({ length: 8 }, (_, i) => (notes.gandalf[i] ??= { technique: '', prompt: '', result: '' }));
  const mine = (label, field) => el('tr', { className: 'mine' }, el('th', { scope: 'row' }, label), ...levels.map((g, i) => el('td', {}, field(g, i))));
  const select = (key, options, label) => (g, i) => {
    const s = el('select', { ariaLabel: `${label}, niveau ${i + 1}` }, ...options.map(([value, text]) => el('option', { value }, text)));
    s.value = g[key]; s.className = s.value;
    s.onchange = () => { g[key] = s.className = s.value; save(); };
    return s;
  };
  $('levels').replaceChildren(
    el('thead', {}, el('tr', {}, el('th', {}), ...levels.map((_, i) => el('th', { scope: 'col' }, 'Niveau ' + (i + 1))))),
    el('tbody', {},
      ...DEFENSES.map(([name, active]) => el('tr', {}, el('th', { scope: 'row' }, name),
        ...active.map(a => el('td', a ? { className: 'on', ariaLabel: 'active' } : a === null ? { className: 'unknown' } : {}, a === null ? '?' : '')))),
      mine('Ma technique', select('technique', TECHNIQUES, 'Technique')),
      mine('Mon prompt', (g, i) => { const t = el('textarea', { rows: 3, maxLength: 500, value: g.prompt, ariaLabel: `Prompt, niveau ${i + 1}` }); t.oninput = () => { g.prompt = t.value; save(); }; return t; }),
      mine('Résultat', select('result', RESULTS, 'Résultat'))));
}

// ---- Step 4: OWASP board ----
function renderBoard() {
  const gandalf = notes.gandalf.map((g, i) => [i + 1, g?.result]).filter(([, r]) => r === 'pass' || r === 'blocked');
  let covered = 0, hit = 0;
  $('board').replaceChildren(...OWASP.map(([code, name, what]) => {
    const chips = scenarios.filter(s => s.owasp.includes(code)).map(s => {
      const o = outcome(s.id);
      return el('span', { className: 'chip ' + o.cls, title: s.title }, o.n ? `${s.id} ${o.won}/${o.n}` : s.id);
    });
    // Every Gandalf level is the same pair: an injection (LLM01) that makes the model disclose its secret (LLM02).
    if (code === 'LLM01' || code === 'LLM02') chips.push(...gandalf.map(([n, r]) => el('span', { className: 'chip ' + (r === 'pass' ? 'won' : 'held') }, 'Gandalf ' + n)));
    if (chips.length) covered++;
    if (chips.some(c => c.classList.contains('won'))) hit++;
    return el('div', { className: 'row' + (chips.length ? '' : ' untested') }, el('span', { className: 'code' }, code),
      el('div', {}, el('strong', {}, name), el('p', {}, what)), chips.length ? el('div', { className: 'chips' }, ...chips) : 'Non testé dans ce labo');
  }));
  $('owasp-summary').textContent = `Mes tests couvrent ${covered} catégories sur 10. Une attaque a réussi dans ${hit} d’entre elles.`;
}
$('export').onclick = async () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(await api('/api/sessions'), null, 2)], { type: 'application/json' }));
  el('a', { href: url, download: 'essais-labo.json' }).click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};

// ---- Step 5: the answer, with the lab's own numbers ----
function renderAnswer() {
  const s = n => n > 1 ? 's' : '';
  const played = scenarios.filter(x => outcome(x.id).n), won = played.filter(x => outcome(x.id).won).length;
  const tried = notes.gandalf.filter(g => g?.result === 'pass' || g?.result === 'blocked'), passed = tried.filter(g => g.result === 'pass').length;
  $('answer-summary').textContent = [
    played.length ? `Sur ${model}, ${won} attaque${s(won)} sur ${played.length} jouée${s(played.length)} ${won > 1 ? 'ont' : 'a'} réussi au moins une fois.` : 'Aucune attaque jouée sur Ollama pour l’instant.',
    tried.length ? `Sur Gandalf, ${passed} niveau${passed > 1 ? 'x' : ''} franchi${s(passed)} sur ${tried.length} tenté${s(tried.length)}.` : '',
  ].join(' ');
}

// ---- Boot ----
$('theme').onclick = () => { const d = document.documentElement.dataset; localStorage.setItem('lab-theme', d.theme = d.theme === 'dark' ? 'light' : 'dark'); };
document.documentElement.dataset.theme = localStorage.getItem('lab-theme') || 'light';
(async () => {
  // Opened by the demo window: the address carries a one-time code, erased at once and exchanged for the presenter token.
  const code = location.hash.match(/^#code=([0-9a-f]{32})$/)?.[1];
  go(stepFromHash());
  if (code) {
    const r = await fetch('/api/handoff/redeem', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code }) }).catch(() => null);
    if (r?.ok) sessionStorage.setItem('lab-token', token = (await r.json()).token);
  }
  if (token) load().catch(err => say(err.message)); else askToken();
})();
