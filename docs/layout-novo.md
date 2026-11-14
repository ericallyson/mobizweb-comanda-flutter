# Layout novo do app do garçom: ligação com o código

Este documento acompanha a troca de layout pedida em `plano-app-garcom.md`
(especificação do gestor, versão 1, 14/11/2026) e no protótipo
`app-garcom-proposta.html`. O plano foi escrito pensando no PWA
(`apps/garcom-pwa` do Mobizweb), mas a mudança é neste app Flutter.

Regra que vale para tudo: **é só layout**. Nenhum endpoint novo, nenhum campo
novo, nenhuma regra de negócio nova. Toda ação da tela nova chama a rotina que
já existia nos stores de `lib/stores`. O backend não muda.

## 1. Andamento por fase

| Fase do plano | Entrega | Situação |
|---|---|---|
| 0 | Mapa do código e tabela da seção 8 | Feita (este documento) |
| 1 | Base visual: cores, barra inferior, botões, janela por baixo, aviso, menu inferior | Feita (frente 1) |
| 2 | Mapa de mesas (5.1) | Feita (frente 1) |
| 3 | Cardápio, pizza e revisão (5.2 a 5.4) | Feita (frente 2). Ver a seção 8 |
| 4 | Mesa aberta e receber conta (5.5, 5.6) | Pendente (fase 4 do plano) |
| 5 | Balcão, Caixa, Mais e Notificações (5.7 a 5.9) | Caixa, Mais e Notificações feitos (frente 1). Balcão: cardápio e "Venda de balcão" feitos (frente 2); "Receber venda" ainda é a janela atual (fase 4) |
| 6 | Revisão final com o roteiro da seção 10 | Pendente |

## 2. Onde está cada coisa

| Arquivo | O que faz |
|---|---|
| `lib/core/theme.dart` | Tokens de cor (`C.navy`, `C.magenta`, `C.green`, `C.orange`, `C.bg`, `C.ink`, `C.sub`, `C.line`, `C.cancel`) e de texto (`T.top`, `T.topSub`, `T.body`, `T.section`, `T.num`) |
| `lib/ui/kit.dart` | Componentes reutilizáveis (lista na seção 5) |
| `lib/ui/screens/home_shell.dart` | Casca com o menu inferior, atualização periódica e retomada do app |
| `lib/ui/screens/tables_screen.dart` | Mapa de mesas (aba Mesas) |
| `lib/ui/table_card.dart` | Card e grade de mesas, de tamanho fixo |
| `lib/ui/table_status.dart` | Cores de status de mesa (não mudaram) |
| `lib/ui/screens/cash_screen.dart` | Caixa (aba Caixa) |
| `lib/ui/screens/more_screen.dart` | Mais (aba Mais) |
| `lib/ui/screens/notifications_screen.dart` | Notificações |
| `lib/ui/sheets/comanda_link_sheet.dart` | Ler QR da comanda (código digitado) |
| `lib/ui/sheets/store_switch_sheet.dart` | Trocar loja |
| `lib/ui/screens/settings_screen.dart` | Configurações do aparelho (inclui "Fale conosco" e pagamentos pendentes) |
| `lib/stores/notifications.dart` | Estado do sino |
| `lib/stores/comanda_link.dart` | Consulta e vínculo de comanda |
| `lib/ui/screens/menu_screen.dart` | Cardápio (5.2): `MenuScreen` (a tela, usada por mesa e balcão), `TableMenuScreen` e `openTableMenu` (fluxo da mesa), `OrderFlowResult` |
| `lib/ui/sheets/product_sheet.dart` | Janelas do produto: montagem em abas (5.3) e quantidade/observação/peso. `showProductSheet` |
| `lib/ui/screens/review_screen.dart` | Revisar pedido (5.4) e a janela "Pedido na cozinha!" |
| `lib/ui/screens/counter_screen.dart` | Balcão (5.7): `CounterScreen` (aba Balcão), `CounterSaleScreen` ("Venda de balcão") e a janela atual de recebimento |
| `lib/ui/order_widgets.dart` | Peças do pedido: `ProductThumb`, `CartLine`, `ItemStatusTag`, textos que citam a mesa, `StoreRebuild` |
| `lib/core/product_builder.dart` | `ProductBuilder`: as regras da tela antiga do produto (sabores, combo, adicionais, peso, bloqueios), sem tela |
| `lib/stores/order_draft.dart` | `OrderCart` (carrinho e chave de idempotência) e `TableOrderDraft` (pedido de uma mesa; abre a mesa livre ao enviar) |
| `lib/ui/screens/session_screen.dart`, `lib/ui/sheets/*.dart` (menos `product_sheet.dart`) | Mesa aberta e suas folhas. Ainda no desenho antigo; a `SessionScreen` é provisória (só ganhou o botão "+ Itens") |
| `lib/ui/sheets/open_table_sheet.dart` | Formulário antigo "Abrir mesa". Só é usado por quem pode abrir mesa mas não pode lançar pedido |

