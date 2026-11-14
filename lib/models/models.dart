/// Modelos do contrato `/api/garcom/v1` — espelho de
/// `apps/garcom-pwa/src/types/index.ts` no Mobizweb.
library;

import 'json.dart';

export 'json.dart';

// ── Autenticação ─────────────────────────────────────────────────────────────

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Json j) =>
      AuthUser(id: asString(j['id']), name: asString(j['name']), email: asString(j['email']));
  Json toJson() => {'id': id, 'name': name, 'email': email};
}

class StoreRef {
  const StoreRef({required this.id, required this.name});
  final String id;
  final String name;

  factory StoreRef.fromJson(Json j) => StoreRef(id: asString(j['id']), name: asString(j['name']));
  Json toJson() => {'id': id, 'name': name};
}

/// Flags de permissão do operador (chaves iguais às do backend). Chave
/// ausente = negado, como `NO_PERMISSIONS` no PWA.
class Permissions {
  const Permissions([this._map = const {}]);
  final Map<String, bool> _map;

  factory Permissions.fromJson(dynamic j) =>
      Permissions({for (final e in asMap(j).entries) e.key: asBool(e.value)});
  Json toJson() => Map<String, dynamic>.from(_map);

  bool can(String key) => _map[key] == true;

  bool get transferTable => can('transfer_table');
  bool get transferItem => can('transfer_item');
  bool get reopenSession => can('reopen_session');
  bool get cancelSession => can('cancel_session');
  bool get cancelItem => can('cancel_item');
  bool get manageComanda => can('manage_comanda');
  bool get processPayment => can('process_payment');
  bool get serviceFeeRemove => can('service_fee_remove');
  bool get cashOpen => can('cash_open');
  bool get cashClose => can('cash_close');
  bool get cashMovement => can('cash_movement');
  bool get counterSale => can('counter_sale');
  bool get openSession => can('open_session');
  bool get requestBill => can('request_bill');
  bool get closeSession => can('close_session');
  bool get couvertAdd => can('couvert_add');
  bool get couvertRemove => can('couvert_remove');
  bool get createOrder => can('create_order');
  bool get sendOrder => can('send_order');
}

// ── Mesas ────────────────────────────────────────────────────────────────────

class TableSessionSummary {
  const TableSessionSummary({
    required this.id,
    required this.status,
    required this.openedAt,
    this.lastActivityAt,
    this.guestCount,
    this.customerName,
    this.openedByName,
    this.total = 0,
  });
  final String id;
  final String status;
  final String openedAt;
  final String? lastActivityAt;
  final int? guestCount;
  final String? customerName;
  final String? openedByName;
  final double total;

  factory TableSessionSummary.fromJson(Json j) => TableSessionSummary(
    id: asString(j['id']),
    status: asString(j['status']),
    openedAt: asString(j['opened_at']),
    lastActivityAt: asStringOrNull(j['last_activity_at']),
    guestCount: asIntOrNull(j['guest_count']),
    customerName: asStringOrNull(j['customer_name']),
    openedByName: asStringOrNull(j['opened_by_name']),
    total: asDouble(j['total']),
  );
}

class DiningTable {
  const DiningTable({
    required this.id,
    required this.number,
    this.label,
    required this.status,
    this.isComanda = false,
    this.areaName,
    this.session,
    this.pendingCalls = 0,
    this.hasUnassignedItems = false,
  });
  final String id;
  final String number;
  final String? label;

  /// `available` | `occupied` | `reserved` | `closing`.
  final String status;

  /// Tipo `C` = comanda/cartão físico (aba "Comandas").
  final bool isComanda;
  final String? areaName;
  final TableSessionSummary? session;
  final int pendingCalls;
  final bool hasUnassignedItems;

  String get title => label ?? number;

  factory DiningTable.fromJson(Json j) => DiningTable(
    id: asString(j['id']),
    number: asString(j['number']),
    label: asStringOrNull(j['label']),
    status: asString(j['status'], 'available'),
    isComanda: asBool(j['is_comanda']) || j['type'] == 'C',
    areaName: j['area'] is Map ? asStringOrNull(j['area']['name']) : null,
    session: j['session'] is Map ? TableSessionSummary.fromJson(asMap(j['session'])) : null,
    pendingCalls: asInt(j['pending_calls']),
    hasUnassignedItems: asBool(j['has_unassigned_items']),
  );
}

// ── Cardápio ─────────────────────────────────────────────────────────────────

class AddonItem {
  const AddonItem({required this.id, required this.name, this.price = 0, this.maxQuantity, this.itemLimit});
  final String id;
  final String name;
  final double price;
  final int? maxQuantity;
  final int? itemLimit;

  factory AddonItem.fromJson(Json j) => AddonItem(
    id: asString(j['id']),
    name: asString(j['name']),
    price: asDouble(j['price']),
    maxQuantity: asIntOrNull(j['max_quantity']),
    itemLimit: asIntOrNull(j['item_limit']),
  );
}

class AddonGroup {
  const AddonGroup({
    required this.id,
    required this.name,
    this.min = 0,
    this.max = 0,
    this.isRequiredFlag,
    this.allowRepeat = false,
    this.items = const [],
  });
  final String id;
  final String name;
  final int min;

