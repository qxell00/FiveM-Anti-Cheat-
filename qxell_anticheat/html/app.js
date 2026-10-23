/* ═══════════════════════════════════════════════
   qxell ANTICHEAT — NUI APP.JS
   Gestionează toată logica interfeței
═══════════════════════════════════════════════ */

'use strict';

// ─────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────
const State = {
    isOpen:         false,
    currentTab:     'players',
    players:        [],
    bans:           [],
    logs:           [],
    strikes:        [],
    stats:          {},
    selectedPlayer: null,
};

// ─────────────────────────────────────────────
// DOM REFS
// ─────────────────────────────────────────────
const overlay        = document.getElementById('overlay');
const navBtns        = document.querySelectorAll('.nav-btn');
const tabs           = document.querySelectorAll('.tab');
const closeBtn       = document.getElementById('close-btn');
const playerModal    = document.getElementById('player-modal');
const modalCloseBt   = document.getElementById('modal-close-btn');

// ─────────────────────────────────────────────
// OPEN / CLOSE
// ─────────────────────────────────────────────
function openMenu() {
    State.isOpen = true;
    overlay.classList.remove('hidden');
    // Solicită titlul serverului de la Lua de fiecare dată când se deschide
    fetch(`https://${RESOURCE_NAME}/qxellAC:NUI:GetServerName`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
    }).then(r => r.json()).then(d => {
        if (d && d.name) {
            const titleEl = document.getElementById('logo-title');
            if (titleEl) titleEl.textContent = d.name;
        }
    }).catch(() => {});
    loadTab(State.currentTab);
}