## 3. Tabela de ligação (seção 8 do plano)

Todas as rotas ficam sob `/api/garcom/v1`. "Tela atual" é a tela deste app
antes da troca de layout.

| Ação na tela nova | Tela atual (arquivo) | Função do store e rota HTTP | Situação |
|---|---|---|---|
| Entrar (buscar mesa) | Mapa › campo "Buscar mesa..." (`tables_screen.dart`) | Busca local sobre `TablesStore.tables` (`GET /tables`): `tableMatchesQuery` filtra enquanto digita e `findTableForEntry` acha a mesa exata. Abrir usa `_TablesScreenState._onTable` | Feito |
| Trocar loja | Mapa › nome da loja no topo | `AuthStore.selectStore` → `POST /stores/{id}/select`; depois `App.resetDomain`, `TablesStore.fetch`, `MenuStore.fetch`, `PaymentMethodsStore.load(force: true)`. Agora em `showStoreSwitch` | Feito |
| Abrir mesa (pessoas, cliente, comandas) | Folha "Abrir mesa" (`sheets/open_table_sheet.dart`) | `TablesStore.open` → `POST /tables/{id}/sessions` com `guest_count`, `customer_name`, `comandas` | Feito. Mesa livre vai direto ao Cardápio (`_TablesScreenState._startFreeTable`); os campos estão em "Revisar pedido" e a mesa só é aberta ao enviar: `TableOrderDraft.submit` chama `TablesStore.open` e depois `SessionStore.sendCart` |
| Adicionar item / observação / peso | Tela do produto (`screens/product_screen.dart`, removida), aberta pelo cardápio (`ui/catalog.dart`, removido) | Monta um `CartItem` no carrinho local (`OrderCart`); nada vai ao servidor até enviar. "+" direto: `OrderCart.addOne`; janela: `showProductSheet` + `ProductBuilder`. Cardápio: `MenuStore.fetch` → `GET /menu` | Feito |
| Montar pizza | Mesma tela do produto (`product_screen.dart`, produto tipo `pizza`) | Regras de sabores e adicionais em `lib/core/addon_rules.dart` e no próprio produto (`PizzaConfig`), aplicadas por `ProductBuilder`; o preço final vem do servidor | Feito (janela em abas) |
| Enviar para cozinha | Folha do carrinho (`CartSheet`, removida) | `SessionStore.sendCart` → `POST /sessions/{id}/orders` com chave de idempotência fixa do carrinho (`OrderCart.key`). Impressão da via: `printOrderTicket` em `lib/ui/printing.dart` | Feito ("Revisar pedido") |
| Pedir conta | "Opções da mesa" (`TableOptionsSheet`) e botão do topo da mesa | `SessionStore.requestBill` → `POST /tables/{id}/sessions/current/bill`; conta impressa com `SessionStore.fetchReceipt` → `GET /sessions/{id}/receipt` | Pendente (fase 4 do plano) |
| Gerar QR do tablet na mesa | **Não existe neste app** | No PWA: `TabletCodeModal.vue` → `POST /sessions/{id}/tablet-code` | **Função ainda não existe no Flutter.** Decidido: entra na frente 3, com a mesma rota do PWA |
| Ver conta parcial | "Opções da mesa" › `PartialBillSheet` | Lê `SessionStore.session.bill` (de `GET /sessions/{id}`); imprimir usa `GET /sessions/{id}/receipt` | Pendente (fase 4 do plano) |
| Lançar couvert | "Opções da mesa" › `CouvertSheet` | `SessionStore.setCouvert` → `POST /sessions/{id}/couvert`; `removeCouvert` → `DELETE /sessions/{id}/couvert`; por comanda: `setComandaCouvert`, `removeComandaCouvert` → `DELETE /comandas/{id}/couvert` | Pendente (fase 4 do plano) |
| Comandas da mesa | "Opções da mesa" › `ComandasSheet` (`sheets/comandas_sheet.dart`) | `SessionStore.loadComandas` → `GET /sessions/{id}/comandas`; `attachComanda` → `POST /sessions/{id}/comandas`; `renameComanda` → `PATCH /comandas/{id}`; `removeComanda` → `DELETE /comandas/{id}`; `requestComandaBill` → `POST /comandas/{id}/bill`; `payComanda` → `POST /comandas/{id}/payments`; `transferComanda`; `cancelComandaItems`; taxa: `removeComandaFee`, `reapplyComandaFee` | Pendente (fase 4 do plano) |
| Transferir mesa | "Opções da mesa" › `TransferTableSheet` | `SessionStore.transferTable` → `POST /sessions/{id}/transfer` | Pendente (fase 4 do plano) |
| Transferir item | "Opções da mesa" e "Itens da comanda" (`SessionItemsScreen`, `TransferItemSheet` em `sheets/items_sheet.dart`) | `SessionStore.transferItems` → `POST /items/{id}/transfer` (um item) ou `POST /sessions/{id}/items/transfer` (vários) | Pendente (fase 4 do plano) |
| Cancelar item | "Itens da comanda" › `CancelItemSheet` | `SessionStore.cancelItem` → `DELETE /items/{id}` com motivo (e liberação do gerente quando exigida) | Pendente (fase 4 do plano) |
| Cancelar mesa | "Opções da mesa" › `CancelSessionSheet` | `SessionStore.cancelSession` → `POST /sessions/{id}/cancel` | Pendente (fase 4 do plano) |
| Receber (mesa e balcão) | Mesa: `ReceiveSheet` e `PixSheet` (`sheets/receive_sheet.dart`). Balcão: folha de recebimento da `CounterScreen` | Mesa: `SessionStore.payTable` → `POST /sessions/{id}/payments`; comanda: `payComanda`; Pix online: `generateTablePix` → `POST /sessions/{id}/pix`; fechar: `closeSession` → `POST /sessions/{id}/close`. Cartão e Pix na maquininha: `TefLedger.chargeAndRecord` (`lib/stores/payments.dart`, deeplink da Stone). Formas: `PaymentMethodsStore.load` → `GET /payment-methods`. Balcão: `TefLedger.chargeOnly` + `CounterStore.checkout` | Pendente (fase 4 do plano) |
| Venda de balcão | Ícone do carrinho no topo do mapa → `CounterScreen` | `CounterStore.fetchContext` → `GET /counter/context`; `CounterStore.checkout` → `POST /counter/checkout` | Feito: a aba "Balcão" abre o mesmo Cardápio (canal `pos`) e a tela "Venda de balcão". O recebimento ainda é a janela atual (`_CheckoutSheet`) |
| Abrir / fechar caixa, suprimento, sangria, detalhes | Ícone da carteira no topo do mapa → `CashScreen` | `CashStore.load` → `GET /cash`; `open` → `POST /cash/open`; `movement` → `POST /cash/sessions/{id}/movements`; `fetchSummary` → `GET /cash/sessions/{id}/summary`; `close` → `POST /cash/sessions/{id}/close`. Impressão do fechamento: `printCashClose` | Feito (aba "Caixa") |
| Notificações | **Não existia neste app** (no PWA: sino → `NotificationCenter.vue`) | `NotificationsStore.fetch` → `GET /tablet/calls`; `acknowledge` → `POST /tablet/calls/{id}/ack`; `resolve` → `POST /tablet/calls/{id}/resolve`; `approveOrder` → `POST /tablet/orders/{id}/approve` | Feito. Função trazida do PWA com as mesmas rotas, por polling de 30 s |
| Ler QR da comanda | **Não existia neste app** (no PWA: ícone do scanner → `ComandaScanModal.vue`) | `ComandaLinkStore.lookup` → `POST /tablet/comandas/lookup`; `link` → `POST /tablet/comandas/link` | Feito, **sem câmera**: o código é digitado (o PWA também aceita digitar). Motivo: o app da maquininha só pode ter a permissão INTERNET |
| Atualizar | Ícone de atualizar no topo do mapa | `TablesStore.fetch` → `GET /tables`. A linha "Atualizar" de Mais chama também `MenuStore.revalidate` (`GET /menu`) e `NotificationsStore.fetch`, que o app já chamava ao voltar do segundo plano. Puxar a grade para baixo continua atualizando | Feito (Mais) |
| Configurações | Ícone da engrenagem no topo do mapa (painel) → `SettingsScreen` | Preferências do aparelho em `Settings` (`lib/stores/settings.dart`); pagamentos pendentes em `TefLedger` | Feito (Mais › Configurações) |

