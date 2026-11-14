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
| 4 | Mesa aberta e receber conta (5.5, 5.6) | Feita (frente 3). Ver a seção 9 |
| 5 | Balcão, Caixa, Mais e Notificações (5.7 a 5.9) | Feita: Caixa, Mais e Notificações (frente 1), cardápio e "Venda de balcão" (frente 2), "Receber venda" e "Venda recebida" (frente 3) |
| 6 | Revisão final com o roteiro da seção 10 | Roteiro feito na prévia web (390 × 844) contra o servidor falso; a lista de aceite está na seção 10. **Falta repetir numa loja de teste, na maquininha** (pagamento real, impressão, câmera) |

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
| `lib/ui/sheets/comanda_link_sheet.dart` | Ler QR da comanda: câmera (`Native.scanQr`) ou código digitado |
| `lib/ui/sheets/store_switch_sheet.dart` | Trocar loja |
| `lib/ui/screens/settings_screen.dart` | Configurações do aparelho (inclui "Fale conosco" e pagamentos pendentes) |
| `lib/stores/notifications.dart` | Estado do sino |
| `lib/stores/comanda_link.dart` | Consulta e vínculo de comanda |
| `lib/ui/screens/menu_screen.dart` | Cardápio (5.2): `MenuScreen` (a tela, usada por mesa e balcão), `TableMenuScreen` e `openTableMenu` (fluxo da mesa), `OrderFlowResult` |
| `lib/ui/sheets/product_sheet.dart` | Janelas do produto: montagem em abas (5.3) e quantidade/observação/peso. `showProductSheet` |
| `lib/ui/screens/review_screen.dart` | Revisar pedido (5.4) e a janela "Pedido na cozinha!" |
| `lib/ui/screens/counter_screen.dart` | Balcão (5.7): `CounterScreen` (aba Balcão) e `CounterSaleScreen` ("Venda de balcão"). "Receber" abre `ReceiveScreen.counter` |
| `lib/ui/order_widgets.dart` | Peças do pedido: `ProductThumb`, `CartLine`, `ItemStatusTag`, textos que citam a mesa, `StoreRebuild` |
| `lib/core/product_builder.dart` | `ProductBuilder`: as regras da tela antiga do produto (sabores, combo, adicionais, peso, bloqueios), sem tela |
| `lib/stores/order_draft.dart` | `OrderCart` (carrinho e chave de idempotência) e `TableOrderDraft` (pedido de uma mesa; abre a mesa livre ao enviar) |
| `lib/ui/screens/session_screen.dart` | Mesa aberta (5.5): total, grade de opções, itens com "Transferir" e "Cancelar", "Cancelar mesa" e a barra de 3 botões |
| `lib/ui/screens/receive_screen.dart` | Receber conta / Receber venda (5.6) e as telas "Conta paga" / "Venda recebida". `ReceiveScreen.table()`, `.comanda(comanda:)`, `.counter(counter:)` |
| `lib/stores/receive.dart` | As regras do recebimento, sem tela: `TableReceiveController` (mesa e comanda) e `CounterReceiveController` (balcão) |
| `lib/ui/sheets/pix_sheet.dart` | Janela do Pix online (QR do servidor), aberta pela tela de recebimento |
| `lib/ui/sheets/tablet_code_sheet.dart` | "Gerar QR do tablet na mesa": código de 6 dígitos e QR |
| `lib/ui/sheets/session_sheets.dart`, `items_sheet.dart`, `comandas_sheet.dart` | Janelas da mesa, as mesmas de antes: conta parcial, couvert, transferir mesa, cancelar mesa, cancelar item, transferir/atribuir item e comandas |
| `lib/core/native.dart`, `android/.../MainActivity.kt`, `QrCaptureActivity.kt` | Canal nativo: além do que já fazia, `scanQr` (leitor de QR pela câmera) e `qrPng` (imagem de QR), os dois com ZXing. Ver `docs/stone.md` |
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
| Pedir conta | "Opções da mesa" (`TableOptionsSheet`, removida) e botão do topo da mesa | `SessionStore.requestBill` → `POST /tables/{id}/sessions/current/bill`; conta impressa com `SessionStore.fetchReceipt` → `GET /sessions/{id}/receipt` | Feito: botão navy da barra (`_SessionScreenState._requestBill`). Depois volta ao mapa com o aviso |
| Gerar QR do tablet na mesa | **Não existia neste app** (no PWA: `TabletCodeModal.vue`) | `SessionStore.generateTabletCode` → `POST /sessions/{id}/tablet-code`; a imagem do QR vem de `Native.qrPng` | Feito. Função trazida do PWA com a mesma rota: `TabletCodeSheet` |
| Ver conta parcial | "Opções da mesa" › `PartialBillSheet` | Lê `SessionStore.session.bill` (de `GET /sessions/{id}`); imprimir usa `GET /sessions/{id}/receipt` | Feito: opção da grade, mesma janela (com o "Imprimir" dentro dela) |
| Lançar couvert | "Opções da mesa" › `CouvertSheet` | `SessionStore.setCouvert` → `POST /sessions/{id}/couvert`; `removeCouvert` → `DELETE /sessions/{id}/couvert`; por comanda: `setComandaCouvert`, `removeComandaCouvert` → `DELETE /comandas/{id}/couvert` | Feito: opção da grade, mesma janela |
| Comandas da mesa | "Opções da mesa" › `ComandasSheet` (`sheets/comandas_sheet.dart`) | `SessionStore.loadComandas` → `GET /sessions/{id}/comandas`; `attachComanda` → `POST /sessions/{id}/comandas`; `renameComanda` → `PATCH /comandas/{id}`; `removeComanda` → `DELETE /comandas/{id}`; `requestComandaBill` → `POST /comandas/{id}/bill`; `payComanda` → `POST /comandas/{id}/payments`; `transferComanda`; `cancelComandaItems`; taxa: `removeComandaFee`, `reapplyComandaFee` | Feito: opção da grade, mesma janela. O "Receber" de cada comanda abre `ReceiveScreen.comanda` |
| Transferir mesa | "Opções da mesa" › `TransferTableSheet` | `SessionStore.transferTable` → `POST /sessions/{id}/transfer` | Feito: opção da grade, mesma janela |
| Transferir item | "Opções da mesa" e "Itens da comanda" (`SessionItemsScreen`, removida; `TransferItemSheet` em `sheets/items_sheet.dart`) | `SessionStore.transferItems` → `POST /items/{id}/transfer` (um item) ou `POST /sessions/{id}/items/transfer` (vários) | Feito: link "Transferir" em cada item e opção da grade (com vários itens, mostra a lista e pede para escolher). Mesma janela |
| Cancelar item | "Itens da comanda" › `CancelItemSheet` | `SessionStore.cancelItem` → `DELETE /items/{id}` com motivo (e liberação do gerente quando exigida) | Feito: link "Cancelar" em cada item, mesma janela |
| Cancelar mesa | "Opções da mesa" › `CancelSessionSheet` | `SessionStore.cancelSession` → `POST /sessions/{id}/cancel` | Feito: botão de texto vermelho no fim da lista, mesma janela (com a senha quando a loja exige) |
| Receber (mesa e balcão) | Mesa: `ReceiveSheet` e `PixSheet` (`sheets/receive_sheet.dart`). Balcão: folha de recebimento da `CounterScreen` | Mesa: `SessionStore.payTable` → `POST /sessions/{id}/payments`; comanda: `payComanda`; Pix online: `generateTablePix` → `POST /sessions/{id}/pix`; fechar: `closeSession` → `POST /sessions/{id}/close`. Cartão e Pix na maquininha: `TefLedger.chargeAndRecord` (`lib/stores/payments.dart`, deeplink da Stone). Formas: `PaymentMethodsStore.load` → `GET /payment-methods`. Balcão: `TefLedger.chargeOnly` + `CounterStore.checkout` | Feito: tela `ReceiveScreen` (regras em `lib/stores/receive.dart`). As janelas `ReceiveSheet` e `_CheckoutSheet` foram removidas; a do Pix (`PixSheet`) continua |
| Venda de balcão | Ícone do carrinho no topo do mapa → `CounterScreen` | `CounterStore.fetchContext` → `GET /counter/context`; `CounterStore.checkout` → `POST /counter/checkout` | Feito: a aba "Balcão" abre o mesmo Cardápio (canal `pos`), a tela "Venda de balcão", "Receber venda" e "Venda recebida" |
| Abrir / fechar caixa, suprimento, sangria, detalhes | Ícone da carteira no topo do mapa → `CashScreen` | `CashStore.load` → `GET /cash`; `open` → `POST /cash/open`; `movement` → `POST /cash/sessions/{id}/movements`; `fetchSummary` → `GET /cash/sessions/{id}/summary`; `close` → `POST /cash/sessions/{id}/close`. Impressão do fechamento: `printCashClose` | Feito (aba "Caixa") |
| Notificações | **Não existia neste app** (no PWA: sino → `NotificationCenter.vue`) | `NotificationsStore.fetch` → `GET /tablet/calls`; `acknowledge` → `POST /tablet/calls/{id}/ack`; `resolve` → `POST /tablet/calls/{id}/resolve`; `approveOrder` → `POST /tablet/orders/{id}/approve` | Feito. Função trazida do PWA com as mesmas rotas, por polling de 30 s |
| Ler QR da comanda | **Não existia neste app** (no PWA: ícone do scanner → `ComandaScanModal.vue`) | `ComandaLinkStore.lookup` → `POST /tablet/comandas/lookup`; `link` → `POST /tablet/comandas/link` | Feito, **com câmera**: botão "Ler com a câmera" (`Native.scanQr`, ZXing, sem Google Play Services) e, como alternativa, o código digitado. O conteúdo lido vai inteiro para o servidor, como no PWA (`comandaCodeFromQr`) |
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
| `QtyStepper(value:, onMinus:, onPlus:, size:)` | Contador −/+: 32 px, "+" magenta cheio, "−" contorno magenta |
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
6. **Sem WebSocket** (sino por polling de 30 s): regra da Stone para app
   embarcado. O "Ler QR da comanda" nasceu sem câmera na frente 1 e ganhou a
   câmera na frente 3 (a Stone proíbe Google Play Services, não a câmera).
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
Aba Balcão ──> CounterScreen ──> Cardápio (canal pos) ──> Venda de balcão ──> Receber venda ──> Venda recebida
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
  abre "Receber venda" (`ReceiveScreen.counter`) e devolve `true` quando a
  venda foi registrada e o operador pediu uma nova venda (a tela fecha
  sozinha).

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
12. **Mesa aberta**: era provisória nesta fase; o desenho novo está na seção 9.
13. **Balcão: com pagamento já cobrado**, o botão "Receber" vira "Concluir
    recebimento" e os itens ficam travados (a tela de recebimento é a da
    seção 9).


