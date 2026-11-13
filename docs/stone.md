# Mobiz POS na maquininha Stone

Como o app conversa com o terminal, como instalar na maquininha de
desenvolvimento e o que falta para homologar. As regras citadas vêm da
documentação pública da Stone (`sdkandroid.stone.com.br`), consultada em
13/11/2026 — **confira no Partner Hub antes de submeter**, porque ela muda e
tem pontos inconsistentes (anotados abaixo).

## 1. Modelo de integração: Deeplink

O app **não usa o SDK da Stone**. Ele abre os apps da própria Stone que já
vêm no terminal e recebe a resposta num deeplink de retorno. É o modelo que a
Stone recomenda e traz três vantagens aqui:

- não precisa do token do repositório privado (packagecloud) para compilar;
- o APK fica pequeno (o SDK e as libs por fabricante não entram);
- o comprovante do cartão é impresso pelo próprio app de pagamento.

| Operação | O app abre | A Stone responde em |
|---|---|---|
| Pagamento | `payment-app://pay?amount=<centavos>&transaction_type=…&editable_amount=0&return_scheme=mobizpos` | `mobizpos://pay-response?code=0&atk=…&authorization_code=…` |
| Estorno | `cancel-app://cancel?atk=…&amount=…` | `mobizpos://cancel?success=true…` |
| Impressão | `printer-app://print?SHOW_FEEDBACK_SCREEN=false&SCHEME_RETURN=mobizpos&PRINTABLE_CONTENT=[…]` | `mobizpos://print?…SUCCESS` |
| 2ª via | `reprinter-app://reprint?ATK=…&TYPE_CUSTOMER=CLIENT` | `mobizpos://reprint?…` |

Onde fica cada parte:

- `lib/stone/stone_deeplink.dart` — monta as URIs e lê as respostas (código
  puro, coberto por `test/stone_deeplink_test.dart`);
- `android/app/src/main/kotlin/.../MainActivity.kt` — dispara o `Intent` e
  recebe o retorno em `onNewIntent`;
- `android/app/src/main/AndroidManifest.xml` — um `intent-filter` por
  operação (`pay-response`, `cancel`, `print`, `reprint`) com o scheme
  `mobizpos`;
- `lib/stone/terminal.dart` — cobrança, estorno e impressão para o resto do app;
- `lib/stores/payments.dart` (`TefLedger`) — cobra **e** registra no Mobizweb.

### Pagamento: cobrar e registrar sem buraco no meio

1. O operador escolhe a forma (as do PDV da loja, `GET /payment-methods`).
   Crédito, débito, voucher e Pix vão para a maquininha; dinheiro e as demais
   são só registradas.
2. Antes de abrir o app da Stone, a cobrança é gravada no aparelho.
3. Aprovado (`code=0` **e** `atk` presente), o app registra em
   `POST /sessions/{id}/payments` ou `POST /comandas/{id}/payments` com
   `tef_provider: stone_deeplink`, `tef_transaction_id: <ATK>`,
   `tef_nsu: <authorization_code>` e uma `Idempotency-Key` fixa.
4. Só sai da lista local quando o servidor confirma. O servidor não duplica
   pagamento com o mesmo `tef_transaction_id`, então reenviar é seguro.

Casos tratados: servidor fora do ar depois do cartão aprovado (fica em
*Configurações › Pagamentos pendentes* e é reenviado quando a rede volta);
Android encerrou o app enquanto o da Stone estava aberto (a resposta é
conciliada na próxima abertura); operador voltou sem resposta (fica marcado
como "conferir no app da Stone", nunca some sozinho). Em qualquer pendência
dá para **registrar agora**, **estornar** ou **tirar 2ª via**.

Decisões e limites:

- **`order_id` não é enviado.** É numérico, precisa ser ligado em Ajustes do
  POS e, enviado com a função desligada, a Stone devolve erro. A conciliação
  é pelo ATK.
- **Parcelamento:** o app manda só o tipo `CREDIT`; à vista × parcelado é
  perguntado na tela da Stone.
- **Pix na maquininha** usa `transaction_type=PIX`. A FAQ da Stone diz que
  esse fluxo mudou e que a doc está desatualizada — **teste no terminal**; se
  não abrir o QR, cadastre a forma Pix da loja como "Pix online" (QR do
  servidor) ou desligue *Cobrar cartão e Pix na maquininha*.