## 4. Ícones do topo antigo e para onde foram

### Topo antigo deste app (mapa de mesas)

| Ícone | Fazia | Agora |
|---|---|---|
| Carrinho ("Balcão") | Abria a `CounterScreen` | Aba **Balcão** do menu inferior |
| Carteira ("Caixa") | Abria a `CashScreen` | Aba **Caixa** do menu inferior |
| Atualizar | `TablesStore.fetch` | **Mais › Atualizar** (e puxar a grade para baixo) |
| Engrenagem ("Configurações"), com contador de pagamentos pendentes | Abria um painel com: colunas da grade, ordenação, botão "Impressão, maquininha e suporte", usuário e "Sair" | **Mais › Configurações** (com o contador) e **Mais › Sair**. O contador de pagamentos pendentes aparece também na aba Mais. Ordenação: Configurações › Mapa de mesas. Colunas da grade: removida (a grade tem sempre 4 colunas) |
| Nome da loja com seta | Abria a lista de lojas no próprio topo | Continua no topo (nome da loja com "▾"), abrindo a janela "Trocar loja". Também em **Mais › Trocar loja** |

O topo novo do mapa tem só o **sino** (Notificações), que este app não tinha.

### Topo do PWA (o "app atual" do vídeo do gestor), 7 ícones

