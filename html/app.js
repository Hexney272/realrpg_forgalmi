let serviceState = null;
let selected = { inspection: true, fuel: false };

const $ = (id) => document.getElementById(id);
const serviceApp = $('serviceApp');
const documentApp = $('documentApp');
const documentPaper = $('documentPaper');
const officeApp = $('officeApp');
const insuranceApp = $('insuranceApp');
const contractApp = $('contractApp');
let officeState = null;
let selectedPlate = null;

function post(name, data = {}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

// Null-biztos képernyő-kezelők: ha egy elem hiányzik, nem száll el a NUI.
function hide(el) { if (el && el.classList) el.classList.add('hidden'); }
function show(el) { if (el && el.classList) el.classList.remove('hidden'); }
function hideAllScreens() {
    hide(serviceApp);
    hide(documentApp);
    hide(officeApp);
    hide(insuranceApp);
    hide(contractApp);
}

function fmtMoney(value, currency) {
    const n = Number(value || 0);
    return n.toLocaleString('hu-HU').replace(/\s/g, ' ') + ' ' + (currency || 'Ft');
}

function closeAll() {
    hideAllScreens();
    post('close');
}

function updateServiceTotals() {
    if (!serviceState) return;
    let total = 0;
    if (selected.inspection) total += Number(serviceState.inspection?.price || 0);
    if (selected.fuel && serviceState.fuel?.enabled) total += Number(serviceState.fuel?.price || 0);

    const ic = $('inspectionCheck'); if (ic) ic.classList.toggle('checked', selected.inspection);
    const fc = $('fuelCheck'); if (fc) fc.classList.toggle('checked', selected.fuel);
    const tp = $('totalPrice'); if (tp) tp.textContent = fmtMoney(total, serviceState.currency);
    const pp = $('payPrice'); if (pp) pp.textContent = fmtMoney(total, serviceState.currency);
}

function openService(payload) {
    serviceState = payload;
    selected = { inspection: true, fuel: false };

    const company = $('serviceCompany'); if (company) company.textContent = payload.company || 'REAL OF LOS SANTOS';
    const insLabel = $('inspectionLabel'); if (insLabel) insLabel.innerHTML = `${payload.inspection?.label || 'Műszaki vizsga'} <em>(${payload.inspection?.time || '00:15'})</em>`;
    const insPrice = $('inspectionPrice'); if (insPrice) insPrice.textContent = fmtMoney(payload.inspection?.price || 0, payload.currency);

    if (payload.fuel?.enabled) {
        show($('fuelRow'));
        const fuelLabel = $('fuelLabel'); if (fuelLabel) fuelLabel.innerHTML = `${payload.fuel?.label || '5L üzemanyag'} <em>(${payload.fuel?.time || '00:05'})</em>`;
        const fuelPrice = $('fuelPrice'); if (fuelPrice) fuelPrice.textContent = fmtMoney(payload.fuel?.price || 0, payload.currency);
    } else {
        hide($('fuelRow'));
    }

    hide(documentApp);
    show(serviceApp);
    updateServiceTotals();
}

function setText(id, value) {
    const el = $(id);
    if (!el) return;
    el.textContent = (value === undefined || value === null || value === '') ? 'nincs' : String(value);
}

function chipColor(el, name) {
    if (!el) return;
    const value = String(name || '').toLowerCase();
    let color = '#111';
    if (value.includes('fehér') || value.includes('white')) color = '#f8f8f8';
    else if (value.includes('kék') || value.includes('blue')) color = '#4468c8';
    else if (value.includes('piros') || value.includes('red')) color = '#bf2a2a';
    else if (value.includes('zöld') || value.includes('green')) color = '#2c8b45';
    else if (value.includes('sárga') || value.includes('yellow') || value.includes('gold')) color = '#e5c83d';
    else if (value.includes('narancs') || value.includes('orange')) color = '#df7c2a';
    else if (value.includes('lila') || value.includes('purple')) color = '#7542aa';
    else if (value.includes('ezüst') || value.includes('silver') || value.includes('szürke')) color = '#a3a3a3';
    else if (value.includes('barna') || value.includes('brown')) color = '#6d472b';
    el.style.background = color;
}

function openDocument(payload) {
    const f = payload.fields || {};
    const invalid = !!payload.invalid;

    if (documentPaper) documentPaper.classList.toggle('invalid', invalid);
    const stamp = $('invalidStamp');
    if (stamp) {
        stamp.classList.toggle('hidden', !invalid);
        stamp.textContent = payload.invalidText || 'ÉRVÉNYTELEN';
    }

    setText('docCity', f.cityName || 'Real City');
    setText('docTitle', f.title || 'Forgalmi engedély');
    setText('docLogo', f.logo || 'REAL');
    setText('docSerial', payload.serial || 'NJ000000');

    setText('f_type', f.type);
    setText('f_owner', f.owner);
    setText('f_vin', f.vin);
    setText('f_engine_code', f.engineCode);
    setText('f_plate', f.plate);
    setText('f_identifier', f.identifier);
    setText('f_fuel', f.fuel);
    setText('f_tier', f.tier);
    setText('f_inspection', f.inspectionValidUntil);

    setText('f_paintjob', f.paintJob);
    setText('f_roofpaint', f.roofPaint);
    chipColor($('chip_interior'), f.interiorColor);
    chipColor($('chip_dashboard'), f.dashboardColor);
    chipColor($('chip_primary'), f.primaryColor);
    chipColor($('chip_secondary'), f.secondaryColor);

    setText('f_rim', f.rim);
    setText('f_rimpaint', f.rimPaint);
    setText('f_rimsticker', f.rimSticker);
    setText('f_engine', f.engine);
    setText('f_suspension', f.suspension);
    setText('f_turbo', f.turbo);
    setText('f_tires', f.tires);
    setText('f_transmission', f.transmission);
    setText('f_brakes', f.brakes);
    setText('f_ecu', f.ecu);
    setText('f_weight', f.weightReduction);

    setText('f_frontcamber', f.frontCamber);
    setText('f_rearcamber', f.rearCamber);
    setText('f_fronttrack', f.frontTrack);
    setText('f_reartrack', f.rearTrack);
    setText('f_steering', f.steeringAngle);
    setText('f_tint', f.windowTint);
    setText('f_lighttype', f.lightType);
    setText('f_lightcolor', f.lightColor);
    setText('f_horn', f.uniqueSound);
    setText('f_nitrous', f.nitrous);
    setText('f_backfire', f.backfire);
    setText('f_height', f.rideHeight || 'nincs');
    setText('f_optical', f.opticalTuning);
    setText('f_neonlayout', f.neonLayout);
    setText('f_neoncolor2', f.neonType);
    setText('f_neoncolor', f.neonColor);
    setText('f_issue', f.issueDate);

    hide(serviceApp);
    show(documentApp);
}

function openInsurance(payload) {
    setText('ins_serial', payload.serial || '-');
    setText('ins_owner', payload.owner || '-');
    setText('ins_vehicle', payload.modelLabel || '-');
    setText('ins_plate', payload.plate || '-');
    setText('ins_valid', payload.validUntil || '-');
    setText('ins_issued', payload.issuedAt || '-');
    setText('ins_price', fmtMoney(payload.price, payload.currency));

    hideAllScreens();
    show(insuranceApp);
}

let contractState = null;

function openContract(payload) {
    contractState = payload;
    setText('ct_seller', payload.sellerName || '-');
    setText('ct_buyer', payload.buyerName || '-');
    setText('ct_model', payload.modelLabel || '-');
    setText('ct_plate', payload.plate || '-');
    setText('ct_price', fmtMoney(payload.price, payload.currency));
    setText('ct_date', payload.date || '-');

    const sigSeller = $('ct_sig_seller');
    const sigBuyer = $('ct_sig_buyer');
    if (sigSeller) sigSeller.textContent = payload.sellerSigned ? payload.sellerName : '';
    if (sigBuyer) sigBuyer.textContent = payload.buyerSigned ? payload.buyerName : '';

    const signBtn = $('btnSign');
    if (signBtn) {
        if (payload.role === 'seller' && !payload.sellerSigned) {
            signBtn.textContent = 'Aláírás (Eladó)';
            signBtn.classList.remove('signed');
            signBtn.style.display = '';
        } else if (payload.role === 'buyer' && !payload.buyerSigned) {
            signBtn.textContent = 'Aláírás (Vevő)';
            signBtn.classList.remove('signed');
            signBtn.style.display = '';
        } else {
            signBtn.style.display = 'none';
        }
    }

    hideAllScreens();
    show(contractApp);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'openService') openService(data.payload || {});
    if (data.action === 'openDocument') openDocument(data.payload || {});
    if (data.action === 'openOffice') openOffice(data.payload || {});
    if (data.action === 'openInsurance') openInsurance(data.payload || {});
    if (data.action === 'openContract') openContract(data.payload || {});
    if (data.action === 'forceClose') {
        hideAllScreens();
    }
});

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' || event.key === 'Backspace') closeAll();
});