- **Balcão:** a venda só é gravada depois de todas as partes cobradas. Se a
  venda for abandonada com cartão já cobrado, ele fica nos pendentes para
  estorno.

### Impressão

O que imprime (cada item liga/desliga em *Configurações › Impressão*):

| Documento | Quando | De onde vem o conteúdo |
|---|---|---|
| Conta da mesa | Ao pedir a conta, pela conta parcial e depois de receber | `GET /sessions/{id}/receipt` (mesmo builder do cupom da Bridge) |
| Conta da comanda | Ao pedir a conta da comanda | Itens da sessão + totais da comanda |
| Via do pedido | A cada envio para a cozinha | Carrinho enviado |
| Venda de balcão | Ao concluir a venda | Carrinho + retorno do checkout |
| Fechamento de caixa | Ao fechar o caixa | Valores contados + resumo |

Por padrão o documento vira **imagem** de 384 px (bobina de 58 mm), quebrada
em pedaços de até 560 px de altura sempre entre linhas, e é enviada em
chamadas pequenas e sequenciais — a Stone avisa que intent grande trava sem
erro e pede "uma imagem (ou poucas) por chamada". Se o terminal não imprimir
imagem, ligue **Imprimir como texto**.

Pontos a validar no terminal (a doc não fecha):

- a página de impressão diz que o recurso depende do **bundle 7.7.0** (outra
  página cita 7.4.5 e a FAQ fala em piloto). Veja a versão do bundle do seu
  terminal; use *Imprimir página de teste*;
- o nome do parâmetro de retorno da impressão não é documentado. O app
  procura o código (`SUCCESS`, `PRINTER_OUT_OF_PAPER`…) na URI inteira;
- no modo texto as colunas (32 normal / 48 pequeno) são o padrão de térmica
  58 mm, não um número da Stone;
- a Stone pede para não gerar relatório grande na impressora do POS: os
  layouts aqui são curtos de propósito.

O comprovante do **cartão** (via do cliente e do lojista) é do app de
pagamento da Stone, não deste app.

## 2. Instalação na maquininha de desenvolvimento

