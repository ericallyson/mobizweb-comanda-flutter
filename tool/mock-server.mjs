// Servidor FALSO de `/api/garcom/v1` — só para desenvolver/testar o app sem o
// Mobizweb (emulador, celular comum ou a prévia web). Guarda tudo em memória.
//
//   node tool/mock-server.mjs            # http://localhost:8787
//   login: qualquer e-mail, senha "123456"
//
// Segue o contrato de `docs/api-comanda.md` do Mobizweb no que o app usa. NÃO
// é referência de regra de negócio: a conta, o troco e as permissões aqui são
// simplificados.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';

const PORT = Number(process.env.PORT || 8787);
const round2 = (n) => Math.round(n * 100) / 100;
const now = () => new Date().toISOString();

// ── Cardápio ────────────────────────────────────────────────────────────────
const addonGroup = (name, items, extra = {}) => ({
    id: randomUUID(), name, min: 0, max: 0, is_required: false, allow_repeat: false,
    items: items.map(([n, price, max]) => ({ id: randomUUID(), name: n, price, max_quantity: max ?? 1, item_limit: max ?? 1 })),
    ...extra,
});
const product = (name, price, extra = {}) => ({
    id: randomUUID(), name, type: 'simple', price, is_available: true, unit_of_measure: 'un',
    allow_fractional_qty: false, image_url: null, addon_groups: [], ...extra,
});
const cat = (name, icon, products, parent_id = null) => ({ id: randomUUID(), name, icon, parent_id, products });

const flavors = [['Calabresa', 49.9], ['Mussarela', 45.9], ['Portuguesa', 54.9], ['Quatro Queijos', 59.9], ['Frango c/ Catupiry', 56.9], ['Marguerita', 52.9], ['Pepperoni', 62.9]]
    .map(([name, price]) => ({ id: randomUUID(), name, price, image_url: null }));
const refri = product('Refrigerante lata', 6);
const fritas = product('Batata frita', 18);

const lanches = cat('Lanches', 'sandwich', [
    product('X-Burger', 22, {
        addon_groups: [
            addonGroup('Ponto da carne', [['Mal passado', 0], ['Ao ponto', 0], ['Bem passado', 0]], { min: 1, max: 1, is_required: true }),
            addonGroup('Adicionais', [['Bacon', 4, 3], ['Cheddar', 3.5, 2], ['Ovo', 2.5], ['Cebola caramelizada', 3]], { max: 4, allow_repeat: false }),
        ],
    }),
    product('X-Salada', 24),
    product('Misto quente', 12.5),
    product('Combo X-Burger', 34.9, {
        type: 'combo',
        combo_groups: [
            { id: randomUUID(), name: 'Bebida', min: 1, max: 1, is_required: true, items: [
                { id: randomUUID(), name: 'Refrigerante lata', product_id: refri.id, extra_price: 0, is_default: true },
                { id: randomUUID(), name: 'Suco natural', product_id: randomUUID(), extra_price: 3, is_default: false },
            ] },
            { id: randomUUID(), name: 'Acompanhamento', min: 0, max: 1, is_required: false, items: [
                { id: randomUUID(), name: 'Batata frita', product_id: fritas.id, extra_price: 0, is_default: true },
                { id: randomUUID(), name: 'Onion rings', product_id: randomUUID(), extra_price: 4, is_default: false },
            ] },
        ],
    }),
]);
const bebidas = cat('Bebidas', 'cup-soda', []);
const menu = [
    lanches,
    cat('Pizzas', 'pizza', [
        product('Pizza Grande (8 fatias)', 0, {
            type: 'pizza',
            pizza: { max_flavors: 2, pricing_rule: 'highest', flavor_group: { id: randomUUID(), name: 'Sabores', items: flavors } },
            addon_groups: [addonGroup('Borda', [['Catupiry', 8], ['Cheddar', 8]], { max: 1 })],
        }),
    ]),
    cat('Porções', 'utensils', [fritas, product('Isca de frango', 32), product('Picanha no quilo', 189.9, { unit_of_measure: 'kg', allow_fractional_qty: true })]),
    bebidas,
    cat('Sobremesas', 'cake', [product('Pudim', 12), product('Petit gâteau', 21.9), product('Brownie (em falta)', 14, { is_available: false })]),
];
menu.push(
    cat('Sem álcool', 'glass-water', [refri, product('Água mineral', 4), product('Suco natural', 9)], bebidas.id),
    cat('Cervejas', 'beer', [product('Long neck', 11), product('Chopp 300ml', 9.5)], bebidas.id),
);
const allProducts = () => menu.flatMap((c) => c.products);

// ── Estado ──────────────────────────────────────────────────────────────────
// A primeira é a loja ativa no login; as outras servem para testar "Trocar loja".
const stores = ['Restaurante Demo', 'Demo Shopping', 'Demo Praia'].map((name) => ({ id: randomUUID(), name }));
let activeStore = stores[0];
const user = { id: randomUUID(), name: 'Ana Operadora', email: 'ana@demo.com' };
const PERMS = Object.fromEntries([
    'transfer_table', 'transfer_item', 'reopen_session', 'cancel_session', 'cancel_item', 'manage_comanda', 'process_payment',
    'service_fee_remove', 'cash_open', 'cash_close', 'cash_movement', 'cash_financial', 'counter_sale', 'open_session',
    'request_bill', 'close_session', 'couvert_add', 'couvert_remove', 'create_order', 'deliver_item', 'send_order',
].map((k) => [k, true]));
const SERVICE_FEE = 10;
const areas = [{ id: randomUUID(), name: 'Salão' }, { id: randomUUID(), name: 'Varanda' }];
// 24 mesas: o critério de aceite do mapa é caberem todas em 390 × 844.
const tables = Array.from({ length: 24 }, (_, i) => ({
    id: randomUUID(), number: String(i + 1), label: `Mesa ${i + 1}`, type: 'M', is_comanda: false, seats: 4,
    area: areas[i < 16 ? 0 : 1], reserved: i === 19,
}));
for (const n of [101, 102, 103]) tables.push({ id: randomUUID(), number: String(n), label: `Comanda ${n}`, type: 'C', is_comanda: true, seats: 1, area: null });
const sessions = new Map();