function closeMenu() {
    State.isOpen = false;
    overlay.classList.add('hidden');
    // Notifică Lua să elibereze cursorul prin postMessage direct
    // NU folosim fetchNUI aici — ar crea o buclă (Lua → JS → Lua → JS...)
    // Lua detectează închiderea prin NUI callback 'qxellAC:NUI:Close'
    // care e apelat DOAR de butoanele X/ESC din JS, nu din Lua
    fetch(`https://${RESOURCE_NAME}/qxellAC:NUI:Close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
    }).catch(() => {});
}

closeBtn.addEventListener('click', closeMenu);
modalCloseBt.addEventListener('click', () => playerModal.classList.add('hidden'));

// Click în afara menu-ului îl închide
overlay.addEventListener('click', (e) => {
    if (e.target === overlay) closeMenu();
});

// ─────────────────────────────────────────────
// NAVIGARE TAB-URI
// ─────────────────────────────────────────────
navBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        const tabName = btn.dataset.tab;
        switchTab(tabName);
        loadTab(tabName);
    });
});

function switchTab(name) {
    State.currentTab = name;
    navBtns.forEach(b => b.classList.toggle('active', b.dataset.tab === name));
    tabs.forEach(t => t.classList.toggle('active', t.id === `tab-${name}`));
}

function loadTab(name) {
    switch (name) {
        case 'players':  loadPlayers();  break;
        case 'bans':     loadBans();     break;
        case 'logs':     loadLogs();     break;
        case 'strikes':  loadStrikes();  break;
        case 'settings': loadStats();    break;
    }
}

// ─────────────────────────────────────────────
// RESOURCE NAME — detectat automat din URL
// Nu depinde de GetParentResourceName() care poate returna
// numele greșit dacă folderul are alt nume
// ─────────────────────────────────────────────
const RESOURCE_NAME = (() => {
    // În FiveM, window.GetParentResourceName() returnează întotdeauna
    // numele real al resursei (folderului), indiferent de "name" din manifest
    if (typeof window.GetParentResourceName === 'function') {
        return window.GetParentResourceName();
    }
    // Fallback: extrage din URL-ul paginii (ex: https://qxell_anticheat/html/index.html)
    try {
        const parts = window.location.href.split('/');
        // URL format: nui://qxell_anticheat/html/index.html
        if (parts[2]) return parts[2];
    } catch (_) {}
    return 'qxell_anticheat';
})();

// ─────────────────────────────────────────────
// FETCH NUI (comunicare cu Lua)
// ─────────────────────────────────────────────
function fetchNUI(event, data) {
    return fetch(`https://${RESOURCE_NAME}/${event}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => null);
}

// ─────────────────────────────────────────────
// TOAST NOTIFICATIONS
// ─────────────────────────────────────────────
const toastContainer = document.getElementById('toast-container');

function showToast(message, type = 'info', duration = 3500) {
    const icons = { success: 'fa-check-circle', error: 'fa-circle-xmark',
                    info: 'fa-circle-info', warning: 'fa-triangle-exclamation' };

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<i class="fa-solid ${icons[type] || icons.info}"></i><span>${sanitize(message)}</span>`;
    toastContainer.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('fade-out');
        setTimeout(() => toast.remove(), 220);
    }, duration);
}

function sanitize(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
}

// ─────────────────────────────────────────────
// PLAYERS TAB
// ─────────────────────────────────────────────
const playersGrid      = document.getElementById('players-grid');
const searchPlayers    = document.getElementById('search-players');
const refreshPlayerBtn = document.getElementById('refresh-players');
const playerCountSide  = document.getElementById('player-count-side');

refreshPlayerBtn.addEventListener('click', loadPlayers);
searchPlayers.addEventListener('input', renderPlayers);

async function loadPlayers() {
    playersGrid.innerHTML = `<div class="loading-placeholder"><i class="fa-solid fa-spinner fa-spin"></i><p>Se încarcă jucătorii...</p></div>`;
    const data = await fetchNUI('qxellAC:NUI:GetPlayers', {});
    if (data && Array.isArray(data)) {
        State.players = data;
    } else {
        State.players = [];
    }
    renderPlayers();
    // Actualizează contorul în sidebar
    const count = State.players.length;
    playerCountSide.textContent = `${count} jucători online`;
}

function renderPlayers() {
    const q = (searchPlayers.value || '').toLowerCase();
    const filtered = State.players.filter(p =>
        p.name.toLowerCase().includes(q) ||
        String(p.id).includes(q)
    );

    if (filtered.length === 0) {
        playersGrid.innerHTML = `<div class="empty-state"><i class="fa-solid fa-users-slash"></i><p>Niciun jucător găsit</p></div>`;
        return;
    }

    playersGrid.innerHTML = filtered.map(p => {
        const initials = (p.name || '?').trim().split(' ')
            .map(w => w[0] || '').join('').toUpperCase().slice(0, 2);
        return `
        <div class="player-card" data-id="${p.id}">
            <div class="player-card-top">
                <div class="player-avatar">${sanitize(initials)}</div>
                <div>
                    <div class="player-name">${sanitize(p.name)}</div>
                    <div class="player-id-badge">ID: ${p.id} &nbsp;|&nbsp; Ping: ${p.ping}ms</div>
                </div>
            </div>
            <div class="player-card-ids">
                ${p.license ? `🔑 ${sanitize(p.license)}` : ''}
            </div>
            <div class="player-card-footer">
                <button class="btn-primary"  onclick="quickAction('ss',   ${p.id}, '${sanitize(p.name)}')"><i class="fa-solid fa-camera"></i></button>
                <button class="btn-warning"  onclick="quickAction('kick', ${p.id}, '${sanitize(p.name)}')"><i class="fa-solid fa-door-open"></i></button>
                <button class="btn-danger"   onclick="openPlayerModal(${p.id})"><i class="fa-solid fa-hammer"></i></button>
            </div>
        </div>`;
    }).join('');
}

// Click card → deschide modal cu detalii complete
playersGrid.addEventListener('click', (e) => {
    const card = e.target.closest('.player-card');
    if (!card || e.target.closest('button')) return;
    const id = parseInt(card.dataset.id);
    openPlayerModal(id);
});

// ─────────────────────────────────────────────
// PLAYER MODAL
// ─────────────────────────────────────────────
const modalPlayerName = document.getElementById('modal-player-name');
const modalPlayerIds  = document.getElementById('modal-player-ids');
const modalBanBtn     = document.getElementById('modal-ban-btn');
const modalKickBtn    = document.getElementById('modal-kick-btn');
const modalSsBtn      = document.getElementById('modal-ss-btn');
const modalBanForm    = document.getElementById('modal-ban-form');
const modalKickForm   = document.getElementById('modal-kick-form');
const modalBanConfirm = document.getElementById('modal-ban-confirm');
const modalKickConfirm= document.getElementById('modal-kick-confirm');

function openPlayerModal(id) {
    const p = State.players.find(x => x.id === id);
    if (!p) return;
    State.selectedPlayer = p;

    modalPlayerName.textContent = `${p.name} (ID: ${id})`;
    modalPlayerIds.innerHTML = [
        p.license  ? `🔑 <b>License:</b> ${sanitize(p.license)}`  : '',
        p.discord  ? `💬 <b>Discord:</b> ${sanitize(p.discord)}`  : '',
        p.steam    ? `🎮 <b>Steam:</b>   ${sanitize(p.steam)}`    : '',
        p.ip       ? `🌐 <b>IP:</b>      ${sanitize(p.ip)}`       : '',
        `📶 <b>Ping:</b> ${p.ping}ms`,
    ].filter(Boolean).join('<br>');

    modalBanForm.classList.add('hidden');
    modalKickForm.classList.add('hidden');
    playerModal.classList.remove('hidden');
}

modalBanBtn.addEventListener('click', () => {
    modalBanForm.classList.toggle('hidden');
    modalKickForm.classList.add('hidden');
});

modalKickBtn.addEventListener('click', () => {
    modalKickForm.classList.toggle('hidden');
    modalBanForm.classList.add('hidden');
});

modalSsBtn.addEventListener('click', () => {
    if (!State.selectedPlayer) return;
    fetchNUI('qxellAC:NUI:Screenshot', { id: State.selectedPlayer.id });
    showToast(`Screenshot solicitat pentru ${State.selectedPlayer.name}`, 'info');
    playerModal.classList.add('hidden');
});

modalBanConfirm.addEventListener('click', async () => {
    const reason   = document.getElementById('modal-ban-reason').value.trim();
    const duration = parseInt(document.getElementById('modal-ban-duration').value) || 0;
    if (!reason) { showToast('Introdu un motiv pentru ban!', 'warning'); return; }
    const res = await fetchNUI('qxellAC:NUI:BanPlayer', {
        id: State.selectedPlayer.id, reason, duration
    });
    if (res && res.success) {
        showToast(`${State.selectedPlayer.name} a fost banat.`, 'success');
        playerModal.classList.add('hidden');
        loadPlayers();
    } else {
        showToast(res?.error || 'Eroare la ban.', 'error');
    }
});

modalKickConfirm.addEventListener('click', async () => {
    const reason = document.getElementById('modal-kick-reason').value.trim();
    if (!reason) { showToast('Introdu un motiv pentru kick!', 'warning'); return; }
    const res = await fetchNUI('qxellAC:NUI:KickPlayer', {
        id: State.selectedPlayer.id, reason
    });
    if (res && res.success) {
        showToast(`${State.selectedPlayer.name} a fost dat afară.`, 'success');
        playerModal.classList.add('hidden');
        loadPlayers();
    } else {
        showToast(res?.error || 'Eroare la kick.', 'error');
    }
});

// ─────────────────────────────────────────────
// QUICK ACTION (din card-uri)
// ─────────────────────────────────────────────
async function quickAction(action, id, name) {
    if (action === 'ss') {
        await fetchNUI('qxellAC:NUI:Screenshot', { id });
        showToast(`Screenshot solicitat pentru ${name}`, 'info');
    } else if (action === 'kick') {
        const reason = prompt(`Motiv kick pentru ${name}:`);
        if (!reason) return;
        const res = await fetchNUI('qxellAC:NUI:KickPlayer', { id, reason });
        if (res?.success) {
            showToast(`${name} a fost dat afară.`, 'success');
            loadPlayers();
        } else {
            showToast(res?.error || 'Eroare la kick.', 'error');
        }
    }
}
window.quickAction    = quickAction;
window.openPlayerModal = openPlayerModal;

// ─────────────────────────────────────────────
// BANS TAB
// ─────────────────────────────────────────────
const bansTbody     = document.getElementById('bans-tbody');
const searchBans    = document.getElementById('search-bans');
const refreshBanBtn = document.getElementById('refresh-bans');

refreshBanBtn.addEventListener('click', loadBans);
searchBans.addEventListener('input', renderBans);

async function loadBans() {
    bansTbody.innerHTML = `<tr><td colspan="7" class="table-empty"><i class="fa-solid fa-spinner fa-spin"></i> Se încarcă...</td></tr>`;
    const data = await fetchNUI('qxellAC:NUI:GetBans', {});
    State.bans = Array.isArray(data) ? data : [];
    renderBans();
}

function renderBans() {
    const q = (searchBans.value || '').toLowerCase();
    const filtered = State.bans.filter(b =>
        (b.ban_id    || '').toLowerCase().includes(q) ||
        (b.player_name || '').toLowerCase().includes(q)
    );

    if (filtered.length === 0) {
        bansTbody.innerHTML = `<tr><td colspan="7" class="table-empty">Niciun ban găsit</td></tr>`;
        return;
    }

    bansTbody.innerHTML = filtered.map(b => `
        <tr>
            <td><code style="color:var(--accent);font-size:12px">${sanitize(b.ban_id)}</code></td>
            <td>${sanitize(b.player_name)}</td>
            <td title="${sanitize(b.reason)}">${sanitize(b.reason?.slice(0,40) + (b.reason?.length > 40 ? '...' : ''))}</td>
            <td>${sanitize(b.banned_by)}</td>
            <td style="color:var(--text-muted);font-size:12px">${sanitize(formatDate(b.ban_date))}</td>
            <td style="color:var(--text-muted);font-size:12px">${b.expire_date ? sanitize(formatDate(b.expire_date)) : '<span style="color:var(--danger)">Permanent</span>'}</td>
            <td>
                <button class="btn-unban" onclick="doUnban('${sanitize(b.ban_id)}')">
                    <i class="fa-solid fa-unlock"></i> Unban
                </button>
            </td>
        </tr>`
    ).join('');
}

async function doUnban(banId) {
    if (!confirm(`Ești sigur că vrei să debanezi ${banId}?`)) return;
    const res = await fetchNUI('qxellAC:NUI:Unban', { banId });
    if (res?.success) {
        showToast(`Unban executat: ${banId}`, 'success');
        loadBans();
    } else {
        showToast(res?.error || 'Eroare la unban.', 'error');
    }
}
window.doUnban = doUnban;

// ─────────────────────────────────────────────
// LOGS TAB
// ─────────────────────────────────────────────
const logsTbody      = document.getElementById('logs-tbody');
const logFilter      = document.getElementById('log-filter');
const refreshLogsBtn = document.getElementById('refresh-logs');

refreshLogsBtn.addEventListener('click', loadLogs);
logFilter.addEventListener('change', renderLogs);

async function loadLogs() {
    logsTbody.innerHTML = `<tr><td colspan="4" class="table-empty"><i class="fa-solid fa-spinner fa-spin"></i> Se încarcă...</td></tr>`;
    const data = await fetchNUI('qxellAC:NUI:GetLogs', {});
    State.logs = Array.isArray(data) ? data : [];
    renderLogs();
}

function renderLogs() {
    const filter   = logFilter.value;
    const filtered = filter === 'ALL'
        ? State.logs
        : State.logs.filter(l => l.action === filter);

    if (filtered.length === 0) {
        logsTbody.innerHTML = `<tr><td colspan="4" class="table-empty">Niciun log găsit</td></tr>`;
        return;
    }

    logsTbody.innerHTML = filtered.map(l => `
        <tr>
            <td style="color:var(--text-muted);font-size:12px;white-space:nowrap">${sanitize(formatDate(l.log_date))}</td>
            <td>${sanitize(l.player_name)}</td>
            <td><span class="badge-action badge-${sanitize(l.action)}">${sanitize(l.action)}</span></td>
            <td title="${sanitize(l.reason)}">${sanitize(l.reason?.slice(0,60) + (l.reason?.length > 60 ? '...' : ''))}</td>
        </tr>`
    ).join('');
}

// ─────────────────────────────────────────────
// STRIKES TAB
// ─────────────────────────────────────────────
const strikesGrid      = document.getElementById('strikes-grid');
const refreshStrikes   = document.getElementById('refresh-strikes');

refreshStrikes.addEventListener('click', loadStrikes);

async function loadStrikes() {
    strikesGrid.innerHTML = `<div class="loading-placeholder"><i class="fa-solid fa-spinner fa-spin"></i><p>Se încarcă...</p></div>`;
    const data = await fetchNUI('qxellAC:NUI:GetStrikes', {});
    State.strikes = Array.isArray(data) ? data : [];
    renderStrikes();
}

function renderStrikes() {
    if (State.strikes.length === 0) {
        strikesGrid.innerHTML = `<div class="empty-state"><i class="fa-solid fa-check-circle"></i><p>Niciun jucător cu strike-uri active</p></div>`;
        return;
    }

    const maxStrikes = 3; // Se poate lua din config dacă e expus
    strikesGrid.innerHTML = State.strikes.map(s => {
        const dots = Array.from({ length: maxStrikes }, (_, i) =>
            `<div class="strike-dot ${i < s.count ? 'filled' : ''}"></div>`
        ).join('');
        return `
        <div class="strike-card">
            <div class="strike-card-header">
                <span class="strike-name">${sanitize(s.name)} <span style="color:var(--text-muted);font-size:11px">(ID: ${s.id})</span></span>
                <div class="strike-badge">${dots}</div>
            </div>
            <div class="strike-id">Strike-uri: <b style="color:var(--danger)">${s.count}</b> / ${maxStrikes}</div>
            <div class="strike-reason">Ultima detecție: ${sanitize(s.lastReason || 'N/A')}</div>
        </div>`;
    }).join('');
}

// ─────────────────────────────────────────────
// SETTINGS TAB
// ─────────────────────────────────────────────
async function loadStats() {
    const data = await fetchNUI('qxellAC:NUI:GetStats', {});
    if (!data) return;
    document.getElementById('info-players').textContent    = data.players    ?? '—';
    document.getElementById('info-bans').textContent       = data.bans       ?? '—';
    document.getElementById('info-detections').textContent = data.detections ?? '—';
    playerCountSide.textContent = `${data.players ?? 0} jucători online`;
}

// Ban manual din settings
document.getElementById('ban-submit-btn').addEventListener('click', async () => {
    const id       = parseInt(document.getElementById('ban-id-input').value);
    const reason   = document.getElementById('ban-reason-input').value.trim();
    const duration = parseInt(document.getElementById('ban-duration-input').value) || 0;
    if (!id || !reason) { showToast('Completează ID-ul și motivul!', 'warning'); return; }
    const res = await fetchNUI('qxellAC:NUI:BanPlayer', { id, reason, duration });
    if (res?.success) {
        showToast(`Jucătorul ID ${id} a fost banat.`, 'success');
        document.getElementById('ban-id-input').value     = '';
        document.getElementById('ban-reason-input').value = '';
    } else {
        showToast(res?.error || 'Eroare la ban.', 'error');
    }
});

// Unban din settings
document.getElementById('unban-submit-btn').addEventListener('click', async () => {
    const banId = document.getElementById('unban-id-input').value.trim();
    if (!banId) { showToast('Introdu un Ban ID!', 'warning'); return; }
    const res = await fetchNUI('qxellAC:NUI:Unban', { banId });
    if (res?.success) {
        showToast(`Unban executat: ${banId}`, 'success');
        document.getElementById('unban-id-input').value = '';
    } else {
        showToast(res?.error || 'Eroare la unban.', 'error');
    }
});

// Screenshot din settings
document.getElementById('ss-submit-btn').addEventListener('click', async () => {
    const id = parseInt(document.getElementById('ss-id-input').value);
    if (!id) { showToast('Introdu un Server ID valid!', 'warning'); return; }
    await fetchNUI('qxellAC:NUI:Screenshot', { id });
    showToast(`Screenshot solicitat pentru ID ${id}`, 'info');
    document.getElementById('ss-id-input').value = '';
});

// ─────────────────────────────────────────────
// UTILS
// ─────────────────────────────────────────────
function formatDate(str) {
    if (!str) return 'N/A';
    try {
        const d = new Date(str);
        return d.toLocaleString('ro-RO', {
            day: '2-digit', month: '2-digit', year: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    } catch { return str; }
}

// ─────────────────────────────────────────────
// NUI MESSAGE LISTENER (din Lua → JS)
// ─────────────────────────────────────────────
window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};

    switch (action) {
        case 'openMenu':
            openMenu();
            break;

        case 'closeMenu':
            overlay.classList.add('hidden');
            State.isOpen = false;
            break;

        case 'setServerName': {
            // Setează titlul serverului în sidebar
            const titleEl = document.getElementById('logo-title');
            if (titleEl && data?.name) {
                titleEl.textContent = data.name;
            }
            // Setează logo dacă există
            if (data?.logo) {
                const logoIcon = document.getElementById('logo-icon');
                if (logoIcon) {
                    logoIcon.innerHTML = `<img src="${sanitize(data.logo)}" style="width:24px;height:24px;border-radius:4px;object-fit:cover" alt="logo">`;
                }
            }
            break;
        }

        case 'toast':
            showToast(data?.message || '', data?.type || 'info');
            break;

        case 'updatePlayerCount':
            playerCountSide.textContent = `${data?.count ?? 0} jucători online`;
            break;
    }
});

// ESC key → închide meniu
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && State.isOpen) {
        if (!playerModal.classList.contains('hidden')) {
            playerModal.classList.add('hidden');
        } else {
            closeMenu();
        }
    }
});
