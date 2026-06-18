let serviceState = null;
let selected = { inspection: true, fuel: false };

const $ = (id) => document.getElementById(id);
const serviceApp = $('serviceApp');
const documentApp = $('documentApp');
const documentPaper = $('documentPaper');

function post(name, data = {}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

function fmtMoney(value, currency) {
    const n = Number(value || 0);
    return n.toLocaleString('hu-HU').replace(/\s/g, ' ') + ' ' + (currency || 'Ft');
}

function closeAll() {
    serviceApp.classList.add('hidden');
    documentApp.classList.add('hidden');
    post('close');
}

function updateServiceTotals() {
    if (!serviceState) return;
    let total = 0;
    if (selected.inspection) total += Number(serviceState.inspection?.price || 0);
    if (selected.fuel && serviceState.fuel?.enabled) total += Number(serviceState.fuel?.price || 0);

    $('inspectionCheck').classList.toggle('checked', selected.inspection);
    $('fuelCheck').classList.toggle('checked', selected.fuel);
    $('totalPrice').textContent = fmtMoney(total, serviceState.currency);
    $('payPrice').textContent = fmtMoney(total, serviceState.currency);
}

function openService(payload) {
    serviceState = payload;
    selected = { inspection: true, fuel: false };

    $('serviceCompany').textContent = payload.company || 'REAL OF LOS SANTOS';
    $('inspectionLabel').innerHTML = `${payload.inspection?.label || 'Műszaki vizsga'} <em>(${payload.inspection?.time || '00:15'})</em>`;
    $('inspectionPrice').textContent = fmtMoney(payload.inspection?.price || 0, payload.currency);

    if (payload.fuel?.enabled) {
        $('fuelRow').classList.remove('hidden');
        $('fuelLabel').innerHTML = `${payload.fuel?.label || '5L üzemanyag'} <em>(${payload.fuel?.time || '00:05'})</em>`;
        $('fuelPrice').textContent = fmtMoney(payload.fuel?.price || 0, payload.currency);
    } else {
        $('fuelRow').classList.add('hidden');
    }

    $('repairTime').textContent = `${payload.duration?.repair || 0} perc`;
    $('clubTime').textContent = `${payload.duration?.club || 0} perc`;
    $('expectedTime').textContent = `${payload.duration?.expected || 0} perc`;

    documentApp.classList.add('hidden');
    serviceApp.classList.remove('hidden');
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

    documentPaper.classList.toggle('invalid', invalid);
    $('invalidStamp').classList.toggle('hidden', !invalid);
    $('invalidStamp').textContent = payload.invalidText || 'ÉRVÉNYTELEN';

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
    setText('f_backfire', f.backfire);
    setText('f_height', f.rideHeight || 'nincs');
    setText('f_optical', f.opticalTuning);
    setText('f_neonlayout', f.neonLayout);
    setText('f_neoncolor2', f.neonType);
    setText('f_neoncolor', f.neonColor);
    setText('f_issue', f.issueDate);

    serviceApp.classList.add('hidden');
    documentApp.classList.remove('hidden');
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'openService') openService(data.payload || {});
    if (data.action === 'openDocument') openDocument(data.payload || {});
    if (data.action === 'forceClose') {
        serviceApp.classList.add('hidden');
        documentApp.classList.add('hidden');
    }
});

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' || event.key === 'Backspace') closeAll();
});

document.querySelectorAll('[data-close="true"]').forEach((btn) => btn.addEventListener('click', closeAll));

document.querySelector('[data-row="inspection"]').addEventListener('click', () => {
    selected.inspection = !selected.inspection;
    updateServiceTotals();
});

document.querySelector('[data-row="fuel"]').addEventListener('click', () => {
    selected.fuel = !selected.fuel;
    updateServiceTotals();
});

$('serviceSubmit').addEventListener('click', () => {
    if (!serviceState) return;
    if (!selected.inspection && !selected.fuel) return;

    const payload = {
        vehicleData: serviceState.vehicleData,
        inspection: selected.inspection,
        fuel: selected.fuel
    };

    serviceApp.classList.add('hidden');
    post('serviceSubmit', payload);
});