// Mesas já em atendimento ao subir o servidor, para o mapa nascer com todos
// os status: ocupada, fechando e ociosa (sem lançamento há mais que o limite).
const IDLE_ALERT_MINUTES = 30;
const minutesAgo = (m) => new Date(Date.now() - m * 60000).toISOString();
function seedSession(number, { status = 'open', customer = null, guests = 2, idleFor = 5, items = [], unassigned = false }) {
    const t = tables.find((x) => x.number === String(number));
    const s = {
        id: randomUUID(), table_id: t.id, status, opened_at: minutesAgo(idleFor + 20), last_activity_at: minutesAgo(idleFor),
        guest_count: guests, customer_name: customer, items: [], payments: [],
        comandas: unassigned ? [{ id: randomUUID(), label: '1', status: 'open' }] : [], couvert: null, fee_removed: false,
    };
    for (const [name, quantity] of items) {
        const p = allProducts().find((x) => x.name === name);
        s.items.push({ id: randomUUID(), order_id: randomUUID(), comanda_id: null, product_name: p.name, quantity, unit_price: p.price, notes: null, status: 'pending', cancellation_reason: null, created_at: s.opened_at, selected_flavors: [], addons: [] });
    }
    sessions.set(s.id, s);
    return s;
}
seedSession(2, { guests: 4, items: [['X-Salada', 2], ['Refrigerante lata', 2], ['Batata frita', 1], ['Long neck', 2]] });
seedSession(3, { customer: 'Jefferson', items: [['Chopp 300ml', 4], ['Isca de frango', 1], ['Batata frita', 1]] });
seedSession(5, { status: 'closing', guests: 3, items: [['X-Salada', 1], ['Suco natural', 3], ['Pudim', 2], ['Isca de frango', 1]] });
seedSession(9, { idleFor: 48, items: [['Refrigerante lata', 2]] });
seedSession(12, { customer: 'Maria Aparecida de Souza', guests: 5, items: [['Long neck', 3], ['Petit gâteau', 1]], unassigned: true });
seedSession(14, { status: 'closing', customer: 'Carlos', items: [['Misto quente', 2], ['Chopp 300ml', 2], ['Isca de frango', 1]] });
seedSession(18, { guests: 6, items: [['X-Salada', 2], ['Refrigerante lata', 4], ['Batata frita', 2], ['Pudim', 1]] });

// Sino: chamados feitos no tablet da mesa, pedidos do tablet aguardando
// liberação e estoque crítico (`GET /tablet/calls`).
const tableByNumber = (n) => tables.find((x) => x.number === String(n));
const sessionOfTable = (t) => [...sessions.values()].find((x) => x.table_id === t.id && ['open', 'closing'].includes(x.status));
const waiterCalls = [
    { id: randomUUID(), table: tableByNumber(3), reason: 'waiter', reason_label: 'Chamar garçom', note: null, status: 'open', created_at: minutesAgo(2) },
    { id: randomUUID(), table: tableByNumber(18), reason: 'missing', reason_label: 'Faltou algo no pedido', note: 'Faltou o molho', status: 'open', created_at: minutesAgo(7) },
];
const tabletOrders = [
    { id: randomUUID(), table: tableByNumber(2), items: [{ name: 'Água mineral', quantity: 2 }, { name: 'Pudim', quantity: 1 }], created_at: minutesAgo(1) },
];
const lowStock = [
    { id: randomUUID(), name: 'Bacon fatiado', unit: 'kg', current_stock: -300, min_stock: 1, kind: 'ingredient' },
    { id: randomUUID(), name: 'Queijo cheddar', unit: 'kg', current_stock: -200, min_stock: 1, kind: 'ingredient' },
    { id: randomUUID(), name: 'Carne moída 150 g', unit: 'un', current_stock: -37, min_stock: 20, kind: 'ingredient' },
    { id: randomUUID(), name: 'Pão de hambúrguer', unit: 'un', current_stock: -37, min_stock: 20, kind: 'ingredient' },
    { id: randomUUID(), name: 'Pão brioche', unit: 'un', current_stock: 0, min_stock: 20, kind: 'product' },
];
const elapsed = (iso) => Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
const pendingByTable = () => {
    const out = {};
    for (const c of waiterCalls) out[c.table.id] = (out[c.table.id] ?? 0) + 1;
    return out;
};
// Comanda (cartão) → sessão da mesa em que foi vinculada.
const comandaLinks = new Map();
const findCard = (code) => tables.find((t) => t.is_comanda && t.number === String(code ?? '').trim());
const presentLink = (card) => {
    const s = sessions.get(comandaLinks.get(card.id));
    if (!s || !['open', 'closing'].includes(s.status)) return null;
    const t = tables.find((x) => x.id === s.table_id);
    return { comanda_id: randomUUID(), label: card.number, table_session_id: s.id, table_id: t.id, table_number: t.number };
};
const paymentMethods = [
    { id: randomUUID(), name: 'Dinheiro', code: 'especie', method: 'cash', icon: null, is_default: true, is_cash: true },
    { id: randomUUID(), name: 'Crédito', code: 'card_credit', method: 'credit_card', icon: null, is_default: false, is_cash: false },
    { id: randomUUID(), name: 'Débito', code: 'card_debit', method: 'debit_card', icon: null, is_default: false, is_cash: false },
    { id: randomUUID(), name: 'Pix', code: 'pix', method: 'pix', icon: null, is_default: false, is_cash: false },
    { id: randomUUID(), name: 'Vale refeição', code: 'vr', method: 'voucher', icon: null, is_default: false, is_cash: false },
];
const METHOD_LABEL = { cash: 'Dinheiro', credit_card: 'Crédito', debit_card: 'Débito', pix: 'Pix', voucher: 'Vale refeição', mp_pix: 'Pix online', other: 'Outro' };
let cash = null;
const cashHistory = { payments: [], orders: 0, ordersTotal: 0 };
let saleNumber = 100;
const pix = new Map();
const idempotency = new Map();
const tokens = new Set();