1. A maquininha de **debug** (marca d'água "debug"/"mockup") aceita `adb` por
   USB; a de produção tem a USB bloqueada.
2. **Gertec e Positivo** só aceitam, no terminal de debug, APK assinado com
   a JKS do fabricante que a Stone fornece (pastas no Drive linkadas nas
   páginas "Processo de build com dispositivos Gertec/Positivo"). A GPOS 730
   é Gertec ("série 7"). Sunmi, Tectoy e Ingenico usam a chave de debug comum.
3. No Windows, um comando faz tudo — acha a `.jks` e o arquivo de senhas em
   `C:\projetos\chaves`, confere a chave, grava `android\key.properties`,
   compila, instala e abre o app:

   ```powershell
   .\tool\maquininha.ps1            # outra pasta: -Chaves D:\caminho
   .\tool\maquininha.ps1 -VarianteDebug   # se o terminal recusar o build de release
   ```

   Manualmente (ou no Linux): crie `android/key.properties` com `storeFile`,
   `storePassword`, `keyAlias` e `keyPassword` da JKS do fabricante e rode
   `tool/build.sh` + `tool/deploy.sh`. Com `signDebug=true` no arquivo, o
   build de debug (`flutter run`) também sai assinado com ela.

   Nenhuma credencial do painel da Stone entra no app: o Token PackageCloud é
   do SDK (não usado), o StoneCode ativa o terminal nos apps da Stone e as
   chaves `QRCode_*` são do Pix via SDK.
4. O terminal precisa estar **ativado** com o StoneCode de teste (o serial é
   vinculado ao StoneCode por formulário; é 1:1).
5. Logs: `tool/deploy.sh --logs` ou `adb logcat`. Para espelhar a tela, `scrcpy`.
   `.\tool\maquininha.ps1 -Diagnostico` mostra o Android do terminal, os apps
   da Stone instalados e quem atende cada deeplink.
   Se o app disser que os apps da Stone não foram detectados num terminal
   Stone, ligue **Configurações › Maquininha › Usar os apps da Stone** (o
   Android 11+ pode esconder de um app a existência de outros; abrir o
   deeplink funciona mesmo assim).
6. No sandbox os **centavos** definem a resposta: `x,00` aprova, `x,51` dá
   "Não autorizada", `x,55` senha inválida. Voucher não é testável em sandbox.

Roteiro de fumaça sugerido: login → abrir caixa → abrir mesa → lançar item com
adicional → enviar (via do pedido) → pedir conta (imprime) → receber débito
R$ x,00 → conferir no PDV web o pagamento com TEF → repetir com R$ x,51
(recusa) → balcão com dois pagamentos → sangria → fechar caixa.

## 3. Checklist de homologação

**Já atendido pelo app** (o que é verificável por máquina, `tool/check-apk.sh` confere):

- [x] APK abaixo de 70 MB.
- [x] `packageName` `br.com.mobizweb.pos` (padrão `br.com.<empresa>.<app>`,
      sem "stone", adquirente, fabricante ou modelo).
- [x] Só a permissão `INTERNET` — nenhuma das proibidas (`WAKE_LOCK`,
      `RECEIVE_BOOT_COMPLETED`, `WRITE_EXTERNAL_STORAGE`, `READ_PHONE_STATE`…).
- [x] Sem WebView, sem WebSocket/MQTT (o mapa de mesas atualiza por polling
      HTTPS de 15 s) e sem Google Play Services.
- [x] Só HTTPS (`usesCleartextTraffic=false`).
- [x] Não altera configuração do sistema, não usa Bluetooth, não tenta modo
      quiosque nem tela sempre acesa.
- [x] Seção **Fale Conosco** visível (login e Configurações).
- [x] Layout responsivo em retrato (360 dp de largura; grade de 2/3/4 colunas).
- [x] Comprovante da transação impresso pelo app de pagamento (deeplink).
- [x] Assinatura V1 + V2 configurada para quando houver `key.properties`.

**Depende de você:**

- [ ] **Keystore de produção.** Gere uma vez e guarde com backup — perder a
      chave impede atualizar o app:

      ```bash
      keytool -genkeypair -v -keystore mobiz-pos.jks -alias mobizpos -keyalg RSA -keysize 2048 -validity 10000
      ```

      Aponte `android/key.properties` para ela (o arquivo e a JKS ficam fora do git).
- [ ] **`packageName` e keystore não mudam nunca mais** depois de homologado.
      Se preferir outro nome, troque **antes** (`android/app/build.gradle.kts`,
      pasta `kotlin/br/com/mobizweb/pos` e `tool/deploy.*`).
- [ ] **Contato do Fale Conosco**: informe telefone/e-mail no build
      (`MOBIZ_SUPPORT_PHONE`, `MOBIZ_SUPPORT_EMAIL` — ver README). Sem isso
      aparece só o nome e o site.
- [ ] **Versão**: `version: X.Y.Z+N` no `pubspec.yaml`. `versionName` só com
      números e ponto, e os dois sempre maiores que os da versão anterior.
- [ ] **Lista de URLs** para a whitelist do chip Stone: o domínio das lojas
      (`*.mobizweb.com.br` e domínios próprios de tenant) e o host das
      **imagens de produto** se forem servidas de outro domínio (CDN/S3).
- [ ] **Android mínimo.** O Flutter atual exige Android 7.0 (API 24); a Stone
      documenta suporte a partir do 6.0 (API 23). Todos os modelos da lista
      atual da Stone são 7.1 ou mais novos (o antigo Ingenico APOS A8, Android
      5.1, fica de fora). Confirme com o time de integração.
- [ ] **"Integração para todos os hardwares Stone"**: teste em cada modelo
      que a Stone pedir (a largura lógica é ~360 dp em todos; as alturas variam).
- [ ] Roteiro de Testes, Guia de Ativação e vídeo (baixados no Partner Hub em
      *Integração › Homologações › Nova Homologação*).

Depois de aprovado, a distribuição é pelo TMS da Stone: o parceiro libera o
app por lojista no Partner Hub e ele baixa sozinho no POS.

## 4. Backend (Mobizweb)

O app usa `/api/garcom/v1`, o mesmo contrato do PWA do garçom, já com os
campos de TEF por deeplink (`docs/api-comanda.md` no Mobizweb). Dois pontos
do servidor que vale conhecer:

- **Venda de balcão com cartão:** `OrderPaymentService` grava
  `tef_provider = 'dspay'` sempre que chega `tef_transaction_id` no checkout
  do balcão. O ATK e o NSU ficam certos, mas o provedor sai "dspay" em vez de
  "stone_deeplink". Na mesa/comanda o provedor é gravado corretamente.
- **Conta por comanda e via do pedido** não têm endpoint de recibo no
  garçom: o app monta os dois localmente.