  /// 0 = sem limite.
  final int max;
  final bool? isRequiredFlag;
  final bool allowRepeat;
  final List<AddonItem> items;

  factory AddonGroup.fromJson(Json j) => AddonGroup(
    id: asString(j['id']),
    name: asString(j['name']),
    min: asInt(j['min']),
    max: asInt(j['max']),
    isRequiredFlag: j['is_required'] == null ? null : asBool(j['is_required']),
    allowRepeat: asBool(j['allow_repeat']),
    items: asList(j['items']).map(AddonItem.fromJson).toList(),
  );
}

class FlavorItem {
  const FlavorItem({required this.id, required this.name, this.price = 0, this.imageUrl});
  final String id;
  final String name;
  final double price;
  final String? imageUrl;

  factory FlavorItem.fromJson(Json j) => FlavorItem(
    id: asString(j['id']),
    name: asString(j['name']),
    price: asDouble(j['price']),
    imageUrl: asStringOrNull(j['image_url']),
  );
}

class PizzaConfig {
  const PizzaConfig({
    required this.maxFlavors,
    required this.pricingRule,
    required this.groupName,
    required this.flavors,
  });
  final int maxFlavors;

  /// `highest` | `average`.
  final String pricingRule;
  final String groupName;
  final List<FlavorItem> flavors;

  factory PizzaConfig.fromJson(Json j) {
    final g = asMap(j['flavor_group']);
    return PizzaConfig(
      maxFlavors: asInt(j['max_flavors'], 1),
      pricingRule: asString(j['pricing_rule'], 'highest'),
      groupName: asString(g['name'], 'Sabores'),
      flavors: asList(g['items']).map(FlavorItem.fromJson).toList(),
    );
  }
}

class ComboGroupItem {
  const ComboGroupItem({
    required this.id,
    required this.name,
    required this.productId,
    this.extraPrice = 0,
    this.isDefault = false,
  });
  final String id;
  final String name;
  final String productId;
  final double extraPrice;
  final bool isDefault;

  factory ComboGroupItem.fromJson(Json j) => ComboGroupItem(
    id: asString(j['id']),
    name: asString(j['name']),
    productId: asString(j['product_id']),
    extraPrice: asDouble(j['extra_price']),
    isDefault: asBool(j['is_default']),
  );
}

class ComboGroup {
  const ComboGroup({
    required this.id,
    required this.name,
    this.min = 0,
    this.max = 1,
    this.isRequired = false,
    this.items = const [],
  });
  final String id;
  final String name;
  final int min;
  final int max;
  final bool isRequired;
  final List<ComboGroupItem> items;

  factory ComboGroup.fromJson(Json j) => ComboGroup(
    id: asString(j['id']),
    name: asString(j['name']),
    min: asInt(j['min']),
    max: asInt(j['max'], 1),
    isRequired: asBool(j['is_required']),
    items: asList(j['items']).map(ComboGroupItem.fromJson).toList(),
  );
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.name,
    this.type = 'simple',
    this.price = 0,
    this.isAvailable = true,
    this.unitOfMeasure,
    this.allowFractionalQty = false,
    this.imageUrl,
    this.addonGroups = const [],
    this.pizza,
    this.comboGroups = const [],
    this.code,
    this.originalPrice,
    this.promotion,
  });
  final String id;
  final String name;

  /// Código (SKU) do cadastro, usado no código de barras da ficha. Servidor
  /// antigo não envia: a ficha usa a posição do item na venda.
  final String? code;

  /// Só com promoção vigente: o preço sem ela ("de") e o nome da promoção.
  /// [price] é sempre o que será cobrado no canal pedido.
  final double? originalPrice;
  final String? promotion;

  bool get onPromotion => originalPrice != null && originalPrice! > price + 0.004;

  /// `simple` | `pizza` | `combo`.
  final String type;
  final double price;
  final bool isAvailable;
  final String? unitOfMeasure;
  final bool allowFractionalQty;
  final String? imageUrl;
  final List<AddonGroup> addonGroups;
  final PizzaConfig? pizza;
  final List<ComboGroup> comboGroups;

  factory MenuProduct.fromJson(Json j) => MenuProduct(
    id: asString(j['id']),
    name: asString(j['name']),
    type: asString(j['type'], 'simple'),
    price: asDouble(j['price']),
    isAvailable: asBool(j['is_available'], true),
    unitOfMeasure: asStringOrNull(j['unit_of_measure']),
    allowFractionalQty: asBool(j['allow_fractional_qty']),
    imageUrl: asStringOrNull(j['image_url']),
    addonGroups: asList(j['addon_groups']).map(AddonGroup.fromJson).toList(),
    pizza: j['pizza'] is Map ? PizzaConfig.fromJson(asMap(j['pizza'])) : null,
    comboGroups: asList(j['combo_groups']).map(ComboGroup.fromJson).toList(),
    code: asStringOrNull(j['sku']) ?? asStringOrNull(j['code']),
    originalPrice: j['original_price'] == null ? null : asDouble(j['original_price']),
    promotion: asStringOrNull(j['promotion']),
  );
}