// ── Regras simplificadas ────────────────────────────────────────────────────
function priceItem(body) {
    const p = allProducts().find((x) => x.id === body.product_id);
    if (!p) throw fail(422, 'Produto não encontrado.');
    if (!p.is_available) throw fail(422, `Produto indisponível: ${p.name}`, { stock: [`${p.name} está em falta. Disponível: 0`] });
    let price = p.price;
    const selectedFlavors = [];
    if (p.type === 'pizza') {
        const chosen = p.pizza.flavor_group.items.filter((f) => (body.selected_flavor_ids ?? []).includes(f.id));
        if (!chosen.length) throw fail(422, 'Escolha ao menos 1 sabor.');
        price = Math.max(...chosen.map((f) => f.price));
        selectedFlavors.push(...chosen.map((f) => f.name));
    }
    const addons = [];
    for (const a of body.addons ?? []) {
        const item = p.addon_groups.flatMap((g) => g.items).find((i) => i.id === a.addon_group_item_id);
        if (item) { price += item.price * a.quantity; addons.push({ name: item.name, quantity: a.quantity }); }
    }
    for (const sel of body.combo_selections ?? []) {
        const group = (p.combo_groups ?? []).find((g) => g.id === sel.group_id);
        for (const it of sel.items ?? []) {
            const gi = group?.items.find((i) => i.product_id === it.id || i.id === it.id);
            if (gi) { price += gi.extra_price; addons.push({ name: gi.name, quantity: 1 }); }
        }
    }
    return { name: p.name, unit_price: round2(price), selected_flavors: selectedFlavors, addons };
}

function billOf(s, comandaId) {
    const items = s.items.filter((i) => i.status !== 'canceled' && (comandaId === undefined || i.comanda_id === comandaId));
    const subtotal = round2(items.reduce((a, i) => a + i.unit_price * i.quantity, 0));
    const removed = comandaId === undefined ? s.fee_removed : s.comandas.find((c) => c.id === comandaId)?.fee_removed;
    const fee = removed ? 0 : round2(subtotal * SERVICE_FEE / 100);
    const couvert = comandaId === undefined
        ? round2((s.couvert?.total ?? 0) + s.comandas.reduce((a, c) => a + (c.couvert?.total ?? 0), 0))
        : (s.comandas.find((c) => c.id === comandaId)?.couvert?.total ?? 0);
    const total = round2(subtotal + fee + couvert);
    const paid = round2(s.payments.filter((p) => comandaId === undefined || p.comanda_id === comandaId).reduce((a, p) => a + p.amount, 0));
    return {
        items_subtotal: subtotal, couvert_amount: couvert, service_fee: fee, service_fee_percentage: removed ? 0 : SERVICE_FEE,
        service_fee_full_percentage: SERVICE_FEE, service_fee_base: subtotal, service_fee_removed: !!removed, discount: 0,
        discount_type: null, discount_value: 0, total, paid, remaining: round2(Math.max(0, total - paid)),
    };
}

const presentComanda = (s, c) => {
    const b = billOf(s, c.id);
    return {
        id: c.id, label: c.label, status: c.status, items_subtotal: b.items_subtotal, service_fee: b.service_fee,
        service_fee_percentage: b.service_fee_percentage, service_fee_removed: b.service_fee_removed,
        couvert: c.couvert ? { amount: c.couvert.amount.toFixed(4), persons: c.couvert.persons, total: c.couvert.total.toFixed(4) } : null,
        total: b.total, paid: b.paid, remaining: b.remaining,
        items_count: s.items.filter((i) => i.comanda_id === c.id && i.status !== 'canceled').length,
        has_payments: b.paid > 0,
    };
};

function tableStatus(t) {
    const s = [...sessions.values()].find((x) => x.table_id === t.id && ['open', 'closing'].includes(x.status));
    if (s) return [s.status === 'closing' ? 'closing' : 'occupied', s];
    return [t.reserved ? 'reserved' : 'available', null];
}

function presentSession(s) {
    const t = tables.find((x) => x.id === s.table_id);
    const active = s.items.filter((i) => i.status !== 'canceled');
    const unassigned = s.comandas.some((c) => ['open', 'closing'].includes(c.status)) ? active.filter((i) => !i.comanda_id) : [];
    const openOthers = [...sessions.values()].filter((x) => ['open', 'closing'].includes(x.status));
    return {
        id: s.id, status: s.status, opened_at: s.opened_at,
        // Pedidos do tablet desta mesa aguardando o garçom liberar.
        pending_tablet_orders: tabletOrders.filter((o) => o.table.id === t.id).map((o) => ({ id: o.id, items: o.items.map((i) => ({ product_name: i.name, quantity: i.quantity, notes: i.notes ?? null })) })), guest_count: s.guest_count,
        customer_name: s.customer_name, couvert: s.couvert, couvert_default_amount: 12, bill: billOf(s),
        table: { id: t.id, number: t.number, label: t.label },
        items: [...s.items].reverse().map((i) => ({ ...i, can_cancel: !['canceled', 'delivered'].includes(i.status), can_transfer: i.status !== 'canceled' })),
        unassigned_items_count: unassigned.length, unassigned_item_ids: unassigned.map((i) => i.id),
        has_comandas: s.comandas.length > 0, enable_comandas: true,
        comandas: s.comandas.map((c) => ({ id: c.id, label: c.label, status: c.status, total: billOf(s, c.id).total, paid_amount: billOf(s, c.id).paid })),
        transfer_targets: openOthers.map((x) => {
            const xt = tables.find((y) => y.id === x.table_id);
            const act = x.comandas.filter((c) => ['open', 'closing'].includes(c.status));
            return { id: x.id, table_number: xt.number, area_name: xt.area?.name ?? null, is_current: x.id === s.id, has_active_comandas: act.length > 0, comandas: x.comandas.filter((c) => c.status === 'open').map((c) => ({ id: c.id, label: c.label })) };
        }),
        free_tables: tables.filter((x) => !x.is_comanda && tableStatus(x)[0] === 'available').map((x) => ({ id: x.id, number: x.number, area_name: x.area?.name ?? null })),
        require_transfer_item_password: false, require_cancel_session_password: false,
        require_discount_password: false, require_service_fee_removal_password: false,
    };
}