document.querySelectorAll('[data-close="true"]').forEach((btn) => btn.addEventListener('click', closeAll));

const inspectionRow = document.querySelector('[data-row="inspection"]');
if (inspectionRow) inspectionRow.addEventListener('click', () => {
    selected.inspection = !selected.inspection;
    updateServiceTotals();
});

document.querySelector('[data-row="fuel"]') && document.querySelector('[data-row="fuel"]').addEventListener('click', () => {
    selected.fuel = !selected.fuel;
    updateServiceTotals();
});

const serviceSubmitBtn = $('serviceSubmit');
if (serviceSubmitBtn) serviceSubmitBtn.addEventListener('click', () => {
    if (!serviceState) return;
    if (!selected.inspection && !selected.fuel) return;

    const payload = {
        vehicleData: serviceState.vehicleData,
        inspection: selected.inspection,
        fuel: selected.fuel
    };

    hide(serviceApp);
    post('serviceSubmit', payload);
});



function openOffice(payload) {
    officeState = payload;
    selectedPlate = null;
    const list = $('officeVehicleList');
    const vehicles = payload.vehicles || [];

    if (list) {
        if (vehicles.length === 0) {
            list.innerHTML = '<div style="color:rgba(255,255,255,.5);text-align:center;padding:20px;font-size:13px;">Nincs elérhető jármű.</div>';
        } else {
            list.innerHTML = vehicles.map(v => `
                <div class="office-vehicle-item" data-plate="${v.plate}">
                    <div>
                        <div class="plate">${v.plate}</div>
                        <div class="model">${v.model_label || 'Ismeretlen'}</div>
                    </div>
                    <span class="status ${v.status}">${v.status === 'valid' ? 'Forgalmi OK' : 'Vizsgázott'}</span>
                </div>
            `).join('');
        }
    }

    hide($('officeActions'));
    const sel = $('officeSelected'); if (sel) sel.textContent = '-';

    hide(serviceApp);
    hide(documentApp);
    show(officeApp);

    // Bind vehicle clicks
    if (list) {
        list.querySelectorAll('.office-vehicle-item').forEach(el => {
            el.addEventListener('click', () => {
                list.querySelectorAll('.office-vehicle-item').forEach(e => e.classList.remove('active'));
                el.classList.add('active');
                selectedPlate = el.dataset.plate;
                const s = $('officeSelected'); if (s) s.textContent = 'Kiválasztva: ' + selectedPlate;
                show($('officeActions'));
            });
        });
    }
}

document.addEventListener('click', (e) => {
    if (e.target.id === 'btnIssueDoc' && selectedPlate) {
        hide(officeApp);
        post('officeAction', { action: 'issueDocument', plate: selectedPlate });
    }
    if (e.target.id === 'btnInsurance' && selectedPlate) {
        hide(officeApp);
        post('officeAction', { action: 'buyInsurance', plate: selectedPlate });
    }
    if (e.target.id === 'btnTax' && selectedPlate) {
        hide(officeApp);
        post('officeAction', { action: 'payTax', plate: selectedPlate });
    }
    if (e.target.id === 'btnReplace' && selectedPlate) {
        hide(officeApp);
        post('officeAction', { action: 'replaceDocument', plate: selectedPlate });
    }
});


document.addEventListener('click', function(e) {
    if (e.target.id === 'btnSign' && contractState) {
        e.target.classList.add('signed');
        e.target.textContent = 'Aláírva';
        hide(contractApp);
        post('contractSign', { plate: contractState.plate, role: contractState.role });
    }
});