class MenuCategory {
  MenuCategory({this.id, required this.name, this.icon, this.parentId, required this.products});
  final String? id;
  final String name;
  final String? icon;
  final String? parentId;
  final List<MenuProduct> products;

  factory MenuCategory.fromJson(Json j) => MenuCategory(
    id: asStringOrNull(j['id']),
    name: asString(j['name']),
    icon: asStringOrNull(j['icon']),
    parentId: asStringOrNull(j['parent_id']),
    products: asList(j['products']).map(MenuProduct.fromJson).toList(),
  );
}

// ── Carrinho ─────────────────────────────────────────────────────────────────

class AddonChoice {
  const AddonChoice(this.addonGroupItemId, this.quantity);
  final String addonGroupItemId;
  final int quantity;
  Json toJson() => {'addon_group_item_id': addonGroupItemId, 'quantity': quantity};
}

class ComboSelection {
  const ComboSelection({required this.groupId, required this.groupName, required this.items});
  final String groupId;
  final String groupName;
  final List<({String id, String name})> items;
  Json toJson() => {
    'group_id': groupId,
    'group_name': groupName,
    'items': [for (final i in items) {'id': i.id, 'name': i.name}],
  };
}

class CartItem {
  CartItem({
    required this.localId,
    required this.product,
    required this.quantity,
    this.notes = '',
    this.addons = const [],
    this.selectedFlavorIds = const [],
    this.comboSelections = const [],
    required this.unitPrice,
  });
  final String localId;
  final MenuProduct product;
  double quantity;
  final String notes;
  final List<AddonChoice> addons;
  final List<String> selectedFlavorIds;
  final List<ComboSelection> comboSelections;

  /// Preço unitário com pizza/adicionais/combo aplicados.
  final double unitPrice;

  double get total => unitPrice * quantity;

  /// Corpo do item no POST de pedido (o backend recalcula o preço).
  Json toPayload() => {
    'product_id': product.id,
    'quantity': quantity == quantity.roundToDouble() ? quantity.toInt() : quantity,
    if (notes.isNotEmpty) 'notes': notes,
    if (addons.isNotEmpty) 'addons': [for (final a in addons) a.toJson()],
    if (selectedFlavorIds.isNotEmpty) 'selected_flavor_ids': selectedFlavorIds,
    if (comboSelections.isNotEmpty) 'combo_selections': [for (final c in comboSelections) c.toJson()],
  };
}

// ── Sessão (mesa aberta) ─────────────────────────────────────────────────────

class SessionItem {
  const SessionItem({
    required this.id,
    this.comandaId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.notes,
    required this.status,
    this.canCancel = false,
    this.canTransfer = false,
    this.createdAt,
    this.flavors = const [],
    this.addons = const [],
  });
  final String id;
  final String? comandaId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final String? notes;

  /// `pending` | `preparing` | `ready` | `delivered` | `canceled`.
  final String status;
  final bool canCancel;
  final bool canTransfer;
  final String? createdAt;
  final List<String> flavors;
  final List<({String name, int quantity})> addons;

  bool get isCanceled => status == 'canceled';
  double get total => unitPrice * quantity;

  String get flavorsLabel => flavors.join(' / ');
  String get addonsLabel => addons.map((a) => a.quantity > 1 ? '${a.quantity}× ${a.name}' : a.name).join(', ');

  factory SessionItem.fromJson(Json j) => SessionItem(
    id: asString(j['id']),
    comandaId: asStringOrNull(j['comanda_id']),
    productName: asString(j['product_name']),
    quantity: asDouble(j['quantity'], 1),
    unitPrice: asDouble(j['unit_price']),
    notes: asStringOrNull(j['notes']),
    status: asString(j['status'], 'pending'),
    canCancel: asBool(j['can_cancel']),
    canTransfer: asBool(j['can_transfer']),
    createdAt: asStringOrNull(j['created_at']),
    // O servidor manda ora só os nomes, ora `{id, name}`.
    flavors: [
      if (j['selected_flavors'] is List)
        for (final f in j['selected_flavors'] as List)
          if (f is Map) asString(f['name']) else asString(f),
    ].where((n) => n.isNotEmpty).toList(),
    addons: asList(j['addons']).map((a) => (name: asString(a['name']), quantity: asInt(a['quantity'], 1))).toList(),
  );
}

/// Conta calculada pelo BillCalculatorService — fonte única de "total".
class SessionBill {
  const SessionBill({
    this.itemsSubtotal = 0,
    this.couvertAmount = 0,
    this.serviceFee = 0,
    this.serviceFeePercentage = 0,
    this.serviceFeeRemoved = false,
    this.discount = 0,
    this.total = 0,
    this.paid = 0,
    this.remaining = 0,
  });
  final double itemsSubtotal;
  final double couvertAmount;
  final double serviceFee;
  final double serviceFeePercentage;
  final bool serviceFeeRemoved;
  final double discount;
  final double total;
  final double paid;
  final double remaining;

  bool get settled => remaining <= 0.005;