function settle(s) {
    for (const c of s.comandas) if (['open', 'closing'].includes(c.status) && billOf(s, c.id).remaining <= 0.005 && billOf(s, c.id).total > 0) c.status = 'paid';
    const b = billOf(s);
    if (b.total > 0 && b.remaining <= 0.005 && !s.items.some((i) => i.status !== 'canceled' && s.comandas.length && !i.comanda_id)) {
        s.status = 'closed';
        s.closed_at = now();
        cashHistory.orders += 1;
        cashHistory.ordersTotal = round2(cashHistory.ordersTotal + b.total);
    }
}

function addPayment(s, body, comandaId) {
    const amount = Number(body.amount);
    if (!(amount > 0)) throw fail(422, 'Valor inválido.');
    const method = paymentMethods.find((m) => m.code === body.method)?.method ?? body.method;
    const b = billOf(s, comandaId);
    if (body.tef_transaction_id && s.payments.some((p) => p.tef_transaction_id === body.tef_transaction_id)) return true;
    if (method === 'cash') {
        if (!(Number(body.cash_received) >= amount)) throw fail(422, 'Valor recebido é menor que o valor do pagamento.');
    } else if (amount > b.remaining + 0.01) {
        throw fail(422, `Valor excede o saldo restante (R$ ${b.remaining.toFixed(2)}).`);
    }
    const applied = round2(Math.min(amount, b.remaining));
    s.payments.push({ id: randomUUID(), method, amount: applied, comanda_id: comandaId, tef_transaction_id: body.tef_transaction_id ?? null, change: method === 'cash' ? round2(Number(body.cash_received) - applied) : 0 });
    cashHistory.payments.push({ method, amount: applied });
    settle(s);
    return false;
}

function receiptOf(s) {
    const t = tables.find((x) => x.id === s.table_id);
    const b = billOf(s);
    return {
        store: { name: stores[0].name, document: '12.345.678/0001-90', phone: '(11) 4000-1234', address_line: 'Rua das Flores, 100 - Centro', print_logo_url: null },
        channel: 'mesa', number: null, datetime: now(), operator: user.name, table_label: t.label.toUpperCase(),
        opened_at: s.opened_at, closed_at: s.closed_at ?? null, waiter: user.name, customer: null, customer_name: s.customer_name, obs: null,
        items: s.items.filter((i) => i.status !== 'canceled').map((i) => ({ rows: [
            { qty_label: String(i.quantity), qty: i.quantity, name: i.product_name, unit: i.unit_price, total: round2(i.unit_price * i.quantity) },
            ...i.addons.map((a) => ({ qty_label: String(a.quantity), qty: a.quantity, name: a.name, unit: 0, total: 0 })),
        ] })),
        items_count: s.items.length, subtotal: b.items_subtotal, couvert: b.couvert_amount, discount: 0, addition: 0,
        service_fee: b.service_fee, service_fee_percentage: b.service_fee_percentage, total: b.total, paid: b.paid, remaining: b.remaining,
        payments: s.payments.map((p) => ({ label: METHOD_LABEL[p.method] ?? p.method, amount: p.amount, change: p.change })),
        comanda_labels: s.comandas.map((c) => c.label),
    };
}

function cashDto() {
    return cash && { id: cash.id, status: cash.status, opened_at: cash.opened_at, closed_at: cash.closed_at ?? null, opening_amount: cash.opening_amount, closing_amount: null, expected_amount: null, difference: null, notes: cash.notes ?? null };
}
function cashSummary() {
    const byMethod = {};
    for (const p of cashHistory.payments) {
        byMethod[p.method] ??= { label: METHOD_LABEL[p.method] ?? p.method, total: 0, count: 0 };
        byMethod[p.method].total = round2(byMethod[p.method].total + p.amount);
        byMethod[p.method].count += 1;
    }
    const mv = (type, label, credit) => {
        const list = cash.movements.filter((m) => m.type === type);
        return { label, is_credit: credit, total: round2(list.reduce((a, m) => a + m.amount, 0)), count: list.length };
    };
    const movementsByType = { supply: mv('supply', 'Suprimentos', true), cash_in: mv('cash_in', 'Entradas', true), withdrawal: mv('withdrawal', 'Sangrias', false), cash_out: mv('cash_out', 'Saídas', false) };
    const cashExpected = round2(cash.opening_amount + (byMethod.cash?.total ?? 0) + movementsByType.supply.total - movementsByType.withdrawal.total);
    const expectedBreakdown = { cash: { label: 'Dinheiro', total: cashExpected, is_digital: false }, credit_card: { label: 'Crédito', total: byMethod.credit_card?.total ?? 0, is_digital: true }, debit_card: { label: 'Débito', total: byMethod.debit_card?.total ?? 0, is_digital: true } };
    if (byMethod.pix) expectedBreakdown.pix = { label: 'Pix', total: byMethod.pix.total, is_digital: true };
    return { paymentsByMethod: byMethod, movementsByType, expectedBreakdown, totalCashIn: movementsByType.supply.total, totalCashOut: movementsByType.withdrawal.total, ordersTotal: cashHistory.ordersTotal, ordersCount: cashHistory.orders };
}

// 1x1 PNG preto ampliado pelo app — só para a tela do Pix ter o que mostrar.
const QR_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAJ0lEQVQYV2NkYGD4z4AKGJG4jDAFjFgVMCJxGbEqYMSqgBGrAkasCgB5pQQJ0e0nNwAAAABJRU5ErkJggg==';

// ── Rotas ───────────────────────────────────────────────────────────────────
const fail = (status, error, errors) => Object.assign(new Error(error), { status, body: errors ? { error, errors } : { error } });
const need = (v, what = 'Registro') => { if (!v) throw fail(404, `${what} não encontrado.`); return v; };
const sessionOf = (id) => need(sessions.get(id), 'Mesa');
const comandaOf = (id) => {
    for (const s of sessions.values()) { const c = s.comandas.find((x) => x.id === id); if (c) return [s, c]; }
    throw fail(404, 'Comanda não encontrada.');
};