| Ícone no PWA | Agora neste app |
|---|---|
| Sino | Sino no topo do mapa e Mais › Notificações |
| Scanner (Ler QR Code da comanda) | Mais › Ler QR da comanda |
| Carrinho (Balcão) | Aba Balcão |
| Carteira (Caixa) | Aba Caixa |
| Atualizar | Mais › Atualizar |
| "↺" (Recarregar sistema, limpa o cache do navegador) | **É o ícone que o plano não identificou.** Só faz sentido no PWA (limpa o cache do service worker). Este app é nativo e não tem cache de navegador, então a função não existe aqui e não foi para Mais |
| Engrenagem (Configurações) | Mais › Configurações |

## 5. Componentes do kit (`lib/ui/kit.dart`)

| Componente | Uso |
|---|---|
| `AppHeader(title, subtitle, onBack, actions, titleWidget, bottom)` | Topo navy: título 17 semibold, subtítulo, voltar e botões. `bottom` entra dentro do navy (busca) |
| `HeaderButton(icon:, onTap:, badge:, tooltip:, spinning:)` e `HeaderButton.text(label, onTap:, spinning:)` | Botão do topo: quadrado translúcido de 36 px (toque de 44), com contador magenta opcional |
| `MainTabBar(current:, onTap:, badges:)` e `enum MainTab { mesas, balcao, caixa, mais }` | Menu inferior com ícone e nome; aba ativa em magenta |
| `Btn(label, kind:, onTap:, loading:, dense:, icon:)` | Botão de raio 14 e altura 46. Cores: `BtnKind.magenta`, `BtnKind.navy`, `BtnKind.green`, `BtnKind.orange`, `BtnKind.secondary`, mais `danger` e `dangerSoft`. Os nomes antigos (`primary`, `accent`, `success`, `warn`, `outline`) continuam valendo |
| `CountBtn(count:, icon:, label:, total:, onTap:, loading:, kind:)` | Botão com contador e total: `[2] Revisar pedido R$ 34,00`. Sem `count`, o selo some (`Receber R$ 23,00`); `icon` entra no lugar dele (`➤ Enviar para cozinha R$ 92,00`). O nome quebra em 2 linhas em tela estreita |
| `BottomBar.trio(a, b, c)` / `BottomBar.duo(secundario, principal)` / `BottomBar(children:, flex:)` | Barra de ações inferior fixa: branca, borda superior, botões de 46 px. Trio = larguras iguais; duo = 1 parte e 2 partes. Vai no `bottomNavigationBar` do `Scaffold` |
| `BtnRow(left, right)` | Dois botões de largura igual (rodapé de janela) |
| `QtyStepper(value:, onMinus:, onPlus:, size:)` | Contador −/+: 32 px, "+" magenta cheio, "−" contorno magenta. `Stepper2` é o nome antigo |
| `showSheet<R>(context, builder, dismissible:)` | Janela por baixo: cantos de 22 px, fundo escurecido, sobe com o teclado |
| `SheetBody(title:, subtitle:, children:, footer:, padding:, closable:, trailing:, top:, fill:, footerLine:)` | Corpo da janela: alça, título, subtítulo e ✕ (só quando a janela pode ser fechada). `top` é uma faixa fixa sob o título (abas); `fill` faz o conteúdo ocupar a altura da janela; `footerLine` põe a linha acima do rodapé |
| `confirm(context, title:, message:, confirmLabel:, cancelLabel:, danger:)` | Confirmação simples |
| `toast(context, message, error:)` | Aviso: faixa escura acima da barra inferior, some em 2 s (erro: vermelha, 4 s) |
| `CardBox(child:, padding:, color:)` | Cartão branco de raio 16 |
| `HeroCard(child:, padding:)` | Destaque navy de raio 18 |
| `SectionLabel(text, trailing:)` | Rótulo de seção: 10,5 px, maiúsculas, espaçado |
| `Tag(text, bg:, fg:)` e `CountBadge(count)` | Etiqueta rosa de contagem e contador magenta |
| `MenuRow(icon:, label:, trailing:, onTap:, last:)` | Linha de lista com ícone e nome |
| `FilterPill(label:, count:, dot:, selected:, onTap:)` | Chip de filtro com bolinha e contagem |
| `Field`, `MoneyField`, `fieldDecoration` | Campos com rótulo de seção e contorno de 1,5 px |
| `T.num(size, w:, c:)` e `tabularFigures` (em `theme.dart`) | Valores com algarismos tabulares |
| `ProductThumb(url:, name:, color:, size:)` (em `order_widgets.dart`) | Foto do produto; sem foto, quadrado com as iniciais |
| `CartLine(item:, cart:, last:, enabled:)` (em `order_widgets.dart`) | Linha do carrinho: nome, escolhas e observação, −/+ (ou peso com ✕) e valor |
| `ItemStatusTag(status)` e `itemStatusLabel(status)` (em `order_widgets.dart`) | Status do item já lançado (Aguardando, Preparando, Pronto, Entregue, Cancelado) |
| `StoreRebuild` (mixin, em `order_widgets.dart`) | `store.addListener(rebuild)`: redesenha a tela mesmo quando o store avisa no meio da montagem de outra tela |