  factory SessionBill.fromJson(Json j) => SessionBill(
    itemsSubtotal: asDouble(j['items_subtotal']),
    couvertAmount: asDouble(j['couvert_amount']),
    serviceFee: asDouble(j['service_fee']),
    serviceFeePercentage: asDouble(j['service_fee_percentage']),
    serviceFeeRemoved: asBool(j['service_fee_removed']),
    discount: asDouble(j['discount']),
    total: asDouble(j['total']),
    paid: asDouble(j['paid']),
    remaining: asDouble(j['remaining']),
  );
}

class SessionComandaSummary {
  const SessionComandaSummary({required this.id, required this.label, required this.status});
  final String id;
  final String label;

  /// `open` | `closing` | `paid` | `canceled`.
  final String status;

  factory SessionComandaSummary.fromJson(Json j) =>
      SessionComandaSummary(id: asString(j['id']), label: asString(j['label']), status: asString(j['status']));
}

class PendingTabletOrder {
  const PendingTabletOrder({required this.id, required this.items});
  final String id;
  final List<({String productName, double quantity, String? notes})> items;

  factory PendingTabletOrder.fromJson(Json j) => PendingTabletOrder(
    id: asString(j['id']),
    items: asList(j['items'])
        .map(
          (i) => (
            productName: asString(i['product_name']),
            quantity: asDouble(i['quantity'], 1),
            notes: asStringOrNull(i['notes']),
          ),
        )
        .toList(),
  );
}

class TransferTarget {
  const TransferTarget({
    required this.id,
    required this.tableNumber,
    this.areaName,
    this.isCurrent = false,
    this.hasActiveComandas = false,
    this.comandas = const [],
  });
  final String id;
  final String tableNumber;
  final String? areaName;
  final bool isCurrent;
  final bool hasActiveComandas;
  final List<({String id, String label})> comandas;

  String get label =>
      isCurrent ? 'Mesa $tableNumber (esta mesa)' : 'Mesa $tableNumber${areaName != null ? ' · $areaName' : ''}';

  factory TransferTarget.fromJson(Json j) => TransferTarget(
    id: asString(j['id']),
    tableNumber: asString(j['table_number']),
    areaName: asStringOrNull(j['area_name']),
    isCurrent: asBool(j['is_current']),
    hasActiveComandas: asBool(j['has_active_comandas']),
    comandas: asList(j['comandas']).map((c) => (id: asString(c['id']), label: asString(c['label']))).toList(),
  );
}

class FreeTable {
  const FreeTable({required this.id, required this.number, this.areaName});
  final String id;
  final String number;
  final String? areaName;
  String get label => areaName != null ? 'Mesa $number · $areaName' : 'Mesa $number';

  factory FreeTable.fromJson(Json j) =>
      FreeTable(id: asString(j['id']), number: asString(j['number']), areaName: asStringOrNull(j['area_name']));
}

class SessionCouvert {
  const SessionCouvert({required this.amount, required this.persons, required this.total});
  final double amount;
  final int persons;
  final double total;

  factory SessionCouvert.fromJson(Json j) =>
      SessionCouvert(amount: asDouble(j['amount']), persons: asInt(j['persons']), total: asDouble(j['total']));
}

class SessionDetail {
  const SessionDetail({
    required this.id,
    required this.status,
    this.openedAt,
    this.guestCount,
    this.customerName,
    this.tableId,
    this.tableNumber,
    this.tableLabel,
    this.items = const [],
    this.pendingTabletOrders = const [],
    this.hasComandas = false,
    this.unassignedItemsCount,
    this.enableComandas = true,
    this.comandas = const [],
    this.transferTargets = const [],
    this.freeTables = const [],
    this.requireTransferItemPassword = false,
    this.requireCancelSessionPassword = false,
    this.requireServiceFeeRemovalPassword = false,
    this.couvert,
    this.couvertDefaultAmount,
    this.bill = const SessionBill(),
  });
  final String id;

  /// `open` | `closing` | `closed` | `canceled`.
  final String status;
  final String? openedAt;
  final int? guestCount;
  final String? customerName;
  final String? tableId;
  final String? tableNumber;
  final String? tableLabel;
  final List<SessionItem> items;
  final List<PendingTabletOrder> pendingTabletOrders;
  final bool hasComandas;
  final int? unassignedItemsCount;
  final bool enableComandas;
  final List<SessionComandaSummary> comandas;
  final List<TransferTarget> transferTargets;
  final List<FreeTable> freeTables;
  final bool requireTransferItemPassword;
  final bool requireCancelSessionPassword;
  final bool requireServiceFeeRemovalPassword;
  final SessionCouvert? couvert;
  final double? couvertDefaultAmount;
  final SessionBill bill;

  bool get isOpen => status == 'open';
  bool get isClosing => status == 'closing';
  String get title => tableLabel ?? tableNumber ?? 'Mesa';
  List<SessionItem> get activeItems => items.where((i) => !i.isCanceled).toList();
  List<SessionComandaSummary> get openComandas => comandas.where((c) => c.status == 'open').toList();
  bool get hasActiveComandas => comandas.any((c) => c.status == 'open' || c.status == 'closing');