const routes = [
    ['POST', '/auth/login', (m, b) => {
        if (b.password !== '123456') throw fail(401, 'Credenciais inválidas.');
        const token = `mock|${randomUUID()}`;
        tokens.add(token);
        activeStore = stores[0];
        return { token, user: { ...user, email: b.email || user.email }, store: activeStore, stores, permissions: PERMS };
    }, true],
    ['GET', '/ping', () => ({ ok: true }), true],
    ['POST', '/auth/logout', () => ({})],
    ['GET', '/auth/me', () => ({ user, permissions: PERMS })],
    ['POST', '/stores/:id/select', (m) => { activeStore = need(stores.find((s) => s.id === m.id), 'Loja'); return { store: activeStore }; }],
    ['GET', '/menu', () => ({ categories: menu })],
    ['GET', '/payment-methods', () => ({ payment_methods: paymentMethods, pix_online: { code: 'mp_pix', label: 'Pix Mercado Pago' } })],
    ['GET', '/tables', () => ({
        settings: { enable_comandas: true, idle_alert_minutes: IDLE_ALERT_MINUTES },
        tables: tables.map((t) => {
            const [status, s] = tableStatus(t);
            const b = s && billOf(s);
            return {
                id: t.id, number: t.number, label: t.label, is_comanda: t.is_comanda, type: t.type, seats: t.seats, status, area: t.area,
                session: s && { id: s.id, opened_at: s.opened_at, last_activity_at: s.last_activity_at, guest_count: s.guest_count, customer_name: s.customer_name, opened_by_name: user.name, status: s.status, total: b.total, items_subtotal: b.items_subtotal, service_fee: b.service_fee, service_fee_percentage: b.service_fee_percentage },
                pending_calls: pendingByTable()[t.id] ?? 0,
                has_unassigned_items: !!s && s.comandas.some((c) => ['open', 'closing'].includes(c.status)) && s.items.some((i) => i.status !== 'canceled' && !i.comanda_id),
            };
        }),
    })],
    ['POST', '/tables/:id/sessions', (m, b) => {
        const t = need(tables.find((x) => x.id === m.id), 'Mesa');
        const [, existing] = tableStatus(t);
        if (existing) return { session: { id: existing.id, table_id: t.id, status: existing.status }, reused: true };
        const s = { id: randomUUID(), table_id: t.id, status: 'open', opened_at: now(), last_activity_at: now(), guest_count: b.guest_count ?? null, customer_name: b.customer_name ?? null, items: [], payments: [], comandas: (b.comandas ?? []).map((label) => ({ id: randomUUID(), label, status: 'open' })), couvert: null, fee_removed: false };
        sessions.set(s.id, s);
        return { session: { id: s.id, table_id: t.id, opened_at: s.opened_at, guest_count: s.guest_count, customer_name: s.customer_name, status: s.status }, reused: false };
    }],
    ['POST', '/tables/:id/sessions/current/bill', (m) => {
        const [, s] = tableStatus(need(tables.find((x) => x.id === m.id), 'Mesa'));
        need(s, 'Mesa aberta').status = 'closing';
        return { message: 'Conta solicitada.' };
    }],
    ['GET', '/sessions/:id', (m) => ({ session: presentSession(sessionOf(m.id)) })],
    // "Gerar QR do tablet na mesa": código de 6 dígitos (gerar de novo substitui o anterior).
    ['POST', '/sessions/:id/tablet-code', (m) => {
        const s = sessionOf(m.id);
        if (!['open', 'closing'].includes(s.status)) throw fail(409, 'Mesa não está aberta.');
        s.tablet_code = String(Math.floor(Math.random() * 1000000)).padStart(6, '0');
        return { code: s.tablet_code, table_number: tables.find((x) => x.id === s.table_id).number };
    }],
    ['GET', '/sessions/:id/receipt', (m) => { const s = sessionOf(m.id); return { receipt: receiptOf(s), bill: billOf(s) }; }],
    ['POST', '/sessions/:id/orders', (m, b) => {
        const s = sessionOf(m.id);
        if (s.status !== 'open') throw fail(422, 'A mesa não está aberta.');
        if (!Array.isArray(b.items) || !b.items.length) throw fail(422, 'Informe ao menos um item.');
        if (b.session_comanda_id && !s.comandas.some((c) => c.id === b.session_comanda_id && c.status === 'open')) throw fail(422, 'Comanda fechada ou inexistente.');
        const orderId = randomUUID();
        const priced = b.items.map((it) => ({ it, p: priceItem(it) }));
        for (const { it, p } of priced) {
            s.items.push({ id: randomUUID(), order_id: orderId, comanda_id: b.session_comanda_id ?? null, product_name: p.name, quantity: Number(it.quantity), unit_price: p.unit_price, notes: it.notes ?? null, status: 'pending', cancellation_reason: null, created_at: now(), selected_flavors: p.selected_flavors, addons: p.addons });
        }
        s.last_activity_at = now();
        return { order: { id: orderId, code: String(1000 + s.items.length), session_id: s.id, status: 'pending' }, kitchen_sent: true };
    }],
    ['DELETE', '/items/:id', (m, b) => {
        if (!b.reason) throw fail(422, 'Informe o motivo.');
        for (const s of sessions.values()) {
            const i = s.items.find((x) => x.id === m.id);
            if (i) { i.status = 'canceled'; i.cancellation_reason = b.reason; return { message: 'Item cancelado.' }; }
        }
        throw fail(404, 'Item não encontrado.');
    }],
    ['POST', '/items/:id/transfer', (m, b) => transfer([m.id], b)],
    ['POST', '/sessions/:id/items/transfer', (m, b) => transfer(b.items ?? [], b)],
    ['PATCH', '/sessions/:id/customer', (m, b) => { sessionOf(m.id).customer_name = b.customer_name ?? null; return { customer_name: b.customer_name ?? null }; }],
    ['POST', '/sessions/:id/reopen', (m) => { sessionOf(m.id).status = 'open'; return { message: 'Mesa reaberta.' }; }],
    ['POST', '/sessions/:id/cancel', (m) => {
        const s = sessionOf(m.id);
        if (s.payments.length) throw fail(422, 'Mesa com pagamento registrado: estorne no caixa antes de cancelar.');
        s.status = 'canceled';
        return { message: 'Mesa cancelada.' };
    }],
    ['POST', '/sessions/:id/close', (m) => {
        const s = sessionOf(m.id);
        if (billOf(s).remaining > 0.01) throw fail(422, 'A conta ainda tem saldo em aberto.');
        s.status = 'closed';
        return { closed: true };
    }],
    ['POST', '/sessions/:id/transfer', (m, b) => {
        const s = sessionOf(m.id);
        const t = need(tables.find((x) => x.id === b.target_table_id), 'Mesa de destino');
        if (tableStatus(t)[0] !== 'available') throw fail(422, 'A mesa de destino não está livre.');
        s.table_id = t.id;
        return { message: 'Mesa transferida.', session_id: s.id };
    }],
    ['POST', '/sessions/:id/couvert', (m, b) => {
        const s = sessionOf(m.id);
        const amount = Number(b.amount);
        if (Array.isArray(b.comandas)) {
            for (const row of b.comandas) {
                const c = need(s.comandas.find((x) => x.id === row.id), 'Comanda');
                c.couvert = { amount, persons: row.persons, total: round2(amount * row.persons) };
            }
        } else {
            s.couvert = { amount, persons: b.persons, total: round2(amount * b.persons) };
        }
        return { bill: billOf(s) };
    }],
    ['DELETE', '/sessions/:id/couvert', (m) => { const s = sessionOf(m.id); s.couvert = null; return { bill: billOf(s) }; }],
    ['POST', '/sessions/:id/payments', (m, b) => {
        const s = sessionOf(m.id);
        const duplicate = addPayment(s, b, undefined);
        const bill = billOf(s);
        return { bill: { total: bill.total, paid: bill.paid, remaining: bill.remaining }, ...(duplicate ? { duplicate: true } : {}) };
    }],
    ['POST', '/sessions/:id/pix', (m, b) => newPix(Number(b.amount) || billOf(sessionOf(m.id)).remaining)],
    ['GET', '/comanda-pix/:id/status', (m) => {
        const p = need(pix.get(m.id), 'Cobrança');
        p.polls += 1;
        const paid = p.polls >= 2; // "paga" na segunda consulta
        return { provider: 'mock', charge_id: m.id, paid, status: paid ? 'paid' : 'pending' };
    }],
    ['GET', '/sessions/:id/comandas', (m) => {
        const s = sessionOf(m.id);
        const used = new Set([...sessions.values()].flatMap((x) => x.comandas.map((c) => c.table_ref)));
        return {
            comandas: s.comandas.map((c) => presentComanda(s, c)),
            available: tables.filter((t) => t.is_comanda && !used.has(t.id)).map((t) => ({ id: t.id, label: t.number })),
            transfer_tables: tables.filter((t) => !t.is_comanda && t.id !== s.table_id).map((t) => ({ id: t.id, number: t.number, area_name: t.area?.name ?? null, state: { available: 'free', reserved: 'free', occupied: 'open', closing: 'closing' }[tableStatus(t)[0]] })),
            transfer_requires_password: false, cancel_requires_password: false,
        };
    }],
    ['POST', '/sessions/:id/comandas', (m, b) => {
        const s = sessionOf(m.id);
        const label = b.label ?? tables.find((t) => t.id === b.comanda_table_id)?.number;
        if (!label) throw fail(422, 'Informe o número ou nome da comanda.');
        if (s.comandas.some((c) => c.label.toLowerCase() === String(label).toLowerCase() && c.status !== 'canceled')) throw fail(422, 'Já existe uma comanda com esse nome nesta mesa.');
        const c = { id: randomUUID(), label: String(label), status: 'open', table_ref: b.comanda_table_id ?? null };
        s.comandas.push(c);
        return { comanda: presentComanda(s, c) };
    }],
    ['PATCH', '/comandas/:id', (m, b) => { const [s, c] = comandaOf(m.id); c.label = b.label; return { comanda: presentComanda(s, c) }; }],
    ['DELETE', '/comandas/:id', (m) => {
        const [s, c] = comandaOf(m.id);
        if (s.items.some((i) => i.comanda_id === c.id && i.status !== 'canceled')) throw fail(422, 'Comanda com itens não pode ser excluída.');
        s.comandas = s.comandas.filter((x) => x.id !== c.id);
        return { removed: true };
    }],
    ['DELETE', '/comandas/:id/couvert', (m) => { const [s, c] = comandaOf(m.id); c.couvert = null; return { comanda: presentComanda(s, c) }; }],
    ['POST', '/comandas/:id/bill', (m) => { const [s, c] = comandaOf(m.id); c.status = 'closing'; return { comanda: presentComanda(s, c) }; }],
    ['POST', '/comandas/:id/reopen', (m) => { const [s, c] = comandaOf(m.id); c.status = 'open'; return { comanda: presentComanda(s, c) }; }],
    ['POST', '/comandas/:id/cancel-items', (m, b) => {
        const [s, c] = comandaOf(m.id);
        if (!b.reason) throw fail(422, 'Informe o motivo.');
        for (const i of s.items) if (i.comanda_id === c.id) i.status = 'canceled';
        c.status = 'canceled';
        return { comanda: presentComanda(s, c) };
    }],
    ['POST', '/comandas/:id/service-fee/remove', (m) => { const [s, c] = comandaOf(m.id); c.fee_removed = true; return { comanda: presentComanda(s, c) }; }],
    ['POST', '/comandas/:id/service-fee/reapply', (m) => { const [s, c] = comandaOf(m.id); c.fee_removed = false; return { comanda: presentComanda(s, c) }; }],
    ['POST', '/comandas/:id/transfer', (m, b) => {
        const [s, c] = comandaOf(m.id);
        const t = need(tables.find((x) => x.id === b.target_table_id), 'Mesa de destino');
        let [, dest] = tableStatus(t);
        if (!dest) { dest = { id: randomUUID(), table_id: t.id, status: 'open', opened_at: now(), last_activity_at: now(), guest_count: null, customer_name: null, items: [], payments: [], comandas: [], couvert: null, fee_removed: false }; sessions.set(dest.id, dest); }
        dest.comandas.push(c);
        dest.items.push(...s.items.filter((i) => i.comanda_id === c.id));
        s.items = s.items.filter((i) => i.comanda_id !== c.id);
        s.comandas = s.comandas.filter((x) => x.id !== c.id);
        if (!s.comandas.length && !s.items.some((i) => i.status !== 'canceled')) s.status = 'canceled';
        return { comanda: { id: c.id }, origin_session: { id: s.id, status: s.status }, destination_session: { id: dest.id, table_number: t.number } };
    }],
    ['POST', '/comandas/:id/payments', (m, b) => {
        const [s, c] = comandaOf(m.id);
        const duplicate = addPayment(s, b, c.id);
        return { comanda: presentComanda(s, c), ...(duplicate ? { duplicate: true } : {}) };
    }],
    ['POST', '/comandas/:id/pix', (m, b) => { const [s, c] = comandaOf(m.id); return newPix(Number(b.amount) || billOf(s, c.id).remaining); }],
    ['GET', '/cash', () => ({ enabled: true, settings: { blind_close: false, single_cash_session: false, allow_close_by_any_user: true, allow_close_with_open_sales: true }, permissions: { open: true, close: true, movement: true, financial: true }, session: cash?.status === 'open' ? cashDto() : null })],
    ['POST', '/cash/open', (m, b) => {
        if (cash?.status === 'open') throw fail(422, 'Já existe um caixa aberto para este usuário.');
        cash = { id: randomUUID(), status: 'open', opened_at: now(), opening_amount: Number(b.opening_amount) || 0, notes: b.notes, movements: [] };
        return { session: cashDto() };
    }],
    ['POST', '/cash/sessions/:id/movements', (m, b) => {
        if (!cash || cash.id !== m.id) throw fail(404, 'Caixa não encontrado.');
        cash.movements.push({ id: randomUUID(), type: b.type, amount: Number(b.amount), reason: b.reason ?? null, created_at: now() });
        return { session: cashDto() };
    }],
    ['GET', '/cash/sessions/:id/summary', (m) => {
        if (!cash || cash.id !== m.id) throw fail(404, 'Caixa não encontrado.');
        return { session: cashDto(), movements: cash.movements, summary: cashSummary() };
    }],
    ['POST', '/cash/sessions/:id/close', (m, b) => {
        if (!cash || cash.id !== m.id) throw fail(404, 'Caixa não encontrado.');
        if (!b.closing_breakdown || typeof b.closing_breakdown !== 'object') throw fail(422, 'Informe os valores contados.');
        cash.status = 'closed';
        cash.closed_at = now();
        cashHistory.payments = [];
        cashHistory.orders = 0;
        cashHistory.ordersTotal = 0;
        return { session: cashDto() };
    }],
    // ── Sino e "Ler QR da comanda" (mesmos endpoints do PWA) ──
    ['GET', '/tablet/calls', () => ({
        calls: waiterCalls.map((c) => ({
            id: c.id, table_id: c.table.id, table_number: c.table.number, table_label: c.table.label,
            table_session_id: sessionOfTable(c.table)?.id ?? null, reason: c.reason, reason_label: c.reason_label,
            status: c.status, note: c.note, created_at: c.created_at, elapsed_seconds: elapsed(c.created_at), opened_by: user.name,
        })),
        pending_orders: tabletOrders.map((o) => ({
            id: o.id, table_id: o.table.id, table_number: o.table.number, table_label: o.table.label, items: o.items,
            created_at: o.created_at, elapsed_seconds: elapsed(o.created_at),
        })),
        pending_by_table: pendingByTable(),
        low_stock_alerts: lowStock,
    })],
    ['POST', '/tablet/calls/:id/ack', (m) => { need(waiterCalls.find((c) => c.id === m.id), 'Chamado').status = 'acknowledged'; return { ok: true }; }],
    ['POST', '/tablet/calls/:id/resolve', (m) => {
        const i = waiterCalls.findIndex((c) => c.id === m.id);
        if (i >= 0) waiterCalls.splice(i, 1);
        return { ok: true };
    }],
    ['POST', '/tablet/orders/:id/approve', (m) => {
        const i = tabletOrders.findIndex((o) => o.id === m.id);
        if (i < 0) throw Object.assign(new Error('Pedido já liberado.'), { status: 409, body: { message: 'Pedido já liberado.' } });
        tabletOrders.splice(i, 1);
        return { ok: true, message: 'Pedido liberado para a cozinha.' };
    }],
    ['POST', '/tablet/comandas/lookup', (m, b) => {
        const card = findCard(b.code);
        if (!card) throw Object.assign(new Error('Comanda não encontrada nesta loja.'), { status: 404, body: { message: 'Comanda não encontrada nesta loja.' } });
        const link = presentLink(card);
        return { comanda_table: { id: card.id, number: card.number, label: card.number }, linked: !!link, link };
    }],
    ['POST', '/tablet/comandas/link', (m, b) => {
        const card = findCard(b.code);
        if (!card) throw Object.assign(new Error('Comanda não encontrada nesta loja.'), { status: 404, body: { message: 'Comanda não encontrada nesta loja.' } });
        const t = tables.find((x) => x.id === b.table_id && !x.is_comanda);
        if (!t) throw Object.assign(new Error('Mesa não encontrada nesta loja.'), { status: 404, body: { message: 'Mesa não encontrada nesta loja.' } });
        const existing = presentLink(card);
        if (existing) {
            if (existing.table_id === t.id) return { link: existing, already_linked: true };
            const message = `Esta comanda já está vinculada à mesa ${existing.table_number}. Feche-a antes de vincular a outra.`;
            throw Object.assign(new Error(message), { status: 409, body: { message } });
        }
        let s = sessionOfTable(t);
        if (!s) {
            s = { id: randomUUID(), table_id: t.id, status: 'open', opened_at: now(), last_activity_at: now(), guest_count: null, customer_name: null, items: [], payments: [], comandas: [], couvert: null, fee_removed: false };
            sessions.set(s.id, s);
        }
        s.comandas.push({ id: randomUUID(), label: card.number, status: 'open' });
        comandaLinks.set(card.id, s.id);
        return { link: presentLink(card) };
    }],
    ['GET', '/counter/context', () => ({ enabled: true, permissions: { sell: true }, payment_methods: paymentMethods, cash_session: cash?.status === 'open' ? { id: cash.id, opened_at: cash.opened_at } : null })],
    ['POST', '/counter/checkout', (m, b) => {
        if (!Array.isArray(b.items) || !b.items.length) throw fail(422, 'Informe ao menos um item.');
        // MOCK_PROMO=10 simula uma promoção de 10% que o cardápio não mostra
        // (o servidor real recalcula o preço com promoções e tabelas).
        const promo = Number(process.env.MOCK_PROMO ?? 0);
        const full = round2(b.items.reduce((a, it) => a + priceItem(it).unit_price * Number(it.quantity), 0));
        const total = round2(full * (1 - promo / 100));
        const paid = round2((b.payments ?? []).reduce((a, p) => a + Number(p.amount), 0));
        if (paid < total - 0.005) throw fail(422, 'O valor recebido não cobre o total da venda.');
        for (const p of b.payments) cashHistory.payments.push({ method: p.method, amount: Math.min(Number(p.amount), total) });
        cashHistory.orders += 1;
        cashHistory.ordersTotal = round2(cashHistory.ordersTotal + total);
        return { order: { id: randomUUID(), number: ++saleNumber, total, change_amount: round2(Math.max(0, paid - total)), cash_session_id: cash?.id ?? null }, receipt: { status: 'skipped', requires_operator_decision: false, block_reason: null } };
    }],
];