## 6. O que ficou diferente do plano, e por quê

1. **Cor de "ociosa".** O plano pede azul `#2563eb`. O app (e o PWA) pinta
   ociosa de **âmbar** e **reservada de azul**. No vídeo do app atual não
   aparece nenhuma mesa azul: só verde (livre), vermelho (ocupada) e laranja
   (fechando). Como o vídeo não mostra "Ociosa" em azul, ficaram as cores que
   o app já usava (ociosa âmbar com texto escuro, reservada azul). Trocar é
   mudar uma constante em `lib/ui/table_status.dart`, mas aí ociosa e
   reservada ficariam da mesma cor.
2. **Chips "Ocupadas" e "Ociosas" são grupos separados**, como no protótipo:
   a mesa ociosa conta em "Ociosas" e sai de "Ocupadas", acompanhando a cor do
   card. Antes não havia chip "Ociosas" e a ociosa aparecia em "Ocupadas".
3. **Número do sino.** Conta chamados e pedidos do tablet aguardando
   liberação, como no PWA. O protótipo mostra no sino a quantidade de itens de
   estoque crítico; aqui o estoque crítico aparece na lista, mas não soma no
   número, porque o garçom não tem como "atender" estoque.
4. **Cartão navy do Caixa só com status e data.** O sistema não tem um total
   único de caixa (o esperado vem por forma de pagamento), e o plano manda não
   criar cálculo novo.