  factory SessionDetail.fromJson(Json j) {
    final t = asMap(j['table']);
    var targets = asList(j['transfer_targets']).map(TransferTarget.fromJson).toList();
    if (targets.isEmpty) {
      // Servidor antigo: só as outras sessões, sem comandas.
      targets = asList(j['other_open_sessions'])
          .map((s) => TransferTarget(id: asString(s['id']), tableNumber: asString(s['table_number'])))
          .toList();
    }
    return SessionDetail(
      id: asString(j['id']),
      status: asString(j['status'], 'open'),
      openedAt: asStringOrNull(j['opened_at']),
      guestCount: asIntOrNull(j['guest_count']),
      customerName: asStringOrNull(j['customer_name']),
      tableId: asStringOrNull(t['id']),
      tableNumber: asStringOrNull(t['number']),
      tableLabel: asStringOrNull(t['label']),
      items: asList(j['items']).map(SessionItem.fromJson).toList(),
      pendingTabletOrders: asList(j['pending_tablet_orders']).map(PendingTabletOrder.fromJson).toList(),
      hasComandas: asBool(j['has_comandas']),
      unassignedItemsCount: asIntOrNull(j['unassigned_items_count']),
      enableComandas: asBool(j['enable_comandas'], true),
      comandas: asList(j['comandas']).map(SessionComandaSummary.fromJson).toList(),
      transferTargets: targets,
      freeTables: asList(j['free_tables']).map(FreeTable.fromJson).toList(),
      requireTransferItemPassword: asBool(j['require_transfer_item_password']),
      requireCancelSessionPassword: asBool(j['require_cancel_session_password']),
      requireServiceFeeRemovalPassword: asBool(j['require_service_fee_removal_password']),
      couvert: j['couvert'] is Map ? SessionCouvert.fromJson(asMap(j['couvert'])) : null,
      couvertDefaultAmount: asDoubleOrNull(j['couvert_default_amount']),
      bill: j['bill'] is Map ? SessionBill.fromJson(asMap(j['bill'])) : const SessionBill(),
    );
  }
}

// ── Comandas dentro da mesa ──────────────────────────────────────────────────

class Comanda {
  const Comanda({
    required this.id,
    required this.label,
    required this.status,
    this.itemsSubtotal = 0,
    this.serviceFee = 0,
    this.serviceFeePercentage = 0,
    this.serviceFeeRemoved = false,
    this.total = 0,
    this.paid = 0,
    this.remaining = 0,
    this.itemsCount,
    this.hasPayments = false,
    this.couvert,
  });
  final String id;
  final String label;
  final String status;
  final double itemsSubtotal;
  final double serviceFee;
  final double serviceFeePercentage;
  final bool serviceFeeRemoved;
  final double total;
  final double paid;
  final double remaining;
  final int? itemsCount;
  final bool hasPayments;
  final SessionCouvert? couvert;

  bool get isActive => status == 'open' || status == 'closing';

  factory Comanda.fromJson(Json j) => Comanda(
    id: asString(j['id']),
    label: asString(j['label']),
    status: asString(j['status'], 'open'),
    itemsSubtotal: asDouble(j['items_subtotal']),
    serviceFee: asDouble(j['service_fee']),
    serviceFeePercentage: asDouble(j['service_fee_percentage']),
    serviceFeeRemoved: asBool(j['service_fee_removed']),
    total: asDouble(j['total']),
    paid: asDouble(j['paid']),
    remaining: asDouble(j['remaining']),
    itemsCount: asIntOrNull(j['items_count']),
    hasPayments: asBool(j['has_payments']) || asDouble(j['paid']) > 0,
    couvert: j['couvert'] is Map ? SessionCouvert.fromJson(asMap(j['couvert'])) : null,
  );
}

class ComandaTransferTable {
  const ComandaTransferTable({required this.id, required this.number, this.areaName, required this.state});
  final String id;
  final String number;
  final String? areaName;

  /// `free` | `open` | `closing`.
  final String state;

  factory ComandaTransferTable.fromJson(Json j) => ComandaTransferTable(
    id: asString(j['id']),
    number: asString(j['number']),
    areaName: asStringOrNull(j['area_name']),
    state: asString(j['state'], 'free'),
  );
}

class ComandasResponse {
  const ComandasResponse({
    this.comandas = const [],
    this.available = const [],
    this.transferTables = const [],
    this.transferRequiresPassword = false,
    this.cancelRequiresPassword = false,
  });
  final List<Comanda> comandas;
  final List<({String id, String label})> available;
  final List<ComandaTransferTable> transferTables;
  final bool transferRequiresPassword;
  final bool cancelRequiresPassword;

  factory ComandasResponse.fromJson(Json j) => ComandasResponse(
    comandas: asList(j['comandas']).map(Comanda.fromJson).toList(),
    available: asList(j['available']).map((a) => (id: asString(a['id']), label: asString(a['label']))).toList(),
    transferTables: asList(j['transfer_tables']).map(ComandaTransferTable.fromJson).toList(),
    transferRequiresPassword: asBool(j['transfer_requires_password']),
    cancelRequiresPassword: asBool(j['cancel_requires_password']),
  );
}

// ── Pagamento ────────────────────────────────────────────────────────────────

