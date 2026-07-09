// ============================================================
//  VGX Showroom v4 — UI (multi-showroom + in-game admin panel)
// ============================================================

const S = {
    data: null,
    role: null,
    showroomId: null,
    slots: [],            // [{slot_no, x, y, z, heading}]
    taxRate: 0.10,
    showroomName: 'Showroom',
    currentListing: null,
    selectedVehForAdd: null,
    confirmCallback: null,
};

// admin panel state
const A = {
    data: null,           // { showrooms, admins, isSuper }
    createPoints: {},     // { entrance, dropoff, tdspawn, tdreturn }
    createSlots: [],      // [{x,y,z,w}]
    editId: null,
    editPoints: {},
};

const POINT_DEFS = [
    { key: 'entrance', label: 'Entrance (Browse marker)', hint: 'Players press E here to open the showroom', required: true },
    { key: 'dropoff',  label: 'Vehicle drop-off',         hint: 'Staff drive in here to list a vehicle',      required: true },
    { key: 'tdspawn',  label: 'Test-drive spawn',          hint: 'Optional — where test-drive cars spawn',     required: false },
    { key: 'tdreturn', label: 'Test-drive return',         hint: 'Optional — players return here afterwards',  required: false },
];

const VehicleClasses = ['Compact','Sedan','SUV','Coupe','Muscle','Sport Classic',
    'Sport','Super','Motorcycle','Off-road','Industrial','Utility','Van',
    'Cycles','Boat','Helicopter','Plane','Service','Emergency','Military','Commercial','Train'];

// ── NUI messages ──────────────────────────────────────────
window.addEventListener('message', ({ data: e }) => {
    switch (e.action) {
        case 'openMain':
            S.data        = e.data.data;
            S.role        = e.data.data.role;
            S.showroomId  = e.data.data.showroomId;
            S.slots       = e.data.data.slots || [];
            S.taxRate     = e.data.taxRate;
            S.showroomName= e.data.showroomName;
            showMain();
            break;
        case 'openInspect':
            S.showroomId = e.data.showroomId ?? S.showroomId;
            showInspect(e.data.listing, e.data.details, e.data.role);
            break;
        case 'updateListings':
            if (S.data) S.data.listings = e.data.listings;
            renderSlots();
            updateSidebar();
            break;
        case 'updateStaff':
            if (S.data) S.data.staff = e.data.staff;
            renderStaff();
            break;
        case 'updateTreasury':
            if (S.data && S.data.treasury) {
                S.data.treasury.balance = e.data.balance;
                if (e.data.log) S.data.treasury.log = e.data.log;
            }
            renderTreasury();
            break;
        case 'slotChanged':
            if (S.data) renderSlots();
            break;
        case 'openAdmin':
            A.data = e.data;
            showAdmin();
            break;
        case 'refreshAdmin':
            A.data = e.data;
            renderAdmin();
            break;
        case 'close':
            hideAll();
            break;
    }
});

// ── Show / hide ───────────────────────────────────────────
function showMain() {
    document.getElementById('brandName').textContent = S.showroomName;
    updateRoleBadge();
    updateSidebar();
    document.getElementById('mainApp').classList.remove('hidden');
    document.getElementById('inspectApp').classList.add('hidden');
    document.getElementById('adminApp').classList.add('hidden');

    const isStaff = S.role !== null;
    show('nav-addVehicle', isStaff);
    show('nav-staff', S.role === 'owner');
    show('nav-sales', isStaff);
    show('nav-treasury', (S.role === 'owner' || S.role === 'manager') && (S.data?.treasury?.enabled));

    switchMain('slots');
}

function hideAll() {
    document.getElementById('mainApp').classList.add('hidden');
    document.getElementById('inspectApp').classList.add('hidden');
    document.getElementById('adminApp').classList.add('hidden');
    cancelConfirm();
}

function closeMain() {
    post('close');
    hideAll();
}

function show(id, visible) {
    const el = document.getElementById(id);
    if (el) el.style.display = visible ? '' : 'none';
}