function newPix(amount) {
    const id = `pix_${randomUUID().slice(0, 8)}`;
    pix.set(id, { polls: 0 });
    return { mp_payment_id: id, charge_id: id, provider: 'mock', amount: round2(amount), qr_code: `00020126MOCK${id}5204000053039865802BR6304ABCD`, qr_code_base64: QR_PNG, expires_at: now(), payment_method: 'mp_pix' };
}

function transfer(itemIds, b) {
    const origin = [...sessions.values()].find((s) => s.items.some((i) => itemIds.includes(i.id)));
    need(origin, 'Item');
    let dest;
    if (b.target_table_id) {
        const t = need(tables.find((x) => x.id === b.target_table_id), 'Mesa de destino');
        dest = { id: randomUUID(), table_id: t.id, status: 'open', opened_at: now(), last_activity_at: now(), guest_count: null, customer_name: null, items: [], payments: [], comandas: [], couvert: null, fee_removed: false };
        sessions.set(dest.id, dest);
    } else {
        dest = sessionOf(b.target_session_id);
    }
    for (const id of itemIds) {
        const item = origin.items.find((i) => i.id === id);
        if (!item) continue;
        if (b.quantity && b.quantity < item.quantity) {
            item.quantity -= b.quantity;
            dest.items.push({ ...item, id: randomUUID(), quantity: b.quantity, comanda_id: b.target_comanda_id ?? null });
        } else {
            origin.items = origin.items.filter((i) => i.id !== id);
            dest.items.push({ ...item, comanda_id: b.target_comanda_id ?? null });
        }
    }
    return { message: 'Item transferido.', item_ids: itemIds, destination_session_id: dest.id };
}