/// Forma de pagamento do PDV da loja (ADR-014: por loja).
class PaymentMethodOption {
  const PaymentMethodOption({
    required this.code,
    required this.name,
    required this.method,
    this.isDefault = false,
    this.isCash = false,
  });

  /// Código cadastrado na loja (`card_credit`, `especie`…).
  final String code;
  final String name;

  /// Método canônico do pipeline (`cash`, `credit_card`, `debit_card`, `pix`…).
  final String method;
  final bool isDefault;
  final bool isCash;

  factory PaymentMethodOption.fromJson(Json j) => PaymentMethodOption(
    code: asString(j['code']),
    name: asString(j['name']),
    method: asString(j['method'], asString(j['code'])),
    isDefault: asBool(j['is_default']),
    isCash: asBool(j['is_cash']),
  );
}

class PixCharge {
  const PixCharge({
    required this.mpPaymentId,
    required this.amount,
    required this.qrCode,
    required this.qrCodeBase64,
    this.paymentMethod,
  });
  final String mpPaymentId;
  final double amount;
  final String qrCode;
  final String qrCodeBase64;
  final String? paymentMethod;

  /// Forma com que o recebimento é registrado: a do provedor que abriu o QR.
  String get recordMethod => (paymentMethod == null || paymentMethod!.isEmpty) ? 'mp_pix' : paymentMethod!;

  factory PixCharge.fromJson(Json j) => PixCharge(
    mpPaymentId: asString(j['mp_payment_id']),
    amount: asDouble(j['amount']),
    qrCode: asString(j['qr_code']),
    qrCodeBase64: asString(j['qr_code_base64']),
    paymentMethod: asStringOrNull(j['payment_method']),
  );
}

// ── Caixa ────────────────────────────────────────────────────────────────────

class CashSession {
  const CashSession({
    required this.id,
    required this.status,
    this.openedAt,
    this.closedAt,
    this.openingAmount,
    this.closingAmount,
    this.expectedAmount,
    this.difference,
  });
  final String id;
  final String status;
  final String? openedAt;
  final String? closedAt;

  /// Valores `null` quando o usuário não pode ver dinheiro do caixa.
  final double? openingAmount;
  final double? closingAmount;
  final double? expectedAmount;
  final double? difference;

  bool get isOpen => status == 'open';

  factory CashSession.fromJson(Json j) => CashSession(
    id: asString(j['id']),
    status: asString(j['status'], 'open'),
    openedAt: asStringOrNull(j['opened_at']),
    closedAt: asStringOrNull(j['closed_at']),
    openingAmount: asDoubleOrNull(j['opening_amount']),
    closingAmount: asDoubleOrNull(j['closing_amount']),
    expectedAmount: asDoubleOrNull(j['expected_amount']),
    difference: asDoubleOrNull(j['difference']),
  );
}

class CashContext {
  const CashContext({
    this.enabled = false,
    this.blindClose = true,
    this.canOpen = false,
    this.canClose = false,
    this.canMove = false,
    this.canSeeFinancial = true,
    this.session,
  });
  final bool enabled;
  final bool blindClose;
  final bool canOpen;
  final bool canClose;
  final bool canMove;
  final bool canSeeFinancial;
  final CashSession? session;

  factory CashContext.fromJson(Json j) {
    final s = asMap(j['settings']);
    final p = asMap(j['permissions']);
    final sess = j['session'] is Map ? CashSession.fromJson(asMap(j['session'])) : null;
    return CashContext(
      enabled: asBool(j['enabled']),
      blindClose: asBool(s['blind_close'], true),
      canOpen: asBool(p['open']),
      canClose: asBool(p['close']),
      canMove: asBool(p['movement']),
      canSeeFinancial: asBool(p['financial'], true),
      // Sessão já fechada não é "caixa aberto".
      session: (sess != null && sess.isOpen) ? sess : null,
    );
  }

  CashContext withSession(CashSession? s) => CashContext(
    enabled: enabled,
    blindClose: blindClose,
    canOpen: canOpen,
    canClose: canClose,
    canMove: canMove,
    canSeeFinancial: canSeeFinancial,
    session: (s != null && s.isOpen) ? s : null,
  );
}

class CashMovement {
  const CashMovement({required this.id, required this.type, required this.amount, this.reason, this.createdAt});
  final String id;

  /// `cash_in` | `cash_out` | `supply` | `withdrawal`.
  final String type;
  final double amount;
  final String? reason;
  final String? createdAt;

  bool get isCredit => type == 'supply' || type == 'cash_in';
  String get label => switch (type) {
    'supply' => 'Suprimento',
    'withdrawal' => 'Sangria',
    'cash_in' => 'Entrada',
    _ => 'Saída',
  };

  factory CashMovement.fromJson(Json j) => CashMovement(
    id: asString(j['id']),
    type: asString(j['type']),
    amount: asDouble(j['amount']),
    reason: asStringOrNull(j['reason']),
    createdAt: asStringOrNull(j['created_at']),
  );
}

class CashExpectedEntry {
  const CashExpectedEntry({required this.key, required this.label, this.total, this.isDigital = false});
  final String key;
  final String label;
  final double? total;
  final bool isDigital;
}