// ── Main tabs ─────────────────────────────────────────────
function switchMain(name) {
    document.querySelectorAll('#mainApp .nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('#mainApp .page').forEach(p => p.classList.remove('active'));
    const btn = document.getElementById('nav-' + name);
    if (btn) btn.classList.add('active');
    const page = document.getElementById('page-' + name);
    if (page) page.classList.add('active');

    if (name === 'slots')      renderSlots();
    if (name === 'addVehicle') loadMyVehicles();
    if (name === 'staff')      { renderStaff(); closeHirePanel(); }
    if (name === 'sales')      renderSales();
    if (name === 'treasury')   renderTreasury();
}

// ── Format helpers ────────────────────────────────────────
const fmt  = n => '$' + Number(n || 0).toLocaleString('en-US');
const fmtD = ts => ts ? new Date(ts).toLocaleDateString() + ' ' + new Date(ts).toLocaleTimeString([], { hour:'2-digit', minute:'2-digit' }) : '';
const modLevel = v => v < 0 ? 'Stock' : `Level ${v + 1}`;
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// ── Slots ─────────────────────────────────────────────────
function renderSlots() {
    const grid = document.getElementById('slotsGrid');
    const listings = S.data?.listings || [];
    const canAdd   = S.role && ['owner','manager','employee'].includes(S.role);
    const q = (document.getElementById('slotSearch')?.value || '').toLowerCase().trim();

    document.getElementById('slotCountLabel').textContent =
        listings.length + ' / ' + S.slots.length + ' slots occupied';
    updateSidebar();

    grid.innerHTML = '';

    if (S.slots.length === 0) {
        grid.innerHTML = '<div class="empty-state"><i class="fas fa-square-parking"></i><span>No parking slots yet — an admin can add them via /showrooms</span></div>';
        return;
    }

    for (const slot of S.slots) {
        const i   = slot.slot_no;
        const l   = listings.find(x => x.slot_id === i);
        if (q && (!l || !(String(l.label).toLowerCase().includes(q) || String(l.plate).toLowerCase().includes(q)))) continue;
        const div = document.createElement('div');
        div.className = 'slot-card' + (l ? ' occupied' : '');

        if (l) {
            div.innerHTML = `
                <span class="slot-num">#${i}</span>
                <i class="fas fa-car slot-car-icon"></i>
                <div class="slot-vname">${esc(l.label)}</div>
                <div class="slot-vprice">${fmt(l.price)}</div>
                <button class="slot-inspect-btn" onclick="inspectFromSlot(${i}, event)">
                    <i class="fas fa-eye"></i> Inspect
                </button>`;
        } else {
            div.innerHTML = `
                <span class="slot-num">#${i}</span>
                <i class="fas fa-parking slot-car-icon"></i>
                <div class="slot-empty">Empty Slot</div>
                ${canAdd ? `<button class="slot-add-chip" onclick="quickAddToSlot(${i}, event)"><i class="fas fa-plus"></i> Add</button>` : ''}`;
        }
        grid.appendChild(div);
    }
}

function inspectFromSlot(slotId, e) {
    if (e) e.stopPropagation();
    post('inspectSlot', { slotId, showroomId: S.showroomId });
}

function quickAddToSlot(slotId, e) {
    if (e) e.stopPropagation();
    switchMain('addVehicle');
    setTimeout(() => {
        const sel = document.getElementById('addSlotSelect');
        if (sel) sel.value = slotId;
    }, 300);
}

// ── Inspect modal ─────────────────────────────────────────
function showInspect(listing, details, role) {
    S.currentListing = listing;
    document.getElementById('mainApp').classList.add('hidden');
    document.getElementById('adminApp').classList.add('hidden');
    document.getElementById('inspectApp').classList.remove('hidden');
    document.getElementById('setPriceBox').classList.add('hidden');
    document.getElementById('changeSlotBox').classList.add('hidden');

    const tax   = Math.floor(listing.price * S.taxRate);
    const total = listing.price + tax;
    const cls   = VehicleClasses[details.class] || 'Vehicle';

    document.getElementById('inspectClass').textContent   = cls;
    document.getElementById('inspectName').textContent    = listing.label;
    document.getElementById('inspectModel').textContent   = listing.model;
    document.getElementById('inspectPlate').textContent   = listing.plate;
    document.getElementById('inspectPrice').textContent   = listing.price === 0 ? 'Price TBD' : fmt(listing.price);
    document.getElementById('inspectTotal').textContent   = listing.price > 0
        ? `Total with ${Math.round(S.taxRate * 100)}% tax: ${fmt(total)}`
        : 'Owner has not set a price yet';

    // Stats
    document.getElementById('statSpeed').textContent      = details.maxSpeed ? Math.round(details.maxSpeed) + ' km/h' : 'N/A';
    document.getElementById('statEngine').textContent     = modLevel(details.engine ?? -1);
    document.getElementById('statTrans').textContent      = modLevel(details.transmission ?? -1);
    document.getElementById('statSuspension').textContent = modLevel(details.suspension ?? -1);
    document.getElementById('statBrakes').textContent     = modLevel(details.brakes ?? -1);
    document.getElementById('statTurbo').textContent      = details.turbo ? '✓ Yes' : '✗ No';

    // Detail rows
    const detailList = document.getElementById('detailList');
    detailList.innerHTML = [
        ['Slot',        '#' + listing.slot_id],
        ['Listed Price', fmt(listing.price)],
        ['Tax',         fmt(tax)],
        ['Total Cost',  fmt(total)],
        ['Vehicle Class', cls],
        ['Plate',       listing.plate],
    ].map(([k, v]) => `
        <div class="detail-row"><span>${k}</span><span>${v}</span></div>
    `).join('');

    // Buttons
    const isStaff  = role && ['owner','manager'].includes(role);
    const canBuy   = listing.price > 0;
    document.getElementById('buyBtn').style.display = canBuy ? '' : 'none';
    document.getElementById('buyBtn').textContent = '';
    document.getElementById('buyBtn').innerHTML = `<i class="fas fa-shopping-cart"></i> Purchase ${fmt(total)}`;

    const staffActions = document.getElementById('staffInspectActions');
    staffActions.classList.toggle('hidden', !isStaff);
    if (isStaff) staffActions.style.display = 'flex';

    // Focus camera on vehicle in world
    post('focusSlot', { slotId: listing.slot_id, showroomId: S.showroomId });
}

function closeInspect() {
    post('releaseCamera');
    document.getElementById('inspectApp').classList.add('hidden');
    document.getElementById('mainApp').classList.remove('hidden');
    S.currentListing = null;
    cancelSetPrice();
    switchMain('slots');
}

// ── Buy vehicle ───────────────────────────────────────────
function confirmBuy() {
    if (!S.currentListing) return;
    const tax   = Math.floor(S.currentListing.price * S.taxRate);
    const total = S.currentListing.price + tax;
    showConfirm(
        'Purchase ' + S.currentListing.label + '?',
        `Total cost: ${fmt(total)} (incl. ${fmt(tax)} tax)\nThe vehicle will be added to your garage.`,
        () => {
            post('buyVehicle', { listingId: S.currentListing.id });
        }
    );
}

// ── Set price ─────────────────────────────────────────────
function openSetPrice() {
    const box = document.getElementById('setPriceBox');
    box.classList.remove('hidden');
    document.getElementById('newPriceInput').value = S.currentListing?.price || 0;
    document.getElementById('newPriceInput').focus();
}

function cancelSetPrice() {
    document.getElementById('setPriceBox').classList.add('hidden');
}

function submitPrice() {
    const price = parseInt(document.getElementById('newPriceInput').value);
    if (isNaN(price) || price < 0) return;
    post('setPrice', { listingId: S.currentListing.id, price });
    if (S.currentListing) S.currentListing.price = price;
    // Update UI
    const tax   = Math.floor(price * S.taxRate);
    const total = price + tax;
    document.getElementById('inspectPrice').textContent = fmt(price);
    document.getElementById('inspectTotal').textContent = `Total with ${Math.round(S.taxRate*100)}% tax: ${fmt(total)}`;
    document.getElementById('buyBtn').innerHTML = `<i class="fas fa-shopping-cart"></i> Purchase ${fmt(total)}`;
    cancelSetPrice();
}

// ── Change slot ───────────────────────────────────────────
function openChangeSlot() {
    const box = document.getElementById('changeSlotBox');
    document.getElementById('setPriceBox').classList.add('hidden');
    const listings = S.data?.listings || [];
    const cur = S.currentListing?.slot_id;
    const sel = document.getElementById('newSlotSelect');
    const free = [];
    for (const slot of S.slots) {
        if (slot.slot_no === cur) continue;
        if (!listings.find(l => l.slot_id === slot.slot_no)) free.push(slot.slot_no);
    }
    sel.innerHTML = free.length === 0
        ? '<option value="">No free slots</option>'
        : free.map(s => `<option value="${s}">Slot #${s}</option>`).join('');
    box.classList.remove('hidden');
}

function cancelChangeSlot() {
    document.getElementById('changeSlotBox').classList.add('hidden');
}

function submitChangeSlot() {
    const newSlot = parseInt(document.getElementById('newSlotSelect').value);
    if (isNaN(newSlot)) return;
    post('changeSlot', { listingId: S.currentListing.id, newSlot });
    if (S.currentListing) S.currentListing.slot_id = newSlot;
    cancelChangeSlot();
    closeInspect();
}

// ── Treasury ──────────────────────────────────────────────
function renderTreasury() {
    const t = S.data?.treasury || { balance: 0, log: [] };
    document.getElementById('treasuryBalance').textContent = fmt(t.balance);
    const log = document.getElementById('treasuryLog');
    if (!t.log || t.log.length === 0) {
        log.innerHTML = '<div class="empty-state"><i class="fas fa-inbox"></i><span>No treasury activity yet</span></div>';
        return;
    }
    const icon = { deposit: 'fa-arrow-down', withdraw: 'fa-arrow-up', sale: 'fa-car' };
    const sign = { deposit: '+', withdraw: '\u2212', sale: '+' };
    log.innerHTML = t.log.map(e => `
        <div class="treasury-row">
            <div class="treasury-row-left">
                <i class="fas ${icon[e.type] || 'fa-circle'} amt-${e.type}"></i>
                <div>
                    <div class="treasury-row-type">${(e.type || '').toUpperCase()}</div>
                    <div class="treasury-row-note">${esc(e.name)}${e.note ? ' • ' + esc(e.note) : ''}</div>
                </div>
            </div>
            <div class="treasury-row-right">
                <div class="treasury-row-amt amt-${e.type}">${sign[e.type] || ''}${fmt(e.amount)}</div>
                <div class="treasury-row-date">${fmtD(e.created_at)}</div>
            </div>
        </div>
    `).join('');
}

function treasuryDo(action) {
    const id = action === 'withdraw' ? 'withdrawAmount' : 'depositAmount';
    const amount = parseInt(document.getElementById(id).value);
    if (isNaN(amount) || amount <= 0) return;
    post('treasuryAction', { action, amount, showroomId: S.showroomId });
    document.getElementById(id).value = '';
}

// ── Remove vehicle ────────────────────────────────────────
function confirmRemove() {
    if (!S.currentListing) return;
    showConfirm(
        'Remove ' + S.currentListing.label + '?',
        'The vehicle will be removed from the showroom and returned to the owner\'s garage.',
        () => {
            post('removeVehicle', { listingId: S.currentListing.id });
            closeInspect();
        }
    );
}

// ── Add vehicle page ───────────────────────────────────────
async function loadMyVehicles() {
    const picker = document.getElementById('myVehiclesList');
    picker.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin"></i><span>Loading your vehicles...</span></div>';
    document.getElementById('addVehicleForm').classList.add('hidden');
    S.selectedVehForAdd = null;

    const vehs = await postAsync('getMyVehicles');
    if (!vehs || vehs.length === 0) {
        picker.innerHTML = '<div class="empty-state"><i class="fas fa-car-crash"></i><span>No vehicles available to list</span></div>';
        return;
    }

    // Build slot dropdown (only empty slots)
    const listings = S.data?.listings || [];
    const freeSlots = [];
    for (const slot of S.slots) {
        if (!listings.find(l => l.slot_id === slot.slot_no)) freeSlots.push(slot.slot_no);
    }
    const slotSel = document.getElementById('addSlotSelect');
    slotSel.innerHTML = freeSlots.map(s => `<option value="${s}">Slot #${s}</option>`).join('');

    picker.innerHTML = vehs.map((v, idx) => `
        <div class="veh-pick-card" id="vpick-${idx}" onclick="selectVehicleForAdd(${idx}, '${esc(v.model)}', '${esc(v.plate)}', '${esc(v.label || v.model)}')">
            <div class="veh-pick-icon"><i class="fas fa-car"></i></div>
            <div>
                <div class="veh-pick-name">${esc(v.label || v.model)}</div>
                <div class="veh-pick-plate">${esc(v.plate)}</div>
            </div>
        </div>
    `).join('');

    // Store vehicles for later
    window._myVehs = vehs;
}

function selectVehicleForAdd(idx, model, plate, label) {
    document.querySelectorAll('.veh-pick-card').forEach(c => c.classList.remove('selected'));
    document.getElementById('vpick-' + idx)?.classList.add('selected');
    S.selectedVehForAdd = { model, plate, label };
    document.getElementById('addLabel').value = label || model;
    document.getElementById('addVehicleForm').classList.remove('hidden');
}

function cancelAddVehicle() {
    document.getElementById('addVehicleForm').classList.add('hidden');
    S.selectedVehForAdd = null;
    document.querySelectorAll('.veh-pick-card').forEach(c => c.classList.remove('selected'));
}

function submitAddVehicle() {
    if (!S.selectedVehForAdd) return;
    const label  = document.getElementById('addLabel').value.trim();
    const price  = parseInt(document.getElementById('addPrice').value);
    const slotId = parseInt(document.getElementById('addSlotSelect').value);

    if (!label) { alert('Enter a display name'); return; }
    if (isNaN(price) || price < 0) { alert('Enter a valid price'); return; }
    if (isNaN(slotId)) { alert('No free slot selected'); return; }

    post('addVehicle', {
        showroomId: S.showroomId,
        slotId,
        model : S.selectedVehForAdd.model,
        plate : S.selectedVehForAdd.plate,
        label,
        price,
    });
    cancelAddVehicle();
    switchMain('slots');
}

// ── Staff ─────────────────────────────────────────────────
function renderStaff() {
    const list  = document.getElementById('staffList');
    const staff = S.data?.staff || [];
    const isOwner = S.role === 'owner';

    if (staff.length === 0) {
        list.innerHTML = '<div class="empty-state"><i class="fas fa-user-slash"></i><span>No staff hired yet</span></div>';
        return;
    }

    list.innerHTML = staff.map(s => `
        <div class="staff-card">
            <div class="staff-info">
                <div class="staff-avatar"><i class="fas fa-user"></i></div>
                <div>
                    <div class="staff-name">${esc(s.name)}</div>
                    <div class="staff-cid">${esc(s.citizenid)}</div>
                </div>
            </div>
            <div class="staff-right">
                <span class="badge badge-${esc(s.role)}">${esc(s.role)}</span>
                ${isOwner ? `<button class="btn btn-danger btn-sm" onclick="fireStaff(${s.id},'${esc(s.name)}')"><i class="fas fa-user-minus"></i></button>` : ''}
            </div>
        </div>
    `).join('');
}

async function openHirePanel() {
    document.getElementById('hirePanel').classList.remove('hidden');
    const sel = document.getElementById('hirePlayerSelect');
    sel.innerHTML = '<option value="">Loading players...</option>';
    const players = await postAsync('getOnlinePlayers', { showroomId: S.showroomId });
    if (!players || players.length === 0) {
        sel.innerHTML = '<option value="">No players online</option>';
        return;
    }
    sel.innerHTML = players.map(p =>
        `<option value="${esc(p.citizenid)}" data-name="${esc(p.name)}">${esc(p.name)} — ${esc(p.citizenid)}</option>`
    ).join('');
}

function closeHirePanel() {
    document.getElementById('hirePanel').classList.add('hidden');
}

function submitHire() {
    const sel  = document.getElementById('hirePlayerSelect');
    const cid  = sel.value;
    const name = sel.options[sel.selectedIndex]?.getAttribute('data-name') || cid;
    const role = document.getElementById('hireRole').value;
    if (!cid) return;
    post('hireStaff', { showroomId: S.showroomId, citizenid: cid, name, role });
    closeHirePanel();
}

function fireStaff(staffId, name) {
    showConfirm('Fire ' + name + '?', 'They will lose access to the showroom immediately.', () => {
        post('fireStaff', { staffId });
    });
}

// ── Sales log ─────────────────────────────────────────────
function renderSales() {
    const list  = document.getElementById('salesList');
    const sales = S.data?.sales || [];

    if (sales.length === 0) {
        list.innerHTML = '<div class="empty-state"><i class="fas fa-receipt"></i><span>No sales recorded yet</span></div>';
        return;
    }

    list.innerHTML = sales.map(s => `
        <div class="sale-card">
            <div>
                <div class="sale-veh"><i class="fas fa-car" style="color:var(--accent);margin-right:6px"></i>${esc(s.label)}</div>
                <div class="sale-info">Buyer: ${esc(s.buyer_name)} &bull; Seller: ${esc(s.seller_cid)} &bull; Plate: ${esc(s.plate)}</div>
            </div>
            <div>
                <div class="sale-price">${fmt(s.price)}</div>
                <div class="sale-date">${fmtD(s.sold_at)}</div>
            </div>
        </div>
    `).join('');
}

// ══════════════════════════════════════════════════════════
//  ADMIN PANEL — create showrooms / slots / points in-game
// ══════════════════════════════════════════════════════════

function showAdmin() {
    hideAll();
    A.createPoints = {};
    A.createSlots  = [];
    A.editId       = null;
    A.editPoints   = {};
    document.getElementById('adminApp').classList.remove('hidden');
    show('anav-admins', !!A.data?.isSuper);
    renderAdmin();
    switchAdmin('list');
}

function closeAdmin() {
    post('close');
    hideAll();
}

function switchAdmin(name) {
    document.querySelectorAll('#adminApp .nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('#adminApp .page').forEach(p => p.classList.remove('active'));
    const btn = document.getElementById('anav-' + name);
    if (btn) btn.classList.add('active');
    const page = document.getElementById('apage-' + name);
    if (page) page.classList.add('active');
}

function renderAdmin() {
    renderAdminList();
    renderCreatePoints();
    renderCreateSlots();
    renderAdminAdmins();
    show('anav-admins', !!A.data?.isSuper);
}

// — Showroom list —
function renderAdminList() {
    const list = document.getElementById('adminSrList');
    const showrooms = A.data?.showrooms || [];

    if (showrooms.length === 0) {
        list.innerHTML = '<div class="empty-state"><i class="fas fa-warehouse"></i><span>No showrooms yet — create your first one!</span></div>';
        return;
    }

    list.innerHTML = showrooms.map(sr => `
        <div class="admin-sr-card">
            <div class="admin-sr-head">
                <div>
                    <div class="admin-sr-name">${esc(sr.name)} <small>#${sr.id}</small></div>
                    <div class="admin-sr-meta">
                        <span>Owner: <b>${esc(sr.owner_name || '—')}</b></span>
                        <span>Slots: <b>${(sr.slots || []).length}</b></span>
                        <span>Listed cars: <b>${sr.listings || 0}</b></span>
                        <span>Treasury: <b>${fmt(sr.treasury)}</b></span>
                    </div>
                </div>
                <button class="btn btn-danger btn-sm" onclick="confirmDeleteShowroom(${sr.id}, '${esc(sr.name)}')"><i class="fas fa-trash"></i> Delete</button>
            </div>

            <div class="admin-slot-strip">
                ${(sr.slots || []).map(s => `
                    <span class="slot-chip">#${s.slot_no}
                        <button class="chip-x" title="Remove slot" onclick="removeSlot(${sr.id}, ${s.slot_no})"><i class="fas fa-times"></i></button>
                    </span>`).join('') || '<span class="hint-note">No parking slots yet</span>'}
            </div>

            <div class="admin-sr-actions">
                <input type="number" id="own_${sr.id}" placeholder="Player ID"/>
                <button class="btn btn-ghost btn-sm" onclick="setOwner(${sr.id})"><i class="fas fa-key"></i> Set owner</button>
                <button class="btn btn-ghost btn-sm" onclick="clearOwner(${sr.id})"><i class="fas fa-key"></i> Clear owner</button>
                <button class="btn btn-ghost btn-sm" onclick="addSlotHere(${sr.id})"><i class="fas fa-square-parking"></i> Add parking slot here</button>
                <button class="btn btn-ghost btn-sm" onclick="openEditPoints(${sr.id})"><i class="fas fa-location-dot"></i> Edit points</button>
                <input type="text" id="rename_${sr.id}" placeholder="New name" style="width:150px"/>
                <button class="btn btn-ghost btn-sm" onclick="renameShowroom(${sr.id})"><i class="fas fa-pen"></i> Rename</button>
            </div>
        </div>
    `).join('');
}

function setOwner(id) {
    const v = document.getElementById('own_' + id)?.value;
    if (!v) return;
    post('adminSetOwner', { id, targetId: v });
}
function clearOwner(id) { post('adminSetOwner', { id, targetId: 0 }); }

function renameShowroom(id) {
    const v = document.getElementById('rename_' + id)?.value.trim();
    if (!v) return;
    post('adminRename', { id, name: v });
}

async function addSlotHere(id) {
    const point = await postAsync('getMyCoords');
    if (!point) return;
    post('adminAddSlot', { id, point });
}

function removeSlot(id, slotNo) {
    showConfirm('Remove slot #' + slotNo + '?',
        'The parking slot will be deleted. Slots with a listed vehicle cannot be removed.',
        () => post('adminRemoveSlot', { id, slotNo }));
}

function confirmDeleteShowroom(id, name) {
    showConfirm('Delete ' + name + '?',
        'All listed vehicles will be returned to their owners\' garages. This cannot be undone.',
        () => post('adminDelete', { id }));
}

// — Point capture (shared renderer for create + edit) —
const fmtPt = p => p ? `x ${(+p.x).toFixed(2)}  y ${(+p.y).toFixed(2)}  z ${(+p.z).toFixed(2)}${p.w !== undefined ? '  h ' + (+p.w).toFixed(1) : ''}` : 'Not captured yet';

function pointRowsHTML(points, prefix) {
    return POINT_DEFS.map(def => {
        const p = points[def.key];
        return `
        <div class="point-row">
            <div class="pr-label">${def.label}${def.required ? ' *' : ''}<small>${def.hint}</small></div>
            <div class="pr-coords ${p ? 'set' : ''}">${fmtPt(p)}</div>
            <button class="btn btn-accent btn-sm" onclick="capturePoint('${prefix}','${def.key}')"><i class="fas fa-crosshairs"></i> Capture</button>
            <button class="btn btn-ghost btn-sm" onclick="clearPoint('${prefix}','${def.key}')"><i class="fas fa-eraser"></i></button>
        </div>`;
    }).join('');
}

function renderCreatePoints() {
    document.getElementById('createPointRows').innerHTML = pointRowsHTML(A.createPoints, 'create');
}
function renderEditPoints() {
    document.getElementById('editPointRows').innerHTML = pointRowsHTML(A.editPoints, 'edit');
}

async function capturePoint(prefix, key) {
    const c = await postAsync('getMyCoords');
    if (!c) return;
    const target = prefix === 'create' ? A.createPoints : A.editPoints;
    // tdspawn keeps a heading; the rest are position-only
    target[key] = (key === 'tdspawn') ? c : { x: c.x, y: c.y, z: c.z };
    prefix === 'create' ? renderCreatePoints() : renderEditPoints();
}

function clearPoint(prefix, key) {
    const target = prefix === 'create' ? A.createPoints : A.editPoints;
    delete target[key];
    prefix === 'create' ? renderCreatePoints() : renderEditPoints();
}

// — Create showroom —
function renderCreateSlots() {
    const list = document.getElementById('createSlotList');
    if (A.createSlots.length === 0) {
        list.innerHTML = '<span class="hint-note">No slots captured yet — every captured spot becomes one display parking slot.</span>';
        return;
    }
    list.innerHTML = A.createSlots.map((s, i) => `
        <span class="slot-chip">#${i + 1}
            <small>${(+s.x).toFixed(1)}, ${(+s.y).toFixed(1)}</small>
            <button class="chip-x" onclick="removeCreateSlot(${i})"><i class="fas fa-times"></i></button>
        </span>
    `).join('');
}

async function captureCreateSlot() {
    const c = await postAsync('getMyCoords');
    if (!c) return;
    A.createSlots.push(c);
    renderCreateSlots();
}

function removeCreateSlot(i) {
    A.createSlots.splice(i, 1);
    renderCreateSlots();
}

function resetCreateForm() {
    A.createPoints = {};
    A.createSlots  = [];
    document.getElementById('createName').value = '';
    renderCreatePoints();
    renderCreateSlots();
}

function submitCreateShowroom() {
    const name = document.getElementById('createName').value.trim();
    if (!name) { alert('Enter a showroom name'); return; }
    if (!A.createPoints.entrance || !A.createPoints.dropoff) {
        alert('Capture the entrance and drop-off points first');
        return;
    }
    if (A.createSlots.length === 0) {
        alert('Capture at least one vehicle parking slot');
        return;
    }
    post('adminCreate', {
        name,
        points: A.createPoints,
        slots: A.createSlots,
    });
    resetCreateForm();
    switchAdmin('list');
}

// — Edit points —
function openEditPoints(id) {
    const sr = (A.data?.showrooms || []).find(s => s.id === id);
    if (!sr) return;
    A.editId = id;
    A.editPoints = JSON.parse(JSON.stringify(sr.points || {}));
    document.getElementById('editPointsTitle').textContent = sr.name + ' (#' + id + ')';
    renderEditPoints();
    switchAdmin('editpoints');
}

function submitEditPoints() {
    if (!A.editId) return;
    if (!A.editPoints.entrance || !A.editPoints.dropoff) {
        alert('Entrance and drop-off points are required');
        return;
    }
    post('adminUpdatePoints', { id: A.editId, points: A.editPoints });
    switchAdmin('list');
}

// — Admin management —
function renderAdminAdmins() {
    const list = document.getElementById('adminAdminList');
    const admins = A.data?.admins || [];

    if (admins.length === 0) {
        list.innerHTML = '<div class="empty-state"><i class="fas fa-user-slash"></i><span>No extra admins — only Config.SuperAdmins have access</span></div>';
        return;
    }

    list.innerHTML = admins.map(a => `
        <div class="staff-card">
            <div class="staff-info">
                <div class="staff-avatar"><i class="fas fa-user-shield"></i></div>
                <div>
                    <div class="staff-name">${esc(a.name)}</div>
                    <div class="staff-cid">${esc(a.identifier)}</div>
                </div>
            </div>
            <button class="btn btn-danger btn-sm" onclick="removeAdmin('${esc(a.identifier)}')"><i class="fas fa-user-minus"></i></button>
        </div>
    `).join('');
}

function submitAddAdmin() {
    const v = document.getElementById('adminAddInput').value.trim();
    if (!v) return;
    post('adminAddAdmin', { input: v });
    document.getElementById('adminAddInput').value = '';
}

function removeAdmin(identifier) {
    showConfirm('Remove this admin?', identifier, () => post('adminRemoveAdmin', { identifier }));
}

// ── Confirm overlay ───────────────────────────────────────
function showConfirm(title, sub, onConfirm) {
    S.confirmCallback = onConfirm;
    document.getElementById('confirmTitle').textContent = title;
    document.getElementById('confirmSub').textContent   = sub;
    document.getElementById('confirmOverlay').classList.remove('hidden');
    document.getElementById('confirmOkBtn').onclick = () => {
        S.confirmCallback?.();
        cancelConfirm();
    };
}

function cancelConfirm() {
    document.getElementById('confirmOverlay').classList.add('hidden');
    S.confirmCallback = null;
}

// ── Sidebar stats ─────────────────────────────────────────
function updateSidebar() {
    const listings = S.data?.listings || [];
    const sales    = S.data?.sales || [];

    const elCount = document.getElementById('statListedCount');
    if (!elCount) return;
    elCount.textContent = listings.length;
    document.getElementById('statSlotTotal').textContent = S.slots.length || 0;
    const pct = S.slots.length ? Math.round((listings.length / S.slots.length) * 100) : 0;
    document.getElementById('statSlotFill').style.width = pct + '%';

    let revenue = 0, taxes = 0;
    for (const s of sales) { revenue += Number(s.price) || 0; taxes += Number(s.tax) || 0; }
    document.getElementById('statTotalSales').textContent = sales.length;
    document.getElementById('statRevenue').textContent    = fmt(revenue);
    document.getElementById('statTaxes').textContent      = fmt(taxes);
}

function updateRoleBadge() {
    const badge = document.getElementById('roleBadge');
    if (!badge) return;
    const role = S.role || 'visitor';
    badge.className = 'badge badge-' + role;
    badge.textContent = role.charAt(0).toUpperCase() + role.slice(1);
}

// ── NUI post helpers ──────────────────────────────────────
function post(action, data) {
    fetch('https://vgx-showroom/' + action, {
        method: 'POST',
        body: JSON.stringify(data || {})
    });
}

function postAsync(action, data) {
    return fetch('https://vgx-showroom/' + action, {
        method: 'POST',
        body: JSON.stringify(data || {})
    }).then(r => r.json()).catch(() => null);
}

// ── ESC ───────────────────────────────────────────────────
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
        if (!document.getElementById('inspectApp').classList.contains('hidden')) {
            closeInspect();
        } else if (!document.getElementById('adminApp').classList.contains('hidden')) {
            closeAdmin();
        } else {
            closeMain();
        }
    }
});