5. **Subtítulo do mapa** é "Garçom {nome}", sem salão: o usuário do app não
   tem salão.
6. **Ler QR da comanda sem câmera** (código digitado) e **sem WebSocket**
   (sino por polling de 30 s): regras da Stone para app embarcado.
7. **Mesa reservada sem atendimento** mostra a palavra "reservada" no lugar de
   "livre". O protótipo não tem esse estado; sem a palavra o card azul ficaria
   vazio.
8. **Aviso de erro** dura 4 s e é vermelho (o aviso normal dura 2 s): mensagem
   de falha de pagamento ou de rede precisa de tempo para ser lida.
9. **Fonte:** a do sistema. As fontes do protótipo não foram embarcadas.

## 7. Card de mesa: tamanho fixo

- A grade é um `GridView` de 4 colunas com `childAspectRatio` fixo
  (`tableCardAspect` em `lib/ui/table_card.dart`): toda célula tem a mesma
  largura e a mesma altura, calculadas só pela largura da tela.
- Dentro do card tudo é sobreposto (`Stack` com `Positioned`): nenhum texto ou
  selo consegue aumentar o card. Textos de uma linha com reticências; o valor
  da conta encolhe (`FittedBox`) em vez de cortar.
- Os tamanhos de letra acompanham a largura do card, então o desenho se mantém
  em telas de 320 a 430 px.
- O status por extenso fica nos chips de filtro e no rótulo de acessibilidade
  do card ("Mesa 5, fechando, Wanderson, R$ 108,90").
- Testes: `test/tables_map_test.dart`.

## 8. Cardápio, montagem e revisão (fase 3 do plano)

### 8.1 Fluxo e quem chama

```
Mapa ──(mesa livre)──> openTableMenu(freeTableDraft(mesa))
                          Cardápio ──> Revisar pedido ──> "Pedido na cozinha!"
Mesa aberta ──(+ Itens)──> openTableMenu(sessionDraft(sessionId:, title:))
Aba Balcão ──> CounterScreen ──> Cardápio (canal pos) ──> Venda de balcão ──> recebimento atual
```

- **`TableOrderDraft`** (`lib/stores/order_draft.dart`) é o pedido em montagem
  de uma mesa: o carrinho (`draft.cart`, um `OrderCart`) e, para mesa livre,
  pessoas, cliente e comandas. Quem abre o fluxo cria e descarta o rascunho:
  `freeTableDraft(DiningTable)` para mesa livre, `sessionDraft(sessionId:,
  title:)` para mesa aberta (ambos em `menu_screen.dart`).
- **`Future<OrderFlowResult> openTableMenu(BuildContext, TableOrderDraft)`**
  abre o Cardápio e, dele, a Revisão. Devolve `OrderFlowResult(exit,
  sessionId:, notice:)`:

| `exit` | O que aconteceu | O que quem chamou faz |
|---|---|---|
| `canceled` | Cancelou ou voltou. O carrinho foi descartado | Nada (o mapa atualiza as mesas) |
| `bill` | Tocou em "Conta" no topo do cardápio. O carrinho CONTINUA no rascunho | Mostra a mesa aberta |
| `tables` | Enviou e escolheu "Voltar às mesas" | Volta ao mapa |
| `stay` | Enviou e escolheu "Ficar na mesa" | Abre (ou continua em) a mesa aberta com `sessionId` |

  `notice` vem preenchido quando o pedido foi gravado mas não saiu na
  produção (`kitchen_sent == false`): a tela da mesa deve manter o aviso.
  `sessionId` existe sempre que a mesa está aberta no servidor (inclusive em
  `canceled`, se a mesa abriu e o envio falhou).
- **`MenuScreen(cart:, title:, subtitle:, channel:, actions:, banner:,
  blockedText:, primaryLabel:, onPrimary:, onCancel:)`** é a tela do cardápio
  em si, sem fluxo: `TableMenuScreen(draft:)` e `CounterScreen` montam nela.
- **`ReviewScreen(draft:)`** fecha com `null` ("+ Itens" ou voltar) ou com o
  `OrderFlowResult` do envio. Quem usa `openTableMenu` não precisa abri-la.