class CashSummary {
  const CashSummary({
    this.paymentsByMethod = const [],
    this.movementsByType = const {},
    this.expectedBreakdown = const [],
    this.totalCashIn,
    this.totalCashOut,
    this.ordersTotal,
    this.ordersCount = 0,
  });
  final List<({String label, double? total, int count})> paymentsByMethod;

  /// Total por tipo de movimento; `null` no mapa inteiro = servidor antigo.
  final Map<String, double?> movementsByType;
  final List<CashExpectedEntry> expectedBreakdown;
  final double? totalCashIn;
  final double? totalCashOut;
  final double? ordersTotal;
  final int ordersCount;

  factory CashSummary.fromJson(Json j) {
    final pm = asMap(j['paymentsByMethod']);
    final mv = asMap(j['movementsByType']);
    final eb = asMap(j['expectedBreakdown']);
    return CashSummary(
      paymentsByMethod: [
        for (final e in pm.entries)
          (
            label: asString(asMap(e.value)['label'], e.key),
            total: asDoubleOrNull(asMap(e.value)['total']),
            count: asInt(asMap(e.value)['count']),
          ),
      ],
      movementsByType: {for (final e in mv.entries) e.key: asDoubleOrNull(asMap(e.value)['total'])},
      expectedBreakdown: [
        for (final e in eb.entries)
          CashExpectedEntry(
            key: e.key,
            label: asString(asMap(e.value)['label'], e.key),
            total: asDoubleOrNull(asMap(e.value)['total']),
            isDigital: asBool(asMap(e.value)['is_digital']),
          ),
      ],
      totalCashIn: asDoubleOrNull(j['totalCashIn']),
      totalCashOut: asDoubleOrNull(j['totalCashOut']),
      ordersTotal: asDoubleOrNull(j['ordersTotal']),
      ordersCount: asInt(j['ordersCount']),
    );
  }
}

class CashDetail {
  const CashDetail({required this.session, this.movements = const [], this.summary = const CashSummary()});
  final CashSession session;
  final List<CashMovement> movements;
  final CashSummary summary;

  factory CashDetail.fromJson(Json j) => CashDetail(
    session: CashSession.fromJson(asMap(j['session'])),
    movements: asList(j['movements']).map(CashMovement.fromJson).toList(),
    summary: CashSummary.fromJson(asMap(j['summary'])),
  );
}

// ── Balcão ───────────────────────────────────────────────────────────────────

class CounterContext {
  const CounterContext({
    this.enabled = false,
    this.canSell = false,
    this.methods = const [],
    this.cashOpen = false,
    this.fiscalActive = false,
  });
  final bool enabled;
  final bool canSell;
  final List<PaymentMethodOption> methods;
  final bool cashOpen;

  /// A loja tem emissão fiscal ativa: a venda sai sem nota e "Venda recebida"
  /// oferece "Imprimir nota fiscal". Servidor antigo não informa (`false`).
  final bool fiscalActive;

  factory CounterContext.fromJson(Json j) => CounterContext(
    enabled: asBool(j['enabled']),
    canSell: asBool(asMap(j['permissions'])['sell']),
    methods: asList(j['payment_methods']).map(PaymentMethodOption.fromJson).toList(),
    cashOpen: j['cash_session'] is Map,
    fiscalActive: asBool(asMap(j['fiscal'])['active']),
  );
}

/// Uma linha do DANFE NFC-e, já composta pelo servidor na largura do aparelho.
class DanfeLine {
  const DanfeLine(this.text, {this.center = false, this.bold = false, this.big = false, this.qr = false});
  final String text;
  final bool center;
  final bool bold;
  final bool big;

  /// A linha é o QR-Code de consulta: [text] é o conteúdo do QR.
  final bool qr;

  factory DanfeLine.fromJson(Json j) => DanfeLine(
    asString(j['text']),
    center: asString(j['align']) == 'center',
    bold: asBool(j['bold']),
    big: asBool(j['big']),
    qr: asBool(j['qr']),
  );
}

/// A NFC-e de uma venda de balcão (`POST /counter/orders/{id}/fiscal`) com o
/// DANFE pronto para a impressora da maquininha.
class FiscalNote {
  const FiscalNote({this.number, this.series, this.accessKey, this.contingency = false, this.columns = 32, this.lines = const []});
  final int? number;
  final int? series;
  final String? accessKey;
  final bool contingency;

  /// Largura em colunas com que o servidor compôs as linhas.
  final int columns;
  final List<DanfeLine> lines;

  factory FiscalNote.fromJson(Json j) {
    final n = asMap(j['nfce']);
    final d = asMap(j['danfe']);
    final columns = asInt(d['columns']);
    return FiscalNote(
      number: asIntOrNull(n['number']),
      series: asIntOrNull(n['series']),
      accessKey: asStringOrNull(n['access_key']),
      contingency: asBool(n['is_contingency']),
      columns: columns > 0 ? columns : 32,
      lines: asList(d['lines']).map(DanfeLine.fromJson).toList(),
    );
  }
}