## 9. Mesa aberta e recebimento (fase 4 do plano)

### 9.1 Fluxo e quem chama

```
Mapa ──(mesa com atendimento)──> SessionScreen (Mesa aberta)
   + Itens ───────> openTableMenu(sessionDraft)                       (seção 8)
   Pedir conta ───> SessionStore.requestBill ──> imprime ──> volta ao mapa com o aviso
   Receber conta ─> ReceiveScreen.table() ──> "Conta paga" ──> volta ao mapa
        (mesa com comandas: abre "Comandas da mesa"; o "Receber" de cada
         comanda abre ReceiveScreen.comanda(comanda:))
Venda de balcão ──(Receber)──> ReceiveScreen.counter(...) ──> "Venda recebida" ──> nova venda
```

- **`SessionScreen`** guarda o `sessionDraft` da mesa (o carrinho sobrevive à
  ida e volta pelo botão "Conta" do cardápio) e chama, em cada opção, a mesma
  janela e a mesma rotina de antes. As janelas são as de
  `lib/ui/sheets/session_sheets.dart`, `items_sheet.dart` e
  `comandas_sheet.dart`, sem mudança de regra.
- **Onde foram as 9 opções do antigo menu "Opções da mesa":**

| Opção de hoje | Onde está | Quando fica apagada (e avisa ao toque) |
|---|---|---|
| Pedir conta | Barra, botão navy | Sem `request_bill`; mesa já fechando; mesa sem itens |
| Gerar QR do tablet na mesa | Grade | Sem `open_session`; mesa fechando (regra do PWA) |
| Ver conta parcial | Grade | Nunca |
| Lançar couvert | Grade | Sem `couvert_add`; mesa fechando |
| Receber conta | Barra, botão magenta | Sem `process_payment`; mesa sem itens; conta já quitada. Mesa com comandas: precisa de `manage_comanda` e abre "Comandas da mesa" |
| Comandas da mesa | Grade | Sem `manage_comanda`; loja sem comandas (e mesa sem comanda) |
| Transferir mesa | Grade | Sem `transfer_table` |
| Transferir item | Grade e link em cada item | Sem `transfer_item`; mesa sem itens. O link do item some quando o item não pode ser transferido |
| Cancelar mesa | Texto vermelho no fim da lista | Sem `cancel_session` |

  Antes, opção sem permissão sumia do menu. Agora ela continua no lugar,
  apagada, e o toque explica o motivo: assim a grade e a barra não mudam de
  forma. "+ Itens" (verde) completa a barra e segue a mesma regra (sem
  `create_order` ou com a mesa fechando).