- **`CounterSaleScreen(cart:, onReceive:)`**: "Venda de balcão". `onReceive`
  abre o recebimento e devolve `true` quando a venda foi registrada (a tela
  fecha sozinha). A fase 4 troca só o que `CounterScreen._checkout` abre.

### 8.2 Regras que continuam as mesmas

- Preço, mínimo e máximo de adicionais, sabores, combo e peso: `ProductBuilder`
  (`lib/core/product_builder.dart`) é a lógica da tela antiga do produto, sem
  alteração de regra, e usa `addon_rules.dart`.
- Chave de idempotência: `OrderCart.key`. Só troca quando o envio é
  confirmado (`commit`) ou o pedido é descartado (`discard`). Reenviar depois
  de timeout usa a mesma chave.
- Mesa livre: `TableOrderDraft.submit` chama `TablesStore.open` uma única vez.
  Se o envio do pedido falhar, a sessão criada fica em `draft.sessionId` e a
  nova tentativa manda só o pedido. Mesa nova com comandas: depois de abrir, o
  rótulo escolhido é resolvido para o id lendo `GET /sessions/{id}`.
- Continuam: via impressa do pedido (se ligada em Configurações; o erro da
  impressora aparece na janela "Pedido na cozinha!"), aviso de produção
  (`kitchen_sent == false`), aviso "Sem conexão", item indisponível
  bloqueando o envio, balcão desabilitado ou sem permissão, e a trava de
  "há pagamento já cobrado na maquininha" no balcão (`OrderCart.lockReason`).

### 8.3 O que ficou diferente do plano ou do protótipo, e por quê

1. **Pessoas na mesa começa em 0, não em 2.** Zero é "não informado" e não
   manda `guest_count`, como o campo vazio do formulário antigo. O protótipo
   começa em 2; isso gravaria 2 pessoas em toda mesa que o garçom não
   conferisse. Para mudar: valor inicial de `TableOrderDraft.guestCount`.
2. **Mesa já aberta: pessoas só leitura.** Não existe rotina para alterar o
   número de pessoas depois de abrir a mesa. O cliente continua editável
   (`SessionStore.updateCustomer`).
3. **Sem descrição do produto.** O cardápio (`GET /menu`) não manda descrição.
   A linha de apoio mostra só o que existe: "Pizza · até N sabores", "Combo"
   ou "Vendido por kg". Produto simples fica com nome e preço.
4. **Categorias: ordem do cadastro lida coluna a coluna** (1ª em cima, 2ª
   embaixo, 3ª ao lado), como no protótipo, para a faixa rolar de lado sem
   embaralhar. Até 4 categorias, uma linha só. Blocos de 44 px de altura
   (protótipo: 40) pela regra de toque mínimo.
5. **Subcategorias viram seções** dentro da categoria raiz (o protótipo não
   tem hierarquia).
6. **Aba dos adicionais leva o nome do grupo** quando há um grupo só
   ("Borda"); com vários grupos chama "Adicionais" e cada grupo é uma seção.
   Combo: "Opções → Resumo". O contador verde aparece em toda aba com escolha.
7. **Grupo com mais de 6 opções tem busca** ("Buscar sabor..."), como na tela
   antiga. O protótipo não tem.
8. **"Total do item" de pizza sem sabor** mostra "a partir de R$ x" (o preço
   vem dos sabores).
9. **"Pedido na cozinha!" sem o nome das impressoras**: o app não sabe onde a
   cozinha imprimiu. Com `kitchen_sent == false` o título vira "Pedido
   gravado" e o aviso de produção aparece na janela.
10. **Toque no nome de produto simples** abre quantidade e observação e também
    os adicionais OPCIONAIS do produto, se houver (antes ficavam na tela
    cheia).
11. **Quem pode abrir mesa mas não pode lançar pedido** continua abrindo a
    mesa vazia pelo formulário antigo ("Abrir mesa"): o cardápio não serviria
    para nada.
12. **Mesa aberta provisória.** A `SessionScreen` perdeu o cardápio embutido e
    ganhou o botão "+ Itens" e o resumo da conta. O desenho novo (5.5) é da
    fase 4.
13. **Balcão: "Receber" abre a janela atual** de recebimento; com pagamento já
    cobrado, o botão vira "Concluir recebimento" e os itens ficam travados.