class CounterSaleResult {
  const CounterSaleResult({
    required this.orderId,
    this.number,
    this.total = 0,
    this.changeAmount = 0,
    this.requiresOperatorDecision = false,
    this.blockReason,
  });
  final String orderId;
  final int? number;
  final double total;
  final double changeAmount;
  final bool requiresOperatorDecision;
  final String? blockReason;

  factory CounterSaleResult.fromJson(Json j) {
    final o = asMap(j['order']);
    final r = asMap(j['receipt']);
    return CounterSaleResult(
      orderId: asString(o['id']),
      number: asIntOrNull(o['number']),
      total: asDouble(o['total']),
      changeAmount: asDouble(o['change_amount']),
      requiresOperatorDecision: asBool(r['requires_operator_decision']),
      blockReason: asStringOrNull(r['block_reason']),
    );
  }
}

// ── Notificações (sino) ──────────────────────────────────────────────────────

/// Solicitação feita pelo cliente no tablet da mesa (chamar garçom, faltou
/// algo, pedir a conta, vincular comanda). `GET /tablet/calls`.
class TabletCall {
  const TabletCall({
    required this.id,
    required this.tableId,
    required this.tableLabel,
    this.tableSessionId,
    required this.reasonLabel,
    this.status = 'open',
    this.note,
    this.createdAt,
    this.elapsedSeconds = 0,
  });
  final String id;
  final String tableId;
  final String tableLabel;
  final String? tableSessionId;
  final String reasonLabel;

  /// `open` | `acknowledged` ("a caminho").
  final String status;
  final String? note;
  final String? createdAt;

  /// Tempo decorrido NO MOMENTO DA RESPOSTA; o relógio local segue daqui.
  final int elapsedSeconds;

  bool get isAcknowledged => status == 'acknowledged';

  TabletCall acknowledged() => TabletCall(
    id: id,
    tableId: tableId,
    tableLabel: tableLabel,
    tableSessionId: tableSessionId,
    reasonLabel: reasonLabel,
    status: 'acknowledged',
    note: note,
    createdAt: createdAt,
    elapsedSeconds: elapsedSeconds,
  );

  factory TabletCall.fromJson(Json j) => TabletCall(
    id: asString(j['id']),
    tableId: asString(j['table_id']),
    tableLabel: asString(j['table_label'], asString(j['table_number'])),
    tableSessionId: asStringOrNull(j['table_session_id']),
    reasonLabel: asString(j['reason_label'], asString(j['reason'])),
    status: asString(j['status'], 'open'),
    note: asStringOrNull(j['note']),
    createdAt: asStringOrNull(j['created_at']),
    elapsedSeconds: asInt(j['elapsed_seconds']),
  );
}

/// Pedido feito no tablet aguardando liberação do garçom, como vem na lista
/// do sino (`pending_orders` de `GET /tablet/calls`).
class TabletOrderNotice {
  const TabletOrderNotice({
    required this.id,
    this.tableId,
    required this.tableLabel,
    this.items = const [],
    this.createdAt,
    this.elapsedSeconds = 0,
  });
  final String id;
  final String? tableId;
  final String tableLabel;
  final List<({String name, double quantity})> items;
  final String? createdAt;
  final int elapsedSeconds;

  factory TabletOrderNotice.fromJson(Json j) => TabletOrderNotice(
    id: asString(j['id']),
    tableId: asStringOrNull(j['table_id']),
    tableLabel: asStringOrNull(j['table_label']) ?? asString(j['table_number']),
    items: [for (final i in asList(j['items'])) (name: asString(i['name']), quantity: asDouble(i['quantity'], 1))],
    createdAt: asStringOrNull(j['created_at']),
    elapsedSeconds: asInt(j['elapsed_seconds']),
  );
}

/// Item abaixo do estoque mínimo na loja ativa. Só informativo: não entra no
/// número do sino porque o garçom não "atende" estoque.
class LowStockAlert {
  const LowStockAlert({
    required this.id,
    required this.name,
    this.unit = 'un',
    this.currentStock = 0,
    this.minStock = 0,
    this.kind = 'ingredient',
  });
  final String id;
  final String name;
  final String unit;
  final double currentStock;
  final double minStock;
  final String kind;

  factory LowStockAlert.fromJson(Json j) => LowStockAlert(
    id: asString(j['id']),
    name: asString(j['name']),
    unit: asString(j['unit'], 'un'),
    currentStock: asDouble(j['current_stock']),
    minStock: asDouble(j['min_stock']),
    kind: asString(j['kind'], 'ingredient'),
  );
}

// ── Ler QR da comanda ────────────────────────────────────────────────────────

/// Resposta de `POST /tablet/comandas/lookup`: a comanda (cartão) e, se já
/// estiver em uso, em que mesa ela está.
class ComandaLookup {
  const ComandaLookup({required this.label, this.linked = false, this.tableNumber});
  final String label;
  final bool linked;
  final String? tableNumber;

  factory ComandaLookup.fromJson(Json j) => ComandaLookup(
    label: asString(asMap(j['comanda_table'])['label'], asString(asMap(j['comanda_table'])['number'])),
    linked: asBool(j['linked']),
    tableNumber: asStringOrNull(asMap(j['link'])['table_number']),
  );
}