- **O que não é opção e continua existindo:** "Imprimir conta" (dentro de
  "Ver conta parcial"), "Reabrir mesa" (texto na faixa "Conta solicitada.
  Aguardando pagamento."), "Fechar mesa" (botão na faixa "Conta quitada.
  Aguardando fechamento da mesa." e na tela "Conta paga"), pedidos do tablet
  com "Liberar para a cozinha" e o bloco "itens sem comanda" com "Atribuir".
- **`ReceiveScreen`** só desenha. As regras estão em `lib/stores/receive.dart`:
  - `TableReceiveController(kind: 'session' | 'comanda', ...)`: valida (valor,
    restante, valor recebido do dinheiro), cobra na maquininha por
    `TefLedger.chargeAndRecord`, registra por `SessionStore.payTable` /
    `payComanda` e devolve um `ReceiveOutcome` (`failed`, `partial`, `done`,
    `pix`, `unconfirmed`). O total, o pago e o restante são sempre os do
    servidor (`bill` da mesa ou a comanda de `GET /sessions/{id}/comandas`).
  - `CounterReceiveController`: as partes ficam no aparelho (cartão é cobrado
    na hora por `TefLedger.chargeOnly`) e a venda só é gravada quando elas
    cobrem o total (`CounterStore.checkout`, com a chave do carrinho).
  - São o código das antigas janelas `ReceiveSheet` e `_CheckoutSheet`,
    mudado de lugar: mesmas validações, mesmas mensagens, mesmas rotas.
- **Ícone da forma de pagamento**: `paymentIcon` (em `receive_screen.dart`),
  pelo método canônico (`cash`, `pix`, `debit_card`, `credit_card`, `voucher`,
  `courtesy`, `credit_account`, o resto como "outro").

### 9.2 O que continua igual (e o plano não cita)

- Cartão, Pix e voucher cobrados na maquininha, com a tela "Aguardando a
  maquininha…" e o botão "Voltei e nada aconteceu"; pendências em
  Configurações › Pagamentos pendentes; aviso "Cobrado, mas não registrado" /
  "Sem resposta da maquininha" (depois dele a tela volta para a mesa).
- Pix online com QR do servidor (`PixSheet`): sempre no valor restante.
- Dinheiro com "Valor recebido" e troco (mesa e comanda); no balcão o troco é
  o que passa do total, como antes.
- Pagamento parcial; fechamento automático da mesa pelo servidor; "Fechar
  mesa" para conta quitada com a mesa ainda aberta.
- Impressão: conta ao pedir a conta e na conta parcial, comprovante depois de
  receber ("Imprimir comprovante" na tela "Conta paga", quando a impressão de
  conta está ligada), venda de balcão ao concluir.
- Avisos "Sem conexão", senha de gerente para cancelar mesa e transferir
  item, mesa com comandas e itens sem comanda.

### 9.3 O que ficou diferente do plano, do protótipo ou do app de antes, e por quê

1. **"Pedir conta" em mesa com comandas continua pedindo a conta da MESA**,
   como o app e o PWA fazem hoje (`requestBill` não olha comandas). Só o
   "Receber conta" leva a "Comandas da mesa", porque o recebimento é por
   comanda. Mandar o "Pedir conta" também para as comandas tiraria uma ação
   que existe hoje. Para mudar: em `_SessionScreenState._requestBill`,
   chamar `_openComandas()` quando `s.hasComandas`.
2. **Total da mesa mostra o que o servidor devolve**, não "itens + 10%": as
   parcelas são Itens, Couvert, Desconto, Taxa de serviço com o percentual
   real e, havendo pagamento, Pago e Restante. Nada é somado no app.
3. **"Lançar couvert" tem nome fixo.** O menu antigo trocava para "Couvert
   (alterar pessoas)" quando já havia couvert; a janela mostra o que está
   lançado.
4. **A hora do lançamento de cada item saiu da lista** (a tela "Itens da
   comanda" mostrava; o plano e o protótipo não têm). O nome da comanda do
   item continua.
5. **"Transferir item" da grade**: com um item só abre a janela de destino;
   com vários, rola até a lista, realça e pede para tocar em "Transferir" no
   item.
6. **Pagamentos já feitos no resumo**: a mesa lista "Pagamento N · forma"
   lendo os pagamentos do mesmo payload da conta impressa
   (`GET /sessions/{id}/receipt`), só quando a soma fecha com o "pago" do
   servidor; senão (e sempre na comanda) aparece a linha única "Pago".
7. **Pix online não tem campo "Valor"**: é sempre o restante inteiro, como
   antes. O botão vira "Gerar Pix de R$ x".
8. **Botão da barra**: "Receber R$ x em {forma}"; "Cobrar R$ x em {forma}"
   quando a forma abre a maquininha; "Registrar venda R$ x" no balcão quando
   as partes já cobrem o total.
9. **Balcão: o botão principal lança a parte.** Antes havia um botão extra
   "+ Adicionar como parcial"; agora valor menor que o restante lança a
   parte e fica na tela, e o valor que cobre o total grava a venda. A parte
   não cobrada pode ser retirada no ✕ do resumo.
10. **Balcão ganhou o "Voltei e nada aconteceu"** (a janela antiga ficava só
    com "Aguardando a maquininha…"). É a mesma saída que a mesa já tinha.
11. **"Valor recebido" acompanha o "Valor"** enquanto o operador não mexe
    nele (antes ficava parado no restante e gerava troco falso num parcial).
12. **Aviso de cobrança pendente na tela de recebimento**: se a maquininha
    cobrou e o registro ainda não entrou, a tela avisa para não cobrar de
    novo (antes só aparecia em Configurações).
13. **"Conta paga" de comanda** volta para "Comandas da mesa" enquanto a mesa
    tiver outra comanda aberta; quando a mesa encerra, "Voltar às mesas".
14. **Cliente (opcional)** só existe no balcão, como antes. Na mesa o nome do
    cliente é o do topo da mesa aberta.
15. **Ler QR da comanda**: o campo de digitar deixou de abrir o teclado
    sozinho, para o botão "Ler com a câmera" ficar à vista.
16. **Janelas da mesa** (couvert, transferir, comandas, cancelar) mantêm o
    miolo de antes, dentro da janela nova (alça, título, ✕).

## 10. Lista de aceite (seções 5.1 a 5.9 do plano)

Como foi verificado: **T** = teste automático (`flutter test`, 131 testes);
**P** = roteiro da seção 10 do plano feito na prévia web em 390 × 844 contra
o servidor falso (`tool/mock-server.mjs`), comparando com o protótipo;
**N** = não verificado (precisa de loja de teste ou do aparelho).

### 5.1 Mapa de mesas
- [x] 24 mesas visíveis sem rolar em 390 × 844. T (`tables_map_test`), P.
- [ ] Cores de status iguais às de hoje, **incluindo ociosa em azul**. As
      cores são as de hoje (T), mas ociosa é âmbar e reservada é azul: ver a
      seção 6, item 1. Decisão pendente do gestor.
- [x] Digitar "12" e tocar Entrar abre a mesa 12. T (`app_flow_test`,
      `tables_map_test`), P.
- [x] Nenhum ícone sem nome no topo além do sino. T, P.

### 5.2 Cardápio
- [x] 2 latas = 2 toques no "+", sem abrir outra tela. T (`order_flow_test`), P.
- [x] Observação vai no pedido. T (payload `notes`), P (via impressa em modo
      demonstração). **N:** chegada na cozinha real.
- [x] "Pedir conta" não aparece nesta tela. T.

### 5.3 Montagem de pizza
- [x] Mesmas regras de mínimo e máximo do cadastro. T (`ProductBuilder`), P.
- [x] Item vai com sabores, borda e observação. T (payload), P. **N:**
      cozinha real.

### 5.4 Revisar pedido
- [x] Mesa nova grava pessoas, cliente e comandas pela mesma rota do
      formulário "Abrir mesa". T (`POST /tables/{id}/sessions`), P.
- [x] Envio pela mesma rotina de "Enviar para a cozinha". T
      (`POST /sessions/{id}/orders`, mesma chave de idempotência no reenvio), P.

### 5.5 Mesa aberta
- [x] As 9 opções de hoje estão na tela (Pedir conta, Gerar QR do tablet na
      mesa, Ver conta parcial, Lançar couvert, Receber conta, Comandas da
      mesa, Transferir mesa, Transferir item, Cancelar mesa). T
      (`session_receive_test`), P.
- [x] Nenhuma opção nova. T (grade com exatamente 6, barra com exatamente 3,
      mais "Cancelar mesa"), P.
- [x] Total da mesa e parcelas do servidor; itens com status, valor,
      "Transferir" e "Cancelar" (mesmas janelas). T, P (transferir 1 de 2
      para a mesa 8, cancelar com motivo, couvert, QR do tablet).
- [x] Pedir conta: mesma ação, mesa fica laranja e o app volta ao mapa com
      o aviso. T, P.
- [x] Opção sem permissão fica apagada e explica ao toque. T.
- [ ] **N:** senha de gerente exigida pela loja (o servidor falso não exige),
      QR do tablet lido por um tablet de verdade, impressão da conta no papel.

### 5.6 Receber conta / Receber venda
- [x] Pagamento pela mesma rotina de "Receber". T (rotas e corpos de
      `POST /sessions/{id}/payments`, `/comandas/{id}/payments` e
      `/counter/checkout`), P.
- [x] Formas vindas do cadastro da loja. T, P.
- [x] Valor menor que o restante registra e continua na tela com o novo
      restante; o total leva a "Conta paga". T, P (Pix parcial e dinheiro no
      restante, com troco).
- [x] Cartão na maquininha pelo `TefLedger`, com os campos de TEF; recusa e
      "sem resposta". T (canal nativo simulado). **N:** maquininha real.
- [x] Dinheiro exige o valor recebido. T.
- [ ] **N:** o pagamento "aparece no caixa como hoje" num backend real (no
      servidor falso o caixa somou as vendas); Pix online com provedor real.

### 5.7 Balcão
- [x] Aba Balcão abre o mesmo cardápio, com "Balcão" e "Venda de balcão ·
      {loja}"; barra "Cancelar" e "Ver venda". T, P.
- [x] "Venda de balcão" com −/+ e total; "+ Itens" e "Receber R$" levando a
      "Receber venda" (sem taxa) e "Venda recebida". T, P (débito; duas
      formas; dinheiro com troco).
- [x] Loja sem balcão mostra a mensagem atual. T.

### 5.8 Caixa
- [x] Caixa fechado: abrir com valor inicial. T (tela), P (R$ 200,00).
- [x] Caixa aberto: 4 blocos, Suprimento, Sangria, Ver detalhes, Fechar
      caixa. P (suprimento de R$ 50,00, sangria de R$ 30,00, detalhes, resumo
      do fechamento). O cartão navy tem só status e data (seção 6, item 4).
- [ ] **N:** confirmar o fechamento num backend real e a via impressa.

### 5.9 Mais e Notificações
- [x] Mais lista, nesta ordem: Notificações (com número), Ler QR da comanda,
      Atualizar, Trocar loja, Configurações (e Sair). T, P.
- [x] Notificações em cartão branco; voltar retorna de onde veio. T, P.
- [x] Trocar loja e voltar. P.
- [x] Ícone não identificado do topo antigo: listado na seção 4 ("↺" do PWA,
      sem equivalente no app nativo).
- [x] Ler QR da comanda com a câmera. T (canal nativo simulado: leu, voltou
      sem ler, sem câmera, permissão negada). **N:** câmera de verdade.