const compiled = routes.map(([method, path, handler, open]) => ({
    method, handler, open, keys: [...path.matchAll(/:(\w+)/g)].map((x) => x[1]),
    re: new RegExp(`^/api/garcom/v1${path.replace(/:(\w+)/g, '([^/]+)')}$`),
}));

createServer(async (req, res) => {
    const send = (status, body) => {
        res.writeHead(status, {
            'Content-Type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Authorization, Content-Type, Accept, Idempotency-Key',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        });
        res.end(status === 204 ? undefined : JSON.stringify(body));
    };
    if (req.method === 'OPTIONS') return send(204);
    const url = new URL(req.url, 'http://x');
    let raw = '';
    for await (const chunk of req) raw += chunk;
    let body = {};
    try { body = raw ? JSON.parse(raw) : {}; } catch { return send(422, { error: 'JSON inválido.' }); }

    for (const r of compiled) {
        if (r.method !== req.method) continue;
        const match = r.re.exec(url.pathname);
        if (!match) continue;
        if (!r.open && !tokens.has((req.headers.authorization ?? '').replace(/^Bearer /, ''))) return send(401, { message: 'Unauthenticated.' });
        const mutating = req.method !== 'GET';
        const key = req.headers['idempotency-key'];
        if (mutating && !r.open && !key) return send(422, { error: 'Idempotency-Key header is required.' });
        if (mutating && key && idempotency.has(key)) return send(...idempotency.get(key));
        try {
            const params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(match[i + 1])]));
            const out = r.handler(params, body, url);
            const status = req.method === 'POST' && /\/(orders|sessions|comandas|open|checkout)$/.test(url.pathname) ? 201 : 200;
            if (mutating && key) idempotency.set(key, [status, out]);
            console.log(`${req.method} ${url.pathname} → ${status}`);
            return send(status, out);
        } catch (e) {
            console.log(`${req.method} ${url.pathname} → ${e.status ?? 500} ${e.message}`);
            return send(e.status ?? 500, e.body ?? { error: e.message });
        }
    }
    send(404, { message: 'Rota não encontrada no servidor de desenvolvimento.' });
}).listen(PORT, () => console.log(`Mobiz mock em http://localhost:${PORT} — senha de qualquer usuário: 123456`));
